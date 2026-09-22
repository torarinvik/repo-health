#!/usr/bin/env bash
# tests/test_succession_cli.sh — M04-08 succession execution path:
# `rh_cli succession --input <file> --out <file>` publishes
# `succession.handover_overlap_months` (complete months in which a declared
# predecessor/successor pair are both active). An absent declared pair is
# not_applicable, never zero overlap.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-succession"

fail() { echo "[succession] FAIL: $1" >&2; exit 1; }

echo "[succession] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
echo "[succession] declared pair overlap is an exact count"
python3 - "$T/in.json" <<'PY'
import json, sys
alice = [True]*6 + [False]*6
bob = [False]*3 + [True]*9
open(sys.argv[1], "w").write(json.dumps({
  "schema":"rh-succession-input/1","complete_months":12,
  "predecessor":0,"successor":1,"presence":[alice,bob]}))
PY
"$ROOT/build/rh_cli" succession --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "succession run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-continuity-metrics/1", d
assert d["metric"] == "succession.handover_overlap_months", d
assert d["version"] == "1.0.0", d
assert d["status"] == "observed" and d["value"] == 3, d
assert d["pair"] == {"predecessor": 0, "successor": 1}, d
assert d["window_complete_months"] == 12, d
assert "no motive attribution" in d["note"], d
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["succession.declared_handovers"]["status"] == "observed", metrics
assert metrics["succession.declared_handovers"]["value"] == 1, metrics
assert metrics["succession.observed_activity_overlap_months"]["value"] == 3, metrics
print("[succession] overlap OK")
PY

echo "[succession] explicit follow-up reports activity and right censoring"
python3 - "$T/follow-up.json" <<'PY'
import json, sys
alice = [True]*6 + [False]*6
bob = [False]*3 + [True]*9
open(sys.argv[1], "w").write(json.dumps({
  "schema":"rh-succession-input/2","complete_months":12,
  "predecessor":0,"successor":1,"handover_month":5,"follow_up_months":6,
  "presence":[alice,bob]}))
PY
"$ROOT/build/rh_cli" succession --input "$T/follow-up.json" --out "$T/follow-up.out" >/dev/null || fail "follow-up run"
python3 - "$T/follow-up.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["handover_month"] == 5, d
assert d["follow_up"] == {"requested_months":6,"observed_months":6,"successor_active_months":6}, d
m = {x["key"]: x for x in d["metrics"]}["succession.successor_follow_up_active_months"]
assert m["status"] == "observed" and m["value"] == 6, m
print("[succession] complete follow-up OK")
PY
python3 - "$T/follow-up.json" "$T/censored.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["follow_up_months"] = 10
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" succession --input "$T/censored.json" --out "$T/censored.out" >/dev/null || fail "censored follow-up run"
python3 - "$T/censored.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["follow_up"] == {"requested_months":10,"observed_months":6,"successor_active_months":6}, d
m = {x["key"]: x for x in d["metrics"]}["succession.successor_follow_up_active_months"]
assert m["status"] == "partial" and m["value"] == 6 and m["requested_months"] == 10, m
print("[succession] right-censored follow-up OK")
PY

echo "[succession] activity-derived primary changes use unique monthly maxima"
cp "$ROOT/fixtures/succession/input-v3.json" "$T/activity.json"
"$ROOT/build/rh_cli" succession --input "$T/activity.json" --out "$T/activity.out" >/dev/null || fail "activity-derived primary run"
python3 - "$T/activity.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["activity_primary_actor_change_by_month"] == [None,None,None,False,True,False], d
m = {x["key"]: x for x in d["metrics"]}["succession.activity_primary_actor_changes"]
assert m["status"] == "observed" and m["value"] == 1 and m["eligible_month_pairs"] == 3, m
print("[succession] ties break the series; only adjacent known primary actors are compared")
PY

echo "[succession] absent declared pair is not_applicable (never zero)"
python3 - "$T/nopair.json" <<'PY'
import json, sys
alice = [True]*6 + [False]*6
bob = [False]*3 + [True]*9
open(sys.argv[1], "w").write(json.dumps({
  "schema":"rh-succession-input/1","complete_months":12,"presence":[alice,bob]}))
PY
"$ROOT/build/rh_cli" succession --input "$T/nopair.json" --out "$T/np.json" >/dev/null || fail "no-pair run"
python3 - "$T/np.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "not_applicable", d
assert "no-declared" in d["reason"], d
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["succession.declared_handovers"]["status"] == "not_applicable", metrics
assert metrics["succession.observed_activity_overlap_months"]["status"] == "not_applicable", metrics
print("[succession] not_applicable OK")
PY

echo "[succession] predecessor == successor is not_applicable"
python3 - "$T/same.json" <<'PY'
import json, sys
alice = [True]*6 + [False]*6
open(sys.argv[1], "w").write(json.dumps({
  "schema":"rh-succession-input/1","complete_months":12,
  "predecessor":0,"successor":0,"presence":[alice]}))
PY
"$ROOT/build/rh_cli" succession --input "$T/same.json" --out "$T/same.out" >/dev/null || fail "same-actor run"
python3 - "$T/same.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "not_applicable" and "same-actor" in d["reason"], d
print("[succession] same-actor OK")
PY

echo "[succession] determinism"
a="$("$ROOT/build/rh_cli" succession --input "$T/in.json" --out "$T/d1" >/dev/null; cat "$T/d1")"
b="$("$ROOT/build/rh_cli" succession --input "$T/in.json" --out "$T/d2" >/dev/null; cat "$T/d2")"
[[ "$a" == "$b" ]] || fail "succession must be deterministic"

echo "[succession] malformed input fails closed"
check_rc() {
  printf '%s' "$1" > "$T/bad.json"
  "$ROOT/build/rh_cli" succession --input "$T/bad.json" --out "$T/bad.out" >/dev/null 2>&1
  echo $?
}
set +e
rc1=$(check_rc '{"schema":"rh-succession-input/2","complete_months":12,"presence":[]}')
rc2=$(check_rc '{"schema":"rh-succession-input/1","presence":[]}')
rc3=$(check_rc '{"schema":"rh-succession-input/1","complete_months":12}')
rc4=$(check_rc '{"schema":"rh-succession-input/1","complete_months":12,"presence":[[true,false]]}')
rc5=$(check_rc '{"schema":"rh-succession-input/1","complete_months":12,"predecessor":0,"successor":1,"presence":[[1,0]]}')
rc6=$(check_rc 'not json')
rc8=$(check_rc '{"schema":"rh-succession-input/2","complete_months":12,"presence":[]}')
rc9=$(check_rc '{"schema":"rh-succession-input/3","complete_months":2,"handover_month":0,"follow_up_months":1,"presence":[[true,false]],"activity_counts":[[1,-1]]}')
rc10=$(check_rc '{"schema":"rh-succession-input/3","complete_months":2,"handover_month":0,"follow_up_months":1,"presence":[[true,false]],"activity_counts":[[1]]}')
rc11=$(check_rc '{"schema":"rh-succession-input/3","complete_months":2,"handover_month":0,"follow_up_months":1,"presence":[[true,false]],"activity_counts":[[0,0]]}')
rc12=$(check_rc '{"schema":"rh-succession-input/3","complete_months":2,"handover_month":0,"follow_up_months":1,"presence":[[true,false]],"activity_counts":[[1,0],[0,0]]}')
"$ROOT/build/rh_cli" succession --input "$T/nope.json" --out "$T/x.out" >/dev/null 2>&1
rc7=$?
set -e
for rc in "$rc1" "$rc2" "$rc3" "$rc4" "$rc5" "$rc6" "$rc7" "$rc8" "$rc9" "$rc10" "$rc11" "$rc12"; do
  [[ "$rc" -eq 4 ]] || fail "malformed succession input must exit 4 (got $rc)"
done

echo "test_succession_cli OK"
