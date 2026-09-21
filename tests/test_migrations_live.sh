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

echo "[migrations-live] source/run, staged normalization, enqueue/claim/finish, lease-reclaim audit, stale/expired fencing, rollback, and crash-recovery boundaries OK"
echo "test_migrations_live OK"
