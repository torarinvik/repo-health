#!/usr/bin/env bash
# tests/test_m03.sh — M03 gate: package identities, resolved graphs, OSV.
# Deterministic, offline: fixture files + checked-in canonical goldens.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
W="/tmp/rh-m03-wd"

fail() { echo "[m03] FAIL: $1" >&2; exit 1; }
expect() {
  local want="$1"; shift
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  [[ "$got" == "$want" ]] || fail "expected exit $want, got $got: $*"
}

echo "[m03] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_package" ]] || fail "test_package not built"

rm -rf "$W"; mkdir -p "$W"
cp "$ROOT"/fixtures/packages/* "$W"/
cp "$ROOT"/fixtures/inventory/* "$W"/

echo "[m03] graph/OSV assertions (exact counts, scopes, unresolved, aliases)"
out="$("$ROOT/build/test_package" "$W" check)" || fail "test_package: $out"
[[ "$out" == *"PACKAGE OK"* ]] || fail "test_package: $out"
echo "$out"

echo "[m03] fixtures are valid JSON (including NuGet JSON lock; Cargo TOML lock is skipped)"
python3 - "$ROOT/fixtures/packages" <<'EOF'
import json, glob, sys
for p in sorted(glob.glob(sys.argv[1] + "/*.json")):
    d = json.load(open(p))
    if p.endswith(".golden.json"):
        assert d["schema"] == "rh-dep-graph/1", p
        assert d["ecosystem"] in ("cargo", "npm", "pypi", "go", "rubygems", "composer", "nuget", "maven"), p
        ids = [n["id"] for n in d["nodes"]]
        assert ids == list(range(len(ids))), ("node ids must be dense", p)
        for e in d["edges"]:
            assert 0 <= e["from"] < len(ids) and 0 <= e["to"] < len(ids), p
        for artifact in d.get("artifacts", []):
            assert 0 <= artifact["package_node"] < len(ids), (p, artifact)
        for a in d["advisories"]:
            assert 0 <= a["node"] < len(ids), p
            assert a["witness"], ("witness must not be empty", p)
    print("json OK:", p.rsplit("/", 1)[1])
EOF

echo "[m03] inventory: two pinned formats with declared spec support"
python3 - "$ROOT/fixtures/inventory/cyclonedx-1.5.json" "$ROOT/fixtures/inventory/spdx-2.3.json" <<'EOF'
import json, sys
cdx = json.load(open(sys.argv[1]))
assert cdx["bomFormat"] == "CycloneDX", cdx
assert cdx["specVersion"] in ("1.4", "1.5", "1.6") and cdx["components"]
spdx = json.load(open(sys.argv[2]))
assert spdx["spdxVersion"] == "SPDX-2.3", spdx
assert spdx["packages"], spdx
print("[m03] inventory fixtures OK: CycloneDX", cdx["specVersion"], "+", spdx["spdxVersion"])
EOF
grep -q "DECLARED" "$ROOT/src/rh_inventory.elisa" || fail "declared-spec-set note missing"
grep -q "valid != complete" "$ROOT/src/rh_inventory.elisa" || fail "valid-vs-complete caveat missing"
grep -q "unknown_top_keys" "$ROOT/src/rh_spdx.elisa" || fail "spdx unknown-field note missing"

echo "[m03] registry enrichment: yanks retained, links are assertions"
grep -q "yanked is NOT deleted" "$ROOT/src/rh_registry_meta.elisa" || fail "yank-retention note missing"
grep -q "ASSERTION, not identity" "$ROOT/src/rh_registry_meta.elisa" || fail "link-assertion note missing"

echo "[m03] golden determinism (re-dump in a scratch dir matches checked-in)"
S="/tmp/rh-m03-scratch"
rm -rf "$S"; mkdir -p "$S"
cp "$ROOT"/fixtures/packages/* "$S"/
cp "$ROOT"/fixtures/inventory/* "$S"/
"$ROOT/build/test_package" "$S" dump >/dev/null || fail "re-dump"
cmp -s "$S/cargo-graph.golden.json" "$ROOT/fixtures/packages/cargo-graph.golden.json" || fail "cargo golden nondeterministic"
cmp -s "$S/npm-graph.golden.json" "$ROOT/fixtures/packages/npm-graph.golden.json" || fail "npm golden nondeterministic"
cmp -s "$S/python-graph.golden.json" "$ROOT/fixtures/packages/python-graph.golden.json" || fail "python golden nondeterministic"
cmp -s "$S/go-graph.golden.json" "$ROOT/fixtures/packages/go-graph.golden.json" || fail "go golden nondeterministic"
echo "[m03] determinism OK"

echo "test_m03 OK"
