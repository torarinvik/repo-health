#!/usr/bin/env bash
# tests/test_intervention_cli.sh — M11 intervention evaluation evidence.
# Scope, selection, baseline, comparison, outcomes, and limitations remain
# explicit; before/after counts never become causal or prevented-incident claims.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-intervention"

fail() { echo "[intervention] FAIL: $1" >&2; exit 1; }

echo "[intervention] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-intervention-input/1","intervention_id":"support-2026-01","scope":"project-family:alpha","selection_rationale":"owner-requested maintainer support","baseline":{"window_start":1700000000,"window_end":1702592000,"event_count":12},"comparison":{"design":"matched_control","control_group":"project-family:beta","window_days":30},"outcomes":[{"metric":"release_events","before":{"num":2,"den":4},"after":{"num":3,"den":4}}],"limitations":["observational selection","short horizon"]}
JSON
"$ROOT/build/rh_cli" intervention --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "intervention run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-intervention-result/1", d
assert d["status"] == "observational", d
assert d["baseline"]["event_count"] == 12, d
assert d["comparison"]["design"] == "matched_control", d
assert d["outcome_count"] == 1 and d["outcomes"][0]["after"] == {"num": 3, "den": 4}, d
assert d["limitations"] == ["observational selection", "short horizon"], d
assert "do not establish causal benefit" in d["note"], d
print("[intervention] design + outcome evidence OK")
PY

echo "[intervention] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" intervention --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "intervention output not deterministic"
set +e
sed 's/"limitations":\["observational selection","short horizon"\]/"limitations":[]/' "$T/in.json" > "$T/bad-limits.json"
"$ROOT/build/rh_cli" intervention --input "$T/bad-limits.json" --out "$T/x" >/dev/null 2>&1; rc_limits=$?
sed 's/"window_end":1702592000/"window_end":1602592000/' "$T/in.json" > "$T/bad-window.json"
"$ROOT/build/rh_cli" intervention --input "$T/bad-window.json" --out "$T/x" >/dev/null 2>&1; rc_window=$?
printf 'not json' > "$T/notjson"
"$ROOT/build/rh_cli" intervention --input "$T/notjson" --out "$T/x" >/dev/null 2>&1; rc_json=$?
set -e
[[ "$rc_limits" -eq 4 && "$rc_window" -eq 4 && "$rc_json" -eq 4 ]] || fail "invalid intervention must exit 4 (got $rc_limits/$rc_window/$rc_json)"

echo "test_intervention_cli OK"
