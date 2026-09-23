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
python3 - "$ROOT" <<'PY'
import glob, json, os, sys
root = sys.argv[1]
names = set()
for p in sorted(glob.glob(os.path.join(root, "schemas", "*.schema.json"))):
    s = json.load(open(p))
    assert s["schema"] == "rh-jsonschema/1", p
    assert s["targets"], p
    names.add(s["name"])
for want in ("connector-manifest", "canonical-repo", "dep-graph", "artifact-observation-result", "go-mod-observation-result", "go-zip-observation-result", "pylock-artifact-observation-result", "projection-snapshot", "cyclonedx", "spdx", "inventory-result", "registry-meta", "registry-meta-result", "distribution", "archive", "role-publication", "homebrew", "osv-query-input", "osv-commit-query-input", "osv-query-batch-result", "osv-query-batch-pages-result", "osv-query-batch-hydrated-result", "snapshot-reconcile-input", "snapshot-reconcile-result", "forge-events-input", "ingest-input", "postgres-legacy-ingest-input", "postgres-command", "postgres-result", "github-review-capability-probe-result", "github-collaborator-probe-result", "gitlab-capability-matrix", "forge-capability-matrix", "bitbucket-capability-matrix", "correction-evidence-policy", "correction-evidence-verification"):
    assert want in names, ("missing schema", want)
print("[schemas] families OK:", ", ".join(sorted(names)))
PY

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

echo "test_schemas OK"
