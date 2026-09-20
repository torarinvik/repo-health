#!/usr/bin/env bash
# Optional adapter-to-PostgreSQL test. It needs Docker and a local libpq dylib.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${RH_PG_IMAGE:-postgres:16-alpine}"
CONTAINER="rh-pg-adapter-${$}"

if [[ "${RH_PG_ADAPTER:-0}" != "1" ]]; then
  echo "[pg-adapter-live] skipped (RH_PG_ADAPTER!=1)"
  exit 0
fi

fail() { echo "[pg-adapter-live] FAIL: $1" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || fail "docker is required"
docker info >/dev/null 2>&1 || fail "docker daemon is unavailable"
docker image inspect "$IMAGE" >/dev/null 2>&1 || fail "image is unavailable: $IMAGE"
cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

bash "$ROOT/tools/build.sh" >/dev/null
docker run --rm -d --name "$CONTAINER" -e POSTGRES_PASSWORD=repo-health-test -e POSTGRES_DB=repo_health -p 127.0.0.1::5432 "$IMAGE" >/dev/null || fail "start PostgreSQL"
for _ in $(seq 1 60); do
  docker exec "$CONTAINER" pg_isready -U postgres -d repo_health >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$CONTAINER" pg_isready -U postgres -d repo_health >/dev/null 2>&1 || fail "PostgreSQL did not become ready"
docker cp "$ROOT/db/migrations/001_initial.sql" "$CONTAINER:/tmp/001_initial.sql" >/dev/null || fail "copy migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/001_initial.sql >/dev/null || fail "apply migration"
docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "seed collection run"
INSERT INTO source_instance (id, kind, base_url, visibility_scope, configuration_revision, created_at)
VALUES ('00000000-0000-0000-0000-000000000001', 'github', 'https://api.github.com', 'public', 1, '2026-01-01T00:00:00Z');
INSERT INTO collection_run (id, source_instance_id, capability, connector_name, connector_version, started_at, status, completeness)
VALUES ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'issues', 'github', '1.0.0', '2026-01-01T00:00:00Z', 'running', 'unknown');
INSERT INTO job (id, source_instance_id, kind, visibility_scope, state, priority, next_attempt_at, attempt_count, fencing_token, worker_id, lease_expires_at, created_at)
VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'collection', 'public', 'running', 1, '2026-01-01T00:00:00Z', 1, 4, 'worker-a', '2026-09-22T00:00:00Z', '2026-01-01T00:00:00Z');
INSERT INTO job (id, source_instance_id, kind, visibility_scope, state, priority, next_attempt_at, created_at)
VALUES ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'collection', 'public', 'queued', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
SQL
PORT="$(docker port "$CONTAINER" 5432/tcp | sed 's/.*://')"
[[ -n "$PORT" ]] || fail "published PostgreSQL port is missing"
if [[ -n "${RH_LIBPQ_PATH:-}" ]]; then
  RH_TEST_PG_CONNINFO="host=127.0.0.1 port=$PORT dbname=repo_health user=postgres password=repo-health-test sslmode=disable" RH_LIBPQ_PATH="$RH_LIBPQ_PATH" "$ROOT/build/test_postgres_live" || fail "parameterized page commit and duplicate replay"
else
  env -u RH_LIBPQ_PATH RH_TEST_PG_CONNINFO="host=127.0.0.1 port=$PORT dbname=repo_health user=postgres password=repo-health-test sslmode=disable" "$ROOT/build/test_postgres_live" || fail "libpq unavailable; set RH_LIBPQ_PATH to its library"
fi
echo "[pg-adapter-live] page replay, fenced job lifecycle, and empty-queue claim OK"
