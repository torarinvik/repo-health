#!/usr/bin/env bash
# tests/test_coverage_cli.sh — M05 source-specific capability coverage.
# Validity intervals preserve unknown endpoints as null, while capability
# state remains separate from observed activity and project conclusions.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-coverage"

fail() { echo "[coverage] FAIL: $1" >&2; exit 1; }

echo "[coverage] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-coverage-input/1","source":"github","source_instance":"github.com/acme/project","collected_at":1700003700,"capabilities":[{"capability":"review_events","state":"partial","reason":"page cap","valid_start":null,"valid_end":1700000000,"known_as_of":1700000100},{"capability":"maintainer_permissions","state":"unauthorized","reason":"owner authorization required","valid_start":1690000000,"valid_end":null,"known_as_of":1700000100},{"capability":"git_log","state":"observed","reason":"complete public log","valid_start":1690000000,"valid_end":1700000000,"known_as_of":1700000100}]}
JSON
"$ROOT/build/rh_cli" coverage --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "coverage run"
python3 - "$T/out.json" "$T/in.json" "$T/out.json.transformations.json" "$ROOT" <<'PY'
import glob, hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-coverage-result/1", d
assert d["source"] == "github" and d["source_instance"] == "github.com/acme/project", d
assert d["state_counts"] == {"observed": 1, "partial": 1, "stale": 0, "unavailable": 0, "unauthorized": 1, "not_applicable": 0, "unsupported": 0}, d
metrics = {m["key"]: m for m in d["metrics"]}
definitions = {}
for path in glob.glob(sys.argv[4] + "/metrics/definitions/*.json"):
    definition = json.load(open(path))
    definitions[(definition["key"], definition["version"])] = definition
state_count_inputs = ["capability_coverage_records", "source_instance", "capability_state"]
expected_inputs = {
    "coverage.observed_capability_count": state_count_inputs,
    "coverage.partial_capability_count": state_count_inputs,
    "coverage.stale_capability_count": state_count_inputs,
    "coverage.unavailable_capability_count": state_count_inputs,
    "coverage.unauthorized_capability_count": state_count_inputs,
    "coverage.unsupported_capability_count": state_count_inputs,
    "coverage.not_applicable_capability_count": state_count_inputs,
    "coverage.requested_capabilities": ["source_capability_coverage"],
    "coverage.available_capability_share": ["capability_coverage_records", "applicability_state", "capability_state"],
    "coverage.unauthorized_capabilities": ["capability_coverage_records", "capability_state"],
    "coverage.partial_collection_count": ["capability_coverage_records", "capability_state"],
    "coverage.source_freshness_hours": ["capability_coverage_records", "capability_state", "capability_known_as_of", "collected_at"],
}
assert set(metrics) == set(expected_inputs) and len(metrics) == 12, metrics
for metric in d["metrics"]:
    identity = (metric["key"], metric["version"])
    definition = definitions[identity]
    assert definition["subject_kind"] == "project", (identity, definition)
    assert definition["source_requirements"] == ["captured-capability-coverage"], (identity, definition)
    assert definition["inputs"] == expected_inputs[metric["key"]], (identity, definition.get("inputs"))
    assert metric["evidence"] == ["coverage-input"], (identity, metric)
    output_type = definition["output"]["type"]
    if metric["status"] == "observed":
        if output_type == "integer":
            assert type(metric["value"]) is int, (identity, metric)
            assert definition["denominator_rule"] == "none" or definition["denominator_rule"].startswith("none;"), (identity, definition)
        else:
            assert output_type == "ratio" and set(metric["value"]) == {"num", "den"} and metric["value"]["den"] > 0, (identity, metric)
            assert definition["output"]["numerator"] and definition["output"]["denominator"] and definition["denominator_rule"] == "applicable requested capabilities", (identity, definition)
assert definitions[("coverage.available_capability_share", "1.0.0")]["output"]["numerator"] == "requested capability records in observed, partial, or stale state"
print("[coverage] all 12 metrics match catalog sources, inputs, types, and denominators")
assert metrics["coverage.observed_capability_count"]["value"] == 1, metrics
assert metrics["coverage.partial_capability_count"]["value"] == 1, metrics
assert metrics["coverage.stale_capability_count"]["value"] == 0, metrics
assert metrics["coverage.unavailable_capability_count"]["value"] == 0, metrics
assert metrics["coverage.unauthorized_capability_count"]["value"] == 1, metrics
assert metrics["coverage.not_applicable_capability_count"]["value"] == 0, metrics
assert metrics["coverage.unsupported_capability_count"]["value"] == 0, metrics
assert metrics["coverage.requested_capabilities"]["value"] == 3, metrics
assert metrics["coverage.available_capability_share"]["value"] == {"num": 2, "den": 3}, metrics
assert metrics["coverage.unauthorized_capabilities"]["value"] == 1, metrics
assert metrics["coverage.partial_collection_count"]["value"] == 1, metrics
assert metrics["coverage.source_freshness_hours"]["value"] == 1, metrics
for metric in metrics.values():
    assert metric["status"] == "observed", metric
    assert metric["evidence"] == ["coverage-input"], metric
    assert metric["quality_dimensions"] == {
        "completeness": "complete",
        "freshness": "unknown",
        "validity": "valid",
        "provenance": "evidence_backed",
    }, metric
assert d["capabilities"][0]["valid_start"] is None, d
assert d["capabilities"][1]["valid_end"] is None, d
assert "source-specific" in d["note"], d
tr = json.load(open(sys.argv[3]))
assert tr["schema"] == "rh-adapter-transformation-report/1" and tr["adapter"] == "source-capability-coverage", tr
assert tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/source-capability-coverage/1").hexdigest(), tr
assert {f["state"] for f in tr["fields"]} == {"preserved", "transformed", "unknown", "unsupported", "discarded"}, tr
print("[coverage] intervals + source-specific state evidence OK")
PY

echo "[coverage] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" coverage --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "coverage output not deterministic"
cmp -s "$T/out.json.transformations.json" "$T/out2.json.transformations.json" || fail "coverage transformation report not deterministic"
set +e
sed 's/"state":"partial"/"state":"unknown"/' "$T/in.json" > "$T/bad-state.json"
"$ROOT/build/rh_cli" coverage --input "$T/bad-state.json" --out "$T/x" >/dev/null 2>&1; rc_state=$?
sed 's/"valid_start":null//' "$T/in.json" > "$T/missing-endpoint.json"
"$ROOT/build/rh_cli" coverage --input "$T/missing-endpoint.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
sed 's/"schema":"rh-coverage-input\/1"/"schema":"rh-coverage-input\/2"/' "$T/in.json" > "$T/bad-schema.json"
"$ROOT/build/rh_cli" coverage --input "$T/bad-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
sed 's/,"collected_at":1700003700//' "$T/in.json" > "$T/missing-collected-at.json"
"$ROOT/build/rh_cli" coverage --input "$T/missing-collected-at.json" --out "$T/x" >/dev/null 2>&1; rc_missing_collected=$?
sed 's/"known_as_of":1700000100/"known_as_of":1700003701/' "$T/in.json" > "$T/future-known-at.json"
"$ROOT/build/rh_cli" coverage --input "$T/future-known-at.json" --out "$T/x" >/dev/null 2>&1; rc_future_known=$?
set -e
[[ "$rc_state" -eq 4 && "$rc_missing" -eq 4 && "$rc_schema" -eq 4 && "$rc_missing_collected" -eq 4 && "$rc_future_known" -eq 4 ]] || fail "invalid coverage must exit 4 (got $rc_state/$rc_missing/$rc_schema/$rc_missing_collected/$rc_future_known)"

printf '%s\n' '{"schema":"rh-coverage-input/1","source":"test","source_instance":"test/zero","collected_at":0,"capabilities":[{"capability":"events","state":"observed","reason":"captured at epoch zero","valid_start":0,"valid_end":null,"known_as_of":0}]}' > "$T/epoch-zero.json"
"$ROOT/build/rh_cli" coverage --input "$T/epoch-zero.json" --out "$T/epoch-zero.out" >/dev/null || fail "epoch zero is a valid instant"
python3 - "$T/epoch-zero.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"][0]["valid_start"] == 0, d
assert d["capabilities"][0]["known_as_of"] == 0, d
print("[coverage] epoch zero remains a valid instant")
PY

printf '%s\n' '{"schema":"rh-coverage-input/1","source":"test","source_instance":"test/no-applicable","collected_at":1700000000,"capabilities":[{"capability":"events","state":"not_applicable","reason":"source has no event API","valid_start":null,"valid_end":null,"known_as_of":1700000000}]}' > "$T/no-applicable.json"
"$ROOT/build/rh_cli" coverage --input "$T/no-applicable.json" --out "$T/no-applicable.out" >/dev/null || fail "no-applicable coverage run"
python3 - "$T/no-applicable.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
metrics = {m["key"]: m for m in d["metrics"]}
for key, reason in (
    ("coverage.available_capability_share", "no-applicable-capabilities"),
    ("coverage.source_freshness_hours", "missing-complete-collection-timestamp"),
):
    metric = metrics[key]
    assert metric["status"] == "not_applicable" and metric["value"] is None, metric
    assert metric["reason"] == reason, metric
    assert metric["evidence"] == ["coverage-input"], metric
    assert metric["quality_dimensions"] == {
        "completeness": "unknown",
        "freshness": "unknown",
        "validity": "unknown",
        "provenance": "evidence_backed",
    }, metric
print("[coverage] not-applicable metrics use absent values and unknown quality")
PY

echo "test_coverage_cli OK"
