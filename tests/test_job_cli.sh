#!/usr/bin/env bash
# tests/test_job_cli.sh — M02-03 ingestion job machine: the `test_job`
# selftest (classification, disposition, backoff, transitions) plus the
# `rh_cli job classify` execution path. Failure kinds are distinct, retries
# back off, and an exhausted retry dead-letters instead of succeeding.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-job"

fail() { echo "[job] FAIL: $1" >&2; exit 1; }

echo "[job] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
[[ -x "$ROOT/build/test_job" ]] || fail "test_job not built"

echo "[job] unit selftest"
"$ROOT/build/test_job" | grep -q "JOB OK" || fail "test_job selftest failed"

rm -rf "$T"; mkdir -p "$T"
echo "[job] failure kinds are distinct and route correctly"
run() { # kind attempt max_attempts
  python3 - "$T/ev.json" "$1" "$2" "$3" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({
  "schema": "rh-job-event/1", "kind": sys.argv[2],
  "attempt": int(sys.argv[3]), "now": 1000,
  "max_attempts": int(sys.argv[4]), "backoff_cap_secs": 3600}))
PY
  "$ROOT/build/rh_cli" job classify --input "$T/ev.json" --out "$T/out.json" >/dev/null
}
run transient 1 5
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-job-next/1", d
assert d["kind"] == "transient" and d["disposition"] == "retry", d
assert d["next_phase"] == "retry_wait" and d["wake_at"] == 1002, d
assert d["next_attempt"] == 2, d
assert "never collapsed" in d["note"], d
print("[job] transient retry OK")
PY
run rate_limit 1 5
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["disposition"] == "retry" and d["wake_at"] == 1030, d
print("[job] rate_limit backoff OK")
PY
run auth 1 5
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["disposition"] == "terminal" and d["next_phase"] == "failed_terminal", d
assert d["wake_at"] == 0, d
print("[job] auth terminal OK")
PY
run unsupported 1 5
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["disposition"] == "terminal", d
print("[job] unsupported terminal OK")
PY
run malformed 1 5
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["disposition"] == "dead_letter" and d["next_phase"] == "dead_letter", d
print("[job] malformed dead-letter OK")
PY
run budget 1 5
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["disposition"] == "retry" and d["wake_at"] == 1060, d
print("[job] budget retry OK")
PY

echo "[job] an exhausted retry dead-letters, never succeeds"
run transient 5 5
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["disposition"] == "dead_letter" and d["next_phase"] == "dead_letter", d
assert d["next_phase"] != "succeeded", d
print("[job] exhausted dead-letter OK")
PY
# max_attempts == 0 means unlimited retries
run transient 999 0
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["next_phase"] == "retry_wait", d
print("[job] unlimited retries OK")
PY

echo "[job] determinism"
a="$("$ROOT/build/rh_cli" job classify --input "$T/ev.json" --out "$T/a.json" >/dev/null; cat "$T/a.json")"
b="$("$ROOT/build/rh_cli" job classify --input "$T/ev.json" --out "$T/b.json" >/dev/null; cat "$T/b.json")"
[[ "$a" == "$b" ]] || fail "job classify must be deterministic"

echo "[job] malformed input fails closed"
check_rc() { # payload
  printf '%s' "$1" > "$T/bad.json"
  "$ROOT/build/rh_cli" job classify --input "$T/bad.json" --out "$T/bad.out" >/dev/null 2>&1
  echo $?
}
set +e
rc1=$(check_rc '{"schema":"rh-job-event/1","kind":"vibes","attempt":1,"now":1}')
rc2=$(check_rc '{"schema":"rh-job-event/2","kind":"auth","attempt":1,"now":1}')
rc3=$(check_rc '{"schema":"rh-job-event/1","kind":"auth","attempt":0,"now":1}')
rc4=$(check_rc '{"schema":"rh-job-event/1","kind":"auth","attempt":1}')
rc5=$(check_rc '{"schema":"rh-job-event/1","kind":"auth","attempt":1,"now":5,"max_attempts":-1}')
rc6=$(check_rc 'not json')
rc7=$(check_rc '{"schema":"rh-job-event/1","attempt":1,"now":1}')
"$ROOT/build/rh_cli" job classify --input "$T/nope.json" --out "$T/x.out" >/dev/null 2>&1
rc8=$?
set -e
for rc in "$rc1" "$rc2" "$rc3" "$rc4" "$rc5" "$rc6" "$rc7" "$rc8"; do
  [[ "$rc" -eq 4 ]] || fail "malformed job event must exit 4 (got $rc)"
done

echo "[job] scheduler run: bounded queue, claims, retry, dead-letter"
cat > "$T/sched.json" <<'JSON'
{"schema":"rh-sched-input/1","capacity":2,
 "quota":{"refill_per_second":100,"base_backoff_seconds":5,"max_backoff_seconds":600},
 "ops":[
  {"op":"enqueue","now":1000},
  {"op":"enqueue","now":1000},
  {"op":"enqueue","now":1000},
  {"op":"claim","owner":1,"now":1000,"ttl":100},
  {"op":"succeed","slot":0,"token":1},
  {"op":"claim","owner":2,"now":1001,"ttl":100},
  {"op":"fail","slot":1,"token":1,"kind":"transient","now":1001,"max_attempts":5},
  {"op":"claim","owner":2,"now":2000,"ttl":100},
  {"op":"fail","slot":1,"token":2,"kind":"malformed","now":2000,"max_attempts":5},
  {"op":"cancel","slot":0}
 ]}
JSON
"$ROOT/build/rh_cli" job run --input "$T/sched.json" --out "$T/sched.out" >/dev/null || fail "scheduler run failed"
python3 - "$T/sched.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-sched-result/1", d
assert d["capacity"] == 2, d
o = {x["index"]: x["outcome"] for x in d["ops"]}
# third enqueue refused (bounded queue), not dropped silently
assert o[0] == 0 and o[1] == 1 and o[2] == -1, o
# claim 0, succeed once
assert o[3] == 0 and o[4] == 1, o
# transient failure -> retry_wait (phase 6)
assert o[6] == 6, o
# malformed failure -> dead_letter (phase 7)
assert o[8] == 7, o
# cancel of an already-succeeded slot is refused
assert o[9] == 0, o
phases = {s["slot"]: s["phase"] for s in d["slots"]}
assert phases == {0: "succeeded", 1: "dead_letter"}, phases
assert "never silent success" in d["note"], d["note"]
print("[job] scheduler run OK")
PY
# determinism
a="$("$ROOT/build/rh_cli" job run --input "$T/sched.json" --out "$T/s1" >/dev/null; cat "$T/s1")"
b="$("$ROOT/build/rh_cli" job run --input "$T/sched.json" --out "$T/s2" >/dev/null; cat "$T/s2")"
[[ "$a" == "$b" ]] || fail "job run must be deterministic"

echo "[job] scheduler malformed input fails closed"
check_run_rc() {
  printf '%s' "$1" > "$T/badrun.json"
  "$ROOT/build/rh_cli" job run --input "$T/badrun.json" --out "$T/badrun.out" >/dev/null 2>&1
  echo $?
}
set +e
sr1=$(check_run_rc '{"schema":"rh-sched-input/2","capacity":2,"ops":[]}')
sr2=$(check_run_rc '{"schema":"rh-sched-input/1","capacity":0,"ops":[]}')
sr3=$(check_run_rc '{"schema":"rh-sched-input/1","capacity":2}')
sr4=$(check_run_rc '{"schema":"rh-sched-input/1","capacity":2,"ops":[{"op":"launch"}]}')
sr5=$(check_run_rc '{"schema":"rh-sched-input/1","capacity":2,"ops":[{"op":"fail","slot":0,"token":1,"kind":"vibes","now":1}]}')
sr6=$(check_run_rc 'not json')
set -e
for rc in "$sr1" "$sr2" "$sr3" "$sr4" "$sr5" "$sr6"; do
  [[ "$rc" -eq 4 ]] || fail "malformed scheduler input must exit 4 (got $rc)"
done
# A structurally valid op that cannot apply is a recorded refusal, not a parse
# error: the run succeeds and the outcome is 0, never a silent success.
printf '%s' '{"schema":"rh-sched-input/1","capacity":2,"ops":[{"op":"succeed","slot":0}]}' > "$T/refuse.json"
"$ROOT/build/rh_cli" job run --input "$T/refuse.json" --out "$T/refuse.out" >/dev/null || fail "structurally valid refuse run must succeed"
python3 - "$T/refuse.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["ops"][0]["outcome"] == 0, d
PY

echo "test_job_cli OK"
