#!/usr/bin/env bash
# tests/test_m00.sh — M00 gate: build Elisa binaries, run oracle suite,
# verify registry mirror consistency and STATUS honesty.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[m00] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_oracles" ]] || { echo "[m00] FAIL: test_oracles not built"; exit 1; }

echo "[m00] oracles"
out="$("$ROOT/build/test_oracles")"
echo "$out" | tail -n 5
[[ "$out" == *"ORACLES OK"* ]] || { echo "[m00] FAIL: oracle suite reported failures"; exit 1; }

echo "[m00] registry mirror: metrics/definitions/*.json vs rh_registry.elisa"
keys_json="$(python3 -c "
import json, glob
keys = sorted(json.load(open(p))['key'] for p in glob.glob('$ROOT/metrics/definitions/*.json'))
print('\n'.join(keys))")"
keys_count="$(echo "$keys_json" | wc -l | tr -d ' ')"
[[ "$keys_count" == "112" ]] || { echo "[m00] FAIL: expected 112 definitions, got $keys_count"; exit 1; }
# The runtime registry mirrors exactly the PUBLISHED definitions: every
# implemented/prototype (key, version) must be present, and a planned metric
# must NOT be in the registry, so the system never implies availability.
python3 - "$ROOT" <<'EOF'
import glob, json, os, sys
root = sys.argv[1]
reg = open(os.path.join(root, "src", "rh_registry.elisa")).read()
impl = 0
for p in sorted(glob.glob(os.path.join(root, "metrics", "definitions", "*.json"))):
    d = json.load(open(p))
    st = d.get("implementation_status")
    assert st in ("planned", "prototype", "implemented", "validated", "released", "retired"), p
    if st == "implemented":
        impl += 1
    if st == "planned" or d.get("group") == "experimental":
        assert ('"%s"' % d["key"]) not in reg, ("unpublished metric advertised in registry", d["key"])
    else:
        assert ('"%s"' % d["key"]) in reg, ("published metric missing from registry", d["key"])
        assert ('"%s"' % d["version"]) in reg, ("version missing from registry", d["version"])
assert impl == 110, ("implemented definitions", impl)
print("[m00] registry mirror OK: published are present, planned are absent; 110 implemented")
EOF
# The M09 admission template is enforced mechanically for every definition.
bash "$ROOT/tools/metric-lint.sh" | tail -n 1

echo "[m00] honesty: STATUS.md must not claim unbuilt work"
grep -q "M02 ingestion/hosts.*in_progress" "$ROOT/STATUS.md" || { echo "[m00] FAIL: STATUS.md misstates M02"; exit 1; }
grep -q "M03 packages/advisories.*in_progress" "$ROOT/STATUS.md" || { echo "[m00] FAIL: STATUS.md misstates M03"; exit 1; }
grep -q "M04 continuity/identity.*in_progress" "$ROOT/STATUS.md" || { echo "[m00] FAIL: STATUS.md misstates M04"; exit 1; }
grep -q "M05 temporal/downstream.*in_progress" "$ROOT/STATUS.md" || { echo "[m00] FAIL: STATUS.md misstates M05"; exit 1; }
grep -q "M06 API/policy/corrections.*in_progress" "$ROOT/STATUS.md" || { echo "[m00] FAIL: STATUS.md misstates M06"; exit 1; }
grep -q "M07 beta gate.*in_progress" "$ROOT/STATUS.md" || { echo "[m00] FAIL: STATUS.md misstates M07"; exit 1; }
grep -q "250 of the 360" "$ROOT/STATUS.md" || { echo "[m00] FAIL: STATUS.md must scope the 360-metric catalog"; exit 1; }
# STATUS metric table and JSON definitions must agree on the implemented set.
python3 - "$ROOT/STATUS.md" "$ROOT/metrics/definitions" <<'EOF'
import json, glob, re, sys
status = open(sys.argv[1]).read()
implemented_json = sorted(
    json.load(open(p))["key"] for p in glob.glob(sys.argv[2] + "/*.json")
    if json.load(open(p)).get("implementation_status") == "implemented")
for key in implemented_json:
    assert ("| %s |" % key) in status, ("STATUS missing implemented key", key)
print("[m00] STATUS/JSON agreement OK:", len(implemented_json), "implemented")
EOF

echo "[m00] threat model + ADR present"
[[ -f "$ROOT/docs/THREAT_MODEL.md" ]] || exit 1
[[ -f "$ROOT/docs/adr/ADR-000.md" ]] || exit 1

echo "test_m00 OK"
