#!/usr/bin/env bash
# tests/test_reconcile_cli.sh — M02-06 reconciliation policy execution path:
# `rh_cli reconcile --input <file> --out <file>` reads an
# rh-reconcile-input/1 and writes rh-reconcile-result/1 (tick mode, look-back
# horizon, incremental overlap start, schedule debt). Only a completed full
# reconcile may advance the clock; a misconfigured zero interval fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-reconcile"

fail() { echo "[reconcile] FAIL: $1" >&2; exit 1; }

echo "[reconcile] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
[[ -x "$ROOT/build/test_reconcile" ]] || fail "test_reconcile not built"

echo "[reconcile] unit selftest"
"$ROOT/build/test_reconcile" | grep -q "RECONCILE OK" || fail "test_reconcile selftest failed"

rm -rf "$T"; mkdir -p "$T"
echo "[reconcile] due full reconcile covers the whole interval since last full"
cat > "$T/due.json" <<'JSON'
{"schema":"rh-reconcile-input/1","interval_secs":86400,"last_full_reconcile":100000,"cursor_time":186000,"overlap_secs":3600,"now":200000}
JSON
"$ROOT/build/rh_cli" reconcile --input "$T/due.json" --out "$T/due.out" | grep -q "mode=full" || fail "expected full reconcile due"
python3 - "$T/due.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-reconcile-result/1", d
assert d["mode"] == "full", d
assert d["horizon_secs"] == 100000, d          # now - last_full, not now - cursor
assert d["overlap_start"] == 182400, d          # cursor - overlap
assert d["schedule_debt"] == 1, d
assert d["next_due_at"] == 186400, d
assert "never silently skips reconciles" in d["note"], d
print("[reconcile] due OK")
PY

echo "[reconcile] on-schedule tick is incremental and carries no debt"
cat > "$T/inc.json" <<'JSON'
{"schema":"rh-reconcile-input/1","interval_secs":86400,"last_full_reconcile":180000,"cursor_time":200000,"overlap_secs":3600,"now":200000}
JSON
"$ROOT/build/rh_cli" reconcile --input "$T/inc.json" --out "$T/inc.out" | grep -q "mode=incremental" || fail "expected incremental"
python3 - "$T/inc.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["mode"] == "incremental" and d["schedule_debt"] == 0, d
assert d["horizon_secs"] == 20000, d
print("[reconcile] incremental OK")
PY

echo "[reconcile] a fresh source is due immediately with debt 1"
cat > "$T/fresh.json" <<'JSON'
{"schema":"rh-reconcile-input/1","interval_secs":600,"now":50}
JSON
"$ROOT/build/rh_cli" reconcile --input "$T/fresh.json" --out "$T/fresh.out" >/dev/null || fail "fresh run"
python3 - "$T/fresh.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["mode"] == "full", d
assert d["last_full_reconcile"] == -1 and d["schedule_debt"] == 1, d
assert d["horizon_secs"] == 0, d
print("[reconcile] fresh OK")
PY

echo "[reconcile] determinism"
a="$("$ROOT/build/rh_cli" reconcile --input "$T/due.json" --out "$T/d1" >/dev/null; cat "$T/d1")"
b="$("$ROOT/build/rh_cli" reconcile --input "$T/due.json" --out "$T/d2" >/dev/null; cat "$T/d2")"
[[ "$a" == "$b" ]] || fail "reconcile must be deterministic"

echo "[reconcile] malformed input fails closed"
check_rc() {
  printf '%s' "$1" > "$T/bad.json"
  "$ROOT/build/rh_cli" reconcile --input "$T/bad.json" --out "$T/bad.out" >/dev/null 2>&1
  echo $?
}
set +e
rc1=$(check_rc '{"schema":"rh-reconcile-input/2","interval_secs":600,"now":1}')
rc2=$(check_rc '{"schema":"rh-reconcile-input/1","now":1}')
rc3=$(check_rc '{"schema":"rh-reconcile-input/1","interval_secs":0,"now":1}')
rc4=$(check_rc '{"schema":"rh-reconcile-input/1","interval_secs":600}')
rc5=$(check_rc '{"schema":"rh-reconcile-input/1","interval_secs":600,"now":1,"cursor_time":-5}')
rc6=$(check_rc 'not json')
"$ROOT/build/rh_cli" reconcile --input "$T/nope.json" --out "$T/x.out" >/dev/null 2>&1
rc7=$?
set -e
for rc in "$rc1" "$rc2" "$rc3" "$rc4" "$rc5" "$rc6" "$rc7"; do
  [[ "$rc" -eq 4 ]] || fail "malformed reconcile input must exit 4 (got $rc)"
done

echo "test_reconcile_cli OK"
