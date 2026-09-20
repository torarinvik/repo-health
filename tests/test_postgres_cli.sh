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

run_ok page committed page-commit
run_ok page duplicate page-commit
run_ok page_events committed page-events
run_ok page_events duplicate page-events
run_ok heartbeat committed heartbeat-job
run_ok heartbeat duplicate heartbeat-job
run_ok finish committed finish-job
run_ok finish duplicate finish-job
run_ok claim committed claim-job
run_ok claim duplicate claim-job

python3 - "$T" <<'PY'
import json, os, sys
root = sys.argv[1]
def read(name):
    with open(os.path.join(root, name)) as f:
        return json.load(f)
assert read("page-commit-committed.json")["status"] == "committed"
assert read("page-commit-duplicate.json")["status"] == "duplicate"
assert read("page-events-committed.json")["operation"] == "page_commit_events"
assert read("page-events-committed.json")["status"] == "committed"
assert read("page-events-duplicate.json")["status"] == "duplicate"
assert read("heartbeat-job-committed.json")["status"] == "applied"
assert read("heartbeat-job-duplicate.json")["status"] == "fenced"
assert read("finish-job-committed.json")["status"] == "applied"
assert read("finish-job-duplicate.json")["status"] == "fenced"
claim = read("claim-job-committed.json")
assert claim["status"] == "claimed" and claim["fencing_token"] == 5, claim
assert claim["job_id"] == "00000000-0000-0000-0000-000000000004", claim
assert claim["lease_expires_at"] == "2026-01-01 00:02:00+00", claim
assert read("claim-job-duplicate.json")["status"] == "empty"
all_output = "".join(open(os.path.join(root, p)).read() for p in os.listdir(root) if p.endswith(".json"))
assert "never-emit-this" not in all_output
print("[postgres-cli] atomic event-page commit, page commit, claim, heartbeat, finish, and bounded reports OK")
PY

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
