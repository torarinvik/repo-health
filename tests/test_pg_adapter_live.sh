#!/usr/bin/env bash
# Optional adapter-to-PostgreSQL test. It needs Docker and a local libpq library.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${RH_PG_IMAGE:-postgres:16-alpine}"
CONTAINER="rh-pg-adapter-${$}"
TMP_DIR="/tmp/rh-pg-adapter-live-${$}"

if [[ "${RH_PG_ADAPTER:-0}" != "1" ]]; then
  echo "[pg-adapter-live] skipped (RH_PG_ADAPTER!=1)"
  exit 0
fi

fail() { echo "[pg-adapter-live] FAIL: $1" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || fail "docker is required"
docker info >/dev/null 2>&1 || fail "docker daemon is unavailable"
docker image inspect "$IMAGE" >/dev/null 2>&1 || fail "image is unavailable: $IMAGE"
cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; rm -rf "$TMP_DIR"; }
trap cleanup EXIT

bash "$ROOT/tools/build.sh" >/dev/null
docker run --rm -d --name "$CONTAINER" -e POSTGRES_PASSWORD=repo-health-test -e POSTGRES_DB=repo_health -p 127.0.0.1::5432 "$IMAGE" >/dev/null || fail "start PostgreSQL"
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
[[ "$ready_checks" -ge 3 ]] || fail "PostgreSQL did not become ready"
docker exec "$CONTAINER" pg_isready -U postgres -d repo_health >/dev/null 2>&1 || fail "PostgreSQL stopped after becoming ready"
docker cp "$ROOT/db/migrations/001_initial.sql" "$CONTAINER:/tmp/001_initial.sql" >/dev/null || fail "copy migration"
docker exec "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health -f /tmp/001_initial.sql >/dev/null || fail "apply migration"

PORT="$(docker port "$CONTAINER" 5432/tcp | sed 's/.*://')"
[[ -n "$PORT" ]] || fail "published PostgreSQL port is missing"
CONNINFO="host=127.0.0.1 port=$PORT dbname=repo_health user=postgres password=repo-health-test sslmode=disable"
mkdir -p "$TMP_DIR/evidence"
run_cli() {
  local input="$1" output="$2"
  local safe_input="$TMP_DIR/command.json"
  cp "$input" "$safe_input" || fail "copy command fixture"
  if [[ -n "${RH_LIBPQ_PATH:-}" ]]; then
    RH_DATABASE_URL="$CONNINFO" RH_EVIDENCE_ROOT="$TMP_DIR/evidence" RH_LIBPQ_PATH="$RH_LIBPQ_PATH" \
      "$ROOT/build/rh_cli" postgres --input "$safe_input" --out "$output" >/dev/null
  else
    env -u RH_LIBPQ_PATH RH_DATABASE_URL="$CONNINFO" RH_EVIDENCE_ROOT="$TMP_DIR/evidence" \
      "$ROOT/build/rh_cli" postgres --input "$safe_input" --out "$output" >/dev/null
  fi
}
run_postgres_ingest() {
  local output="$1"
  local safe_input="$TMP_DIR/ingest-input.json"
  cp "$ROOT/fixtures/postgres/ingest-input.json" "$safe_input" || fail "copy normalized ingest fixture"
  if [[ -n "${RH_LIBPQ_PATH:-}" ]]; then
    RH_DATABASE_URL="$CONNINFO" RH_LIBPQ_PATH="$RH_LIBPQ_PATH" \
      "$ROOT/build/rh_cli" ingest --postgres --input "$safe_input" --out "$output" >/dev/null
  else
    env -u RH_LIBPQ_PATH RH_DATABASE_URL="$CONNINFO" \
      "$ROOT/build/rh_cli" ingest --postgres --input "$safe_input" --out "$output" >/dev/null
  fi
}
run_cli "$ROOT/fixtures/postgres/begin-collection-run-command.json" "$TMP_DIR/run-started.json" || fail "CLI source and run registration"
run_cli "$ROOT/fixtures/postgres/begin-collection-run-command.json" "$TMP_DIR/run-duplicate.json" || fail "CLI source and run replay"
python3 - "$TMP_DIR" <<'PY'
import json, os, sys
root = sys.argv[1]
assert json.load(open(os.path.join(root, "run-started.json")))["status"] == "started"
assert json.load(open(os.path.join(root, "run-duplicate.json")))["status"] == "duplicate"
PY

docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "seed collection run"
INSERT INTO job (id, source_instance_id, kind, visibility_scope, state, priority, next_attempt_at, attempt_count, fencing_token, worker_id, lease_expires_at, created_at, input_manifest)
VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'maintenance', 'public', 'running', 1, '2026-01-01T00:00:00Z', 1, 4, 'worker-a', '2026-09-22T00:00:00Z', '2026-01-01T00:00:00Z', '{}');
INSERT INTO job (id, source_instance_id, kind, visibility_scope, state, priority, next_attempt_at, attempt_count, fencing_token, worker_id, lease_expires_at, created_at, input_manifest)
VALUES ('00000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000001', 'collection', 'public', 'running', 1, '2026-01-01T00:00:00Z', 1, 1, 'worker-page', '2026-09-22T00:00:00Z', '2026-01-01T00:00:00Z', '{"collection_run_id":"00000000-0000-0000-0000-000000000003"}');
INSERT INTO job (id, source_instance_id, kind, visibility_scope, state, priority, next_attempt_at, created_at, input_manifest)
VALUES ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'collection', 'public', 'queued', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '{"collection_run_id":"00000000-0000-0000-0000-000000000003"}');
SQL
if [[ -n "${RH_LIBPQ_PATH:-}" ]]; then
  RH_TEST_PG_CONNINFO="host=127.0.0.1 port=$PORT dbname=repo_health user=postgres password=repo-health-test sslmode=disable" RH_LIBPQ_PATH="$RH_LIBPQ_PATH" "$ROOT/build/test_postgres_live" || fail "parameterized page commit and duplicate replay"
else
  env -u RH_LIBPQ_PATH RH_TEST_PG_CONNINFO="host=127.0.0.1 port=$PORT dbname=repo_health user=postgres password=repo-health-test sslmode=disable" "$ROOT/build/test_postgres_live" || fail "libpq unavailable; set RH_LIBPQ_PATH to its library"
fi

printf 'hello evidence\n' > "$TMP_DIR/evidence-source.txt"
stored_name="$("$ROOT/build/rh_cli" store put --root "$TMP_DIR/evidence" --file "$TMP_DIR/evidence-source.txt" | awk '{print $3}')"
[[ "$stored_name" == "f5e19178d3ff184e" ]] || fail "content-addressed evidence fixture changed"
run_cli "$ROOT/fixtures/postgres/register-evidence-command.json" "$TMP_DIR/evidence-registered.json" || fail "CLI evidence registration"
run_cli "$ROOT/fixtures/postgres/register-evidence-command.json" "$TMP_DIR/evidence-duplicate.json" || fail "CLI evidence replay"
run_cli "$ROOT/fixtures/postgres/evidence-references-command.json" "$TMP_DIR/evidence-references.json" || fail "CLI evidence reference discovery"
docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "seed malformed storage key"
INSERT INTO evidence_object (
    id, visibility_scope, digest_algorithm, digest_value, media_type,
    byte_length, storage_key, retention_class, transformation_kind, created_at
) VALUES (
    '00000000-0000-0000-0000-000000000010', 'public', 'sha256', repeat('b', 64),
    'application/json', 18, 'malformed-storage-key', 'standard', 'captured', '2026-01-01T00:00:00Z'
);
SQL
run_cli "$ROOT/fixtures/postgres/evidence-references-command.json" "$TMP_DIR/evidence-references-invalid.json" || fail "CLI malformed-key reference discovery"
run_cli "$ROOT/fixtures/postgres/page-events-evidence-command.json" "$TMP_DIR/events-committed.json" || fail "CLI event page with registered evidence"
run_cli "$ROOT/fixtures/postgres/page-events-evidence-command.json" "$TMP_DIR/events-duplicate.json" || fail "CLI event page replay"
python3 - "$TMP_DIR" <<'PY'
import json, os, sys
root = sys.argv[1]
def read(name):
    with open(os.path.join(root, name)) as stream:
        return json.load(stream)
assert read("evidence-registered.json")["status"] == "registered"
assert read("evidence-duplicate.json")["status"] == "duplicate"
references = read("evidence-references.json")
assert references == {
    "schema": "rh-postgres-result/1", "operation": "evidence_references", "status": "listed",
    "reference_snapshot": {
        "storage_keys": ["fnv1a64:f5e19178d3ff184e"], "invalid_count": 0,
        "truncated": False, "count": 1,
    },
}, references
invalid_references = read("evidence-references-invalid.json")["reference_snapshot"]
assert invalid_references == {
    "storage_keys": ["fnv1a64:f5e19178d3ff184e"], "invalid_count": 1,
    "truncated": False, "count": 1,
}, invalid_references
assert read("events-committed.json")["status"] == "committed"
assert read("events-duplicate.json")["status"] == "duplicate"
PY
event_count="$(docker exec "$CONTAINER" psql -At -U postgres -d repo_health -c "SELECT count(*) FROM canonical_event WHERE source_object_id = 'issue:live' AND evidence_id = '00000000-0000-0000-0000-000000000006'::uuid AND actor_account_id = '00000000-0000-0000-0000-000000000007'::uuid")"
actor_count="$(docker exec "$CONTAINER" psql -At -U postgres -d repo_health -c "SELECT count(*) FROM account WHERE source_native_id = 'alice'")"
[[ "$event_count" == "1" && "$actor_count" == "1" ]] || fail "registered evidence event and actor did not commit exactly once"

run_cli "$ROOT/fixtures/postgres/enqueue-collection-job-command.json" "$TMP_DIR/job-enqueued.json" || fail "enqueue collection job through libpq adapter"
run_cli "$ROOT/fixtures/postgres/enqueue-collection-job-command.json" "$TMP_DIR/job-duplicate.json" || fail "replay collection job through libpq adapter"
run_cli "$ROOT/fixtures/postgres/claim-collection-job-command.json" "$TMP_DIR/job-claimed.json" || fail "targeted claim of enqueued collection job through libpq adapter"
run_cli "$ROOT/fixtures/postgres/finish-enqueued-collection-job-command.json" "$TMP_DIR/job-finished.json" || fail "finish enqueued collection run through libpq adapter"
python3 - "$TMP_DIR" <<'PY'
import json, os, sys
root = sys.argv[1]
def read(name):
    with open(os.path.join(root, name)) as stream:
        return json.load(stream)
assert read("job-enqueued.json")["status"] == "enqueued"
assert read("job-duplicate.json")["status"] == "duplicate"
claimed = read("job-claimed.json")
assert claimed["job_id"] == "00000000-0000-0000-0000-00000000000a" and claimed["fencing_token"] == 1, claimed
assert read("job-finished.json")["status"] == "applied"
PY
run_state="$(docker exec "$CONTAINER" psql -At -U postgres -d repo_health -c "SELECT r.status || ':' || j.state || ':' || a.outcome FROM collection_run r JOIN job j ON j.input_manifest->>'collection_run_id' = r.id::text JOIN job_attempt a ON a.job_id = j.id WHERE r.id = '00000000-0000-0000-0000-000000000003'::uuid AND j.id = '00000000-0000-0000-0000-00000000000a'::uuid AND a.fencing_token = 1")"
[[ "$run_state" == "succeeded:succeeded:ok" ]] || fail "enqueued run, job, and attempt did not finish together: $run_state"
run_postgres_ingest "$TMP_DIR/ingest-result.json" || fail "normalized PostgreSQL ingest pipeline"
python3 - "$TMP_DIR/ingest-result.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["status"] == "succeeded", result
assert result["pages"] == [{"page_number": 0, "status": "committed"}], result
assert result["fencing_token"] == 1, result
PY
ingest_state="$(docker exec "$CONTAINER" psql -At -U postgres -d repo_health -c "SELECT r.status || ':' || j.state || ':' || a.outcome FROM collection_run r JOIN job j ON j.input_manifest->>'collection_run_id' = r.id::text JOIN job_attempt a ON a.job_id = j.id WHERE r.id = '00000000-0000-0000-0000-000000000020'::uuid AND j.id = '00000000-0000-0000-0000-000000000021'::uuid AND a.fencing_token = 1")"
[[ "$ingest_state" == "succeeded:succeeded:ok" ]] || fail "normalized ingest did not finalize the run, job, and attempt atomically: $ingest_state"
ingest_event_count="$(docker exec "$CONTAINER" psql -At -U postgres -d repo_health -c "SELECT count(*) FROM canonical_event WHERE source_object_id = 'issue:postgres-ingest-live' AND evidence_id = '00000000-0000-0000-0000-000000000006'::uuid")"
[[ "$ingest_event_count" == "1" ]] || fail "normalized ingest event did not commit exactly once"
echo "[pg-adapter-live] source/run setup, enqueue/claim/finish, page replay, evidence reference discovery, actor linkage, and end-to-end normalized PostgreSQL ingest OK"
