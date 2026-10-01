#!/usr/bin/env bash
# tests/test_metric_admission.sh — admission classes and CHAOSS crosswalks
# fail closed when classification or the pinned threshold contract drifts.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$ROOT/build/tmp_metric_admission"

fail() { echo "[metric-admission] FAIL: $1" >&2; exit 1; }

echo "[metric-admission] all versioned metric definitions are classified and crosswalked"
out="$(bash "$ROOT/tools/metric-lint.sh" "$ROOT")" || fail "metric lint"
[[ "$out" == *"229 definitions (implemented=227, prototype=2)"* ]] || fail "unexpected metric catalog: $out"

python3 - "$ROOT" <<'PY'
import glob, json, sys
root = sys.argv[1]
defs = [json.load(open(p)) for p in glob.glob(root + "/metrics/definitions/*.json")]
assert len(defs) == 229, len(defs)
assert {d["measurement_class"] for d in defs} == {"raw", "derived", "modeled"}
assert all(d["measurement_class"] == "modeled" for d in defs if d.get("group") == "experimental")
mapped = [
    (d, c)
    for d in defs
    for c in d.get("standards_crosswalks", [])
    if c["id"] == "CH-CAF"
]
assert len(mapped) == 2, len(mapped)
roles = {c["local_role"] for _, c in mapped}
assert roles == {"canonical", "compatibility_alias"}, roles
for d, c in mapped:
    assert c["local_metric"] == {"key": d["key"], "version": d["version"]}
    assert c["boundary_rule"] == "inclusive_at_or_above_50_percent"
    assert c["zero_population"] == "not_applicable"
    assert c["alignment"] == "conceptual_match_with_population_scope_difference"
    assert c["source_revision_status"] == "default_branch_file_not_commit_pinned"
print("[metric-admission] class coverage and CHAOSS population/boundary contract OK")
PY

echo "[metric-admission] dependency metric definitions match emitted evidence and denominator semantics"
python3 - "$ROOT" <<'PY'
import glob, json, sys
root = sys.argv[1]
definitions = {d["key"]: d for d in
               (json.load(open(path)) for path in glob.glob(root + "/metrics/definitions/*.json"))}
observed = json.load(open(root + "/fixtures/deps-metrics/cargo-npm-osv.json"))
without_osv = json.load(open(root + "/fixtures/deps-metrics/cargo-npm-no-osv.json"))
observed_rows = {row["key"]: row for row in observed["metrics"]}
without_osv_rows = {row["key"]: row for row in without_osv["metrics"]}
assert len(observed_rows) == 38 and observed_rows.keys() == without_osv_rows.keys()
source_evidence = {
    "captured-dependency-manifest": "dependency-input",
    "captured-osv": "osv-input",
}
for key, row in observed_rows.items():
    definition = definitions[key]
    expected_sources = {"captured-dependency-manifest"}
    if key.startswith("security."):
        expected_sources.add("captured-osv")
    assert set(definition["source_requirements"]) == expected_sources, (key, definition["source_requirements"])
    assert set(row["evidence"]) == {source_evidence[source] for source in expected_sources}, (key, row["evidence"])
    output_type = definition["output"]["type"]
    denominator = definition["denominator_rule"]
    if output_type == "integer":
        assert type(row["value"]) is int and (denominator == "none" or denominator.startswith("none;")), (key, row, denominator)
    elif output_type == "boolean":
        assert type(row["value"]) is bool and (denominator == "none" or denominator.startswith("none;")), (key, row, denominator)
    elif output_type == "ratio":
        assert set(row["value"]) == {"num", "den"} and row["value"]["den"] > 0, (key, row)
        assert "denominator" in definition["output"] and not denominator.startswith("none"), (key, definition)
    else:
        raise AssertionError((key, output_type))
for key, row in without_osv_rows.items():
    if key.startswith("security."):
        assert row["status"] == "unavailable" and row["value"] is None and row["evidence"] == [], (key, row)
    else:
        assert row["status"] == "observed" and row["evidence"] == ["dependency-input"], (key, row)
assert definitions["dependencies.unsupported_range_count"]["subject_kind"] == "project"
assert definitions["dependency.resolved_transitive_versions"]["inputs"] == ["resolved_dependency_graph", "selected_graph_root"]
assert "direct destinations" in definitions["dependency.resolved_transitive_versions"]["denominator_rule"]
assert definitions["dependency.artifact_digest_coverage"]["output"]["denominator"] == "all unique resolved edge-destination package nodes"
assert definitions["dependency.maximum_observed_depth"]["denominator_rule"].startswith("none;")
assert definitions["dependency.resolution_complete"]["denominator_rule"].startswith("none;")
print("[metric-admission] 38 dependency rows, emitted evidence, no-OSV states, and denominator rules agree")
PY

echo "[metric-admission] missing class is rejected"
rm -rf "$TMP"
mkdir -p "$TMP/metrics"
cp -R "$ROOT/metrics/definitions" "$TMP/metrics/definitions"
cp "$ROOT/metrics/source-requirements.json" "$TMP/metrics/source-requirements.json"
mkdir -p "$TMP/fixtures"
cp "$ROOT/fixtures/fixture-catalog.json" "$TMP/fixtures/fixture-catalog.json"
python3 - "$TMP/metrics/definitions/activity_accepted_changes.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
del d["measurement_class"]
json.dump(d, open(p, "w"))
PY
if bash "$ROOT/tools/metric-lint.sh" "$TMP" >"$TMP/missing-class.log" 2>&1; then
  fail "missing measurement_class was accepted"
fi
grep -q "missing base field.*measurement_class" "$TMP/missing-class.log" || fail "missing class failed for an unexpected reason"

echo "[metric-admission] changed CHAOSS threshold boundary is rejected"
rm -rf "$TMP/metrics/definitions"
cp -R "$ROOT/metrics/definitions" "$TMP/metrics/definitions"
python3 - "$TMP/metrics/definitions/concentration_change_absence_factor_50.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["standards_crosswalks"][0]["boundary_rule"] = "strictly_above_50_percent"
json.dump(d, open(p, "w"))
PY
if bash "$ROOT/tools/metric-lint.sh" "$TMP" >"$TMP/boundary.log" 2>&1; then
  fail "changed CHAOSS threshold boundary was accepted"
fi
grep -q "CAF threshold boundary changed" "$TMP/boundary.log" || fail "boundary failed for an unexpected reason"

echo "[metric-admission] entity, output type, source, and fixture references are checked"
for case_name in subject_kind output_type cost_class privacy_class ratio_denominator source_requirement fixture_reference; do
  rm -rf "$TMP/metrics/definitions"
  cp -R "$ROOT/metrics/definitions" "$TMP/metrics/definitions"
  python3 - "$TMP/metrics/definitions" "$case_name" <<'PY'
import json, sys
p, case_name = sys.argv[1:]
name = "activity_bot_event_share.json" if case_name == "ratio_denominator" else "activity_accepted_changes.json"
p = p + "/" + name
d = json.load(open(p))
if case_name == "subject_kind": d["subject_kind"] = "unknown"
elif case_name == "output_type": d["output"]["type"] = "ratio"
elif case_name == "cost_class": d["cost_class"] = "unbounded"
elif case_name == "privacy_class": d["privacy_class"] = "individual"
elif case_name == "ratio_denominator": del d["output"]["denominator"]
elif case_name == "source_requirement": d["source_requirements"] = ["undeclared-source"]
else: d["fixture_references"] = ["F999"]
json.dump(d, open(p, "w"))
PY
  if bash "$ROOT/tools/metric-lint.sh" "$TMP" >"$TMP/$case_name.log" 2>&1; then
    fail "$case_name mutation was accepted"
  fi
done
rm -rf "$TMP"

echo "test_metric_admission OK"
