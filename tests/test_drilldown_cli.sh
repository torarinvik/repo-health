#!/usr/bin/env bash
# tests/test_drilldown_cli.sh — RP-07 lineage-aware evidence drill-down.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-drilldown"

fail() { echo "[drilldown] FAIL: $1" >&2; exit 1; }

echo "[drilldown] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/lineage-input.json" <<'JSON'
{"schema":"rh-lineage-input/1","source":"github","source_instance":"github.com/acme/repo","native_object_id":"repo@abc123","locator":"https://github.com/acme/repo","collection_run":"run-1","scope":"public-repo","coverage":"complete","payload_schema":"rh-scorecard-findings-input/1","payload_digest":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","collector_version":"collector-1","config_digest":"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd","rights_class":"public","retention_class":"bounded","delivery_id":"delivery-1","assessment_tool":"OpenSSF Scorecard","assessment_tool_version":"5.0.0","assessment_original_run":"scorecard-run-1","assessment_result_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","observed_at":1700000000,"event_time":null,"updated_at":null,"delivery_time":1700000010,"assessment_subject_revision": "abc123","assessment_original_time":1700000000,"derivation_refs":["scorecard-input"],"transformations":[{"field":"finding.locations","state":"preserved","reason":"retained"},{"field":"finding.remediation","state":"discarded","reason":"not present"}],"metrics":[{"key":"findings.count","version":"1","class":"raw","crosswalk":"assessment total"}]}
JSON
# The lineage contract uses an integer subject revision; keep the test input
# strictly typed while preserving the source revision in the findings result.
sed 's/"assessment_subject_revision": "abc123"/"assessment_subject_revision": 1/' "$T/lineage-input.json" > "$T/lineage-typed.json"
"$ROOT/build/rh_cli" lineage --input "$T/lineage-typed.json" --out "$T/lineage.json" >/dev/null || fail "lineage run"
cp "$ROOT/fixtures/packages/scorecard-findings.json" "$T/scorecard-findings.json"
"$ROOT/build/rh_cli" findings --input "$T/scorecard-findings.json" --out "$T/findings.json" >/dev/null || fail "findings run"
python3 - "$T/lineage.json" "$T/findings.json" "$T/input.json" <<'PY'
import json, sys
lin = json.load(open(sys.argv[1])); fin = json.load(open(sys.argv[2]))
json.dump({"schema":"rh-drilldown-input/1", "lineage":lin, "findings":fin}, open(sys.argv[3], "w"), separators=(",", ":"))
PY

"$ROOT/build/rh_cli" drilldown --input "$T/input.json" --out "$T/out.json" >/dev/null || fail "drilldown run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-evidence-drilldown/1", d
assert d["source_payload"]["digest"] == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", d
assert d["source_payload"]["locator"].startswith("https://github.com"), d
assert d["delivery"]["id"] == "delivery-1", d
assert d["origin_assessment"]["tool"] == "OpenSSF Scorecard", d
assert d["finding_assessment"]["tool_version"] == "5.0.0", d
assert d["summary"] == {"total": 2, "pass": 1, "fail": 0, "unknown": 1, "omitted": 0, "inconclusive": 0, "error": 0}, d
assert d["transformations"][1]["state"] == "discarded", d
assert "source payload identity" in d["note"], d
print("[drilldown] source payload + typed finding + transformation links OK")
PY

echo "[drilldown] determinism + mismatched origin fails closed"
"$ROOT/build/rh_cli" drilldown --input "$T/input.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "drilldown output not deterministic"
sed 's/"tool_version":"5.0.0"/"tool_version":"9.9.9"/' "$T/input.json" > "$T/bad-origin.json"
set +e
"$ROOT/build/rh_cli" drilldown --input "$T/bad-origin.json" --out "$T/x" >/dev/null 2>&1; rc_origin=$?
printf '{"schema":"rh-drilldown-input/2"}' > "$T/bad-schema.json"
"$ROOT/build/rh_cli" drilldown --input "$T/bad-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
set -e
[[ "$rc_origin" -eq 4 && "$rc_schema" -eq 4 ]] || fail "invalid drilldown must exit 4 (got $rc_origin/$rc_schema)"

echo "test_drilldown_cli OK"
