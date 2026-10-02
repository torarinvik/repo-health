#!/usr/bin/env bash
# tests/test_freebsd_catalog_cli.sh — bounded decoded FreeBSD pkg catalog adapter.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-freebsd-catalog"

fail() { echo "[freebsd-catalog] FAIL: $1" >&2; exit 1; }

echo "[freebsd-catalog] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
INPUT="$T/input.json"
cp "$ROOT/fixtures/distribution/freebsd-data.json" "$INPUT"
"$ROOT/build/rh_cli" freebsd-catalog --input "$INPUT" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$ROOT" "$T/out.json" "$INPUT" "$T/out.json.transformations.json" <<'PY'
import hashlib, json, pathlib, sys
root, output, source, sidecar = sys.argv[1:]
d = json.load(open(output))
golden = json.load(open(pathlib.Path(root) / "fixtures/distribution/freebsd-data-result.json"))
assert d == golden, (d, golden)
assert d["schema"] == "rh-freebsd-catalog-result/1" and d["format"] == "freebsd-pkg-data-json", d
tr = json.load(open(sidecar))
assert tr["adapter"] == "freebsd-pkg-data-json" and tr["output_schema"] == d["schema"], tr
assert tr["source_input_sha256"] == hashlib.sha256(open(source, "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(output, "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/freebsd-pkg-data-json/1").hexdigest(), tr
assert {field["state"] for field in tr["fields"]} == {"preserved", "transformed", "unknown", "unsupported", "discarded"}, tr
pkg, data = d["packages"]
assert (pkg["name"], pkg["origin"], pkg["version"], pkg["abi"], pkg["architecture"]) == ("example-tool", "devel/example-tool", "1.4.2", "FreeBSD:14:amd64", "freebsd:14:x86:64"), pkg
assert (pkg["package_size"], pkg["installed_size"], pkg["checksum_claim"], pkg["license_logic"], pkg["licenses"]) == (2048, 8192, "sha256:0123456789abcdef", "single", ["BSD2CLAUSE"]), pkg
assert pkg["relations"] == [
    {"kind": "depends", "name": "libfoo", "origin": "devel/libfoo", "version": "2.0"},
    {"kind": "depends", "name": "runtime", "origin": "lang/runtime", "version": None},
    {"kind": "provides", "expression": "example-tool-api"},
    {"kind": "requires", "expression": "libc.so.7"},
], pkg
assert data["abi"] is None and data["relations"] == [] and data["licenses"] == [], data
assert (d["unknown_package_fields"], d["omitted_free_text_fields"], d["omitted_group_count"], d["omitted_expired_package_count"]) == (1, 6, 1, 1), d
serialized = open(output).read()
for private in ("Private Person", "secret@example.invalid", "Long private description", "All/example-tool.pkg", "https://example.invalid"):
    assert private not in serialized, private
assert "not verified" in d["note"], d
print("[freebsd-catalog] declarations, omissions, and transformation binding OK")
PY

"$ROOT/build/rh_cli" freebsd-catalog --input "$INPUT" --out "$T/out2.json" >/dev/null || fail "deterministic rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "output not deterministic"

printf '%s' '{"packages":[{"name":"integer-version","origin":"misc/integer-version","version":7}]}' > "$T/integer-version.json"
"$ROOT/build/rh_cli" freebsd-catalog --input "$T/integer-version.json" --out "$T/integer-version-result.json" >/dev/null || fail "integer version"
python3 - "$T/integer-version-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["packages"][0]["version"] == 7, d
print("[freebsd-catalog] integer package versions retain their source type")
PY

echo "[freebsd-catalog] malformed and unsupported input fails closed"
cp "$T/out.json" "$T/sentinel.json"
python3 - "$T" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
cases = {
    "missing-packages": {"groups": []},
    "missing-origin": {"packages": [{"name": "x", "version": "1"}]},
    "negative-size": {"packages": [{"name": "x", "origin": "cat/x", "version": "1", "pkgsize": -1}]},
    "bad-dependency": {"packages": [{"name": "x", "origin": "cat/x", "version": "1", "deps": {"y": {"version": "2"}}}]},
    "unknown-dependency-field": {"packages": [{"name": "x", "origin": "cat/x", "version": "1", "deps": {"y": {"origin": "cat/y", "future": "unknown"}}}]},
    "bad-license": {"packages": [{"name": "x", "origin": "cat/x", "version": "1", "licenses": [4]}]},
    "unknown-root": {"packages": [{"name": "x", "origin": "cat/x", "version": "1"}], "future": []},
}
for name, value in cases.items():
    (root / name).write_text(json.dumps(value, separators=(",", ":")))
(root / "duplicate-key").write_text('{"packages":[{"name":"x","origin":"cat/x","version":"1","version":"2"}]}')
PY
set +e
rcs=()
for malformed in "$T"/missing-packages "$T"/missing-origin "$T"/negative-size "$T"/bad-dependency "$T"/unknown-dependency-field "$T"/bad-license "$T"/unknown-root "$T"/duplicate-key; do
  "$ROOT/build/rh_cli" freebsd-catalog --input "$malformed" --out "$T/sentinel.json" >/dev/null 2>&1
  rcs+=("$?")
done
set -e
for rc in "${rcs[@]}"; do
  [[ "$rc" -eq 4 ]] || fail "malformed catalog must exit 4 (got $rc)"
done
cmp -s "$T/out.json" "$T/sentinel.json" || fail "malformed input replaced prior output"

echo "test_freebsd_catalog_cli OK"
