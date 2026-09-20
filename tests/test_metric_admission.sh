#!/usr/bin/env bash
# tests/test_metric_admission.sh — admission classes and CHAOSS crosswalks
# fail closed when classification or the pinned threshold contract drifts.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$ROOT/build/tmp_metric_admission"

fail() { echo "[metric-admission] FAIL: $1" >&2; exit 1; }

echo "[metric-admission] all versioned metric definitions are classified and crosswalked"
out="$(bash "$ROOT/tools/metric-lint.sh" "$ROOT")" || fail "metric lint"
[[ "$out" == *"211 definitions (implemented=209, prototype=2)"* ]] || fail "unexpected metric catalog: $out"

python3 - "$ROOT" <<'PY'
import glob, json, sys
root = sys.argv[1]
defs = [json.load(open(p)) for p in glob.glob(root + "/metrics/definitions/*.json")]
assert len(defs) == 211, len(defs)
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

echo "[metric-admission] missing class is rejected"
rm -rf "$TMP"
mkdir -p "$TMP/metrics"
cp -R "$ROOT/metrics/definitions" "$TMP/metrics/definitions"
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
rm -rf "$TMP"

echo "test_metric_admission OK"
