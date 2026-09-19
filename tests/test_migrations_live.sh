#!/usr/bin/env bash
# tests/test_migrations_live.sh — M02-01 live PostgreSQL rehearsal.
# Applies the checked-in migration to an ephemeral PostgreSQL container and
# exercises the fenced job and collection cursor functions. The default local
# suite remains dependency-free; set RH_PG_MIGRATION=1 to run this gate.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${RH_PG_IMAGE:-postgres:16-alpine}"
CONTAINER="rh-migration-${$}"

fail() { echo "[migrations-live] FAIL: $1" >&2; exit 1; }
cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

command -v docker >/dev/null 2>&1 || fail "docker is required"
docker info >/dev/null 2>&1 || fail "docker daemon is unavailable"
docker image inspect "$IMAGE" >/dev/null 2>&1 || fail "image is unavailable: $IMAGE"

echo "[migrations-live] start $IMAGE"
docker run --rm -d --name "$CONTAINER" -e POSTGRES_PASSWORD=repo-health-test -e POSTGRES_DB=repo_health "$IMAGE" >/dev/null || fail "container start"
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready -U postgres -d repo_health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker exec "$CONTAINER" pg_isready -U postgres -d repo_health >/dev/null 2>&1 || fail "postgres did not become ready"

docker cp "$ROOT/db/migrations/001_initial.sql" "$CONTAINER:/tmp/001_initial.sql" || fail "copy migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/001_initial.sql >/dev/null || fail "apply migration"

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null
INSERT INTO source_instance (id, kind, base_url, visibility_scope, configuration_revision, created_at)
VALUES ('00000000-0000-0000-0000-000000000001', 'github', 'https://api.github.com', 'public', 1, '2026-01-01T00:00:00Z');
INSERT INTO job (id, source_instance_id, kind, visibility_scope, state, priority, next_attempt_at, created_at)
VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'collection', 'public', 'queued', 10, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
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
  IF NOT rh_finish_job(c.job_id, c.fencing_token, 'succeeded', '2026-01-01T00:00:20Z', 'ok', NULL) THEN
    RAISE EXCEPTION 'current finish was refused';
  END IF;
END $$;

INSERT INTO collection_run (id, source_instance_id, capability, connector_name, connector_version, started_at, status, completeness)
VALUES ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'issues', 'github', '1.0.0', '2026-01-01T00:00:00Z', 'running', 'unknown');
DO $$
BEGIN
  BEGIN
    PERFORM rh_commit_collection_page('00000000-0000-0000-0000-000000000003', 0, 'scope-a', '{}'::jsonb, '{"page":1}'::jsonb, 'partial', 1, NULL, '2026-01-01T00:01:00Z');
    RAISE EXCEPTION 'partial page advanced cursor';
  EXCEPTION WHEN OTHERS THEN
    IF POSITION('partial page cannot advance' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
  IF NOT rh_commit_collection_page('00000000-0000-0000-0000-000000000003', 0, 'scope-a', '{}'::jsonb, '{"page":1}'::jsonb, 'complete', 1, NULL, '2026-01-01T00:01:00Z') THEN
    RAISE EXCEPTION 'complete page was refused';
  END IF;
  IF rh_commit_collection_page('00000000-0000-0000-0000-000000000003', 0, 'scope-a', '{}'::jsonb, '{"page":1}'::jsonb, 'complete', 1, NULL, '2026-01-01T00:02:00Z') THEN
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
SQL

echo "test_migrations_live OK"
