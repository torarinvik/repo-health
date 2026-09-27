#!/usr/bin/env bash
# tests/test_worker_daemon.sh — process-wrapper boundary for the bounded
# Elisa worker pass. The wrapper must skip unchanged input and rerun after a
# producer refreshes the worker contract.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T="/tmp/rh-worker-daemon"

fail() { echo "[worker-daemon] FAIL: $1" >&2; exit 1; }

echo "[worker-daemon] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-worker-input/1","capacity":1,"now":5000,"sources":[{"source_id":1,"interval_secs":1000}]}
JSON

echo "[worker-daemon] unchanged input is scheduled once"
log="$("$ROOT/tools/worker-daemon.sh" --input "$T/in.json" --out "$T/out.json" --interval-secs 0 --max-cycles 3)"
[[ "$log" == *"cycles=3 runs=1"* ]] || fail "unexpected unchanged digest run count: $log"
[[ -s "$T/out.json" ]] || fail "worker plan missing"

echo "[worker-daemon] refreshed input schedules again"
sed 's/5000/6000/' "$T/in.json" > "$T/next.json"
log="$("$ROOT/tools/worker-daemon.sh" --input "$T/next.json" --out "$T/out2.json" --interval-secs 0 --max-cycles 1)"
[[ "$log" == *"cycles=1 runs=1"* ]] || fail "refreshed input did not run: $log"
python3 - "$T/out.json" "$T/out2.json" <<'PY'
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:])
assert a["schema"] == b["schema"] == "rh-worker-plan/2", (a, b)
assert a["decisions"] == b["decisions"], (a, b)
print("[worker-daemon] refreshed plan remains schema-valid")
PY

echo "[worker-daemon] persisted cursor survives daemon restart at the same timestamp"
cat > "$T/round-a.json" <<'JSON'
{"schema":"rh-worker-input/1","capacity":1,"now":5000,"sources":[{"source_id":1,"interval_secs":10000,"last_full_reconcile":0},{"source_id":2,"interval_secs":10000,"last_full_reconcile":0},{"source_id":3,"interval_secs":10000,"last_full_reconcile":0}]}
JSON
"$ROOT/tools/worker-daemon.sh" --input "$T/round-a.json" --out "$T/round-plan.json" --interval-secs 0 --max-cycles 1 >/dev/null
sed 's/10000/9999/g' "$T/round-a.json" > "$T/round-b.json"
"$ROOT/tools/worker-daemon.sh" --input "$T/round-b.json" --out "$T/round-plan.json" --interval-secs 0 --max-cycles 1 >/dev/null
python3 - "$T/round-plan.json" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
served = [row["source_id"] for row in plan["decisions"] if row["mode"] != "skipped"]
assert served == [1], plan
print("[worker-daemon] prior plan cursor advanced service despite identical time")
PY

echo "[worker-daemon] concurrent daemons serialize cursor and suppress duplicate inputs"
cat > "$T/concurrent.json" <<'JSON'
{"schema":"rh-worker-input/1","capacity":1,"now":5000,"sources":[{"source_id":1,"interval_secs":10000,"last_full_reconcile":0},{"source_id":2,"interval_secs":10000,"last_full_reconcile":0},{"source_id":3,"interval_secs":10000,"last_full_reconcile":0}]}
JSON
"$ROOT/tools/worker-daemon.sh" --input "$T/concurrent.json" --out "$T/concurrent-plan.json" --interval-secs 0 --max-cycles 1 > "$T/daemon-a.log" &
daemon_a=$!
"$ROOT/tools/worker-daemon.sh" --input "$T/concurrent.json" --out "$T/concurrent-plan.json" --interval-secs 0 --max-cycles 1 > "$T/daemon-b.log" &
daemon_b=$!
wait "$daemon_a" || fail "first concurrent daemon failed"
wait "$daemon_b" || fail "second concurrent daemon failed"
scheduled_count=$(cat "$T/daemon-a.log" "$T/daemon-b.log" | grep -c 'worker-daemon-tick:scheduled' || true)
[[ "$scheduled_count" -eq 1 ]] || fail "same input scheduled $scheduled_count times under contention"
python3 - "$T/concurrent-plan.json" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
served = [row["source_id"] for row in plan["decisions"] if row["mode"] != "skipped"]
assert len(served) == 1, plan
print("[worker-daemon] one serialized schedule produced one complete plan")
PY

echo "[worker-daemon] invalid wrapper arguments fail closed"
set +e
"$ROOT/tools/worker-daemon.sh" --input "$T/in.json" --out "$T/x" --interval-secs nope --max-cycles 1 >/dev/null 2>&1; rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "invalid interval must exit 2 (got $rc)"

echo "test_worker_daemon OK"
