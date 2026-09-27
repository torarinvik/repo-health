#!/usr/bin/env bash
# tests/test_worker_cli.sh — M02-03/M02-06 unattended worker tick:
# `rh_cli worker tick --input <file> --out <file>` runs one bounded,
# deterministic scheduling pass over a source table and writes
# rh-worker-plan/2 (per-source full/incremental/skipped decision, reconcile
# horizon/overlap/debt, and aggregate health). Full reconciles take priority,
# and service rotates within each priority class.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-worker-cli"

fail() { echo "[worker] FAIL: $1" >&2; exit 1; }

echo "[worker] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
[[ -x "$ROOT/build/test_worker" ]] || fail "test_worker not built"

echo "[worker] unit selftest"
"$ROOT/build/test_worker" | grep -q "WORKER OK" || fail "test_worker selftest failed"

rm -rf "$T"; mkdir -p "$T"
echo "[worker] full takes priority, incremental fallback, debt visible"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-worker-input/1","capacity":4,"quota":{"refill_per_second":100,"base_backoff_seconds":5,"max_backoff_seconds":600},"now":2500,
 "sources":[
  {"source_id":1,"interval_secs":1000,"last_full_reconcile":1000,"cursor_time":1900,"overlap_secs":100},
  {"source_id":2,"interval_secs":1000,"last_full_reconcile":2000,"cursor_time":2900,"overlap_secs":100},
  {"source_id":3,"interval_secs":600,"cursor_time":2400,"overlap_secs":60}
 ]}
JSON
"$ROOT/build/rh_cli" worker tick --input "$T/in.json" --out "$T/in.out" | grep -q "overdue=2" || fail "expected 2 overdue"
python3 - "$T/in.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-worker-plan/2", d
modes = {x["source_id"]: x["mode"] for x in d["decisions"]}
assert modes == {1: "full", 2: "incremental", 3: "full"}, modes
debt = {x["source_id"]: x["schedule_debt"] for x in d["decisions"]}
assert debt == {1: 1, 2: 0, 3: 1}, debt
assert d["health"] == {"enqueued": 3, "skipped": 0, "overdue": 2, "max_debt": 1}, d["health"]
assert "never silently dropped" in d["note"], d["note"]
print("[worker] plan OK")
PY

echo "[worker] bounded queue skips the overflow but keeps debt visible"
cat > "$T/bounded.json" <<'JSON'
{"schema":"rh-worker-input/1","capacity":1,"now":5000,
 "sources":[
  {"source_id":1,"interval_secs":1000},
  {"source_id":2,"interval_secs":1000},
  {"source_id":3,"interval_secs":1000}
 ]}
JSON
"$ROOT/build/rh_cli" worker tick --input "$T/bounded.json" --out "$T/bounded.out" >/dev/null || fail "bounded run"
python3 - "$T/bounded.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["decisions"][0]["mode"] == "full", d
assert d["decisions"][1]["mode"] == "skipped" and d["decisions"][2]["mode"] == "skipped", d
assert d["health"]["skipped"] == 2 and d["health"]["overdue"] == 3, d["health"]
print("[worker] bounded OK")
PY

echo "[worker] source operator stop skips only that source before quota consumption"
cat > "$T/operator-stop.json" <<'JSON'
{"schema":"rh-worker-input/1","capacity":1,"now":5000,
 "sources":[
  {"source_id":1,"interval_secs":1000,"operator_stopped":true},
  {"source_id":2,"interval_secs":1000}
 ]}
JSON
"$ROOT/build/rh_cli" worker tick --input "$T/operator-stop.json" --out "$T/operator-stop.out" >/dev/null || fail "operator stop run"
python3 - "$T/operator-stop.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["decisions"][0]["mode"] == "skipped" and d["decisions"][0]["reason"] == "operator_stop", d
assert d["decisions"][1]["mode"] == "full" and d["decisions"][1]["reason"] is None, d
assert d["health"]["enqueued"] == 1 and d["health"]["skipped"] == 1, d["health"]
print("[worker] source-scoped stop and quota preservation OK")
PY

echo "[worker] due reconciles take the slot before incremental work"
cat > "$T/priority.json" <<'JSON'
{"schema":"rh-worker-input/1","capacity":1,"now":2500,
 "sources":[
  {"source_id":10,"interval_secs":1000,"last_full_reconcile":2000},
  {"source_id":20,"interval_secs":1000,"last_full_reconcile":1000}
 ]}
JSON
"$ROOT/build/rh_cli" worker tick --input "$T/priority.json" --out "$T/priority.out" >/dev/null || fail "priority run"
python3 - "$T/priority.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["decisions"][0]["source_id"] == 20 and d["decisions"][0]["mode"] == "full", d
assert d["decisions"][1]["source_id"] == 10 and d["decisions"][1]["mode"] == "skipped", d
print("[worker] global full-reconcile priority OK")
PY

echo "[worker] explicit cursor rotates bounded service across identical timestamps"
python3 - "$ROOT/build/rh_cli" "$T" <<'PY'
import json, pathlib, subprocess, sys
cli, root = sys.argv[1], pathlib.Path(sys.argv[2])
sources = [{"source_id": i, "interval_secs": 10000, "last_full_reconcile": 0} for i in (1, 2, 3)]
cursor = 0
for tick, expected in enumerate((1, 2, 3)):
    input_path, output_path = root / f"rotation-{tick}.json", root / f"rotation-{tick}.out"
    input_path.write_text(json.dumps({"schema": "rh-worker-input/1", "capacity": 1, "now": 5000, "rotation_cursor": cursor, "sources": sources}))
    subprocess.run([cli, "worker", "tick", "--input", str(input_path), "--out", str(output_path)], check=True, stdout=subprocess.DEVNULL)
    plan = json.loads(output_path.read_text())
    served = [row["source_id"] for row in plan["decisions"] if row["mode"] != "skipped"]
    assert served == [expected], (tick, expected, served, plan)
    cursor = plan["next_rotation_cursor"]
    assert cursor == (tick + 1) % len(sources), (tick, cursor, plan)
print("[worker] persisted cursor rotates service without timestamp dependence")
PY

echo "[worker] invalid rotation cursor fails closed"
if "$ROOT/build/rh_cli" worker tick --input <(printf '%s' '{"schema":"rh-worker-input/1","capacity":1,"now":1,"rotation_cursor":-1,"sources":[]}') --out "$T/invalid-rotation.out" >/dev/null 2>&1; then
  fail "negative rotation cursor must be rejected"
fi

echo "[worker] determinism"
a="$("$ROOT/build/rh_cli" worker tick --input "$T/in.json" --out "$T/d1" >/dev/null; cat "$T/d1")"
b="$("$ROOT/build/rh_cli" worker tick --input "$T/in.json" --out "$T/d2" >/dev/null; cat "$T/d2")"
[[ "$a" == "$b" ]] || fail "worker tick must be deterministic"

echo "[worker] malformed input fails closed"
check_rc() {
  printf '%s' "$1" > "$T/bad.json"
  "$ROOT/build/rh_cli" worker tick --input "$T/bad.json" --out "$T/bad.out" >/dev/null 2>&1
  echo $?
}
set +e
rc1=$(check_rc '{"schema":"rh-worker-input/2","capacity":1,"now":1,"sources":[]}')
rc2=$(check_rc '{"schema":"rh-worker-input/1","now":1,"sources":[]}')
rc3=$(check_rc '{"schema":"rh-worker-input/1","capacity":0,"now":1,"sources":[]}')
rc4=$(check_rc '{"schema":"rh-worker-input/1","capacity":1,"sources":[]}')
rc5=$(check_rc '{"schema":"rh-worker-input/1","capacity":1,"now":1}')
rc6=$(check_rc '{"schema":"rh-worker-input/1","capacity":1,"now":1,"sources":[{"source_id":1,"interval_secs":0}]}')
rc7=$(check_rc 'not json')
rc8=$(check_rc '{"schema":"rh-worker-input/1","capacity":1,"now":1,"sources":[{"source_id":1,"interval_secs":60,"operator_stopped":"yes"}]}')
set -e
for rc in "$rc1" "$rc2" "$rc3" "$rc4" "$rc5" "$rc6" "$rc7" "$rc8"; do
  [[ "$rc" -eq 4 ]] || fail "malformed worker input must exit 4 (got $rc)"
done

echo "test_worker_cli OK"
