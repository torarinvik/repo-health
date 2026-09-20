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

echo "[worker-daemon] invalid wrapper arguments fail closed"
set +e
"$ROOT/tools/worker-daemon.sh" --input "$T/in.json" --out "$T/x" --interval-secs nope --max-cycles 1 >/dev/null 2>&1; rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "invalid interval must exit 2 (got $rc)"

echo "test_worker_daemon OK"
