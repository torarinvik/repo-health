#!/usr/bin/env bash
# tests/test_postgres_cli.sh — RH_DATABASE_URL-backed PostgreSQL command path.
# Contracts: rh-postgres-command/1 -> rh-postgres-result/1.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-postgres-cli"

fail() { echo "[postgres-cli] FAIL: $1" >&2; exit 1; }

echo "[postgres-cli] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
command -v cc >/dev/null 2>&1 || fail "C compiler unavailable for libpq ABI fixture"
rm -rf "$T"
mkdir -p "$T"
if [[ "$(uname -s)" == "Darwin" ]]; then
  cc -dynamiclib -o "$T/libpq.dylib" "$ROOT/tests/fixtures/fake_libpq.c" || fail "compile fake libpq"
  LIBPQ="$T/libpq.dylib"
else
  cc -shared -fPIC -o "$T/libpq.so" "$ROOT/tests/fixtures/fake_libpq.c" || fail "compile fake libpq"
  LIBPQ="$T/libpq.so"
fi

run_ok() {
  local operation="$1" mode="$2" name="$3"
  cp "$ROOT/fixtures/postgres/$name-command.json" "$T/$name-command.json"
  RH_DATABASE_URL='host=fake dbname=repo_health password=never-emit-this' \
    RH_LIBPQ_PATH="$LIBPQ" RH_FAKE_PG_OPERATION="$operation" RH_FAKE_PG_EXPECT="$mode" \
    "$ROOT/build/rh_cli" postgres --input "$T/$name-command.json" --out "$T/$name-$mode.json" >/dev/null \
    || fail "$operation $mode command"
}

run_ok begin_run committed begin-collection-run
run_ok begin_run duplicate begin-collection-run
run_ok page committed page-commit
run_ok page duplicate page-commit
run_ok page_events committed page-events
run_ok page_events duplicate page-events
run_ok page_events_subjects committed page-events-evidence
run_ok page_events_subjects duplicate page-events-evidence
run_ok heartbeat committed heartbeat-job
run_ok heartbeat duplicate heartbeat-job
run_ok finish committed finish-job
run_ok finish duplicate finish-job
run_ok finish_collection committed finish-collection-job
run_ok finish_collection duplicate finish-collection-job
run_ok claim committed claim-job
run_ok claim duplicate claim-job

mkdir -p "$T/evidence"
printf 'hello evidence\n' > "$T/evidence-source.txt"
stored_name="$("$ROOT/build/rh_cli" store put --root "$T/evidence" --file "$T/evidence-source.txt" | awk '{print $3}')"
[[ "$stored_name" == "f5e19178d3ff184e" ]] || fail "content-addressed evidence fixture changed"
cp "$ROOT/fixtures/postgres/register-evidence-command.json" "$T/register-evidence-command.json"
for mode in committed duplicate; do
  RH_DATABASE_URL='host=fake dbname=repo_health password=never-emit-this' \
    RH_EVIDENCE_ROOT="$T/evidence" RH_LIBPQ_PATH="$LIBPQ" \
    RH_FAKE_PG_OPERATION=evidence RH_FAKE_PG_EXPECT="$mode" \
    "$ROOT/build/rh_cli" postgres --input "$T/register-evidence-command.json" \
      --out "$T/register-evidence-$mode.json" >/dev/null \
    || fail "register evidence $mode command"
done

python3 - "$T" <<'PY'
import json, os, sys
root = sys.argv[1]
def read(name):
    with open(os.path.join(root, name)) as f:
        return json.load(f)
assert read("begin-collection-run-committed.json")["status"] == "started"
assert read("begin-collection-run-duplicate.json")["status"] == "duplicate"
assert read("page-commit-committed.json")["status"] == "committed"
assert read("page-commit-duplicate.json")["status"] == "duplicate"
assert read("page-events-committed.json")["operation"] == "page_commit_events"
assert read("page-events-committed.json")["status"] == "committed"
assert read("page-events-duplicate.json")["status"] == "duplicate"
assert read("page-events-evidence-committed.json")["status"] == "committed"
assert read("page-events-evidence-duplicate.json")["status"] == "duplicate"
assert read("heartbeat-job-committed.json")["status"] == "applied"
assert read("heartbeat-job-duplicate.json")["status"] == "fenced"
assert read("finish-job-committed.json")["status"] == "applied"
assert read("finish-job-duplicate.json")["status"] == "fenced"
assert read("finish-collection-job-committed.json")["status"] == "applied"
assert read("finish-collection-job-duplicate.json")["status"] == "fenced"
claim = read("claim-job-committed.json")
assert claim["status"] == "claimed" and claim["fencing_token"] == 5, claim
assert claim["job_id"] == "00000000-0000-0000-0000-000000000004", claim
assert claim["lease_expires_at"] == "2026-01-01 00:02:00+00", claim
assert read("claim-job-duplicate.json")["status"] == "empty"
registered = read("register-evidence-committed.json")
assert registered == {
    "schema": "rh-postgres-result/1", "operation": "register_evidence",
    "status": "registered", "evidence_id": "00000000-0000-0000-0000-000000000006",
    "digest_algorithm": "sha256",
    "digest_value": "fe482b5e524c67728f4f2b4f430cd10d9a25659641f995ae537b282ccd181e0b",
    "byte_length": 15, "storage_key": "fnv1a64:f5e19178d3ff184e",
}, registered
duplicate = read("register-evidence-duplicate.json")
assert duplicate["status"] == "duplicate" and duplicate["digest_value"] == registered["digest_value"]
all_output = "".join(open(os.path.join(root, p)).read() for p in os.listdir(root) if p.endswith(".json"))
assert "never-emit-this" not in all_output
print("[postgres-cli] verified evidence registration, event-page commit, page commit, claim, heartbeat, finish, and bounded reports OK")
PY

printf 'X' >> "$T/evidence/$stored_name"
if RH_DATABASE_URL='host=fake dbname=repo_health' RH_EVIDENCE_ROOT="$T/evidence" \
    RH_LIBPQ_PATH="$LIBPQ" RH_FAKE_PG_OPERATION=evidence RH_FAKE_PG_EXPECT=committed \
    "$ROOT/build/rh_cli" postgres --input "$T/register-evidence-command.json" \
      --out "$T/corrupt-evidence.json" >/dev/null 2>&1; then
  fail "corrupt evidence blob accepted"
fi
[[ ! -e "$T/corrupt-evidence.json" ]] || fail "corrupt evidence wrote a result"
rm -f "$T/evidence/$stored_name"
if RH_DATABASE_URL='host=fake dbname=repo_health' RH_EVIDENCE_ROOT="$T/evidence" \
    RH_LIBPQ_PATH="$LIBPQ" RH_FAKE_PG_OPERATION=evidence RH_FAKE_PG_EXPECT=committed \
    "$ROOT/build/rh_cli" postgres --input "$T/register-evidence-command.json" \
      --out "$T/missing-evidence.json" >/dev/null 2>&1; then
  fail "missing evidence blob accepted"
fi
[[ ! -e "$T/missing-evidence.json" ]] || fail "missing evidence wrote a result"
echo "[postgres-cli] missing and corrupt evidence fail before database registration"

cp "$ROOT/fixtures/postgres/page-commit-command.json" "$T/page-commit-command.json"
if env -u RH_DATABASE_URL RH_LIBPQ_PATH="$LIBPQ" "$ROOT/build/rh_cli" postgres --input "$T/page-commit-command.json" --out "$T/missing-url.json" >/dev/null 2>&1; then
  fail "missing database URL accepted"
fi
[[ ! -e "$T/missing-url.json" ]] || fail "missing URL wrote a result"
if RH_DATABASE_URL='host=fake dbname=repo_health' RH_LIBPQ_PATH="$LIBPQ" RH_FAKE_PG_OPERATION=page RH_FAKE_PG_CONNECT_FAIL=1 "$ROOT/build/rh_cli" postgres --input "$T/page-commit-command.json" --out "$T/connect-failure.json" >/dev/null 2>&1; then
  fail "database connection failure accepted"
fi
[[ ! -e "$T/connect-failure.json" ]] || fail "connection failure wrote a result"
printf '%s\n' '{"schema":"rh-postgres-command/1","operation":"page_commit"}' > "$T/malformed.json"
if RH_DATABASE_URL='host=fake dbname=repo_health' RH_LIBPQ_PATH="$LIBPQ" RH_FAKE_PG_OPERATION=page "$ROOT/build/rh_cli" postgres --input "$T/malformed.json" --out "$T/malformed-result.json" >/dev/null 2>&1; then
  fail "malformed command accepted"
fi
[[ ! -e "$T/malformed-result.json" ]] || fail "malformed command wrote a result"
echo "[postgres-cli] missing configuration, transport failure, and malformed input fail closed"
