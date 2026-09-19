#!/usr/bin/env bash
# tests/test_ops_cli.sh — M07-11 monitoring + M07-12 source-respect:
# `rh_cli ops monitor` separates service and project series and reports a
# rate with no denominator as null (unknown, not 0); `rh_cli ops quota`
# runs a per-host token bucket with exponential backoff, operator stop, and
# cancel refund. Malformed input fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-ops"

fail() { echo "[ops] FAIL: $1" >&2; exit 1; }

echo "[ops] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/mon.json" <<'JSON'
{"schema":"rh-monitor-input/1","expected_interval":60,"now":1200,"events":[{"kind":"observed"},{"kind":"observed"},{"kind":"unknown"},{"kind":"stale_partial"},{"kind":"error"},{"kind":"parser_reject"},{"kind":"object_failure"},{"kind":"truncation"},{"kind":"success","now":1150},{"kind":"queue_age","value":30},{"kind":"cursor_lag","value":90}]}
JSON
"$ROOT/build/rh_cli" ops monitor --input "$T/mon.json" --out "$T/mon.out" >/dev/null || fail "monitor run"
python3 - "$T/mon.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-monitor-result/1", d
assert d["service"] == {"queue_age_max": 30, "cursor_lag_max": 90, "last_success_epoch": 1150,
                        "freshness_age": 50, "errors": 1, "parser_rejects": 1, "object_failures": 1}, d["service"]
assert d["project"] == {"observed": 2, "unknown": 1, "observed_rate_bp": 6666,
                        "stale_partial": 1, "truncations": 1}, d["project"]
assert len(d["exposition"]) == 12, d["exposition"]
assert d["exposition"][0].startswith("rh_service_"), d["exposition"]
assert any(x.startswith("rh_project_observed_rate_bp") for x in d["exposition"]), d["exposition"]
assert "separate" in d["note"], d["note"]
print("[ops] monitor series OK")
PY

echo "[ops] no denominator -> null rate (not 0); no success -> null freshness"
printf '{"schema":"rh-monitor-input/1","now":50,"events":[]}' > "$T/empty.json"
"$ROOT/build/rh_cli" ops monitor --input "$T/empty.json" --out "$T/empty.out" >/dev/null || fail "empty monitor"
python3 - "$T/empty.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["project"]["observed_rate_bp"] is None, d["project"]
assert d["service"]["freshness_age"] is None, d["service"]
print("[ops] unknown-not-zero OK")
PY

cat > "$T/quota.json" <<'JSON'
{"schema":"rh-quota-input/1","host_id":1,"capacity":2,"refill_per_second":1,"base_backoff_seconds":10,"max_backoff_seconds":40,"ops":[{"op":"consume","now":0},{"op":"consume","now":0},{"op":"consume","now":0},{"op":"failure","now":0},{"op":"consume","now":5},{"op":"success","now":100},{"op":"consume","now":100},{"op":"stop","now":101},{"op":"consume","now":101},{"op":"cancel","now":200}]}
JSON
"$ROOT/build/rh_cli" ops quota --input "$T/quota.json" --out "$T/quota.out" >/dev/null || fail "quota run"
python3 - "$T/quota.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
o = d["ops"]
assert d["schema"] == "rh-quota-result/1", d
assert [x.get("consumed") for x in o] == [True, True, False, None, False, None, True, None, False, None], o
assert o[3]["backoff_seconds"] == 10 and o[3]["backoff_until"] == 10, o[3]
# backing off: a consume before backoff_until is refused
assert o[4]["consumed"] is False and o[4]["backoff_until"] == 10, o[4]
# success clears backoff
assert o[5]["backoff_until"] == 0, o[5]
# stop is an operator kill switch; cancel refunds a token
assert o[7]["stopped"] is True and o[8]["consumed"] is False, (o[7], o[8])
assert o[9]["tokens"] == 2, o[9]
assert d["final"]["stopped"] is True and d["final"]["tokens"] == 2, d["final"]
print("[ops] quota state machine OK")
PY

echo "[ops] exponential backoff grows and is capped"
cat > "$T/backoff.json" <<'JSON'
{"schema":"rh-quota-input/1","capacity":1,"refill_per_second":0,"base_backoff_seconds":10,"max_backoff_seconds":40,"ops":[{"op":"failure","now":0},{"op":"failure","now":1},{"op":"failure","now":2},{"op":"failure","now":3},{"op":"success","now":4}]}
JSON
"$ROOT/build/rh_cli" ops quota --input "$T/backoff.json" --out "$T/backoff.out" >/dev/null || fail "backoff run"
python3 - "$T/backoff.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
waits = [x["backoff_seconds"] for x in d["ops"] if "backoff_seconds" in x]
assert waits == [10, 20, 40, 40], waits
print("[ops] backoff cap OK")
PY

echo "[ops] determinism + fail-closed negatives"
"$ROOT/build/rh_cli" ops monitor --input "$T/mon.json" --out "$T/mon2.out" >/dev/null || fail "rerun"
cmp -s "$T/mon.out" "$T/mon2.out" || fail "monitor output not deterministic"
set +e
printf '{"schema":"rh-monitor-input/2","events":[]}' > "$T/badms.json"
"$ROOT/build/rh_cli" ops monitor --input "$T/badms.json" --out "$T/x" >/dev/null 2>&1; rc_ms=$?
printf '{"schema":"rh-monitor-input/1","events":[{"kind":"vibes"}]}' > "$T/badmk.json"
"$ROOT/build/rh_cli" ops monitor --input "$T/badmk.json" --out "$T/x" >/dev/null 2>&1; rc_mk=$?
printf '{"schema":"rh-quota-input/1","ops":[{"op":"teleport"}]}' > "$T/badqo.json"
"$ROOT/build/rh_cli" ops quota --input "$T/badqo.json" --out "$T/x" >/dev/null 2>&1; rc_qo=$?
printf '{"schema":"rh-quota-input/1","ops":42}' > "$T/badqa.json"
"$ROOT/build/rh_cli" ops quota --input "$T/badqa.json" --out "$T/x" >/dev/null 2>&1; rc_qa=$?
"$ROOT/build/rh_cli" ops monitor --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_miss=$?
set -e
for rc in "$rc_ms" "$rc_mk" "$rc_qo" "$rc_qa" "$rc_miss"; do
  [[ "$rc" -eq 4 ]] || fail "malformed ops input must exit 4 (got $rc)"
done

echo "test_ops_cli OK"
