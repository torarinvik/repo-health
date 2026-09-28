#!/usr/bin/env bash
# tests/test_lineage_cli.sh — RP-02 evidence lineage and transformation contract (`rh-lineage-input/1`).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-lineage"

fail() { echo "[lineage] FAIL: $1" >&2; exit 1; }

echo "[lineage] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/lineage/input.json" "$T/in.json"
"$ROOT/build/rh_cli" lineage --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "lineage run"
cmp -s "$T/out.json" "$ROOT/fixtures/lineage/result.json" || fail "lineage result differs from the checked-in golden"
python3 - "$T/in.json" "$T/pretty-input.json" <<'PY'
import json, sys
json.dump(json.load(open(sys.argv[1])), open(sys.argv[2], "w"), indent=2)
PY
"$ROOT/build/rh_cli" lineage --input "$T/pretty-input.json" --out "$T/pretty-output.json" >/dev/null || fail "pretty-printed lineage run"
cmp -s "$T/out.json" "$T/pretty-output.json" || fail "lineage serialization depends on observation input formatting"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-lineage-result/1", d
assert d["observation_id"] == "observation-42", d
assert d["subject"] == {"type": "repository", "id": "repo:acme/project"}, d
assert d["lineage"]["source"] == "github" and d["lineage"]["native_object_id"] == "issue-42", d
assert d["payload"]["retained_object"].startswith("evidence:sha256:"), d
assert d["rights"]["license_reference"] == "https://example.invalid/terms/data-use", d
assert d["times"]["event_time"] is None and d["times"]["updated_at"] == 1700000010, d
assert d["times"]["valid_from"] == 1699999800 and d["times"]["valid_until"] == 1700001000, d
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
assert d["metrics"][0]["observation"]["value"] == {"kind": "count", "value": 17}, d
assert d["metrics"][0]["observation"]["evidence"] == ["raw/issues/42"], d
assert d["metrics"][1]["observation"] is None, d
assert "definition_digest" in d["metrics"][1], d
assert "losses remain explicit" in d["note"], d
print("[lineage] separate delivery/origin identities + explicit losses OK")
PY

python3 - "$T/in.json" "$T/legacy-v1.json" <<'PY'
import json, sys
document = json.load(open(sys.argv[1]))
for field in ("observation_id", "subject_type", "subject_id", "retained_object",
              "license_reference", "valid_from", "valid_until"):
    document.pop(field)
json.dump(document, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" lineage --input "$T/legacy-v1.json" --out "$T/legacy-v1-result.json" >/dev/null || fail "legacy lineage v1 must remain accepted"
python3 - "$T/legacy-v1-result.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
assert report["observation_id"] is None
assert report["subject"] == {"type": None, "id": None}
assert report["payload"]["retained_object"] is None
assert report["rights"]["license_reference"] is None
assert report["times"]["valid_from"] is None and report["times"]["valid_until"] is None
print("[lineage] v1 optional provenance additions remain backward compatible")
PY

python3 - "$T/in.json" "$T/incomplete-identity.json" <<'PY'
import json, sys
document = json.load(open(sys.argv[1]))
for field in (
    "assessment_tool", "assessment_tool_version", "assessment_subject_revision",
    "assessment_original_run", "assessment_original_time", "assessment_result_digest",
):
    document.pop(field)
document.pop("valid_from")
document.pop("valid_until")
document["license_reference"] = None
json.dump(document, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" lineage --input "$T/incomplete-identity.json" --out "$T/incomplete-identity-result.json" >/dev/null || fail "incomplete origin identity should remain observable"
python3 - "$T/incomplete-identity-result.json" <<'PY'
import json, sys
assessment = json.load(open(sys.argv[1]))["assessment"]
assert assessment["identity_complete"] is False, assessment
assert assessment["deduplication_state"] == "possible_duplicate", assessment
assert assessment["origin"] == {
    "tool": None, "tool_version": None, "subject_revision": None,
    "original_run": None, "original_time": None, "result_digest": None,
}, assessment
assert json.load(open(sys.argv[1]))["times"]["valid_from"] is None
assert json.load(open(sys.argv[1]))["times"]["valid_until"] is None
assert json.load(open(sys.argv[1]))["rights"]["license_reference"] is None
print("[lineage] incomplete origin identity remains possible duplicate")
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
sed 's/"valid_until":1700001000/"valid_until":1699999800/' "$T/in.json" > "$T/bad-valid-interval.json"
"$ROOT/build/rh_cli" lineage --input "$T/bad-valid-interval.json" --out "$T/x" >/dev/null 2>&1; rc_valid_interval=$?
sed 's/"assessment_tool":"repo-health"/"assessment_tool":7/' "$T/in.json" > "$T/bad-assessment-tool.json"
"$ROOT/build/rh_cli" lineage --input "$T/bad-assessment-tool.json" --out "$T/x" >/dev/null 2>&1; rc_tool=$?
sed 's/"assessment_result_digest":"[0-9a-f]*/"assessment_result_digest":"BAD/' "$T/in.json" > "$T/bad-assessment-digest.json"
"$ROOT/build/rh_cli" lineage --input "$T/bad-assessment-digest.json" --out "$T/x" >/dev/null 2>&1; rc_assessment_digest=$?
sed 's/"assessment_subject_revision":7/"assessment_subject_revision":-1/' "$T/in.json" > "$T/bad-subject-revision.json"
"$ROOT/build/rh_cli" lineage --input "$T/bad-subject-revision.json" --out "$T/x" >/dev/null 2>&1; rc_revision=$?
sed 's/"subject_type":"repository"/"subject_type":"unknown"/' "$T/in.json" > "$T/bad-subject-type.json"
"$ROOT/build/rh_cli" lineage --input "$T/bad-subject-type.json" --out "$T/x" >/dev/null 2>&1; rc_subject_type=$?
sed 's/"retained_object":"evidence:sha256:[^"]*"/"retained_object":""/' "$T/in.json" > "$T/empty-retained-object.json"
"$ROOT/build/rh_cli" lineage --input "$T/empty-retained-object.json" --out "$T/x" >/dev/null 2>&1; rc_retained_object=$?
python3 - "$T/in.json" "$T/duplicate-coverage.json" <<'PY'
import sys
payload = open(sys.argv[1]).read()
needle = '"coverage":"partial"'
assert payload.count(needle) == 1
open(sys.argv[2], "w").write(payload.replace(needle, needle + ',"coverage":"complete"', 1))
PY
"$ROOT/build/rh_cli" lineage --input "$T/duplicate-coverage.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate=$?
python3 - "$T/in.json" "$T/duplicate-transformation-state.json" <<'PY'
import sys
payload = open(sys.argv[1]).read()
needle = '"state":"preserved"'
assert payload.count(needle) == 1
open(sys.argv[2], "w").write(payload.replace(needle, needle + ',"state":"discarded"', 1))
PY
"$ROOT/build/rh_cli" lineage --input "$T/duplicate-transformation-state.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate_state=$?
set -e
[[ "$rc_coverage" -eq 4 && "$rc_digest" -eq 4 && "$rc_state" -eq 4 && "$rc_class" -eq 4 && "$rc_time" -eq 4 && "$rc_valid_interval" -eq 4 && "$rc_tool" -eq 4 && "$rc_assessment_digest" -eq 4 && "$rc_revision" -eq 4 && "$rc_subject_type" -eq 4 && "$rc_retained_object" -eq 4 && "$rc_duplicate" -eq 4 && "$rc_duplicate_state" -eq 4 ]] || fail "invalid lineage must exit 4 (got $rc_coverage/$rc_digest/$rc_state/$rc_class/$rc_time/$rc_valid_interval/$rc_tool/$rc_assessment_digest/$rc_revision/$rc_subject_type/$rc_retained_object/$rc_duplicate/$rc_duplicate_state)"
echo "[lineage] duplicate root and nested object keys rejected"
python3 - "$T/in.json" "$T/duplicate-ref.json" "$T/over-bound-refs.json" "$T/over-bound-transformations.json" "$T/over-bound-metrics.json" <<'PY'
import json, sys
document = json.load(open(sys.argv[1]))
document["derivation_refs"] = ["same", "same"]
json.dump(document, open(sys.argv[2], "w"), separators=(",", ":"))
document["derivation_refs"] = [f"ref-{index}" for index in range(1025)]
json.dump(document, open(sys.argv[3], "w"), separators=(",", ":"))
document["derivation_refs"] = []
document["transformations"] = [
    {"field": f"field-{index}", "state": "preserved", "reason": "copied"}
    for index in range(1025)
]
json.dump(document, open(sys.argv[4], "w"), separators=(",", ":"))
document["transformations"] = []
document["metrics"] = [
    {"key": f"metric-{index}", "version": "1", "definition_digest": "1" * 64,
     "class": "raw", "crosswalk": "test"}
    for index in range(1025)
]
json.dump(document, open(sys.argv[5], "w"), separators=(",", ":"))
PY
set +e
"$ROOT/build/rh_cli" lineage --input "$T/duplicate-ref.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate_ref=$?
"$ROOT/build/rh_cli" lineage --input "$T/over-bound-refs.json" --out "$T/x" >/dev/null 2>&1; rc_refs_bound=$?
"$ROOT/build/rh_cli" lineage --input "$T/over-bound-transformations.json" --out "$T/x" >/dev/null 2>&1; rc_transformations_bound=$?
"$ROOT/build/rh_cli" lineage --input "$T/over-bound-metrics.json" --out "$T/x" >/dev/null 2>&1; rc_metrics_bound=$?
set -e
[[ "$rc_duplicate_ref" -eq 4 && "$rc_refs_bound" -eq 4 && "$rc_transformations_bound" -eq 4 && "$rc_metrics_bound" -eq 4 ]] || fail "duplicate and over-bound lineage collections must fail closed (got $rc_duplicate_ref/$rc_refs_bound/$rc_transformations_bound/$rc_metrics_bound)"
echo "[lineage] derivation references, transformations, and metrics are bounded"
python3 - "$T/in.json" "$T/orphan-observation-evidence.json" <<'PY'
import json, sys
document = json.load(open(sys.argv[1]))
document["metrics"][0]["observation"]["evidence"] = ["not-in-derivation-refs"]
json.dump(document, open(sys.argv[2], "w"), separators=(",", ":"))
PY
set +e
"$ROOT/build/rh_cli" lineage --input "$T/orphan-observation-evidence.json" --out "$T/x" >/dev/null 2>&1
rc_orphan_observation=$?
set -e
[[ "$rc_orphan_observation" -eq 4 ]] || fail "unlinked observation evidence must fail closed (got $rc_orphan_observation)"
python3 - "$T/in.json" "$T/malformed-observation.json" <<'PY'
import json, sys
document = json.load(open(sys.argv[1]))
document["metrics"][0]["observation"]["status"] = 255
json.dump(document, open(sys.argv[2], "w"), separators=(",", ":"))
PY
set +e
"$ROOT/build/rh_cli" lineage --input "$T/malformed-observation.json" --out "$T/x" >/dev/null 2>&1
rc_bad_observation=$?
set -e
[[ "$rc_bad_observation" -eq 4 ]] || fail "malformed metric observation must fail closed (got $rc_bad_observation)"
echo "[lineage] metric observations retain linked external evidence"

python3 - "$T/oversized.json" <<'PY'
import sys
with open(sys.argv[1], "wb") as output:
    output.write(b" " * (4 * 1024 * 1024 + 1))
PY
set +e
"$ROOT/build/rh_cli" lineage --input "$T/oversized.json" --out "$T/x" >/dev/null 2>&1
rc_size=$?
set -e
[[ "$rc_size" -eq 4 ]] || fail "oversized lineage must fail before parsing (got $rc_size)"
echo "[lineage] input bound enforced"

echo "test_lineage_cli OK"
