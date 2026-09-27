#!/usr/bin/env bash
# tests/test_migrations_live.sh — M02-01 live PostgreSQL rehearsal.
# Applies the checked-in migration to an ephemeral PostgreSQL container and
# exercises the fenced job, collection cursor, and atomic event-page functions. The default local
# suite remains dependency-free; set RH_PG_MIGRATION=1 to run this gate.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${RH_PG_IMAGE:-postgres:16-alpine}"
CONTAINER="rh-migration-${$}"
CRASH_LOG="/tmp/${CONTAINER}.crash.log"

fail() { echo "[migrations-live] FAIL: $1" >&2; exit 1; }
cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; rm -f "$CRASH_LOG"; }
trap cleanup EXIT

if [[ "${RH_PG_MIGRATION:-0}" != "1" ]]; then
  echo "[migrations-live] skipped (RH_PG_MIGRATION!=1)"
  exit 0
fi

command -v docker >/dev/null 2>&1 || fail "docker is required"
docker info >/dev/null 2>&1 || fail "docker daemon is unavailable"
docker image inspect "$IMAGE" >/dev/null 2>&1 || fail "image is unavailable: $IMAGE"

echo "[migrations-live] start $IMAGE"
docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=repo-health-test -e POSTGRES_DB=repo_health "$IMAGE" >/dev/null || fail "container start"
ready_checks=0
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready -U postgres -d repo_health >/dev/null 2>&1; then
    ready_checks=$((ready_checks + 1))
    [[ "$ready_checks" -ge 3 ]] && break
  else
    ready_checks=0
  fi
  sleep 1
done
[[ "$ready_checks" -ge 3 ]] || fail "postgres did not become ready"
docker exec "$CONTAINER" pg_isready -U postgres -d repo_health >/dev/null 2>&1 || fail "postgres stopped after becoming ready"

docker cp "$ROOT/db/migrations/001_initial.sql" "$CONTAINER:/tmp/001_initial.sql" || fail "copy migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/001_initial.sql >/dev/null || fail "apply migration"
docker cp "$ROOT/db/migrations/002_current_state_reconciliation.sql" "$CONTAINER:/tmp/002_current_state_reconciliation.sql" || fail "copy current-state migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/002_current_state_reconciliation.sql >/dev/null || fail "apply current-state migration"
docker cp "$ROOT/db/migrations/003_projection_adjacency_batch.sql" "$CONTAINER:/tmp/003_projection_adjacency_batch.sql" || fail "copy projection-adjacency migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/003_projection_adjacency_batch.sql >/dev/null || fail "apply projection-adjacency migration"
docker cp "$ROOT/db/migrations/004_graph_query_claim_attempt.sql" "$CONTAINER:/tmp/004_graph_query_claim_attempt.sql" || fail "copy graph-query worker migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/004_graph_query_claim_attempt.sql >/dev/null || fail "apply graph-query worker migration"
docker cp "$ROOT/db/migrations/005_store_graph_projection.sql" "$CONTAINER:/tmp/005_store_graph_projection.sql" || fail "copy graph-projection storage migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/005_store_graph_projection.sql >/dev/null || fail "apply graph-projection storage migration"
docker cp "$ROOT/db/migrations/006_stage_graph_projection_chunks.sql" "$CONTAINER:/tmp/006_stage_graph_projection_chunks.sql" || fail "copy projection-chunk migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/006_stage_graph_projection_chunks.sql >/dev/null || fail "apply projection-chunk migration"
docker cp "$ROOT/db/migrations/007_projection_adjacency_temporal_metadata.sql" "$CONTAINER:/tmp/007_projection_adjacency_temporal_metadata.sql" || fail "copy projection-adjacency temporal metadata migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/007_projection_adjacency_temporal_metadata.sql >/dev/null || fail "apply projection-adjacency temporal metadata migration"
docker cp "$ROOT/db/migrations/008_bind_projection_query_scope.sql" "$CONTAINER:/tmp/008_bind_projection_query_scope.sql" || fail "copy projection-query scope migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/008_bind_projection_query_scope.sql >/dev/null || fail "apply projection-query scope migration"
docker cp "$ROOT/db/migrations/009_projection_adjacency_walk.sql" "$CONTAINER:/tmp/009_projection_adjacency_walk.sql" || fail "copy projection-adjacency walk migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/009_projection_adjacency_walk.sql >/dev/null || fail "apply projection-adjacency walk migration"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null
DO $$
BEGIN
  IF NOT rh_begin_collection_run(
    '00000000-0000-0000-0000-000000000001', 'github', 'https://api.github.com',
    'public', 1, '2026-01-01T00:00:00Z',
    '00000000-0000-0000-0000-000000000003', 'issues', 'github', '1.0.0',
    NULL, NULL, '2026-01-01T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'initial collection run was not started';
  END IF;
  IF rh_begin_collection_run(
    '00000000-0000-0000-0000-000000000001', 'github', 'https://api.github.com',
    'public', 1, '2026-01-01T00:00:00Z',
    '00000000-0000-0000-0000-000000000003', 'issues', 'github', '1.0.0',
    NULL, NULL, '2026-01-01T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'exact collection run replay was not absorbed';
  END IF;
  BEGIN
    PERFORM rh_begin_collection_run(
      '00000000-0000-0000-0000-000000000004', 'github', 'https://token@example.test/api',
      'public', 1, '2026-01-01T00:00:00Z',
      '00000000-0000-0000-0000-000000000004', 'issues', 'github', '1.0.0',
      NULL, NULL, '2026-01-01T00:00:00Z'
    );
    RAISE EXCEPTION 'credential-bearing source URL was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('source base URL must be absolute and free of credentials' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  BEGIN
    PERFORM rh_begin_collection_run(
      '00000000-0000-0000-0000-000000000001', 'github', 'https://api.github.com/changed',
      'public', 1, '2026-01-01T00:00:00Z',
      '00000000-0000-0000-0000-000000000004', 'issues', 'github', '1.0.0',
      NULL, NULL, '2026-01-01T00:00:00Z'
    );
    RAISE EXCEPTION 'conflicting source metadata was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('source instance identity is already registered' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  BEGIN
    PERFORM rh_begin_collection_run(
      '00000000-0000-0000-0000-000000000001', 'github', 'https://api.github.com',
      'public', 1, '2026-01-01T00:00:00Z',
      '00000000-0000-0000-0000-000000000003', 'pulls', 'github', '1.0.0',
      NULL, NULL, '2026-01-01T00:00:00Z'
    );
    RAISE EXCEPTION 'conflicting collection run metadata was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('collection run identity is already registered' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
END $$;
INSERT INTO job (id, source_instance_id, kind, visibility_scope, state, priority, next_attempt_at, created_at)
VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'maintenance', 'public', 'queued', 10, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
INSERT INTO job (id, source_instance_id, kind, visibility_scope, state, priority, next_attempt_at, attempt_count, fencing_token, worker_id, lease_expires_at, created_at, input_manifest)
VALUES ('00000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000001', 'collection', 'public', 'running', 1, '2026-01-01T00:00:00Z', 1, 1, 'worker-page', '2026-01-02T00:00:00Z', '2026-01-01T00:00:00Z', '{"collection_run_id":"00000000-0000-0000-0000-000000000003"}');
INSERT INTO job_attempt (id, job_id, attempt_number, fencing_token, worker_id, started_at)
VALUES ('00000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000008', 1, 1, 'worker-page', '2026-01-01T00:00:00Z');
DO $$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM rh_claim_next_job('worker-a', '2026-01-01T00:00:01Z', 60);
  IF c.job_id <> '00000000-0000-0000-0000-000000000002'::uuid OR c.fencing_token <> 1 THEN
    RAISE EXCEPTION 'unexpected claim: %', c;
  END IF;
  IF NOT rh_heartbeat_job(c.job_id, c.fencing_token, '2026-01-01T00:00:10Z', 60) THEN
    RAISE EXCEPTION 'current heartbeat was refused';
  END IF;
  IF rh_heartbeat_job(c.job_id, c.fencing_token - 1, '2026-01-01T00:00:10Z', 60) THEN
    RAISE EXCEPTION 'stale heartbeat was accepted';
  END IF;
  IF rh_finish_job(c.job_id, c.fencing_token - 1, 'succeeded', '2026-01-01T00:00:20Z') THEN
    RAISE EXCEPTION 'stale finish was accepted';
  END IF;
  IF rh_finish_job(c.job_id, c.fencing_token, 'failed', '2026-01-01T00:02:00Z', 'expired', NULL) THEN
    RAISE EXCEPTION 'expired finish was accepted';
  END IF;
  IF NOT rh_finish_job(c.job_id, c.fencing_token, 'succeeded', '2026-01-01T00:00:20Z', 'ok', NULL) THEN
    RAISE EXCEPTION 'current finish was refused';
  END IF;
END $$;

DO $$
DECLARE
  valid_request jsonb := '{"schema":"rh-query-input/1","kind":"downstream","ids":[],"graph":{"direction":"downstream","subject":1,"nodes":[1],"entity_ids":["00000000-0000-0000-0000-000001000001"],"edges":[],"projection":{"id":"00000000-0000-0000-0000-000000009001","subject_entity_id":"00000000-0000-0000-0000-000001000001","edge_kind":"depends_on","visibility_scope":"public"}}}'::jsonb;
  invalid_request jsonb;
BEGIN
  BEGIN
    PERFORM rh_enqueue_graph_query_job(
      '00000000-0000-0000-0000-000000000095', 'tenant-private', valid_request, 0,
      '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z'
    );
    RAISE EXCEPTION 'cross-scope projection query was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('crosses job visibility scope' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
  invalid_request := jsonb_set(valid_request, '{graph,projection,id}', '"not-a-uuid"'::jsonb);
  BEGIN
    PERFORM rh_enqueue_graph_query_job(
      '00000000-0000-0000-0000-000000000095', 'public', invalid_request, 0,
      '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z'
    );
    RAISE EXCEPTION 'malformed projection descriptor was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('descriptor is malformed' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
  IF NOT rh_enqueue_graph_query_job(
    '00000000-0000-0000-0000-000000000095', 'public', valid_request, 0,
    '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'matching-scope projection query was not enqueued';
  END IF;
  DELETE FROM graph_query_job WHERE job_id = '00000000-0000-0000-0000-000000000095';
  DELETE FROM job WHERE id = '00000000-0000-0000-0000-000000000095';
END $$;

DO $$
DECLARE
  c jsonb;
  token_value bigint;
  request_value jsonb := '{"schema":"rh-query-input/1","kind":"downstream","ids":[1,2],"cursor":-1,"limit":10}'::jsonb;
  result_value jsonb := '{"schema":"rh-query-result/1","kind":"downstream","graph":{"direction":"downstream","nodes":[2],"truncated":false,"complete":true}}'::jsonb;
BEGIN
  IF NOT rh_enqueue_graph_query_job('00000000-0000-0000-0000-000000000099', 'public', request_value, 3, '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z') THEN
    RAISE EXCEPTION 'graph query job was not enqueued';
  END IF;
  IF rh_enqueue_graph_query_job('00000000-0000-0000-0000-000000000099', 'public', request_value, 3, '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z') THEN
    RAISE EXCEPTION 'exact graph query job replay was not absorbed';
  END IF;
  c := rh_get_graph_query_job('00000000-0000-0000-0000-000000000099', 'public');
  IF c->>'status' <> 'queued' OR c ? 'result' THEN
    RAISE EXCEPTION 'queued graph job exposed a result or wrong status: %', c;
  END IF;
  c := rh_claim_graph_query_job_with_attempt('graph-worker', '2026-01-02T00:00:01Z', 60, '00000000-0000-0000-0000-000000000099');
  token_value := (c->>'fencing_token')::bigint;
  IF c->>'status' <> 'claimed' OR c->>'job_id' <> '00000000-0000-0000-0000-000000000099' OR token_value <> 1 OR c->>'attempt_count' <> '1' OR c->'request' <> request_value THEN
    RAISE EXCEPTION 'graph claim omitted its lease or immutable request: %', c;
  END IF;
  IF rh_read_graph_query_request('00000000-0000-0000-0000-000000000099', token_value, '2026-01-02T00:00:02Z') IS DISTINCT FROM request_value THEN
    RAISE EXCEPTION 'current graph claim could not read its request';
  END IF;
  IF rh_finish_job('00000000-0000-0000-0000-000000000099', token_value, 'succeeded', '2026-01-02T00:00:10Z') THEN
    RAISE EXCEPTION 'generic finish bypassed graph result publication';
  END IF;
  IF rh_publish_graph_query_result('00000000-0000-0000-0000-000000000099', token_value - 1, '2026-01-02T00:00:10Z', result_value) THEN
    RAISE EXCEPTION 'stale graph result publication was accepted';
  END IF;
  BEGIN
    PERFORM rh_publish_graph_query_result(
      '00000000-0000-0000-0000-000000000099', token_value, '2026-01-02T00:00:10Z',
      jsonb_set(result_value, '{kind}', '"upstream"'::jsonb)
    );
    RAISE EXCEPTION 'mismatched graph result kind was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('graph query result kind does not match its immutable request' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  IF NOT rh_publish_graph_query_result('00000000-0000-0000-0000-000000000099', token_value, '2026-01-02T00:00:10Z', result_value) THEN
    RAISE EXCEPTION 'current graph result publication was refused';
  END IF;
  IF rh_publish_graph_query_result('00000000-0000-0000-0000-000000000099', token_value, '2026-01-02T00:00:11Z', result_value) THEN
    RAISE EXCEPTION 'completed graph result was published twice';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM graph_query_job
    WHERE job_id = '00000000-0000-0000-0000-000000000099' AND request = request_value AND result = result_value
      AND result_fencing_token = token_value AND completed_at = '2026-01-02T00:00:10Z'
  ) OR (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000099') <> 'succeeded' THEN
    RAISE EXCEPTION 'graph result and terminal job state were not committed together';
  END IF;
  c := rh_get_graph_query_job('00000000-0000-0000-0000-000000000099', 'public');
  IF c->>'status' <> 'succeeded' OR c->'result' IS DISTINCT FROM result_value THEN
    RAISE EXCEPTION 'poll did not return the published graph result: %', c;
  END IF;
  c := rh_get_graph_query_job('00000000-0000-0000-0000-000000000099', 'tenant-private');
  IF c->>'status' <> 'not_found' THEN
    RAISE EXCEPTION 'poll exposed a graph job across visibility scopes: %', c;
  END IF;
  c := rh_claim_graph_query_job('graph-worker', '2026-01-02T00:00:20Z', 60, NULL);
  IF c->>'status' <> 'empty' THEN
    RAISE EXCEPTION 'completed graph query was claimable again';
  END IF;
END $$;

DO $$
DECLARE
  c jsonb;
  first_token bigint;
  second_token bigint;
  auth_finished boolean;
  malformed_finished boolean;
BEGIN
  IF NOT rh_enqueue_graph_query_job('00000000-0000-0000-0000-000000000098', 'public', '{"schema":"rh-query-input/1","kind":"upstream","ids":[1],"cursor":-1,"limit":10}'::jsonb, 1, '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z') THEN
    RAISE EXCEPTION 'retry graph job was not enqueued';
  END IF;
  c := rh_claim_graph_query_job('retry-worker', '2026-01-02T00:00:01Z', 60, '00000000-0000-0000-0000-000000000098');
  first_token := (c->>'fencing_token')::bigint;
  BEGIN
    PERFORM rh_retry_graph_query_job('00000000-0000-0000-0000-000000000098', first_token, 1, 2, 'transient', 7, 'epoch', '2026-01-02T00:00:01Z');
    RAISE EXCEPTION 'retryable failure was dead-lettered before its configured attempt limit';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('retry decision does not match failure classification' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
  IF NOT rh_retry_graph_query_job('00000000-0000-0000-0000-000000000098', first_token, 1, 2, 'transient', 6, '2026-01-02T00:00:03Z', '2026-01-02T00:00:01Z') THEN
    RAISE EXCEPTION 'current transient failure was not requeued';
  END IF;
  IF rh_retry_graph_query_job('00000000-0000-0000-0000-000000000098', first_token, 1, 2, 'transient', 6, '2026-01-02T00:00:03Z', '2026-01-02T00:00:01Z') THEN
    RAISE EXCEPTION 'closed attempt retry was accepted twice';
  END IF;
  IF (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000098') <> 'queued'
     OR (SELECT outcome FROM job_attempt WHERE job_id = '00000000-0000-0000-0000-000000000098' AND attempt_number = 1) <> 'retry' THEN
    RAISE EXCEPTION 'retry transition did not preserve queued state and attempt outcome';
  END IF;
  c := rh_claim_graph_query_job('retry-worker', '2026-01-02T00:00:04Z', 60, '00000000-0000-0000-0000-000000000098');
  second_token := (c->>'fencing_token')::bigint;
  BEGIN
    PERFORM rh_retry_graph_query_job('00000000-0000-0000-0000-000000000098', second_token, 2, 2, 'transient', 6, '2026-01-02T00:00:07Z', '2026-01-02T00:00:05Z');
    RAISE EXCEPTION 'exhausted retryable failure was requeued';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('retry decision does not match failure classification' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
  IF second_token <= first_token OR NOT rh_retry_graph_query_job('00000000-0000-0000-0000-000000000098', second_token, 2, 2, 'transient', 7, 'epoch', '2026-01-02T00:00:05Z') THEN
    RAISE EXCEPTION 'exhausted retry was not dead-lettered';
  END IF;
  IF (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000098') <> 'dead_letter'
     OR (SELECT count(*) FROM job_attempt WHERE job_id = '00000000-0000-0000-0000-000000000098' AND finished_at IS NOT NULL) <> 2 THEN
    RAISE EXCEPTION 'dead-letter transition did not close both attempts';
  END IF;
  IF NOT rh_enqueue_graph_query_job('00000000-0000-0000-0000-000000000097', 'public', '{"schema":"rh-query-input/1","kind":"upstream","ids":[1],"cursor":-1,"limit":10}'::jsonb, 1, '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z') THEN
    RAISE EXCEPTION 'terminal graph job was not enqueued';
  END IF;
  c := rh_claim_graph_query_job('retry-worker', '2026-01-02T00:00:06Z', 60, '00000000-0000-0000-0000-000000000097');
  auth_finished := rh_retry_graph_query_job('00000000-0000-0000-0000-000000000097', (c->>'fencing_token')::bigint, 1, 5, 'auth', 4, 'epoch', '2026-01-02T00:00:07Z');
  IF NOT auth_finished OR (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000097') <> 'failed' THEN
    RAISE EXCEPTION 'auth failure did not terminate the graph job: claimed=%, result=%, state=%', c, auth_finished, (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000097');
  END IF;
  IF NOT rh_enqueue_graph_query_job('00000000-0000-0000-0000-000000000096', 'public', '{"schema":"rh-query-input/1","kind":"upstream","ids":[1],"cursor":-1,"limit":10}'::jsonb, 1, '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z') THEN
    RAISE EXCEPTION 'malformed graph job was not enqueued';
  END IF;
  c := rh_claim_graph_query_job('retry-worker', '2026-01-02T00:00:08Z', 60, '00000000-0000-0000-0000-000000000096');
  malformed_finished := rh_retry_graph_query_job('00000000-0000-0000-0000-000000000096', (c->>'fencing_token')::bigint, 1, 5, 'malformed', 7, 'epoch', '2026-01-02T00:00:09Z');
  IF NOT malformed_finished OR (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000096') <> 'dead_letter' THEN
    RAISE EXCEPTION 'malformed failure did not dead-letter the graph job: claimed=%, result=%, state=%', c, malformed_finished, (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000096');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT rh_register_evidence_object('00000000-0000-0000-0000-000000000006', 'public', repeat('a', 64), 18, 'application/json', 'fnv1a64:aaaaaaaaaaaaaaaa', 'standard', 'captured', '2026-01-01T00:00:00Z') THEN
    RAISE EXCEPTION 'new evidence object was not registered';
  END IF;
  IF rh_register_evidence_object('00000000-0000-0000-0000-000000000006', 'public', repeat('a', 64), 18, 'application/json', 'fnv1a64:aaaaaaaaaaaaaaaa', 'standard', 'captured', '2026-01-01T00:00:00Z') THEN
    RAISE EXCEPTION 'exact evidence replay was not absorbed';
  END IF;
  BEGIN
    PERFORM rh_register_evidence_object('00000000-0000-0000-0000-000000000006', 'public', repeat('a', 64), 19, 'application/json', 'fnv1a64:aaaaaaaaaaaaaaaa', 'standard', 'captured', '2026-01-01T00:00:00Z');
    RAISE EXCEPTION 'conflicting evidence metadata was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('different immutable metadata' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
END $$;
DO $$
BEGIN
  BEGIN
    PERFORM rh_commit_collection_page('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 0, 'scope-a', '{}'::jsonb, '{"page":1}'::jsonb, 'partial', 1, NULL, '2026-01-01T00:01:00Z');
    RAISE EXCEPTION 'partial page advanced cursor';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('partial page cannot advance' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  IF NOT rh_commit_collection_page('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 0, 'scope-a', '{}'::jsonb, '{"page":1}'::jsonb, 'complete', 1, NULL, '2026-01-01T00:01:00Z') THEN
    RAISE EXCEPTION 'complete page was refused';
  END IF;
  IF rh_commit_collection_page('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 0, 'scope-a', '{}'::jsonb, '{"page":1}'::jsonb, 'complete', 1, NULL, '2026-01-01T00:02:00Z') THEN
    RAISE EXCEPTION 'duplicate page advanced cursor';
  END IF;
END $$;

DO $$
DECLARE page_count integer; cursor_page integer; cursor_value jsonb;
BEGIN
  SELECT count(*) INTO page_count FROM collection_page WHERE collection_run_id = '00000000-0000-0000-0000-000000000003'::uuid;
  SELECT last_page_number, cursor INTO cursor_page, cursor_value FROM collection_cursor WHERE source_instance_id = '00000000-0000-0000-0000-000000000001'::uuid AND capability = 'issues' AND scope_hash = 'scope-a';
  IF page_count <> 1 OR cursor_page <> 0 OR cursor_value <> '{"page":1}'::jsonb THEN
    RAISE EXCEPTION 'cursor replay invariant failed: %, %, %', page_count, cursor_page, cursor_value;
  END IF;
END $$;

DO $$
DECLARE
  event_page jsonb := '[{"source_object_type":"issue","source_object_id":"issue:7","source_revision":"rev-1","event_kind":"created","subject_id":"00000000-0000-0000-0000-000000000005","actor_account_id":"00000000-0000-0000-0000-000000000007","occurred_at":"2026-01-01T00:00:30Z","observed_at":"2026-01-01T00:03:00Z","time_basis":"event","evidence_id":"00000000-0000-0000-0000-000000000006","parser_version":"fixture/1","payload":{"state":"open"}}]'::jsonb;
  event_subjects jsonb := '[{"id":"00000000-0000-0000-0000-000000000005","entity_kind":"issue","visibility_scope":"public","created_at":"2026-01-01T00:00:00Z"}]'::jsonb;
  event_actors jsonb := '[{"id":"00000000-0000-0000-0000-000000000007","source_native_id":"alice","account_kind":"human","display_name":"Alice Example","raw_identity_evidence_id":null,"visibility_scope":"public"}]'::jsonb;
  oversized_records jsonb := '[]'::jsonb;
  reclaimed record;
BEGIN
  IF NOT rh_commit_collection_page_events('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 1, 'scope-events', NULL, '{"page":2}'::jsonb, 'complete', 1, NULL, event_page, event_subjects, event_actors, '2026-01-01T00:03:00Z') THEN
    RAISE EXCEPTION 'event page was refused';
  END IF;
  IF rh_commit_collection_page_events('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 1, 'scope-events', NULL, '{"page":99}'::jsonb, 'complete', 1, NULL, jsonb_set(event_page, '{0,source_object_id}', '"issue:8"'::jsonb), event_subjects, event_actors, '2026-01-01T00:03:30Z') THEN
    RAISE EXCEPTION 'duplicate page was accepted';
  END IF;
  IF (SELECT count(*) FROM canonical_event WHERE source_instance_id = '00000000-0000-0000-0000-000000000001'::uuid) <> 1
     OR (SELECT last_page_number FROM collection_cursor WHERE source_instance_id = '00000000-0000-0000-0000-000000000001'::uuid AND capability = 'issues' AND scope_hash = 'scope-events') <> 1 THEN
    RAISE EXCEPTION 'duplicate page changed event or cursor state';
  END IF;
  IF NOT rh_commit_collection_page_events('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 2, 'scope-events', '{"page":2}'::jsonb, '{"page":3}'::jsonb, 'complete', 1, NULL, event_page, event_subjects, event_actors, '2026-01-01T00:04:00Z') THEN
    RAISE EXCEPTION 'replayed event page was refused';
  END IF;
  IF (SELECT count(*) FROM canonical_event WHERE source_instance_id = '00000000-0000-0000-0000-000000000001'::uuid) <> 1 THEN
    RAISE EXCEPTION 'source-native event replay was not absorbed';
  END IF;
  BEGIN
    PERFORM rh_commit_collection_page_events('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 3, 'scope-events', '{"page":3}'::jsonb, '{"page":4}'::jsonb, 'complete', 1, NULL, event_page, '[{"id":"00000000-0000-0000-0000-000000000005","entity_kind":"issue","visibility_scope":"public","created_at":"2026-01-02T00:00:00Z"}]'::jsonb, event_actors, '2026-01-01T00:04:30Z');
    RAISE EXCEPTION 'conflicting subject metadata was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('different immutable metadata' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  BEGIN
    PERFORM rh_commit_collection_page_events('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 3, 'scope-events', '{"page":3}'::jsonb, '{"page":4}'::jsonb, 'complete', 1, NULL, event_page, event_subjects, '[{"id":"00000000-0000-0000-0000-000000000007","source_native_id":"alice","account_kind":"human","display_name":"Alicia Example","raw_identity_evidence_id":null,"visibility_scope":"public"}]'::jsonb, '2026-01-01T00:04:45Z');
    RAISE EXCEPTION 'conflicting actor metadata was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('page actor identity is already registered with different immutable metadata' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  BEGIN
    PERFORM rh_commit_collection_page_events('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 3, 'scope-events', '{"page":3}'::jsonb, '{"page":4}'::jsonb, 'complete', 1, NULL, '[{"source_object_type":"issue"}]'::jsonb, event_subjects, event_actors, '2026-01-01T00:05:00Z');
    RAISE EXCEPTION 'malformed event page committed';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('page event is missing a required typed field' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  BEGIN
    PERFORM rh_commit_collection_page_events('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 3, 'scope-events', '{"page":3}'::jsonb, '{"page":4}'::jsonb, 'complete', 1, NULL, event_page, event_subjects, '[{"id":"00000000-0000-0000-0000-000000000007"}]'::jsonb, '2026-01-01T00:05:15Z');
    RAISE EXCEPTION 'malformed page actor committed';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('page actor is missing a required typed field' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  UPDATE job SET input_manifest = '{"collection_run_id":"00000000-0000-0000-0000-000000000004"}'::jsonb
  WHERE id = '00000000-0000-0000-0000-000000000008'::uuid;
  BEGIN
    PERFORM rh_commit_collection_page('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 1, 'scope-unbound', '{}'::jsonb, '{"page":1}'::jsonb, 'complete', 1, NULL, '2026-01-01T00:05:20Z');
    RAISE EXCEPTION 'a job for another collection run advanced the cursor';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('collection page lease is stale' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  UPDATE job SET input_manifest = '{"collection_run_id":"00000000-0000-0000-0000-000000000003"}'::jsonb
  WHERE id = '00000000-0000-0000-0000-000000000008'::uuid;
  SELECT * INTO reclaimed FROM rh_claim_next_job('worker-page-reclaimed', '2026-01-03T00:00:00Z', 60);
  IF reclaimed.job_id <> '00000000-0000-0000-0000-000000000008'::uuid
     OR reclaimed.fencing_token <> 2
     OR reclaimed.lease_expires_at <> '2026-01-03T00:01:00Z'::timestamptz THEN
    RAISE EXCEPTION 'expired collection job was not reclaimed with a new lease: %', reclaimed;
  END IF;
  IF (SELECT finished_at FROM job_attempt WHERE job_id = reclaimed.job_id AND fencing_token = 1) <> '2026-01-03T00:00:00Z'::timestamptz
     OR (SELECT outcome FROM job_attempt WHERE job_id = reclaimed.job_id AND fencing_token = 1) <> 'lease_expired'
     OR (SELECT error_kind FROM job_attempt WHERE job_id = reclaimed.job_id AND fencing_token = 1) <> 'lease_expired' THEN
    RAISE EXCEPTION 'reclaim did not close the expired attempt';
  END IF;
  BEGIN
    PERFORM rh_commit_collection_page('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 1, 'scope-stale', '{}'::jsonb, '{"page":1}'::jsonb, 'complete', 1, NULL, '2026-01-03T00:00:30Z');
    RAISE EXCEPTION 'stale page lease advanced a cursor';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('collection page lease is stale' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  BEGIN
    PERFORM rh_commit_collection_page_events('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1, 3, 'scope-events', '{"page":3}'::jsonb, '{"page":4}'::jsonb, 'complete', 1, NULL, event_page, event_subjects, event_actors, '2026-01-03T00:00:45Z');
    RAISE EXCEPTION 'stale event-page lease advanced a cursor';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('collection page lease is stale' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  BEGIN
    PERFORM rh_commit_collection_page('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 2, 1, 'scope-expired', '{}'::jsonb, '{"page":1}'::jsonb, 'complete', 1, NULL, '2026-01-03T00:02:00Z');
    RAISE EXCEPTION 'an expired page lease advanced a cursor';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('collection page lease is stale' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  IF EXISTS (SELECT 1 FROM collection_page WHERE collection_run_id = '00000000-0000-0000-0000-000000000003'::uuid AND page_number = 3)
     OR (SELECT last_page_number FROM collection_cursor WHERE source_instance_id = '00000000-0000-0000-0000-000000000001'::uuid AND capability = 'issues' AND scope_hash = 'scope-events') <> 2 THEN
    RAISE EXCEPTION 'failed event page left a page or advanced cursor';
  END IF;
  IF EXISTS (SELECT 1 FROM collection_page WHERE collection_run_id = '00000000-0000-0000-0000-000000000003'::uuid AND scope_hash IN ('scope-stale', 'scope-unbound', 'scope-expired')) THEN
    RAISE EXCEPTION 'stale simple page left a page row';
  END IF;
  IF NOT rh_commit_staged_collection_page(
    '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 2,
    3, 'scope-staged', NULL, '{"cursor":"raw-page-3"}'::jsonb, 'complete', NULL,
    '[{"collector_label":"issue:raw-a","raw_payload":"{\"id\":\"issue:raw-a\",\"state\":\"open\"}"},{"collector_label":"issue:raw-b","raw_payload":"{\"id\":\"issue:raw-b\",\"state\":\"closed\"}"}]'::jsonb,
    '2026-01-03T00:00:25Z'
  ) THEN
    RAISE EXCEPTION 'complete raw page was not staged';
  END IF;
  IF rh_commit_staged_collection_page(
    '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 2,
    3, 'scope-staged', NULL, '{"cursor":"changed"}'::jsonb, 'complete', NULL,
    '[{"collector_label":"issue:raw-c","raw_payload":"{\"id\":\"issue:raw-c\"}"}]'::jsonb,
    '2026-01-03T00:00:26Z'
  ) THEN
    RAISE EXCEPTION 'duplicate staged page was accepted';
  END IF;
  BEGIN
    PERFORM rh_commit_staged_collection_page(
      '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 2,
      4, 'scope-staged-partial', NULL, '{"cursor":"partial"}'::jsonb, 'partial', NULL,
      '[]'::jsonb, '2026-01-03T00:00:26Z'
    );
    RAISE EXCEPTION 'partial raw page advanced a cursor';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('partial page cannot advance' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  BEGIN
    PERFORM rh_commit_staged_collection_page(
      '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 2,
      4, 'scope-staged-invalid', NULL, '{"cursor":"invalid"}'::jsonb, 'complete', NULL,
      '[{"collector_label":"broken","raw_payload":"not-json"}]'::jsonb,
      '2026-01-03T00:00:26Z'
    );
    RAISE EXCEPTION 'invalid staged payload committed';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('staged record raw payload must be valid JSON' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  BEGIN
    PERFORM rh_commit_staged_collection_page(
      '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 1,
      5, 'scope-staged-stale', NULL, '{"cursor":"stale"}'::jsonb, 'complete', NULL,
      '[{"collector_label":"issue:stale","raw_payload":"{\"id\":\"issue:stale\"}"}]'::jsonb,
      '2026-01-03T00:00:26Z'
    );
    RAISE EXCEPTION 'stale worker staged a raw page';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('collection page lease is stale' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  IF (SELECT count(*) FROM staged_source_record WHERE collection_run_id = '00000000-0000-0000-0000-000000000003'::uuid AND page_number = 3) <> 2
     OR (SELECT raw_payload FROM staged_source_record WHERE collection_run_id = '00000000-0000-0000-0000-000000000003'::uuid AND page_number = 3 AND record_ordinal = 0) <> '{"id":"issue:raw-a","state":"open"}'
     OR EXISTS (SELECT 1 FROM collection_page WHERE collection_run_id = '00000000-0000-0000-0000-000000000003'::uuid AND page_number IN (4, 5))
     OR EXISTS (SELECT 1 FROM staged_source_record WHERE collection_run_id = '00000000-0000-0000-0000-000000000003'::uuid AND page_number IN (4, 5)) THEN
    RAISE EXCEPTION 'staged raw page replay, byte preservation, or rollback invariant failed';
  END IF;
  FOR record_number IN 1..5 LOOP
    oversized_records := oversized_records || jsonb_build_array(jsonb_build_object(
      'collector_label', 'bulk-' || record_number::text,
      'raw_payload', '{"value":"' || repeat('x', 900000) || '"}'
    ));
  END LOOP;
  BEGIN
    PERFORM rh_commit_staged_collection_page(
      '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 2,
      6, 'scope-staged-oversized', NULL, '{"cursor":"oversized"}'::jsonb, 'complete', NULL,
      oversized_records, '2026-01-03T00:00:27Z'
    );
    RAISE EXCEPTION 'oversized staged page was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('staged page raw payload bytes exceed the bounded aggregate limit' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  IF EXISTS (SELECT 1 FROM collection_page WHERE collection_run_id = '00000000-0000-0000-0000-000000000003'::uuid AND page_number = 6)
     OR EXISTS (SELECT 1 FROM staged_source_record WHERE collection_run_id = '00000000-0000-0000-0000-000000000003'::uuid AND page_number = 6) THEN
    RAISE EXCEPTION 'oversized staged page left partial state';
  END IF;
  IF (SELECT count(*) FROM entity WHERE id = '00000000-0000-0000-0000-000000000005'::uuid) <> 1 THEN
    RAISE EXCEPTION 'page subject was not registered exactly once';
  END IF;
  IF (SELECT count(*) FROM account WHERE id = '00000000-0000-0000-0000-000000000007'::uuid) <> 1
     OR (SELECT actor_account_id FROM canonical_event WHERE source_object_id = 'issue:7') <> '00000000-0000-0000-0000-000000000007'::uuid THEN
    RAISE EXCEPTION 'page actor was not registered and linked exactly once';
  END IF;
  IF rh_finish_job('00000000-0000-0000-0000-000000000008', 2, 'succeeded', '2026-01-03T00:00:30Z', 'ok', NULL) THEN
    RAISE EXCEPTION 'generic finish bypassed collection run finalization';
  END IF;
  IF rh_finish_collection_job('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 2, 'succeeded', 'succeeded', 'complete', '{"issues":"observed"}'::jsonb, 'ok', NULL, '2026-01-03T00:02:00Z') THEN
    RAISE EXCEPTION 'expired collection job finished its run';
  END IF;
  IF (SELECT status FROM collection_run WHERE id = '00000000-0000-0000-0000-000000000003'::uuid) <> 'running'
     OR (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000008'::uuid) <> 'running'
     OR (SELECT finished_at FROM job_attempt WHERE job_id = '00000000-0000-0000-0000-000000000008'::uuid AND fencing_token = 2) IS NOT NULL THEN
    RAISE EXCEPTION 'expired collection finish partially changed durable state';
  END IF;
  IF NOT rh_finish_collection_job('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 2, 'succeeded', 'succeeded', 'complete', '{"issues":"observed"}'::jsonb, 'ok', NULL, '2026-01-03T00:00:30Z') THEN
    RAISE EXCEPTION 'current collection job failed to finish its run';
  END IF;
  IF rh_finish_collection_job('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 2, 'succeeded', 'succeeded', 'complete', '{"issues":"observed"}'::jsonb, 'ok', NULL, '2026-01-03T00:00:30Z') THEN
    RAISE EXCEPTION 'terminal collection run finish was not fenced';
  END IF;
  IF (SELECT status FROM collection_run WHERE id = '00000000-0000-0000-0000-000000000003'::uuid) <> 'succeeded'
     OR (SELECT completeness FROM collection_run WHERE id = '00000000-0000-0000-0000-000000000003'::uuid) <> 'complete'
     OR (SELECT coverage_details FROM collection_run WHERE id = '00000000-0000-0000-0000-000000000003'::uuid) <> '{"issues":"observed"}'::jsonb
     OR (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000008'::uuid) <> 'succeeded'
     OR (SELECT finished_at FROM job_attempt WHERE job_id = '00000000-0000-0000-0000-000000000008'::uuid AND fencing_token = 2) <> '2026-01-03T00:00:30Z'::timestamptz THEN
    RAISE EXCEPTION 'collection and job terminal states did not commit together';
  END IF;
END $$;
SQL

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "seed malformed storage key"
DO $$
BEGIN
  IF NOT rh_register_evidence_object(
    '00000000-0000-0000-0000-000000000011', 'public', repeat('b', 64), 18,
    'application/json', 'not-a-content-address', 'standard', 'captured', '2026-01-01T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'malformed storage key seed was not registered';
  END IF;
END $$;
SQL
reference_query="$(python3 - "$ROOT/src/rh_postgres.elisa" <<'PY'
import re, sys
source = open(sys.argv[1], encoding="utf-8").read()
query = re.search(r'Postgres::rh_pg_text_query\(conninfo, "([^\"]+)", out\)', source)
if query is None:
    raise SystemExit("fixed evidence reference query is missing")
print(query.group(1))
PY
)"
reference_snapshot="$(docker exec "$CONTAINER" psql -At -U postgres -d repo_health -c "$reference_query")"
python3 - "$reference_snapshot" <<'PY'
import json, sys
snapshot = json.loads(sys.argv[1])
assert snapshot == {
    "storage_keys": ["fnv1a64:aaaaaaaaaaaaaaaa"], "invalid_count": 1,
    "truncated": False, "count": 1,
}, snapshot
PY
echo "[migrations-live] bounded evidence reference query reports valid keys and malformed rows"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "seed bounded reference population"
INSERT INTO evidence_object (
    id, visibility_scope, digest_algorithm, digest_value, media_type,
    byte_length, storage_key, retention_class, transformation_kind, created_at
)
SELECT
    md5('bounded-reference-' || reference_number::text)::uuid, 'public', 'sha256',
    lpad(to_hex(reference_number), 64, '0'), 'application/octet-stream', 0,
    'fnv1a64:' || lpad(to_hex(reference_number), 16, '0'), 'standard', 'captured',
    '2026-01-01T00:00:00Z'
FROM generate_series(1, 100000) AS reference_number;
SQL
docker exec "$CONTAINER" psql -At -U postgres -d repo_health -c "$reference_query" \
  | python3 -c 'import json, sys; raw=sys.stdin.buffer.read(); snapshot=json.loads(raw); assert len(raw) <= 4194304, len(raw); assert snapshot["count"] == 100001 and len(snapshot["storage_keys"]) == 100001 and snapshot["truncated"] is True and snapshot["invalid_count"] == 0, (len(snapshot["storage_keys"]), snapshot)' \
  || fail "bounded reference truncation and response size"
echo "[migrations-live] 100,001-key snapshot is flagged truncated and stays within 4 MiB"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null
DO $$
DECLARE c record;
BEGIN
  IF NOT rh_begin_collection_run(
    '00000000-0000-0000-0000-000000000001', 'github', 'https://api.github.com',
    'public', 1, '2026-01-01T00:00:00Z',
    '00000000-0000-0000-0000-00000000000a', 'releases', 'github', '1.0.0',
    NULL, NULL, '2026-01-04T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'collection run for enqueue rehearsal was not started';
  END IF;
  IF NOT rh_enqueue_collection_job(
    '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b',
    7, '2026-01-04T00:00:00Z', '2026-01-04T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'collection job was not enqueued';
  END IF;
  IF rh_enqueue_collection_job(
    '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b',
    7, '2026-01-04T00:00:00Z', '2026-01-04T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'exact collection job retry was not absorbed';
  END IF;
  BEGIN
    PERFORM rh_enqueue_collection_job(
      '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b',
      8, '2026-01-04T00:00:00Z', '2026-01-04T00:00:00Z'
    );
    RAISE EXCEPTION 'conflicting collection job metadata was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('collection job identity is already registered with different immutable metadata' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;

  INSERT INTO job (id, source_instance_id, kind, visibility_scope, state, priority, next_attempt_at, created_at)
  VALUES ('00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000001', 'maintenance', 'public', 'queued', 99, '2026-01-04T00:00:00Z', '2026-01-04T00:00:00Z');

  SELECT * INTO c FROM rh_claim_next_job('worker-ingest', '2026-01-04T00:00:01Z', 60, '00000000-0000-0000-0000-00000000000b');
  IF c.job_id <> '00000000-0000-0000-0000-00000000000b'::uuid OR c.fencing_token <> 1 THEN
    RAISE EXCEPTION 'targeted claim did not select the requested collection job: %', c;
  END IF;
  IF NOT rh_finish_collection_job(
    '00000000-0000-0000-0000-00000000000a', c.job_id, c.fencing_token,
    'succeeded', 'succeeded', 'empty', '{"releases":"empty"}'::jsonb,
    'ok', NULL, '2026-01-04T00:00:02Z'
  ) THEN
    RAISE EXCEPTION 'claimed collection job did not finish its run';
  END IF;
  IF (SELECT state FROM job WHERE id = c.job_id) <> 'succeeded'
     OR (SELECT status FROM collection_run WHERE id = '00000000-0000-0000-0000-00000000000a'::uuid) <> 'succeeded'
     OR (SELECT outcome FROM job_attempt WHERE job_id = c.job_id AND fencing_token = c.fencing_token) <> 'ok'
     OR (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-00000000000c'::uuid) <> 'queued' THEN
    RAISE EXCEPTION 'enqueued collection lifecycle did not persist terminal state';
  END IF;
END $$;
SQL

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "seed crash-recovery run and lease"
DO $$
DECLARE c record;
BEGIN
  IF NOT rh_begin_collection_run(
    '00000000-0000-0000-0000-000000000001', 'github', 'https://api.github.com',
    'public', 1, '2026-01-01T00:00:00Z',
    '00000000-0000-0000-0000-000000000030', 'issues', 'github', '1.0.0',
    NULL, NULL, '2026-01-05T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'crash-recovery collection run was not started';
  END IF;
  IF NOT rh_enqueue_collection_job(
    '00000000-0000-0000-0000-000000000030', '00000000-0000-0000-0000-000000000031',
    7, '2026-01-05T00:00:00Z', '2026-01-05T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'crash-recovery collection job was not queued';
  END IF;
  SELECT * INTO c FROM rh_claim_next_job('worker-recovery', '2026-01-05T00:00:01Z', 60, '00000000-0000-0000-0000-000000000031');
  IF c.job_id <> '00000000-0000-0000-0000-000000000031'::uuid OR c.fencing_token <> 1 THEN
    RAISE EXCEPTION 'crash-recovery collection job was not claimed: %', c;
  END IF;
END $$;
SQL

docker exec -i -e PGAPPNAME=repo-health-crash-boundary "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health >"$CRASH_LOG" 2>&1 <<'SQL' &
BEGIN;
SELECT rh_commit_collection_page_events(
  '00000000-0000-0000-0000-000000000030', '00000000-0000-0000-0000-000000000031', 1,
  0, 'scope-crash-recovery', NULL, '{"page":1}'::jsonb, 'complete', 1,
  NULL,
  '[{"source_object_type":"issue","source_object_id":"issue:restart","source_revision":"rev-1","event_kind":"created","subject_id":"00000000-0000-0000-0000-000000000005","actor_account_id":"00000000-0000-0000-0000-000000000007","occurred_at":"2026-01-05T00:00:10Z","observed_at":"2026-01-05T00:00:15Z","time_basis":"event","evidence_id":"00000000-0000-0000-0000-000000000006","parser_version":"fixture/1","payload":{"state":"open"}}]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '2026-01-05T00:00:15Z'
);
SELECT pg_sleep(60);
COMMIT;
SQL
crash_pid=$!
crash_transaction_ready=0
for _ in $(seq 1 100); do
  active_query="$(docker exec "$CONTAINER" psql -At -U postgres -d repo_health -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'repo-health-crash-boundary' AND state = 'active' AND query LIKE '%pg_sleep(60)%'" 2>/dev/null || true)"
  if [[ "$active_query" == "1" ]]; then
    crash_transaction_ready=1
    break
  fi
  kill -0 "$crash_pid" >/dev/null 2>&1 || break
  sleep 0.1
done
[[ "$crash_transaction_ready" -eq 1 ]] || fail "crash-recovery transaction did not reach its uncommitted wait"
docker kill --signal KILL "$CONTAINER" >/dev/null || fail "stop PostgreSQL during uncommitted page transaction"
wait "$crash_pid" >/dev/null 2>&1 || true
docker start "$CONTAINER" >/dev/null || fail "restart PostgreSQL after crash"
ready_checks=0
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready -U postgres -d repo_health >/dev/null 2>&1; then
    ready_checks=$((ready_checks + 1))
    [[ "$ready_checks" -ge 3 ]] && break
  else
    ready_checks=0
  fi
  sleep 1
done
[[ "$ready_checks" -ge 3 ]] || fail "PostgreSQL did not recover after crash"
recovered_state="$(docker exec "$CONTAINER" psql -At -U postgres -d repo_health -c "SELECT (SELECT count(*) FROM collection_page WHERE collection_run_id = '00000000-0000-0000-0000-000000000030'::uuid AND scope_hash = 'scope-crash-recovery') || ':' || (SELECT count(*) FROM canonical_event WHERE source_object_id = 'issue:restart') || ':' || (SELECT count(*) FROM collection_cursor WHERE source_instance_id = '00000000-0000-0000-0000-000000000001'::uuid AND capability = 'issues' AND scope_hash = 'scope-crash-recovery')")"
[[ "$recovered_state" == "0:0:0" ]] || fail "crash recovery left partial page state: $recovered_state"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "replay page after PostgreSQL crash recovery"
DO $$
BEGIN
  IF NOT rh_commit_collection_page_events(
    '00000000-0000-0000-0000-000000000030', '00000000-0000-0000-0000-000000000031', 1,
    0, 'scope-crash-recovery', NULL, '{"page":1}'::jsonb, 'complete', 1,
    NULL,
    '[{"source_object_type":"issue","source_object_id":"issue:restart","source_revision":"rev-1","event_kind":"created","subject_id":"00000000-0000-0000-0000-000000000005","actor_account_id":"00000000-0000-0000-0000-000000000007","occurred_at":"2026-01-05T00:00:10Z","observed_at":"2026-01-05T00:00:15Z","time_basis":"event","evidence_id":"00000000-0000-0000-0000-000000000006","parser_version":"fixture/1","payload":{"state":"open"}}]'::jsonb,
    '[]'::jsonb, '[]'::jsonb, '2026-01-05T00:00:15Z'
  ) THEN
    RAISE EXCEPTION 'page replay after database crash was not committed';
  END IF;
  IF NOT rh_finish_collection_job(
    '00000000-0000-0000-0000-000000000030', '00000000-0000-0000-0000-000000000031', 1,
    'succeeded', 'succeeded', 'complete', '{"issues":"observed"}'::jsonb,
    'ok', NULL, '2026-01-05T00:00:20Z'
  ) THEN
    RAISE EXCEPTION 'crash-recovery collection job did not finalize';
  END IF;
END $$;
SQL
replayed_state="$(docker exec "$CONTAINER" psql -At -U postgres -d repo_health -c "SELECT (SELECT count(*) FROM collection_page WHERE collection_run_id = '00000000-0000-0000-0000-000000000030'::uuid AND scope_hash = 'scope-crash-recovery') || ':' || (SELECT count(*) FROM canonical_event WHERE source_object_id = 'issue:restart') || ':' || (SELECT last_page_number FROM collection_cursor WHERE source_instance_id = '00000000-0000-0000-0000-000000000001'::uuid AND capability = 'issues' AND scope_hash = 'scope-crash-recovery') || ':' || (SELECT status FROM collection_run WHERE id = '00000000-0000-0000-0000-000000000030'::uuid) || ':' || (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000031'::uuid) ")"
[[ "$replayed_state" == "1:1:0:succeeded:succeeded" ]] || fail "post-crash replay did not commit one complete page: $replayed_state"
echo "[migrations-live] PostgreSQL crash recovery rolls back an open page transaction and accepts an exact replay"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "seed staged normalization contract"
INSERT INTO evidence_object (
    id, visibility_scope, digest_algorithm, digest_value, media_type,
    byte_length, storage_key, retention_class, transformation_kind, created_at
) VALUES (
    '00000000-0000-0000-0000-000000000008', 'public', 'sha256', repeat('c', 64),
    'application/json', 1, 'fnv1a64:f0f0f0f0f0f0f0f0', 'standard', 'captured', '2026-01-01T00:00:00Z'
);
INSERT INTO collection_run (
    id, source_instance_id, capability, connector_name, connector_version,
    started_at, finished_at, status, completeness, coverage_details
) VALUES
    ('00000000-0000-0000-0000-000000000040', '00000000-0000-0000-0000-000000000001', 'issues', 'github', '1.0.0', '2026-01-06T00:00:00Z', '2026-01-06T00:01:00Z', 'succeeded', 'complete', '{"issues":"observed"}'),
    ('00000000-0000-0000-0000-000000000043', '00000000-0000-0000-0000-000000000001', 'issues', 'github', '1.0.0', '2026-01-06T00:00:00Z', '2026-01-06T00:01:00Z', 'succeeded', 'complete', '{"issues":"observed"}'),
    ('00000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000001', 'issues', 'github', '1.0.0', '2026-01-06T00:00:00Z', '2026-01-06T00:01:00Z', 'partial', 'partial', '{"issues":"partial"}');
INSERT INTO collection_page (
    id, collection_run_id, page_number, scope_hash, cursor_before, cursor_after,
    status, completeness, record_count, evidence_id, attempted_at, completed_at
) VALUES (
    '00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000040',
    1, 'staged-live-scope', NULL, '{"page":2}', 'success', 'complete', 1,
    '00000000-0000-0000-0000-000000000008', '2026-01-06T00:00:30Z', '2026-01-06T00:00:45Z'
);
INSERT INTO collection_page (
    id, collection_run_id, page_number, scope_hash, cursor_before, cursor_after,
    status, completeness, record_count, evidence_id, attempted_at, completed_at
) VALUES (
    '00000000-0000-0000-0000-000000000044', '00000000-0000-0000-0000-000000000043',
    1, 'other-repository-scope', NULL, '{"page":2}', 'success', 'complete', 1,
    '00000000-0000-0000-0000-000000000008', '2026-01-06T00:00:30Z', '2026-01-06T00:00:45Z'
);
INSERT INTO staged_source_record (
    collection_run_id, page_number, record_ordinal, collector_label, raw_payload, captured_at
) VALUES (
    '00000000-0000-0000-0000-000000000040', 1, 0, 'issues-page-v1',
    '{"id":101,"state":"closed","created_at":"2023-07-22T04:26:40Z"}', '2026-01-06T00:00:45Z'
);
INSERT INTO staged_source_record (
    collection_run_id, page_number, record_ordinal, collector_label, raw_payload, captured_at
) VALUES (
    '00000000-0000-0000-0000-000000000043', 1, 0, 'issues-page-v1',
    '{"id":101,"state":"closed","created_at":"2023-07-22T04:26:40Z"}', '2026-01-06T00:00:45Z'
);
SQL
docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "commit and replay staged normalization"
DO $$
DECLARE events jsonb := '[{"kind":"issues","native_id":"github:101","status":"closed","created_at":1690000000,"updated_at":1695000000,"closed_at":null,"staged_origin":{"page_number":1,"record_ordinal":0,"evidence_id":"00000000-0000-0000-0000-000000000008"}}]'::jsonb;
BEGIN
  IF NOT rh_commit_staged_normalization(
    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000040',
    'e710b485a90d96b174e4aa09d874bc24f77e5722588a0a4212571a2b9dd8f042',
    'f00b322743316bc9459a25fb7aecd0690d614a3b25a83b76972c2d9d1cbfbefb',
    '28fd63073eaf26a97de86ab4dc6027e69f33217858102da590ba4c1095308d26',
    'rh-forge-events/1', 1700000000, events
  ) THEN
    RAISE EXCEPTION 'new staged normalization was not committed';
  END IF;
  IF rh_commit_staged_normalization(
    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000040',
    'e710b485a90d96b174e4aa09d874bc24f77e5722588a0a4212571a2b9dd8f042',
    'f00b322743316bc9459a25fb7aecd0690d614a3b25a83b76972c2d9d1cbfbefb',
    '28fd63073eaf26a97de86ab4dc6027e69f33217858102da590ba4c1095308d26',
      'rh-forge-events/1', 1700000000, events
  ) THEN
    RAISE EXCEPTION 'exact staged normalization replay was not absorbed';
  END IF;
  IF NOT rh_commit_staged_normalization(
    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000043',
    'c710b485a90d96b174e4aa09d874bc24f77e5722588a0a4212571a2b9dd8f042',
    'f00b322743316bc9459a25fb7aecd0690d614a3b25a83b76972c2d9d1cbfbefb', repeat('3', 64),
    'rh-forge-events/1', 1700000000, events
  ) THEN
    RAISE EXCEPTION 'same native ID in a second source scope was not committed';
  END IF;
  BEGIN
    PERFORM rh_commit_staged_normalization(
      '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000040',
      'e710b485a90d96b174e4aa09d874bc24f77e5722588a0a4212571a2b9dd8f042',
      'f00b322743316bc9459a25fb7aecd0690d614a3b25a83b76972c2d9d1cbfbefb', repeat('0', 64),
      'rh-forge-events/1', 1700000000, events
    );
    RAISE EXCEPTION 'conflicting staged normalization replay was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('different output metadata' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM rh_commit_staged_normalization(
      '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000040',
      'e710b485a90d96b174e4aa09d874bc24f77e5722588a0a4212571a2b9dd8f042',
      'f00b322743316bc9459a25fb7aecd0690d614a3b25a83b76972c2d9d1cbfbefb',
      '28fd63073eaf26a97de86ab4dc6027e69f33217858102da590ba4c1095308d26',
      'rh-forge-events/1', 1700000000, jsonb_set(events, '{0,status}', '"open"'::jsonb)
    );
    RAISE EXCEPTION 'replay with a forged matching digest and changed payload was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('replay differs from its committed canonical event payload' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM rh_commit_staged_normalization(
      '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000040',
      'a710b485a90d96b174e4aa09d874bc24f77e5722588a0a4212571a2b9dd8f042',
      'f00b322743316bc9459a25fb7aecd0690d614a3b25a83b76972c2d9d1cbfbefb', repeat('1', 64),
      'rh-forge-events/1', 1700000000,
      jsonb_set(events, '{0,staged_origin,evidence_id}', '"00000000-0000-0000-0000-000000000006"'::jsonb)
    );
    RAISE EXCEPTION 'mismatched staged evidence was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('complete evidence-bearing source page' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM rh_commit_staged_normalization(
      '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000042',
      'b710b485a90d96b174e4aa09d874bc24f77e5722588a0a4212571a2b9dd8f042',
      'f00b322743316bc9459a25fb7aecd0690d614a3b25a83b76972c2d9d1cbfbefb', repeat('2', 64),
      'rh-forge-events/1', 1700000000, events
    );
    RAISE EXCEPTION 'partial staged run was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('succeeded complete or empty run' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
  IF (SELECT count(*) FROM canonical_event WHERE source_object_id = json_build_array('staged-live-scope', 'github:101')::text) <> 1
     OR (SELECT count(DISTINCT subject_id) FROM canonical_event WHERE source_object_type = 'issue' AND source_object_id IN (json_build_array('staged-live-scope', 'github:101')::text, json_build_array('other-repository-scope', 'github:101')::text)) <> 2
     OR (SELECT count(*) FROM staged_normalization WHERE collection_run_id = '00000000-0000-0000-0000-000000000040'::uuid) <> 1 THEN
    RAISE EXCEPTION 'staged normalization replay or rejection changed committed state';
  END IF;
END $$;
SQL
echo "[migrations-live] canonical staged normalization validates source lineage and exact replay"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null
INSERT INTO collection_run (
  id, source_instance_id, capability, connector_name, connector_version,
  started_at, finished_at, status, completeness
) VALUES
  ('00000000-0000-0000-0000-000000000050', '00000000-0000-0000-0000-000000000001', 'issues', 'github', '1.0.0', '2026-01-05T00:00:00Z', '2026-01-05T00:00:10Z', 'partial', 'partial'),
  ('00000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000001', 'issues', 'github', '1.0.0', '2026-01-06T00:00:00Z', '2026-01-06T00:00:10Z', 'succeeded', 'complete'),
  ('00000000-0000-0000-0000-000000000053', '00000000-0000-0000-0000-000000000001', 'issues', 'github', '1.0.0', '2026-01-07T00:00:00Z', '2026-01-07T00:00:10Z', 'succeeded', 'complete'),
  ('00000000-0000-0000-0000-000000000054', '00000000-0000-0000-0000-000000000001', 'issues', 'github', '1.0.0', '2026-01-08T00:00:00Z', '2026-01-08T00:00:10Z', 'failed', 'unknown');
DO $$
DECLARE result jsonb;
BEGIN
  result := rh_reconcile_source_objects(
    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003',
    'issues', 'project-17', 'complete', ARRAY['old-a', 'shared'], '2026-01-04T00:00:00Z'
  );
  IF result->>'status' <> 'applied' OR result->>'absence_inferred' <> 'true' OR
     (SELECT state FROM source_object_state WHERE scope_key = 'project-17' AND native_id = 'old-a') <> 'present' THEN
    RAISE EXCEPTION 'complete current-state snapshot was not committed';
  END IF;
  result := rh_reconcile_source_objects(
    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003',
    'issues', 'project-17', 'complete', ARRAY['shared', 'old-a'], '2026-01-04T00:00:00Z'
  );
  IF result->>'status' <> 'duplicate' THEN
    RAISE EXCEPTION 'exact current-state replay was not absorbed';
  END IF;
  BEGIN
    PERFORM rh_reconcile_source_objects(
      '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003',
      'issues', 'project-17', 'complete', ARRAY['different'], '2026-01-04T00:00:00Z'
    );
    RAISE EXCEPTION 'changed current-state replay was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('replay differs from its committed reconciliation' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
  result := rh_reconcile_source_objects(
    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000050',
    'issues', 'project-17', 'partial', ARRAY['shared', 'new-b'], '2026-01-05T00:00:10Z'
  );
  IF result->>'absence_inferred' <> 'false' OR
     (SELECT state FROM source_object_state WHERE scope_key = 'project-17' AND native_id = 'old-a') <> 'unconfirmed' OR
     (SELECT state FROM source_object_state WHERE scope_key = 'project-17' AND native_id = 'shared') <> 'present' THEN
    RAISE EXCEPTION 'partial snapshot inferred absence or lost an observed ID';
  END IF;
  PERFORM rh_reconcile_source_objects(
    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000051',
    'issues', 'project-18', 'complete', ARRAY['old-a'], '2026-01-06T00:00:10Z'
  );
  PERFORM rh_reconcile_source_objects(
    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000053',
    'issues', 'project-17', 'complete', ARRAY['shared'], '2026-01-06T00:00:10Z'
  );
  IF (SELECT state FROM source_object_state WHERE scope_key = 'project-17' AND native_id = 'old-a') <> 'absent' OR
     (SELECT state FROM source_object_state WHERE scope_key = 'project-17' AND native_id = 'new-b') <> 'absent' OR
     (SELECT state FROM source_object_state WHERE scope_key = 'project-18' AND native_id = 'old-a') <> 'present' THEN
    RAISE EXCEPTION 'complete snapshot absence escaped its exact scope';
  END IF;
  PERFORM rh_reconcile_source_objects(
    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000054',
    'issues', 'project-17', 'failed', ARRAY[]::text[], '2026-01-08T00:00:10Z'
  );
  IF EXISTS (SELECT 1 FROM source_object_state WHERE scope_key = 'project-17' AND state = 'absent') THEN
    RAISE EXCEPTION 'failed acquisition retained absence inference';
  END IF;
  BEGIN
    PERFORM rh_reconcile_source_objects(
      '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000050',
      'issues', 'project-17', 'complete', ARRAY['shared'], '2026-01-08T00:00:00Z'
    );
    RAISE EXCEPTION 'partial run was accepted as complete';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('disagrees with terminal collection run' IN SQLERRM) = 0 THEN RAISE; END IF;
  END;
END $$;
SQL
echo "[migrations-live] durable current-state projection scopes absence to successful complete snapshots"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "exercise essential-work load shedding"
DO $$
DECLARE
  c record;
  result_value jsonb;
  request_value jsonb := '{"schema":"rh-query-input/1","kind":"downstream","ids":[1],"graph":{"direction":"downstream","nodes":[1],"truncated":false,"complete":true}}'::jsonb;
BEGIN
  IF NOT rh_begin_collection_run(
    '00000000-0000-0000-0000-000000000001', 'github', 'https://api.github.com',
    'public', 1, '2026-01-01T00:00:00Z',
    '00000000-0000-0000-0000-000000000080', 'issues', 'github', '1.0.0',
    NULL, NULL, '2026-01-09T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'load-shedding collection run was not started';
  END IF;
  IF NOT rh_enqueue_collection_job(
    '00000000-0000-0000-0000-000000000080',
    '00000000-0000-0000-0000-000000000081', -100,
    '2026-01-09T00:00:00Z', '2026-01-09T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'load-shedding collection job was not queued';
  END IF;
  IF NOT rh_enqueue_graph_query_job(
    '00000000-0000-0000-0000-000000000082', 'public', request_value, 2147483647,
    '2026-01-09T00:00:00Z', '2026-01-09T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'high-priority optional graph job was not queued';
  END IF;

  result_value := rh_claim_graph_query_job('optional-worker', '2026-01-09T00:00:01Z', 60, NULL);
  IF result_value->>'status' <> 'empty'
     OR result_value->>'reason' <> 'load_shed_collection_backlog'
     OR EXISTS (SELECT 1 FROM job_attempt WHERE job_id = '00000000-0000-0000-0000-000000000082') THEN
    RAISE EXCEPTION 'optional graph work was not shed behind essential collection: %', result_value;
  END IF;

  SELECT * INTO c FROM rh_claim_next_job('collection-worker', '2026-01-09T00:00:01Z', 60);
  IF c.job_id <> '00000000-0000-0000-0000-000000000081'::uuid OR c.fencing_token <> 1 THEN
    RAISE EXCEPTION 'essential collection work did not outrank high-priority maintenance: %', c;
  END IF;
  result_value := rh_claim_graph_query_job('optional-worker', '2026-01-09T00:00:02Z', 60, NULL);
  IF result_value->>'reason' <> 'load_shed_collection_backlog' THEN
    RAISE EXCEPTION 'leased essential work did not keep optional computation shed: %', result_value;
  END IF;
  IF NOT rh_finish_collection_job(
    '00000000-0000-0000-0000-000000000080', '00000000-0000-0000-0000-000000000081', c.fencing_token,
    'failed', 'failed', 'unknown', '{"issues":"unavailable"}'::jsonb,
    'failed', 'fixture_failure', '2026-01-09T00:00:03Z'
  ) THEN
    RAISE EXCEPTION 'essential collection job did not reach a terminal state';
  END IF;
  result_value := rh_claim_graph_query_job('optional-worker', '2026-01-09T00:00:04Z', 60, NULL);
  IF result_value->>'status' <> 'claimed'
     OR result_value->>'job_id' <> '00000000-0000-0000-0000-000000000082'
     OR result_value->'request' <> request_value THEN
    RAISE EXCEPTION 'optional graph work did not resume after essential work ended: %', result_value;
  END IF;
END $$;
SQL
echo "[migrations-live] collection backlog sheds optional graph work regardless of caller priority, then resumes it"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "measure high-degree graph adjacency plans"
INSERT INTO entity (id, entity_kind, visibility_scope, created_at)
SELECT ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       'package_version', 'public', '2026-01-01T00:00:00Z'
FROM generate_series(1000001, 1005002) AS n;
INSERT INTO entity (id, entity_kind, visibility_scope, created_at)
VALUES ('00000000-0000-0000-0000-000001006000', 'package_version', 'tenant-private', '2026-01-01T00:00:00Z');
INSERT INTO graph_projection
    (id, projection_kind, visibility_scope, input_cutoff, as_of, identity_revision, mapping_revision, completeness, manifest_digest)
VALUES ('00000000-0000-0000-0000-000000009001', 'dependency', 'public',
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 'identity-high-degree', 'mapping-1', 'complete', 'fixture');
INSERT INTO graph_projection
    (id, projection_kind, visibility_scope, input_cutoff, as_of, identity_revision, mapping_revision, completeness, manifest_digest)
VALUES ('00000000-0000-0000-0000-000000009002', 'dependency', 'public',
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 'identity-partial', 'mapping-1', 'partial', 'partial-fixture');
INSERT INTO projection_membership (projection_id, from_entity_id, to_entity_id, edge_kind, known_at)
SELECT '00000000-0000-0000-0000-000000009001',
       '00000000-0000-0000-0000-000001000001',
       ('00000000-0000-0000-0000-' || lpad((n + 1000001)::text, 12, '0'))::uuid,
       'depends_on', '2026-01-01T00:00:00Z'
FROM generate_series(1, 4000) AS n;
INSERT INTO projection_membership (projection_id, from_entity_id, to_entity_id, edge_kind, known_at)
SELECT '00000000-0000-0000-0000-000000009001',
       ('00000000-0000-0000-0000-' || lpad((n + 1000001)::text, 12, '0'))::uuid,
       '00000000-0000-0000-0000-000001005002',
       'depends_on', '2026-01-01T00:00:00Z'
FROM generate_series(1, 4000) AS n;
INSERT INTO projection_membership (projection_id, from_entity_id, to_entity_id, edge_kind, known_at)
SELECT '00000000-0000-0000-0000-000000009001',
       ('00000000-0000-0000-0000-' || lpad((n / 30 + 1000002)::text, 12, '0'))::uuid,
       ('00000000-0000-0000-0000-' || lpad((1004972 + n % 30)::text, 12, '0'))::uuid,
       'depends_on', '2026-01-01T00:00:00Z'
FROM generate_series(0, 149999) AS n;
INSERT INTO projection_membership (projection_id, from_entity_id, to_entity_id, edge_kind, known_at)
VALUES ('00000000-0000-0000-0000-000000009002',
        '00000000-0000-0000-0000-000001000001',
        '00000000-0000-0000-0000-000001000002',
        'depends_on', '2026-01-01T00:00:00Z');
ANALYZE projection_membership;
DO $$
DECLARE
  outgoing_plan json;
  incoming_plan json;
  batch_outgoing_plan json;
  batch_incoming_plan json;
  outgoing_count integer;
  limited_count integer;
  incoming_count integer;
  wrong_scope_count integer;
  result_edges jsonb;
  result_truncated boolean;
BEGIN
  IF (SELECT count(*) FROM projection_membership
      WHERE projection_id = '00000000-0000-0000-0000-000000009001'
        AND from_entity_id = '00000000-0000-0000-0000-000001000001'
        AND edge_kind = 'depends_on') <> 4000 THEN
    RAISE EXCEPTION 'high-degree outgoing fixture is incomplete';
  END IF;
  IF (SELECT count(*) FROM projection_membership
      WHERE projection_id = '00000000-0000-0000-0000-000000009001'
        AND to_entity_id = '00000000-0000-0000-0000-000001005002'
        AND edge_kind = 'depends_on') <> 4000 THEN
    RAISE EXCEPTION 'high-degree incoming fixture is incomplete';
  END IF;
  EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT to_entity_id FROM projection_membership WHERE projection_id = ''00000000-0000-0000-0000-000000009001'' AND from_entity_id = ''00000000-0000-0000-0000-000001000001'' AND edge_kind = ''depends_on'' AND known_at <= ''2026-01-01T00:00:00Z''::timestamptz AND (valid_from IS NULL OR valid_from <= ''2026-01-01T00:00:00Z''::timestamptz) AND (valid_to IS NULL OR valid_to > ''2026-01-01T00:00:00Z''::timestamptz)' INTO outgoing_plan;
  EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT from_entity_id FROM projection_membership WHERE projection_id = ''00000000-0000-0000-0000-000000009001'' AND to_entity_id = ''00000000-0000-0000-0000-000001005002'' AND edge_kind = ''depends_on'' AND known_at <= ''2026-01-01T00:00:00Z''::timestamptz AND (valid_from IS NULL OR valid_from <= ''2026-01-01T00:00:00Z''::timestamptz) AND (valid_to IS NULL OR valid_to > ''2026-01-01T00:00:00Z''::timestamptz)' INTO incoming_plan;
  EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) WITH candidates AS MATERIALIZED (SELECT pm.from_entity_id, pm.to_entity_id FROM projection_membership AS pm WHERE pm.projection_id = ''00000000-0000-0000-0000-000000009001'' AND pm.edge_kind = ''depends_on'' AND pm.from_entity_id = ANY (ARRAY[''00000000-0000-0000-0000-000001000001''::uuid, ''00000000-0000-0000-0000-000001000002''::uuid]) AND pm.known_at <= ''2026-01-01T00:00:00Z''::timestamptz AND (pm.valid_from IS NULL OR pm.valid_from <= ''2026-01-01T00:00:00Z''::timestamptz) AND (pm.valid_to IS NULL OR pm.valid_to > ''2026-01-01T00:00:00Z''::timestamptz) ORDER BY pm.from_entity_id, pm.to_entity_id LIMIT 10001) SELECT from_entity_id, to_entity_id FROM candidates ORDER BY from_entity_id, to_entity_id LIMIT 10000' INTO batch_outgoing_plan;
  EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) WITH candidates AS MATERIALIZED (SELECT pm.from_entity_id, pm.to_entity_id FROM projection_membership AS pm WHERE pm.projection_id = ''00000000-0000-0000-0000-000000009001'' AND pm.edge_kind = ''depends_on'' AND pm.to_entity_id = ANY (ARRAY[''00000000-0000-0000-0000-000001005002''::uuid]) AND pm.known_at <= ''2026-01-01T00:00:00Z''::timestamptz AND (pm.valid_from IS NULL OR pm.valid_from <= ''2026-01-01T00:00:00Z''::timestamptz) AND (pm.valid_to IS NULL OR pm.valid_to > ''2026-01-01T00:00:00Z''::timestamptz) ORDER BY pm.to_entity_id, pm.from_entity_id LIMIT 10001) SELECT from_entity_id, to_entity_id FROM candidates ORDER BY to_entity_id, from_entity_id LIMIT 10000' INTO batch_incoming_plan;
  IF outgoing_plan::text LIKE '%"Node Type": "Seq Scan"%'
     OR outgoing_plan::text NOT LIKE '%dependency_outgoing%'
        AND outgoing_plan::text NOT LIKE '%projection_membership_pkey%' THEN
    RAISE EXCEPTION 'outgoing high-degree query did not use an adjacency index: %', outgoing_plan;
  END IF;
  IF incoming_plan::text LIKE '%"Node Type": "Seq Scan"%'
     OR incoming_plan::text NOT LIKE '%dependency_incoming%' THEN
    RAISE EXCEPTION 'incoming high-degree query did not use its adjacency index: %', incoming_plan;
  END IF;
  IF batch_outgoing_plan::text LIKE '%"Node Type": "Seq Scan"%'
     OR batch_outgoing_plan::text NOT LIKE '%dependency_outgoing%'
        AND batch_outgoing_plan::text NOT LIKE '%projection_membership_pkey%' THEN
    RAISE EXCEPTION 'batched outgoing query did not use an adjacency index: %', batch_outgoing_plan;
  END IF;
  IF batch_incoming_plan::text LIKE '%"Node Type": "Seq Scan"%'
     OR batch_incoming_plan::text NOT LIKE '%dependency_incoming%' THEN
    RAISE EXCEPTION 'batched incoming query did not use its adjacency index: %', batch_incoming_plan;
  END IF;
  SELECT edges, truncated INTO result_edges, result_truncated
  FROM rh_projection_adjacency_batch(
    '00000000-0000-0000-0000-000000009001', 'public', 'depends_on', 'outgoing',
    ARRAY['00000000-0000-0000-0000-000001000001'::uuid,
          '00000000-0000-0000-0000-000001000002'::uuid], 10000
  );
  outgoing_count := jsonb_array_length(result_edges);
  IF outgoing_count <> 4031 OR result_truncated THEN
    RAISE EXCEPTION 'batched outgoing adjacency returned % rows (truncated=%), expected 4031 complete rows', outgoing_count, result_truncated;
  END IF;
  SELECT edges, truncated INTO result_edges, result_truncated
  FROM rh_projection_adjacency_batch(
    '00000000-0000-0000-0000-000000009001', 'public', 'depends_on', 'outgoing',
    ARRAY['00000000-0000-0000-0000-000001000001'::uuid], 37
  );
  limited_count := jsonb_array_length(result_edges);
  IF limited_count <> 37 OR NOT result_truncated THEN
    RAISE EXCEPTION 'batched adjacency limit returned % rows (truncated=%), expected 37 and truncated', limited_count, result_truncated;
  END IF;
  UPDATE projection_membership
  SET valid_from = '2025-12-01T00:00:00Z',
      valid_to = '2026-02-02T00:00:00Z',
      known_at = '2025-12-31T00:00:00Z'
  WHERE projection_id = '00000000-0000-0000-0000-000000009001'
    AND from_entity_id = '00000000-0000-0000-0000-000001000001'
    AND to_entity_id = '00000000-0000-0000-0000-000001000002'
    AND edge_kind = 'depends_on';
  UPDATE projection_membership
  SET valid_from = '2026-01-02T00:00:00Z'
  WHERE projection_id = '00000000-0000-0000-0000-000000009001'
    AND from_entity_id = '00000000-0000-0000-0000-000001000001'
    AND to_entity_id = '00000000-0000-0000-0000-000001000003'
    AND edge_kind = 'depends_on';
  UPDATE projection_membership
  SET known_at = '2026-01-02T00:00:00Z'
  WHERE projection_id = '00000000-0000-0000-0000-000000009001'
    AND from_entity_id = '00000000-0000-0000-0000-000001000001'
    AND to_entity_id = '00000000-0000-0000-0000-000001000004'
    AND edge_kind = 'depends_on';
  SELECT edges, truncated INTO result_edges, result_truncated
  FROM rh_projection_adjacency_batch(
    '00000000-0000-0000-0000-000000009001', 'public', 'depends_on', 'outgoing',
    ARRAY['00000000-0000-0000-0000-000001000001'::uuid], 10000
  );
  IF jsonb_array_length(result_edges) <> 3998
     OR result_edges @> '[{"to":"00000000-0000-0000-0000-000001000003"}]'::jsonb
     OR result_edges @> '[{"to":"00000000-0000-0000-0000-000001000004"}]'::jsonb THEN
    RAISE EXCEPTION 'batched adjacency did not enforce projection time axes: % edges', jsonb_array_length(result_edges);
  END IF;
  IF result_edges->0->>'valid_from' IS DISTINCT FROM '2025-12-01T00:00:00+00:00'
     OR result_edges->0->>'valid_to' IS DISTINCT FROM '2026-02-02T00:00:00+00:00'
     OR result_edges->0->>'known_at' IS DISTINCT FROM '2025-12-31T00:00:00+00:00' THEN
    RAISE EXCEPTION 'batched outgoing adjacency lost edge temporal metadata: %', result_edges->0;
  END IF;
  SELECT edges, truncated INTO result_edges, result_truncated
  FROM rh_projection_adjacency_batch(
    '00000000-0000-0000-0000-000000009001', 'public', 'depends_on', 'incoming',
    ARRAY['00000000-0000-0000-0000-000001005002'::uuid], 10000
  );
  incoming_count := jsonb_array_length(result_edges);
  IF incoming_count <> 4000 OR result_truncated THEN
    RAISE EXCEPTION 'batched incoming adjacency returned % rows (truncated=%), expected 4000 complete rows', incoming_count, result_truncated;
  END IF;
  IF result_edges->0->>'known_at' IS DISTINCT FROM '2026-01-01T00:00:00+00:00' THEN
    RAISE EXCEPTION 'batched incoming adjacency lost known-at metadata: %', result_edges->0;
  END IF;
  SELECT edges, truncated INTO result_edges, result_truncated
  FROM rh_projection_adjacency_batch(
    '00000000-0000-0000-0000-000000009001', 'tenant-private', 'depends_on', 'outgoing',
    ARRAY['00000000-0000-0000-0000-000001000001'::uuid], 10000
  );
  wrong_scope_count := jsonb_array_length(result_edges);
  IF wrong_scope_count <> 0 OR result_truncated THEN
    RAISE EXCEPTION 'batched adjacency crossed projection visibility scope';
  END IF;
  BEGIN
    PERFORM * FROM rh_projection_adjacency_batch(
      '00000000-0000-0000-0000-000000009002', 'public', 'depends_on', 'outgoing',
      ARRAY['00000000-0000-0000-0000-000001000001'::uuid], 10000
    );
    RAISE EXCEPTION 'incomplete projection was available for adjacency reads';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    PERFORM * FROM rh_projection_adjacency_batch(
      '00000000-0000-0000-0000-000000009001', 'public', 'depends_on', 'sideways',
      ARRAY['00000000-0000-0000-0000-000001000001'::uuid], 10000
    );
    RAISE EXCEPTION 'invalid adjacency direction was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
END $$;
SQL
echo "[migrations-live] indexed high-degree plans and bounded visibility-scoped batch adjacency pass"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "store immutable graph projection"
DO $$
DECLARE
  projection_input jsonb;
  stored boolean;
  replay_rejected boolean;
  visibility_rejected boolean;
  walk_result jsonb;
  result_edges jsonb;
  result_truncated boolean;
BEGIN
  projection_input := jsonb_build_object(
    'schema', 'rh-postgres-projection-input/1',
    'projection', jsonb_build_object(
      'id', '00000000-0000-0000-0000-000000009004',
      'projection_kind', 'dependency',
      'visibility_scope', 'public',
      'input_cutoff', '2026-01-01T00:00:00Z',
      'as_of', '2026-01-01T00:00:00Z',
      'identity_revision', 'identity-walk',
      'mapping_revision', 'mapping-1',
      'completeness', 'complete',
      'manifest_digest', repeat('a', 64)
    ),
    'edges', jsonb_build_array(
      jsonb_build_object('from_entity_id', '00000000-0000-0000-0000-000001000001', 'to_entity_id', '00000000-0000-0000-0000-000001000002', 'edge_kind', 'depends_on', 'known_at', '2026-01-01T00:00:00Z'),
      jsonb_build_object('from_entity_id', '00000000-0000-0000-0000-000001000002', 'to_entity_id', '00000000-0000-0000-0000-000001000003', 'edge_kind', 'depends_on', 'valid_from', '2025-01-01T00:00:00Z', 'valid_to', NULL, 'known_at', '2026-01-01T00:00:00Z')
    )
  );
  stored := rh_store_graph_projection(projection_input);
  IF NOT stored OR rh_store_graph_projection(projection_input) THEN
    RAISE EXCEPTION 'graph projection store did not distinguish first write from exact replay';
  END IF;
  walk_result := rh_projection_adjacency_walk(
    '00000000-0000-0000-0000-000000009004', 'public', 'depends_on', 'outgoing',
    '00000000-0000-0000-0000-000001000001', 10, 5, 10
  );
  IF walk_result->>'projection_available' <> 'true'
     OR walk_result->>'truncated' <> 'false'
     OR jsonb_array_length(walk_result->'edges') <> 2 THEN
    RAISE EXCEPTION 'one-call projection walk did not return the full two-edge chain: %', walk_result;
  END IF;
  walk_result := rh_projection_adjacency_walk(
    '00000000-0000-0000-0000-000000009004', 'public', 'depends_on', 'outgoing',
    '00000000-0000-0000-0000-000001000001', 1, 5, 10
  );
  IF walk_result->>'truncated' <> 'true' OR jsonb_array_length(walk_result->'edges') <> 2 THEN
    RAISE EXCEPTION 'node-capped projection walk lost its boundary probe: %', walk_result;
  END IF;
  walk_result := rh_projection_adjacency_walk(
    '00000000-0000-0000-0000-000000009004', 'public', 'depends_on', 'outgoing',
    '00000000-0000-0000-0000-000001000001', 10, 1, 10
  );
  IF walk_result->>'truncated' <> 'true' OR jsonb_array_length(walk_result->'edges') <> 2 THEN
    RAISE EXCEPTION 'depth-limited projection walk lost its boundary edge or truncation: %', walk_result;
  END IF;
  SELECT edges, truncated INTO result_edges, result_truncated
  FROM rh_projection_adjacency_batch(
    '00000000-0000-0000-0000-000000009004', 'public', 'depends_on', 'outgoing',
    ARRAY['00000000-0000-0000-0000-000001000001'::uuid], 10
  );
  IF jsonb_array_length(result_edges) <> 1 OR result_truncated
     OR result_edges->0->>'to' <> '00000000-0000-0000-0000-000001000002' THEN
    RAISE EXCEPTION 'stored projection is not available to the bounded adjacency query: %', result_edges;
  END IF;
  replay_rejected := false;
  BEGIN
    PERFORM rh_store_graph_projection(jsonb_set(projection_input, '{edges,0,known_at}', '"2026-01-02T00:00:00Z"'));
  EXCEPTION WHEN raise_exception THEN
    replay_rejected := true;
  END;
  IF NOT replay_rejected THEN RAISE EXCEPTION 'altered graph projection replay was accepted'; END IF;
  projection_input := jsonb_set(projection_input, '{projection,id}', to_jsonb('00000000-0000-0000-0000-000000009003'::text));
  projection_input := jsonb_set(projection_input, '{edges,0,to_entity_id}', to_jsonb('00000000-0000-0000-0000-000001006000'::text));
  visibility_rejected := false;
  BEGIN
    PERFORM rh_store_graph_projection(projection_input);
  EXCEPTION WHEN insufficient_privilege THEN
    visibility_rejected := true;
  END;
  IF NOT visibility_rejected THEN RAISE EXCEPTION 'graph projection accepted an edge across visibility scopes'; END IF;
END $$;
SQL
echo "[migrations-live] immutable projection storage replays exactly, fences visibility, and feeds bounded adjacency reads"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "stage immutable graph projection chunk"
DO $$
DECLARE
  chunk_input jsonb;
  edges_input jsonb;
  first_edges jsonb;
  last_edges jsonb;
  stage_status text;
  replay_rejected boolean;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'from_entity_id', '00000000-0000-0000-0000-' || lpad((1000001 + ((edge_number - 1) / 100))::text, 12, '0'),
    'to_entity_id', '00000000-0000-0000-0000-' || lpad((1000201 + ((edge_number - 1) % 100))::text, 12, '0'),
    'edge_kind', 'depends_on',
    'known_at', '2026-01-01T00:00:00Z'
  ) ORDER BY edge_number)
  INTO edges_input
  FROM generate_series(1, 10001) AS edge_number;
  SELECT jsonb_agg(edge.value ORDER BY edge.ordinality) INTO first_edges
  FROM jsonb_array_elements(edges_input) WITH ORDINALITY AS edge(value, ordinality)
  WHERE edge.ordinality <= 10000;
  SELECT jsonb_agg(edge.value ORDER BY edge.ordinality) INTO last_edges
  FROM jsonb_array_elements(edges_input) WITH ORDINALITY AS edge(value, ordinality)
  WHERE edge.ordinality > 10000;
  chunk_input := jsonb_build_object(
    'schema', 'rh-postgres-projection-chunk/1',
    'projection', jsonb_build_object(
      'id', '00000000-0000-0000-0000-000000009005',
      'projection_kind', 'dependency',
      'visibility_scope', 'public',
      'input_cutoff', '2026-01-01T00:00:00Z',
      'as_of', '2026-01-01T00:00:00Z',
      'identity_revision', 'identity-chunk',
      'mapping_revision', 'mapping-1',
      'completeness', 'complete',
      'manifest_digest', repeat('b', 64)
    ),
    'expected_edge_count', 10001,
    'chunk_index', 0,
    'chunk_count', 2,
    'edges', first_edges
  );
  stage_status := rh_stage_graph_projection_chunk(chunk_input);
  IF stage_status <> 'staged' OR EXISTS (SELECT 1 FROM graph_projection WHERE id = '00000000-0000-0000-0000-000000009005') THEN
    RAISE EXCEPTION 'incomplete projection became visible before its final chunk: %', stage_status;
  END IF;
  chunk_input := jsonb_set(chunk_input, '{chunk_index}', '1'::jsonb);
  chunk_input := jsonb_set(chunk_input, '{edges}', last_edges);
  stage_status := rh_stage_graph_projection_chunk(chunk_input);
  IF stage_status <> 'stored' OR rh_stage_graph_projection_chunk(
    jsonb_set(jsonb_set(chunk_input, '{chunk_index}', '0'::jsonb), '{edges}', first_edges)
  ) <> 'replay' THEN
    RAISE EXCEPTION 'multi-chunk projection did not publish and replay: %', stage_status;
  END IF;
  IF (SELECT count(*) FROM projection_membership WHERE projection_id = '00000000-0000-0000-0000-000000009005') <> 10001 THEN
    RAISE EXCEPTION 'published chunk projection has the wrong membership count';
  END IF;
  replay_rejected := false;
  BEGIN
    PERFORM rh_stage_graph_projection_chunk(jsonb_set(
      jsonb_set(jsonb_set(chunk_input, '{chunk_index}', '0'::jsonb), '{edges}', first_edges),
      '{edges,0,known_at}', '"2026-01-02T00:00:00Z"'::jsonb
    ));
  EXCEPTION WHEN raise_exception THEN
    replay_rejected := true;
  END;
  IF NOT replay_rejected THEN RAISE EXCEPTION 'altered chunk replay was accepted'; END IF;
END $$;
SQL
echo "[migrations-live] incomplete chunk sets stay invisible; final publication, exact replay, and altered replay are checked"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "durable operator source stop lifecycle"
DO $$
DECLARE
  claimed record;
BEGIN
  IF NOT rh_begin_collection_run(
    '00000000-0000-0000-0000-000000000201', 'fixture', 'https://example.org/stopped', 'public', 1,
    '2026-01-09T00:00:00Z', '00000000-0000-0000-0000-000000000202', 'issues', 'fixture', '1',
    NULL, NULL, '2026-01-09T00:00:00Z'
  ) THEN RAISE EXCEPTION 'initial stop-test run was not created'; END IF;
  IF NOT rh_begin_collection_run(
    '00000000-0000-0000-0000-000000000201', 'fixture', 'https://example.org/stopped', 'public', 1,
    '2026-01-09T00:00:00Z', '00000000-0000-0000-0000-000000000203', 'issues', 'fixture', '1',
    NULL, NULL, '2026-01-09T00:00:00Z'
  ) THEN RAISE EXCEPTION 'queued stop-test run was not created'; END IF;
  IF NOT rh_enqueue_collection_job('00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000204', 1, '2026-01-09T00:00:00Z', '2026-01-09T00:00:00Z')
     OR NOT rh_enqueue_collection_job('00000000-0000-0000-0000-000000000203', '00000000-0000-0000-0000-000000000205', 1, '2026-01-09T00:00:00Z', '2026-01-09T00:00:00Z') THEN
    RAISE EXCEPTION 'stop-test jobs were not enqueued';
  END IF;
  SELECT * INTO claimed FROM rh_claim_next_job('stop-test-worker', '2026-01-09T00:00:01Z', 60, '00000000-0000-0000-0000-000000000204');
  IF claimed.job_id <> '00000000-0000-0000-0000-000000000204'::uuid OR claimed.fencing_token <> 1 THEN
    RAISE EXCEPTION 'stop-test job was not leased';
  END IF;
  IF NOT rh_request_source_stop('00000000-0000-0000-0000-000000000201', 'operator@example.org', 'Requested stop', '2026-01-10T00:00:00Z')
     OR rh_request_source_stop('00000000-0000-0000-0000-000000000201', 'operator@example.org', 'Repeated stop', '2026-01-10T00:00:01Z') THEN
    RAISE EXCEPTION 'source stop did not record once';
  END IF;
  IF (SELECT count(*) FROM job WHERE source_instance_id = '00000000-0000-0000-0000-000000000201' AND state = 'canceled') <> 2
     OR (SELECT fencing_token FROM job WHERE id = '00000000-0000-0000-0000-000000000204') <> 2
     OR (SELECT outcome FROM job_attempt WHERE job_id = '00000000-0000-0000-0000-000000000204') <> 'operator_stopped'
     OR rh_heartbeat_job('00000000-0000-0000-0000-000000000204', 1, '2026-01-10T00:00:01Z', 60) THEN
    RAISE EXCEPTION 'source stop failed to cancel and fence collection work';
  END IF;
  BEGIN
    PERFORM rh_enqueue_collection_job('00000000-0000-0000-0000-000000000203', '00000000-0000-0000-0000-000000000208', 1, '2026-01-10T00:00:00Z', '2026-01-10T00:00:00Z');
    RAISE EXCEPTION 'stopped source accepted an enqueue';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'stopped source accepted an enqueue' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM rh_begin_collection_run(
      '00000000-0000-0000-0000-000000000201', 'fixture', 'https://example.org/stopped', 'public', 1,
      '2026-01-09T00:00:00Z', '00000000-0000-0000-0000-000000000206', 'issues', 'fixture', '1',
      NULL, NULL, '2026-01-10T00:00:00Z'
    );
    RAISE EXCEPTION 'stopped source accepted a new run';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'stopped source accepted a new run' THEN RAISE; END IF;
  END;
  IF NOT rh_resolve_source_stop('00000000-0000-0000-0000-000000000201', 'reviewer@example.org', 'Stop withdrawn', '2026-01-11T00:00:00Z')
     OR rh_resolve_source_stop('00000000-0000-0000-0000-000000000201', 'reviewer@example.org', 'Repeated resume', '2026-01-11T00:00:01Z') THEN
    RAISE EXCEPTION 'source stop resolution did not record once';
  END IF;
  IF (SELECT count(*) FROM source_stop_request WHERE source_instance_id = '00000000-0000-0000-0000-000000000201' AND resolved_at IS NOT NULL) <> 1
     OR (SELECT state FROM job WHERE id = '00000000-0000-0000-0000-000000000204') <> 'canceled'
     OR NOT rh_begin_collection_run(
       '00000000-0000-0000-0000-000000000201', 'fixture', 'https://example.org/stopped', 'public', 1,
       '2026-01-09T00:00:00Z', '00000000-0000-0000-0000-000000000206', 'issues', 'fixture', '1',
       NULL, NULL, '2026-01-11T00:00:00Z'
     ) THEN
    RAISE EXCEPTION 'resume did not preserve the audit or permit a fresh run';
  END IF;
END $$;
SQL
echo "[migrations-live] audited source stop cancels/fences work, blocks new runs/jobs, and requires a fresh run after resume"

echo "[migrations-live] source/run, staged normalization, enqueue/claim/finish, lease-reclaim audit, stale/expired fencing, rollback, and crash-recovery boundaries OK"
echo "test_migrations_live OK"
