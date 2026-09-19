#!/usr/bin/env bash
# tests/test_forecast_cli.sh — M11 forecast evidence adapter. Evaluation
# splits, exact scores/calibration, and opt-in labels are retained; the
# adapter never changes policy decisions.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-forecast"

fail() { echo "[forecast] FAIL: $1" >&2; exit 1; }

echo "[forecast] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-forecast-input/1","model_id":"prior-activity/1","population":"project-family","baseline":"prior_activity","cutoff":1700000000,"horizon_days":30,"split":{"temporal":true,"family_separated":true,"censoring_aware":true},"predictions":[{"subject_id":1,"label":"event","score":{"num":1,"den":2}},{"subject_id":2,"label":"no_event","score":{"num":0,"den":1}}],"calibration":{"brier":{"num":1,"den":4},"false_positive_count":1,"subgroup_coverage_percent":80,"alert_burden":{"num":1,"den":10},"sample_count":20}}
JSON
"$ROOT/build/rh_cli" forecast --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "forecast run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-forecast-result/1", d
assert d["status"] == "experimental", d
assert d["split"] == {"temporal": True, "family_separated": True, "censoring_aware": True}, d
assert d["prediction_count"] == 2 and d["predictions"][0]["score"] == {"num": 1, "den": 2}, d
assert d["calibration"]["brier"] == {"num": 1, "den": 4}, d
assert d["calibration"]["alert_burden"] == {"num": 1, "den": 10}, d
assert "cannot change default policy decisions" in d["note"], d
print("[forecast] split + exact calibration evidence OK")
PY

echo "[forecast] determinism + invalid split/score fail closed"
"$ROOT/build/rh_cli" forecast --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "forecast output not deterministic"
set +e
sed 's/"censoring_aware":true/"censoring_aware":false/' "$T/in.json" > "$T/bad-split.json"
"$ROOT/build/rh_cli" forecast --input "$T/bad-split.json" --out "$T/x" >/dev/null 2>&1; rc_split=$?
sed 's/"num":1,"den":2/"num":3,"den":2/' "$T/in.json" > "$T/bad-score.json"
"$ROOT/build/rh_cli" forecast --input "$T/bad-score.json" --out "$T/x" >/dev/null 2>&1; rc_score=$?
printf 'not json' > "$T/notjson"
"$ROOT/build/rh_cli" forecast --input "$T/notjson" --out "$T/x" >/dev/null 2>&1; rc_json=$?
set -e
[[ "$rc_split" -eq 4 && "$rc_score" -eq 4 && "$rc_json" -eq 4 ]] || fail "invalid forecast must exit 4 (got $rc_split/$rc_score/$rc_json)"

echo "test_forecast_cli OK"
