#!/usr/bin/env bash
# tools/metric-lint.sh — M00-05 / M09 metric admission lint.
#
# Every definition must carry the base contract fields. Anything not yet
# `implemented` must ALSO carry the M09 admission-template fields (inputs,
# output numerator/denominator for ratios, params, missing_behavior,
# confounders) so a planned metric cannot be a bare name. Every metric also
# declares a raw/derived/modeled class, and standards mappings are checked
# against their local key/version. Ratio outputs need an explicit numerator
# and denominator; no metric is publishable without a denominator rule.
set -euo pipefail
ROOT="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

python3 - "$ROOT" <<'PY'
import glob, json, os, re, sys
root = sys.argv[1]
STATUS = {"planned", "prototype", "implemented", "validated", "released", "retired"}
COST = {"low", "medium", "high"}
MEASUREMENT_CLASS = {"raw", "derived", "modeled"}
SUBJECT_KIND = {"project", "repository", "package", "artifact"}
PRIVACY_CLASS = {"project_aggregate"}
base = ["key", "version", "implementation_status", "owner", "subject_kind",
        "output", "denominator_rule", "source_requirements", "cost_class",
        "privacy_class", "fixture_references", "measurement_class"]
admission = ["inputs", "params", "missing_behavior", "confounders"]
seen = {}
files = sorted(glob.glob(os.path.join(root, "metrics", "definitions", "*.json")))
assert files, "no metric definitions"
source_registry = json.load(open(os.path.join(root, "metrics", "source-requirements.json")))
assert source_registry.get("schema") == "rh-metric-source-requirements/1", "bad source requirement registry schema"
source_requirements = source_registry.get("requirements")
assert isinstance(source_requirements, list) and source_requirements, "empty source requirement registry"
assert len(source_requirements) == len(set(source_requirements)), "duplicate source requirement"
assert all(re.fullmatch(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*", x) for x in source_requirements), "bad source requirement identifier"
known_sources = set(source_requirements)
fixture_catalog = json.load(open(os.path.join(root, "fixtures", "fixture-catalog.json")))
fixture_rows = fixture_catalog.get("fixtures", [])
fixture_ids = [f.get("id") for f in fixture_rows]
assert len(fixture_ids) == len(set(fixture_ids)), "duplicate fixture catalog ID"
known_fixtures = {f["id"]: f.get("status") for f in fixture_rows}
assert known_fixtures, "empty fixture catalog"
unit_type = {"ratio": "ratio", "boolean": "boolean", "enum": "enum", "timestamp": "timestamp", "events_per_week_squared": "rational", "events_squared": "rational"}
for p in files:
    d = json.load(open(p))
    for f in base:
        assert f in d and d[f] not in (None, "", [], {}), (p, "missing base field", f)
    assert re.fullmatch(r"\d+\.\d+\.\d+", d["version"]), (p, "bad version", d["version"])
    assert d["implementation_status"] in STATUS, (p, d["implementation_status"])
    assert d["cost_class"] in COST, (p, d["cost_class"])
    assert d["subject_kind"] in SUBJECT_KIND, (p, "unknown subject_kind", d["subject_kind"])
    assert d["privacy_class"] in PRIVACY_CLASS, (p, "unknown privacy_class", d["privacy_class"])
    assert d["measurement_class"] in MEASUREMENT_CLASS, (p, "bad measurement_class", d["measurement_class"])
    if d.get("group") == "experimental":
        assert d["measurement_class"] == "modeled", (p, "experimental metric must be modeled")
    else:
        assert d["measurement_class"] != "modeled", (p, "modeled metric must be isolated as experimental")
    assert d.get("status_note"), (p, "missing status_note")
    out = d["output"]
    assert isinstance(out, dict) and out.get("unit"), (p, "output.unit")
    unit = out["unit"]
    expected_type = unit_type.get(unit, "histogram" if out.get("shape") == "fixed_bucket_histogram" else "integer")
    assert out.get("type") == expected_type, (p, "output unit/type mismatch", unit, out.get("type"), expected_type)
    if out["unit"] == "ratio":
        assert out.get("numerator") and out.get("denominator"), (p, "ratio needs numerator+denominator")
        assert d["denominator_rule"].strip().lower() != "none", (p, "ratio needs a denominator rule")
    if out.get("shape") == "fixed_bucket_histogram":
        assert out["type"] == "histogram" and isinstance(out.get("bucket_upper_seconds"), list) and out["bucket_upper_seconds"] and out["bucket_upper_seconds"][-1] is None, (p, "malformed fixed histogram")
    assert isinstance(d["source_requirements"], list) and d["source_requirements"], (p, "source_requirements must be nonempty")
    assert len(d["source_requirements"]) == len(set(d["source_requirements"])), (p, "duplicate source requirement")
    assert set(d["source_requirements"]) <= known_sources, (p, "unknown source requirement", sorted(set(d["source_requirements"]) - known_sources))
    assert isinstance(d["fixture_references"], list) and d["fixture_references"], (p, "fixture_references must be nonempty")
    assert len(d["fixture_references"]) == len(set(d["fixture_references"])), (p, "duplicate fixture reference")
    missing_fixtures = set(d["fixture_references"]) - known_fixtures.keys()
    assert not missing_fixtures, (p, "unknown fixture reference", sorted(missing_fixtures))
    if d["implementation_status"] in ("implemented", "validated", "released"):
        uncovered = [f for f in d["fixture_references"] if known_fixtures[f] != "covered"]
        assert not uncovered, (p, "implemented metric references an uncovered fixture", uncovered)
    if d["implementation_status"] != "implemented":
        for f in admission:
            assert f in d and d[f] not in (None, "", [], {}), (p, "planned/prototype missing", f)
    # R024: an experimental metric must declare wave, limits, cost, opt-in.
    if d.get("group") == "experimental":
        assert d.get("wave") == "G", (p, "experimental metric must be wave G")
        assert d.get("limits"), (p, "experimental metric needs explicit limits")
        assert d["cost_class"] in ("medium", "high"), (p, "experimental metric must be costed medium/high")
        assert d["implementation_status"] != "implemented", (p, "experimental cannot be published implemented")
        blob = json.dumps(d).lower()
        for bad in ("abandon", "unreliab", "unhealth"):
            assert bad not in blob, (p, "experimental metric must not label:", bad)
    for crosswalk in d.get("standards_crosswalks", []):
        required_crosswalk = [
            "id", "concept", "source_uri", "source_object_id",
            "source_object_id_kind", "source_revision_status", "reviewed_at",
            "upstream_definition", "local_population", "local_formula",
            "boundary_rule", "zero_population", "alignment", "differences",
            "interpretation_limit", "local_metric", "local_role",
        ]
        for f in required_crosswalk:
            assert f in crosswalk and crosswalk[f] not in (None, "", [], {}), (p, "crosswalk missing", f)
        assert re.fullmatch(r"[0-9a-f]{40}", crosswalk["source_object_id"]), (p, "invalid source object id")
        assert crosswalk["source_object_id_kind"] == "git_blob_sha1", (p, "source hash must be identified as a Git blob SHA-1")
        assert crosswalk["source_revision_status"] == "default_branch_file_not_commit_pinned", (p, "source pinning status missing")
        assert crosswalk["local_metric"] == {"key": d["key"], "version": d["version"]}, (p, "crosswalk points at another metric")
        assert crosswalk["alignment"] in ("aligned", "conceptual_match_with_population_scope_difference", "extension"), (p, "unknown alignment")
        assert isinstance(crosswalk["differences"], list) and crosswalk["differences"], (p, "crosswalk must state differences")
        assert crosswalk["local_role"] in ("canonical", "compatibility_alias"), (p, "unknown local crosswalk role")
        if crosswalk["id"] == "CH-CAF":
            assert d["measurement_class"] == "derived", (p, "Contributor Absence Factor is derived")
            assert crosswalk["concept"] == "Contributor Absence Factor", (p, "unexpected CHAOSS concept")
            assert crosswalk["boundary_rule"] == "inclusive_at_or_above_50_percent", (p, "CAF threshold boundary changed")
            assert crosswalk["zero_population"] == "not_applicable", (p, "empty population must remain undefined")
            assert crosswalk["alignment"] == "conceptual_match_with_population_scope_difference", (p, "do not imply blanket equivalence")
    pair = (d["key"], d["version"])
    assert pair not in seen, ("duplicate key/version", pair)
    seen[pair] = d["implementation_status"]

for p in files:
    d = json.load(open(p))
    for crosswalk in d.get("standards_crosswalks", []):
        alias = crosswalk.get("canonical_local_metric")
        if crosswalk["local_role"] == "compatibility_alias":
            assert alias and (alias["key"], alias["version"]) in seen, (p, "missing canonical crosswalk target")
        else:
            assert not alias, (p, "canonical mapping cannot point to an alias target")

counts = {}
for st in seen.values():
    counts[st] = counts.get(st, 0) + 1
print("metric-lint OK: %d definitions (%s)"
      % (len(seen), ", ".join("%s=%d" % (k, counts[k]) for k in sorted(counts))))
PY

echo "metric-lint OK"
