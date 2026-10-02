#!/usr/bin/env bash
# tests/test_debian_index_cli.sh — bounded Debian binary Packages Deb822 reader.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-debian-index"

fail() { echo "[debian-index] FAIL: $1" >&2; exit 1; }

echo "[debian-index] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
INPUT="$T/input.txt"
cp "$ROOT/fixtures/distribution/debian-packages.txt" "$INPUT"
"$ROOT/build/rh_cli" debian-index --input "$INPUT" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$ROOT" "$T/out.json" "$INPUT" "$T/out.json.transformations.json" <<'PY'
import hashlib, json, pathlib, sys
root, output, source, sidecar = sys.argv[1:]
doc = json.load(open(output))
golden = json.load(open(pathlib.Path(root) / "fixtures/distribution/debian-packages-result.json"))
assert doc == golden, (doc, golden)
assert doc["schema"] == "rh-debian-packages-index-result/1" and doc["format"] == "debian-packages-deb822", doc
transform = json.load(open(sidecar))
assert transform["adapter"] == "debian-packages-deb822" and transform["output_schema"] == doc["schema"], transform
assert transform["source_input_sha256"] == hashlib.sha256(open(source, "rb").read()).hexdigest(), transform
assert transform["normalized_output_sha256"] == hashlib.sha256(open(output, "rb").read()).hexdigest(), transform
assert transform["configuration_sha256"] == hashlib.sha256(b"repo-health/debian-packages-deb822/1").hexdigest(), transform
assert {item["state"] for item in transform["fields"]} == {"preserved", "transformed", "unknown", "unsupported", "discarded"}, transform
assert len(doc["packages"]) == 3, doc["packages"]
libc, libc_i386, common = doc["packages"]
assert (libc["name"], libc["version"], libc["architecture"], libc["source"]) == ("libc6", "2.38-7", "amd64", "glibc (2.38-7)"), libc
assert (libc["multi_arch"], libc["essential"], libc["archive_size"], libc["installed_size"]) == ("same", "yes", 2750000, 12940), libc
assert libc["relations"] == [
    {"kind": "pre-depends", "expression": "libgcc-s1 (>= 3.0)"},
    {"kind": "depends", "expression": "libfoo (>= 1.0), libc-bin (= 2.38-7) | libc-bin-alt"},
    {"kind": "recommends", "expression": "tzdata"},
    {"kind": "provides", "expression": "libc6-abi (= 2.38-7)"},
    {"kind": "conflicts", "expression": "old-libc"},
    {"kind": "replaces", "expression": "old-libc"},
    {"kind": "enhances", "expression": "application"},
], libc["relations"]
assert libc_i386["name"] == libc["name"] and libc_i386["architecture"] == "i386", libc_i386
assert libc_i386["multi_arch"] is None and libc_i386["installed_size"] is None, libc_i386
assert common["version"] == "1:2.0~rc1+dfsg-1" and common["architecture"] == "all", common
assert common["relations"] == [{"kind": "depends", "expression": "base-files (>= 12), libc6 (>= 2.36) | libc6-compat"}], common
assert (doc["unknown_fields"], doc["omitted_fields"]) == (1, 5), doc
serialized = open(output).read()
for private in ("pool/main/g/glibc", "Private Maintainer", "private@example.invalid", "Private package description", "continuation text", "omitted extension text", "0123456789abcdef0123456789abcdef"):
    assert private not in serialized, private
assert "not verified" in doc["note"] and "not resolved" in doc["note"], doc
print("[debian-index] Deb822 stanzas, folded relations, privacy, and transformation binding OK")
PY

"$ROOT/build/rh_cli" debian-index --input "$INPUT" --out "$T/out2.json" >/dev/null || fail "deterministic rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "output not deterministic"

printf 'package: demo\nVERSION: 1.0-1\narchitecture: all\n' > "$T/case-insensitive.txt"
"$ROOT/build/rh_cli" debian-index --input "$T/case-insensitive.txt" --out "$T/case-insensitive.json" >/dev/null || fail "case-insensitive tags"
python3 - "$T/case-insensitive.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
assert [(p["name"], p["version"], p["architecture"]) for p in doc["packages"]] == [("demo", "1.0-1", "all")], doc
print("[debian-index] field names compare case-insensitively")
PY

echo "[debian-index] malformed stanzas fail closed and preserve prior output"
cp "$T/out.json" "$T/sentinel.json"
python3 - "$T" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
cases = {
    "missing-version": b"Package: demo\nArchitecture: all\n",
    "bad-package": b"Package: -demo\nVersion: 1.0\nArchitecture: all\n",
    "bad-version": b"Package: demo\nVersion: alpha\nArchitecture: all\n",
    "bad-architecture": b"Package: demo\nVersion: 1.0\nArchitecture: -amd64\n",
    "duplicate-field": b"Package: demo\npackage: other\nVersion: 1.0\nArchitecture: all\n",
    "negative-size": b"Package: demo\nVersion: 1.0\nArchitecture: all\nSize: -1\n",
    "overflow-size": b"Package: demo\nVersion: 1.0\nArchitecture: all\nSize: 9999999999999999999999999999999999\n",
    "bad-sha256": b"Package: demo\nVersion: 1.0\nArchitecture: all\nSHA256: not-a-digest\n",
    "folded-simple-field": b"Package: demo\nVersion: 1.0\nArchitecture:\n amd64\n",
    "orphan-continuation": b" continuation\nPackage: demo\nVersion: 1.0\nArchitecture: all\n",
    "empty-relation-line": b"Package: demo\nVersion: 1.0\nArchitecture: all\nDepends: demo\n .\n",
    "comments-not-in-index": b"# comment\nPackage: demo\nVersion: 1.0\nArchitecture: all\n",
    "bad-utf8": b"Package: demo\nVersion: 1.0\nArchitecture: all\nDescription: \xff\n",
}
for name, content in cases.items():
    (root / name).write_bytes(content)
PY
set +e
rcs=()
for malformed in "$T"/missing-version "$T"/bad-package "$T"/bad-version "$T"/bad-architecture "$T"/duplicate-field "$T"/negative-size "$T"/overflow-size "$T"/bad-sha256 "$T"/folded-simple-field "$T"/orphan-continuation "$T"/empty-relation-line "$T"/comments-not-in-index "$T"/bad-utf8; do
  "$ROOT/build/rh_cli" debian-index --input "$malformed" --out "$T/sentinel.json" >/dev/null 2>&1
  rcs+=("$?")
done
set -e
for rc in "${rcs[@]}"; do
  [[ "$rc" -eq 4 ]] || fail "malformed Debian index must exit 4 (got $rc)"
done
cmp -s "$T/out.json" "$T/sentinel.json" || fail "malformed input replaced prior output"

echo "test_debian_index_cli OK"
