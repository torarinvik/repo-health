#!/usr/bin/env bash
# tests/test_lineage_cli.sh — RP-02 evidence lineage and transformation contract.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-lineage"

fail() { echo "[lineage] FAIL: $1" >&2; exit 1; }

echo "[lineage] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-lineage-input/1","source":"github","source_instance":"github.com/acme/repo","native_object_id":"issue-42","locator":"https://github.com/acme/repo/issues/42","collection_run":"run-20260919","scope":"public-issues","coverage":"partial","payload_schema":"rh-findings-result/1","payload_digest":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","collector_version":"collector-3","config_digest":"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd","rights_class":"public","retention_class":"bounded-30d","delivery_id":"delivery-42","assessment_tool":"repo-health","assessment_tool_version":"1.4.0","assessment_original_run":"assessment-17","assessment_result_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","observed_at":1700000000,"event_time":null,"updated_at":1700000010,"delivery_time":1700000020,"assessment_subject_revision":7,"assessment_original_time":1699999900,"derivation_refs":["raw/issues/42","normalized/issues/42"],"transformations":[{"field":"title","state":"preserved","reason":"copied without loss"},{"field":"body","state":"transformed","reason":"markdown normalized"},{"field":"author_role","state":"inferred","reason":"role mapping"},{"field":"private_note","state":"discarded","reason":"rights scope"},{"field":"reaction","state":"unsupported","reason":"provider omitted field"}],"metrics":[{"key":"findings.count","version":"1","definition_digest":"1111111111111111111111111111111111111111111111111111111111111111","class":"raw","crosswalk":"native issue count"},{"key":"findings.rate","version":"2","definition_digest":"2222222222222222222222222222222222222222222222222222222222222222","class":"derived","crosswalk":"metric registry findings.rate/2"},{"key":"findings.rate","version":"3","definition_digest":"3333333333333333333333333333333333333333333333333333333333333333","class":"derived","crosswalk":"metric registry findings.rate/3 definition update"},{"key":"risk.score","version":"1","definition_digest":"4444444444444444444444444444444444444444444444444444444444444444","class":"modeled","crosswalk":"experimental model score"}]}
JSON
"$ROOT/build/rh_cli" lineage --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "lineage run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-lineage-result/1", d
assert d["lineage"]["source"] == "github" and d["lineage"]["native_object_id"] == "issue-42", d
assert d["times"]["event_time"] is None and d["times"]["updated_at"] == 1700000010, d
assert d["collection"]["coverage"]["state"] == "partial", d
assert d["assessment"]["delivery"]["id"] == "delivery-42", d
assert d["assessment"]["origin"]["original_run"] == "assessment-17", d
assert d["assessment"]["dedup_scope"] == "origin_assessment", d
assert d["assessment"]["identity_complete"] is True, d
assert d["transformation_counts"] == {"preserved": 1, "transformed": 1, "inferred": 1, "discarded": 1, "unsupported": 1}, d
assert d["metric_class_counts"] == {"raw": 1, "derived": 2, "modeled": 1}, d
assert d["transformations"][3]["state"] == "discarded", d
assert d["metrics"][2]["version"] == "3" and d["metrics"][2]["definition_digest"] == "3" * 64, d
assert d["metrics"][3]["class"] == "modeled", d
assert "definition_digest" in d["metrics"][1], d
assert "losses remain explicit" in d["note"], d
print("[lineage] separate delivery/origin identities + explicit losses OK")
PY

echo "[lineage] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" lineage --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "lineage output not deterministic"
set +e
sed 's/"coverage":"partial"/"coverage":"unknown"/' "$T/in.json" > "$T/bad-coverage.json"
"$ROOT/build/rh_cli" lineage --input "$T/bad-coverage.json" --out "$T/x" >/dev/null 2>&1; rc_coverage=$?
sed 's/"payload_digest":"[0-9a-f]*/"payload_digest":"BAD/' "$T/in.json" > "$T/bad-digest.json"
"$ROOT/build/rh_cli" lineage --input "$T/bad-digest.json" --out "$T/x" >/dev/null 2>&1; rc_digest=$?
sed 's/"state":"discarded"/"state":"unknown"/' "$T/in.json" > "$T/bad-state.json"
"$ROOT/build/rh_cli" lineage --input "$T/bad-state.json" --out "$T/x" >/dev/null 2>&1; rc_state=$?
sed 's/"class":"modeled"/"class":"unknown"/' "$T/in.json" > "$T/bad-class.json"
"$ROOT/build/rh_cli" lineage --input "$T/bad-class.json" --out "$T/x" >/dev/null 2>&1; rc_class=$?
sed 's/"event_time":null/"event_time":-1/' "$T/in.json" > "$T/bad-time.json"
"$ROOT/build/rh_cli" lineage --input "$T/bad-time.json" --out "$T/x" >/dev/null 2>&1; rc_time=$?
set -e
[[ "$rc_coverage" -eq 4 && "$rc_digest" -eq 4 && "$rc_state" -eq 4 && "$rc_class" -eq 4 && "$rc_time" -eq 4 ]] || fail "invalid lineage must exit 4 (got $rc_coverage/$rc_digest/$rc_state/$rc_class/$rc_time)"

echo "test_lineage_cli OK"
