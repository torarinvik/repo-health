#!/usr/bin/env bash
# PEP 751 lock audit keeps package relationships informational and rootless.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-pylock"

fail() { echo "[pylock] FAIL: $1" >&2; exit 1; }

echo "[pylock] build"
bash "$ROOT/tools/build.sh" >/dev/null
rm -rf "$T"
mkdir -p "$T"
cat > "$T/pylock.toml" <<'EOF'
lock-version = '1.0'
created-by = 'uv'
requires-python = '>=3.12'
environments = ["sys_platform == 'win32'", "sys_platform == 'linux'"]

[[packages]]
name = 'attrs'
version = '25.1.0'
marker = "sys_platform == 'linux' # retained inside string"
requires-python = '>=3.8'
[[packages.wheels]]
name = 'attrs-25.1.0-py3-none-any.whl'
url = 'https://files.example.invalid/attrs-25.1.0.whl'
hashes = {sha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', blake2b_256 = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'}

[[packages.wheels]]
name = 'attrs-25.1.0-cp312-cp312-manylinux.whl'
path = '../wheelhouse/attrs-cp312.whl'
[packages.wheels.hashes]
sha256 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

[packages.sdist]
name = 'attrs-25.1.0.tar.gz'
url = 'https://files.example.invalid/attrs-25.1.0.tar.gz'
[packages.sdist.hashes]
sha256 = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'

[[packages]]
name = 'attrs'
version = '24.1.0'

[[packages]]
name = 'cattrs'
version = '24.1.2'
dependencies = [
  # Fake entry ignored because this line is TOML comment text: {name = 'not-a-package'}
  {name = 'attrs', version = '25.1.0'},
]

[[packages]]
name = 'ambiguous-consumer'
version = '1.0.0'
dependencies = [{name = 'attrs'}]

[[packages]]
name = 'context-consumer'
version = '1.0.0'
dependencies = [{name = 'private', vcs = {url = 'https://example.invalid/private'}}]
[packages.archive]
name = 'context-consumer-1.0.0.zip'
path = 'vendor/context-consumer-1.0.0.zip'
[packages.archive.hashes]
sha256 = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'

[[packages]]
name = 'missing-consumer'
version = '1.0.0'
[[packages.dependencies]]
name = 'not-in-lock'

[[packages]]
name = 'table-context-consumer'
version = '1.0.0'
[[packages.dependencies]]
name = 'private'
[packages.dependencies.vcs]
url = 'https://example.invalid/private'

[[packages]]
name = 'inline-artifact-consumer'
wheels = [
  {name = 'inline.whl', url = 'https://files.example.invalid/inline.whl', hashes = {sha256 = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'}},
  {name = 'inline-alt.whl', path = 'vendor/inline-alt.whl', hashes = {sha512 = '11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111'}},
]
sdist = {name = 'inline.tar.gz', url = 'https://files.example.invalid/inline.tar.gz', hashes = {sha256 = '2222222222222222222222222222222222222222222222222222222222222222'}}
EOF

"$ROOT/build/rh_cli" pylock --input "$T/pylock.toml" --out "$T/result.json" | grep -q 'PEP 751 audit emitted' || fail "command did not emit audit"
cmp "$ROOT/fixtures/packages/pylock-audit-result.json" "$T/result.json" || fail "audit output drifted from golden"
python3 - "$T/result.json" "$T/pylock.toml" <<'PY'
import hashlib, json, sys
report = json.load(open(sys.argv[1]))
source = open(sys.argv[2], "rb").read()
assert report["schema"] == "rh-pylock-audit/1", report
assert report["parser"] == "bounded-core-projection", report
assert report["created_by"] == "uv" and report["requires_python"] == ">=3.12", report
assert report["input_sha256"] == hashlib.sha256(source).hexdigest(), report
assert report["root_relationship"] == "not_recorded", report
assert report["dependency_semantics"] == "informational_only", report
pkgs = report["packages"]
assert [p["name"] for p in pkgs] == ["attrs", "attrs", "cattrs", "ambiguous-consumer", "context-consumer", "missing-consumer", "table-context-consumer", "inline-artifact-consumer"], pkgs
assert pkgs[0]["marker"] == "sys_platform == 'linux' # retained inside string", pkgs[0]
assert pkgs[2]["dependencies"] == [{"name": "attrs", "version": "25.1.0", "target": 0, "resolution": "resolved"}], pkgs[2]
assert pkgs[3]["dependencies"][0]["resolution"] == "ambiguous", pkgs[3]
assert pkgs[4]["dependencies"][0]["resolution"] == "context", pkgs[4]
assert pkgs[5]["dependencies"][0]["resolution"] == "missing", pkgs[5]
assert pkgs[6]["dependencies"][0]["resolution"] == "context", pkgs[6]
assert [a["kind"] for a in pkgs[0]["artifacts"]] == ["wheel", "wheel", "sdist"], pkgs[0]["artifacts"]
assert pkgs[0]["artifacts"][0]["hashes"] == [
    {"algorithm": "sha256", "value": "a" * 64},
    {"algorithm": "blake2b_256", "value": "c" * 64},
], pkgs[0]["artifacts"][0]
assert pkgs[0]["artifacts"][1]["hashes"] == [{"algorithm": "sha256", "value": "b" * 64}], pkgs[0]["artifacts"][1]
assert pkgs[0]["artifacts"][2]["hashes"] == [{"algorithm": "sha256", "value": "d" * 64}], pkgs[0]["artifacts"][2]
assert pkgs[0]["artifacts"][0]["source_kind"] == "url", pkgs[0]["artifacts"][0]
assert pkgs[0]["artifacts"][0]["source_sha256"] == hashlib.sha256(b"https://files.example.invalid/attrs-25.1.0.whl").hexdigest(), pkgs[0]["artifacts"][0]
assert pkgs[0]["artifacts"][1]["source_kind"] == "path", pkgs[0]["artifacts"][1]
assert pkgs[4]["artifacts"][0]["kind"] == "archive" and pkgs[4]["artifacts"][0]["source_kind"] == "path", pkgs[4]
assert [a["kind"] for a in pkgs[7]["artifacts"]] == ["wheel", "wheel", "sdist"], pkgs[7]
assert pkgs[7]["artifacts"][0]["hashes"] == [{"algorithm": "sha256", "value": "f" * 64}], pkgs[7]["artifacts"][0]
assert pkgs[7]["artifacts"][1]["hashes"] == [{"algorithm": "sha512", "value": "1" * 128}], pkgs[7]["artifacts"][1]
assert pkgs[7]["artifacts"][0]["source_sha256"] == hashlib.sha256(b"https://files.example.invalid/inline.whl").hexdigest(), pkgs[7]["artifacts"][0]
serialized = json.dumps(report)
for locator in ["https://files.example.invalid/attrs-25.1.0.whl", "https://files.example.invalid/inline.whl", "vendor/inline-alt.whl"]:
    assert locator not in serialized, report
coverage = report["coverage"]
assert coverage["direct_dependencies"] == "not_recorded" and coverage["markers_evaluated"] is False, coverage
assert coverage["artifacts_projected"] is False and coverage["artifact_hashes_projected"] is True, coverage
assert coverage["unprojected_artifact_fields"] == 0 and coverage["unprojected_top_level_fields"] == 1, coverage
assert coverage["unprojected_package_fields"] == 0 and coverage["unprojected_dependency_fields"] == 2, coverage
assert coverage["unprojected_tables"] == 1, coverage
print("[pylock] PEP 751 relationships and loss coverage OK")
PY

echo "[pylock] unsupported lock versions and string escapes fail closed"
sed "s/lock-version = '1.0'/lock-version = '2.0'/" "$T/pylock.toml" > "$T/bad-version.toml"
printf "lock-version = '1.0'\ncreated-by = \"bad\\\\escape\"\n[[packages]]\nname = 'x'\n" > "$T/bad-string.toml"
for input in "$T/bad-version.toml" "$T/bad-string.toml"; do
  set +e
  "$ROOT/build/rh_cli" pylock --input "$input" --out "$T/bad-result.json" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || fail "unsupported PEP 751 input must fail closed (got $rc)"
done
cat > "$T/missing-artifact-hash.toml" <<'EOF'
lock-version = '1.0'
created-by = 'uv'
[[packages]]
name = 'x'
[packages.sdist]
name = 'x.tar.gz'
url = 'https://example.invalid/x.tar.gz'
EOF
cat > "$T/duplicate-artifact-hash.toml" <<'EOF'
lock-version = '1.0'
created-by = 'uv'
[[packages]]
name = 'x'
[[packages.wheels]]
name = 'x.whl'
hashes = {sha256 = 'aa', sha256 = 'bb'}
EOF
for input in "$T/missing-artifact-hash.toml" "$T/duplicate-artifact-hash.toml"; do
  set +e
  "$ROOT/build/rh_cli" pylock --input "$input" --out "$T/bad-artifact.json" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || fail "missing or duplicate artifact hashes must fail closed (got $rc)"
done

cat > "$T/partial-artifact.toml" <<'EOF'
lock-version = '1.0'
created-by = 'uv'
[[packages]]
name = 'x'
[packages.sdist]
name = 'x.tar.gz'
url = 'https://example.invalid/x.tar.gz'
size = 128
hashes = {sha256 = 'aa'}
EOF
"$ROOT/build/rh_cli" pylock --input "$T/partial-artifact.toml" --out "$T/partial-artifact.json" >/dev/null
python3 - "$T/partial-artifact.json" <<'PY'
import json, sys
coverage = json.load(open(sys.argv[1]))["coverage"]
assert coverage["artifact_hashes_projected"] is False, coverage
assert coverage["unprojected_artifact_fields"] == 1, coverage
PY

set +e
"$ROOT/build/rh_cli" pylock --input "$T/pylock.toml" --input "$T/pylock.toml" --out "$T/duplicate-option.json" >/dev/null 2>&1
rc_duplicate_option=$?
set -e
[[ "$rc_duplicate_option" -eq 2 ]] || fail "duplicate CLI options must be rejected (got $rc_duplicate_option)"

echo "test_pylock_cli OK"
