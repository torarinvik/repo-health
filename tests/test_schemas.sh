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
for want in ("connector-manifest", "canonical-repo", "dep-graph", "cyclonedx", "spdx", "registry-meta", "distribution", "archive", "role-publication"):
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

echo "test_schemas OK"
