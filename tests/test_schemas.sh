#!/usr/bin/env bash
# tests/test_schemas.sh — public schema gate: every schema declares a
# version, every target glob resolves to real fixtures, and the checker
# actually rejects a malformed document (negative control).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[schemas] FAIL: $1" >&2; exit 1; }

echo "[schemas] all checked-in fixtures validate"
out="$(bash "$ROOT/tools/schema-check.sh")" || fail "schema-check"
echo "$out"

echo "[schemas] schemas are versioned and cover the named families"
python3 - "$ROOT/schemas/evidence-bundle-manifest.spec.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-evidence-bundle-manifest-schema/1", d
assert set(d["versions"]) == {"1", "2"}, d
assert "expected-output-sha256-report.md" in d["versions"]["2"]["expected_outputs"], d
assert "expected-output-sha256-report.md" in d["versions"]["1"]["optional_outputs"], d
print("[schemas] evidence bundle text manifest contract is versioned")
PY
python3 - "$ROOT" <<'PY'
import glob, json, os, sys
root = sys.argv[1]
names = set()
for p in sorted(glob.glob(os.path.join(root, "schemas", "*.schema.json"))):
    s = json.load(open(p))
    assert s["schema"] == "rh-jsonschema/1", p
    assert s["targets"], p
    names.add(s["name"])
for want in ("connector-manifest", "canonical-repo", "dep-graph", "adapter-transformation", "artifact-observation-result", "go-mod-observation-result", "go-zip-observation-result", "pylock-artifact-observation-result", "pylock-marker-evaluation", "projection-snapshot", "cyclonedx", "spdx", "inventory-result", "continuity-metrics", "registry-meta", "registry-meta-result", "distribution", "archive", "role-publication", "homebrew", "osv-query-input", "osv-commit-query-input", "osv-query-batch-result", "osv-query-batch-pages-result", "osv-query-batch-hydrated-result", "snapshot-reconcile-input", "snapshot-reconcile-result", "forge-events-input", "ingest-input", "postgres-legacy-ingest-input", "postgres-command", "postgres-result", "github-review-capability-probe-result", "github-collaborator-probe-result", "gitlab-capability-matrix", "forge-capability-matrix", "bitbucket-capability-matrix", "correction-evidence-policy", "correction-evidence-verification", "privacy-history"):
    assert want in names, ("missing schema", want)
print("[schemas] families OK:", ", ".join(sorted(names)))
PY

echo "[schemas] inventory metric status constrains nullable values"
inventory_negative="$ROOT/fixtures/inventory-results/_schema-negative.json"
trap 'rm -f "$inventory_negative"' EXIT
for invalid in observed-null not-applicable-value; do
  python3 - "$ROOT/fixtures/inventory-results/cyclonedx-1.5.json" "$inventory_negative" "$invalid" <<'PY'
import json, sys
source, target, invalid = sys.argv[1:]
document = json.load(open(source))
metric = document["metrics"][0]
if invalid == "observed-null":
    metric["value"] = None
else:
    metric["status"] = "not_applicable"
    metric["value"] = 1
json.dump(document, open(target, "w"), separators=(",", ":"))
PY
  if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
    rm -f "$inventory_negative"
    trap - EXIT
    fail "inventory schema accepted $invalid metric value"
  fi
done
rm -f "$inventory_negative"
trap - EXIT
echo "[schemas] inventory observed and absent metric values are constrained"

echo "[schemas] continuity metric statuses constrain values and quality"
continuity_negative="$ROOT/fixtures/continuity/continuity-metrics-negative.json"
for invalid in observed-null zero-denominator unsupported-value partial-quality; do
  python3 - "$ROOT/fixtures/continuity/continuity-metrics-full.json" "$ROOT/fixtures/continuity/continuity-metrics-windowed.json" "$continuity_negative" "$invalid" <<'PY'
import json, sys
full_path, window_path, target, invalid = sys.argv[1:]
source_path = window_path if invalid == "partial-quality" else full_path
document = json.load(open(source_path))
metric = (next(row for row in document["metrics"] if row["status"] == "partial")
          if invalid == "partial-quality" else document["metrics"][0])
if invalid == "observed-null":
    metric["value"] = None
elif invalid == "zero-denominator":
    metric["value"]["den"] = 0
elif invalid == "unsupported-value":
    metric = next(row for row in document["metrics"] if row["status"] == "unsupported")
    metric["value"] = 0
else:
    metric["status"] = "observed"
json.dump(document, open(target, "w"), separators=(",", ":"))
PY
  if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
    rm -f "$continuity_negative"
    fail "continuity schema accepted $invalid metric state"
  fi
done
rm -f "$continuity_negative"
echo "[schemas] observed, partial, unsupported, and ratio states are constrained"

echo "[schemas] negative control: a malformed document is rejected"
tmp="$ROOT/build/tmp_schema_neg"
rm -rf "$tmp"; mkdir -p "$tmp"
python3 - "$ROOT" "$tmp" <<'PY'
import json, os, sys
root, tmp = sys.argv[1], sys.argv[2]
# A connector manifest missing required capabilities must fail the checker.
bad = {"api_version": "x", "auth_scopes": [], "connector_id": "bad", "connector_version": "1.0.0",
       "pagination": "none", "time_precision": "second",
       "capabilities": {"history": "generic-git"}}
json.dump(bad, open(os.path.join(root, "connectors", "manifests", "_bad_negative.json"), "w"))
PY
if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
  rm -f "$ROOT/connectors/manifests/_bad_negative.json"
  fail "checker accepted a manifest missing required capability keys"
fi
rm -f "$ROOT/connectors/manifests/_bad_negative.json"
echo "[schemas] negative control OK"

echo "[schemas] connector scope entries and capability states are constrained"
python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
doc = json.load(open(os.path.join(root, "connectors", "manifests", "github.json")))
doc["auth_scopes"] = [42]
with open(os.path.join(root, "connectors", "manifests", "_bad_scope.json"), "w") as f:
    json.dump(doc, f)
PY
if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
  rm -f "$ROOT/connectors/manifests/_bad_scope.json"
  fail "checker accepted a non-string authentication scope"
fi
rm -f "$ROOT/connectors/manifests/_bad_scope.json"
python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
doc = json.load(open(os.path.join(root, "connectors", "manifests", "github.json")))
doc["capabilities"]["traffic"] = "maybe"
with open(os.path.join(root, "connectors", "manifests", "_bad_capability.json"), "w") as f:
    json.dump(doc, f)
PY
if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
  rm -f "$ROOT/connectors/manifests/_bad_capability.json"
  fail "checker accepted an undeclared capability state"
fi
rm -f "$ROOT/connectors/manifests/_bad_capability.json"
echo "[schemas] connector manifest contract OK"

echo "[schemas] publisher-specific attestation fields must stay strings"
pylock_fixture="$ROOT/fixtures/packages/pylock-audit-result.json"
pylock_backup="$tmp/pylock-audit-result.json"
cp "$pylock_fixture" "$pylock_backup"
restore_pylock_fixture() { cp "$pylock_backup" "$pylock_fixture"; }
trap restore_pylock_fixture EXIT
python3 - "$pylock_fixture" <<'PY'
import json, sys
path = sys.argv[1]
report = json.load(open(path))
report["packages"][0]["attestation_identities"][0]["repository"] = 42
json.dump(report, open(path, "w"), separators=(",", ":"))
PY
if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
  restore_pylock_fixture
  trap - EXIT
  fail "checker accepted a non-string publisher-specific attestation field"
fi
restore_pylock_fixture
trap - EXIT
echo "[schemas] dynamic attestation field type check OK"

echo "[schemas] tagged observation variants reject incorrect payload types"
lineage_input="$ROOT/fixtures/lineage/input.json"
lineage_backup="$tmp/lineage-input.json"
cp "$lineage_input" "$lineage_backup"
restore_lineage_input() { cp "$lineage_backup" "$lineage_input"; }
trap restore_lineage_input EXIT
for variant in absent count count_pair timestamp ratio boolean enumeration; do
  python3 - "$lineage_input" "$variant" <<'PY'
import json, sys
path, kind = sys.argv[1:]
document = json.load(open(path))
observation = document["metrics"][0]["observation"]
payloads = {
    "absent": {"kind": "absent"},
    "count": {"kind": "count", "value": 17},
    "count_pair": {"kind": "count_pair", "first": 3, "second": 4},
    "timestamp": {"kind": "timestamp", "value": 1700000000},
    "ratio": {"kind": "ratio", "num": 1, "den": 2},
    "boolean": {"kind": "boolean", "value": True},
    "enumeration": {"kind": "enumeration", "code": 1},
}
observation["value"] = payloads[kind]
if kind == "absent":
    observation["status"] = 2
    observation["quality"] = {"completeness": "unknown", "freshness": "unknown", "validity": "unknown", "provenance": "unknown"}
    observation["evidence"] = []
json.dump(document, open(path, "w"), separators=(",", ":"))
PY
  bash "$ROOT/tools/schema-check.sh" >/dev/null || fail "schema rejected valid $variant observation variant"
  restore_lineage_input
done
echo "[schemas] all tagged observation variants accepted"
python3 - "$lineage_input" <<'PY'
import json, sys
path = sys.argv[1]
document = json.load(open(path))
document["metrics"][0]["observation"]["value"]["value"] = "17"
json.dump(document, open(path, "w"), separators=(",", ":"))
PY
if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
  restore_lineage_input
  trap - EXIT
  fail "schema accepted a string for the count observation value"
fi
restore_lineage_input
trap - EXIT
echo "[schemas] input count observation payload type check OK"
lineage_result="$ROOT/fixtures/lineage/result.json"
lineage_result_backup="$tmp/lineage-result.json"
cp "$lineage_result" "$lineage_result_backup"
restore_lineage_result() { cp "$lineage_result_backup" "$lineage_result"; }
trap restore_lineage_result EXIT
python3 - "$lineage_result" <<'PY'
import json, sys
path = sys.argv[1]
document = json.load(open(path))
document["metrics"][0]["observation"]["value"]["value"] = "17"
json.dump(document, open(path, "w"), separators=(",", ":"))
PY
if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
  restore_lineage_result
  trap - EXIT
  fail "result schema accepted a string for the count observation value"
fi
restore_lineage_result
trap - EXIT
echo "[schemas] result count observation payload type check OK"
cp "$lineage_result_backup" "$lineage_result"
trap restore_lineage_result EXIT
python3 - "$lineage_result" <<'PY'
import json, sys
path = sys.argv[1]
document = json.load(open(path))
document["future_field"] = "must-not-disappear"
json.dump(document, open(path, "w"), separators=(",", ":"))
PY
if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
  restore_lineage_result
  trap - EXIT
  fail "result schema accepted an unknown root field"
fi
restore_lineage_result
trap - EXIT
echo "[schemas] lineage result root rejects unknown fields"
cp "$lineage_result_backup" "$lineage_result"
trap restore_lineage_result EXIT
python3 - "$lineage_result" <<'PY'
import json, sys
path = sys.argv[1]
document = json.load(open(path))
document["subject"]["future_field"] = "must-not-disappear"
json.dump(document, open(path, "w"), separators=(",", ":"))
PY
if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
  restore_lineage_result
  trap - EXIT
  fail "result schema accepted an unknown nested subject field"
fi
restore_lineage_result
trap - EXIT
echo "[schemas] lineage result nested objects reject unknown fields"
for lineage_fixture in "$lineage_input" "$lineage_result"; do
  ratio_backup="$tmp/lineage-ratio.json"
  cp "$lineage_fixture" "$ratio_backup"
  restore_lineage_ratio() { cp "$ratio_backup" "$lineage_fixture"; }
  trap restore_lineage_ratio EXIT
  python3 - "$lineage_fixture" <<'PY'
import json, sys
path = sys.argv[1]
document = json.load(open(path))
observation = document["metrics"][0]["observation"]
observation["value"] = {"kind": "ratio", "num": 0, "den": 0}
json.dump(document, open(path, "w"), separators=(",", ":"))
PY
  if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
    restore_lineage_ratio
    trap - EXIT
    fail "schema accepted a zero denominator in $lineage_fixture"
  fi
  restore_lineage_ratio
  trap - EXIT
done
echo "[schemas] input and result ratio denominators must be positive"
for lineage_fixture in "$lineage_input" "$lineage_result"; do
  pair_backup="$tmp/lineage-pair.json"
  cp "$lineage_fixture" "$pair_backup"
  restore_lineage_pair() { cp "$pair_backup" "$lineage_fixture"; }
  trap restore_lineage_pair EXIT
  python3 - "$lineage_fixture" <<'PY'
import json, sys
path = sys.argv[1]
document = json.load(open(path))
observation = document["metrics"][0]["observation"]
observation["value"] = {"kind": "count_pair", "first": 4, "second": 3}
json.dump(document, open(path, "w"), separators=(",", ":"))
PY
  if bash "$ROOT/tools/schema-check.sh" >/dev/null 2>&1; then
    restore_lineage_pair
    trap - EXIT
    fail "schema accepted a reversed count pair in $lineage_fixture"
  fi
  restore_lineage_pair
  trap - EXIT
done
echo "[schemas] input and result count-pair order is enforced"
echo "test_schemas OK"
