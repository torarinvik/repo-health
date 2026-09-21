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
run_ok enqueue committed enqueue-collection-job
run_ok enqueue duplicate enqueue-collection-job
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
run_ok claim_collection committed claim-collection-job
run_ok claim_collection duplicate claim-collection-job

cp "$ROOT/fixtures/postgres/ingest-input.json" "$T/ingest-input.json"
RH_DATABASE_URL='host=fake dbname=repo_health password=never-emit-this' \
  RH_LIBPQ_PATH="$LIBPQ" RH_FAKE_PG_OPERATION=ingest RH_FAKE_PG_EXPECT=committed \
  "$ROOT/build/rh_cli" ingest --postgres --input "$T/ingest-input.json" --out "$T/ingest-result.json" >/dev/null \
  || fail "normalized PostgreSQL page ingest"
RH_DATABASE_URL='host=fake dbname=repo_health password=never-emit-this' \
  RH_LIBPQ_PATH="$LIBPQ" RH_FAKE_PG_OPERATION=ingest RH_FAKE_PG_EXPECT=duplicate \
  "$ROOT/build/rh_cli" ingest --postgres --input "$T/ingest-input.json" --out "$T/ingest-not-claimed.json" >/dev/null \
  || fail "normalized PostgreSQL ingest replay without a runnable lease"

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

cp "$ROOT/fixtures/postgres/evidence-references-command.json" "$T/evidence-references-command.json"
RH_DATABASE_URL='host=fake dbname=repo_health password=never-emit-this' \
  RH_LIBPQ_PATH="$LIBPQ" RH_FAKE_PG_OPERATION=evidence_references RH_FAKE_PG_EXPECT=listed \
  "$ROOT/build/rh_cli" postgres --input "$T/evidence-references-command.json" \
    --out "$T/evidence-references-result.json" >/dev/null || fail "database evidence reference discovery"
for mode in failure oversize; do
  if RH_DATABASE_URL='host=fake dbname=repo_health' RH_LIBPQ_PATH="$LIBPQ" \
      RH_FAKE_PG_OPERATION=evidence_references RH_FAKE_PG_EXPECT="$mode" \
      "$ROOT/build/rh_cli" postgres --input "$T/evidence-references-command.json" \
        --out "$T/evidence-references-$mode.json" >/dev/null 2>&1; then
    fail "database evidence reference $mode accepted"
  fi
  [[ ! -e "$T/evidence-references-$mode.json" ]] || fail "$mode evidence reference query wrote a result"
done
echo "[postgres-cli] evidence reference query failures and oversized results fail closed"

cp "$ROOT/fixtures/postgres/evidence-gc-command.json" "$T/evidence-gc-command.json"
printf '%s\n' '{"schema":"rh-postgres-command/1","operation":"evidence_gc","candidate_names":["../outside"]}' > "$T/evidence-gc-invalid.json"
printf '%s\n' '{"schema":"rh-postgres-command/1","operation":"evidence_gc","candidate_names":["f5e19178d3ff184e","f5e19178d3ff184e"]}' > "$T/evidence-gc-duplicate.json"
for invalid in invalid duplicate; do
  if RH_DATABASE_URL='host=fake dbname=repo_health' RH_EVIDENCE_ROOT="$T/evidence" \
      RH_LIBPQ_PATH="$LIBPQ" RH_FAKE_PG_OPERATION=evidence_references \
      "$ROOT/build/rh_cli" postgres --input "$T/evidence-gc-$invalid.json" \
        --out "$T/evidence-gc-$invalid-result.json" >/dev/null 2>&1; then
    fail "evidence GC accepted $invalid candidate names"
  fi
  [[ ! -e "$T/evidence-gc-$invalid-result.json" ]] || fail "$invalid evidence GC wrote a result"
done
printf 'orphan evidence\n' > "$T/orphan-evidence.txt"
orphan_name="$("$ROOT/build/rh_cli" store put --root "$T/evidence" --file "$T/orphan-evidence.txt" | awk '{print $3}')"
[[ "$orphan_name" == "4d9bc51a88048cee" ]] || fail "content-addressed orphan fixture changed"
RH_DATABASE_URL='host=fake dbname=repo_health password=never-emit-this' \
  RH_EVIDENCE_ROOT="$T/evidence" RH_LIBPQ_PATH="$LIBPQ" \
  RH_FAKE_PG_OPERATION=evidence_references RH_FAKE_PG_EXPECT=listed \
  "$ROOT/build/rh_cli" postgres --input "$T/evidence-gc-command.json" \
    --out "$T/evidence-gc-result.json" >/dev/null || fail "database-backed evidence cleanup"
python3 - "$T/evidence-gc-result.json" "$ROOT/fixtures/postgres/evidence-gc-result.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    actual = json.load(f)
with open(sys.argv[2]) as f:
    expected = json.load(f)
assert actual == expected, actual
PY
"$ROOT/build/rh_cli" store verify --root "$T/evidence" --name f5e19178d3ff184e >/dev/null || fail "evidence GC removed a referenced blob"
set +e
"$ROOT/build/rh_cli" store verify --root "$T/evidence" --name "$orphan_name" >/dev/null 2>&1
orphan_rc=$?
set -e
[[ "$orphan_rc" -eq 5 ]] || fail "evidence GC did not remove the orphan"
for mode in failure oversize invalid_refs truncated_refs; do
  "$ROOT/build/rh_cli" store put --root "$T/evidence" --file "$T/orphan-evidence.txt" >/dev/null || fail "recreate orphan before $mode snapshot"
  if RH_DATABASE_URL='host=fake dbname=repo_health' RH_EVIDENCE_ROOT="$T/evidence" \
      RH_LIBPQ_PATH="$LIBPQ" RH_FAKE_PG_OPERATION=evidence_references RH_FAKE_PG_EXPECT="$mode" \
      "$ROOT/build/rh_cli" postgres --input "$T/evidence-gc-command.json" \
        --out "$T/evidence-gc-$mode.json" >/dev/null 2>&1; then
    fail "evidence GC accepted $mode reference snapshot"
  fi
  [[ ! -e "$T/evidence-gc-$mode.json" ]] || fail "$mode evidence GC wrote a result"
  "$ROOT/build/rh_cli" store verify --root "$T/evidence" --name "$orphan_name" >/dev/null || fail "$mode evidence GC deleted an orphan without a complete snapshot"
done
echo "[postgres-cli] evidence GC preserves references and fails closed on incomplete snapshots"

python3 - "$T" "$ROOT/fixtures/postgres/ingest-output.json" "$ROOT/fixtures/postgres/evidence-references-result.json" "$ROOT/fixtures/postgres/evidence-gc-result.json" <<'PY'
import json, os, sys
root = sys.argv[1]
expected_ingest = json.load(open(sys.argv[2]))
expected_references = json.load(open(sys.argv[3]))
expected_gc = json.load(open(sys.argv[4]))
def read(name):
    with open(os.path.join(root, name)) as f:
        return json.load(f)
assert read("begin-collection-run-committed.json")["status"] == "started"
assert read("begin-collection-run-duplicate.json")["status"] == "duplicate"
assert read("enqueue-collection-job-committed.json")["status"] == "enqueued"
assert read("enqueue-collection-job-duplicate.json")["status"] == "duplicate"
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
specific_claim = read("claim-collection-job-committed.json")
assert specific_claim["status"] == "claimed" and specific_claim["fencing_token"] == 1, specific_claim
assert specific_claim["job_id"] == "00000000-0000-0000-0000-00000000000a", specific_claim
assert read("claim-collection-job-duplicate.json")["status"] == "empty"
assert read("ingest-result.json") == expected_ingest
not_claimed = read("ingest-not-claimed.json")
assert not_claimed["status"] == "not_claimed" and not_claimed["pages"] == [] and not_claimed["fencing_token"] == 0, not_claimed
assert not_claimed["schema"] == "rh-postgres-ingest-result/1" and not_claimed["operation"] == "ingest", not_claimed
assert not_claimed["source_id"] == expected_ingest["source_id"] and not_claimed["lease_expires_at"] == "", not_claimed
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
assert read("evidence-references-result.json") == expected_references
assert read("evidence-gc-result.json") == expected_gc
all_output = "".join(open(os.path.join(root, p)).read() for p in os.listdir(root) if p.endswith(".json"))
assert "never-emit-this" not in all_output
print("[postgres-cli] verified source/run setup, normalized PostgreSQL ingest, enqueue/targeted claim, evidence registration/reference discovery/cleanup, page commits, job lifecycle, and bounded reports OK")
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

python3 - "$T/ingest-input.json" "$T/ingest-malformed.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
value["pages"][0]["record_count"] = 2
json.dump(value, open(sys.argv[2], "w"))
PY
if RH_DATABASE_URL='host=fake dbname=repo_health' RH_LIBPQ_PATH="$LIBPQ" \
    RH_FAKE_PG_OPERATION=ingest RH_FAKE_PG_CONNECT_MARK="$T/malformed-connected" \
    "$ROOT/build/rh_cli" ingest --postgres --input "$T/ingest-malformed.json" \
      --out "$T/ingest-malformed-result.json" >/dev/null 2>&1; then
  fail "malformed normalized page batch accepted"
fi
[[ ! -e "$T/malformed-connected" ]] || fail "malformed batch connected to PostgreSQL before validation"
[[ ! -e "$T/ingest-malformed-result.json" ]] || fail "malformed batch wrote a result"
python3 - "$T/ingest-input.json" "$T/ingest-invalid-event.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
events = json.loads(value["pages"][0]["events_json"])
events[0]["subject_id"] = "not-a-uuid"
value["pages"][0]["events_json"] = json.dumps(events, separators=(",", ":"))
json.dump(value, open(sys.argv[2], "w"))
PY
if RH_DATABASE_URL='host=fake dbname=repo_health' RH_LIBPQ_PATH="$LIBPQ" \
    RH_FAKE_PG_OPERATION=ingest RH_FAKE_PG_CONNECT_MARK="$T/invalid-event-connected" \
    "$ROOT/build/rh_cli" ingest --postgres --input "$T/ingest-invalid-event.json" \
      --out "$T/ingest-invalid-event-result.json" >/dev/null 2>&1; then
  fail "malformed normalized event accepted"
fi
[[ ! -e "$T/invalid-event-connected" ]] || fail "malformed event connected to PostgreSQL before validation"
[[ ! -e "$T/ingest-invalid-event-result.json" ]] || fail "malformed event wrote a result"
python3 - "$T/ingest-input.json" "$T/ingest-invalid-time.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
value["pages"][0]["committed_at"] = "2026-02-30T00:03:00Z"
json.dump(value, open(sys.argv[2], "w"))
PY
if RH_DATABASE_URL='host=fake dbname=repo_health' RH_LIBPQ_PATH="$LIBPQ" \
    RH_FAKE_PG_OPERATION=ingest RH_FAKE_PG_CONNECT_MARK="$T/invalid-time-connected" \
    "$ROOT/build/rh_cli" ingest --postgres --input "$T/ingest-invalid-time.json" \
      --out "$T/ingest-invalid-time-result.json" >/dev/null 2>&1; then
  fail "invalid normalized page timestamp accepted"
fi
[[ ! -e "$T/invalid-time-connected" ]] || fail "invalid timestamp connected to PostgreSQL before validation"
[[ ! -e "$T/ingest-invalid-time-result.json" ]] || fail "invalid timestamp wrote a result"
echo "[postgres-cli] page records, timestamps, and lease bounds are preflighted before PostgreSQL"
