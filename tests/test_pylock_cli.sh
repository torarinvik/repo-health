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
size = 50
hashes = {sha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', blake2b_256 = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'}

[[packages.wheels]]
name = 'attrs-25.1.0-cp312-cp312-manylinux.whl'
path = '../wheelhouse/attrs-cp312.whl'
size = 0b110010
[packages.wheels.hashes]
sha256 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

[packages.sdist]
name = 'attrs-25.1.0.tar.gz'
url = 'https://files.example.invalid/attrs-25.1.0.tar.gz'
size = +50
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
size = 0o62
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
  {name = 'inline.whl', url = 'https://files.example.invalid/inline.whl', size = 0x32, hashes = {sha256 = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'}},
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
assert pkgs[0]["artifacts"][0]["size_bytes"] == 50, pkgs[0]["artifacts"][0]
assert pkgs[0]["artifacts"][1]["hashes"] == [{"algorithm": "sha256", "value": "b" * 64}], pkgs[0]["artifacts"][1]
assert pkgs[0]["artifacts"][1]["size_bytes"] == 50, pkgs[0]["artifacts"][1]
assert pkgs[0]["artifacts"][2]["hashes"] == [{"algorithm": "sha256", "value": "d" * 64}], pkgs[0]["artifacts"][2]
assert pkgs[0]["artifacts"][2]["size_bytes"] == 50, pkgs[0]["artifacts"][2]
assert pkgs[0]["artifacts"][0]["source_kind"] == "url", pkgs[0]["artifacts"][0]
assert pkgs[0]["artifacts"][0]["source_sha256"] == hashlib.sha256(b"https://files.example.invalid/attrs-25.1.0.whl").hexdigest(), pkgs[0]["artifacts"][0]
assert pkgs[0]["artifacts"][1]["source_kind"] == "path", pkgs[0]["artifacts"][1]
assert pkgs[4]["artifacts"][0]["kind"] == "archive" and pkgs[4]["artifacts"][0]["source_kind"] == "path", pkgs[4]
assert pkgs[4]["artifacts"][0]["size_bytes"] == 50, pkgs[4]
assert [a["kind"] for a in pkgs[7]["artifacts"]] == ["wheel", "wheel", "sdist"], pkgs[7]
assert pkgs[7]["artifacts"][0]["hashes"] == [{"algorithm": "sha256", "value": "f" * 64}], pkgs[7]["artifacts"][0]
assert pkgs[7]["artifacts"][0]["size_bytes"] == 50, pkgs[7]["artifacts"][0]
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
size = 1_28
hashes = {sha256 = 'aa'}
EOF
"$ROOT/build/rh_cli" pylock --input "$T/partial-artifact.toml" --out "$T/partial-artifact.json" >/dev/null
python3 - "$T/partial-artifact.json" <<'PY'
import json, sys
coverage = json.load(open(sys.argv[1]))["coverage"]
artifact = json.load(open(sys.argv[1]))["packages"][0]["artifacts"][0]
assert artifact["size_bytes"] == 128, artifact
assert coverage["artifact_hashes_projected"] is True, coverage
assert coverage["unprojected_artifact_fields"] == 0, coverage
PY

sed "s/size = 1_28/size = -1/" "$T/partial-artifact.toml" > "$T/negative-artifact-size.toml"
set +e
"$ROOT/build/rh_cli" pylock --input "$T/negative-artifact-size.toml" --out "$T/negative-size.json" >/dev/null 2>&1
rc_negative_size=$?
set -e
[[ "$rc_negative_size" -eq 4 ]] || fail "negative artifact size must fail closed (got $rc_negative_size)"
sed "s/size = 1_28/size = 0X80/" "$T/partial-artifact.toml" > "$T/uppercase-radix-artifact-size.toml"
set +e
"$ROOT/build/rh_cli" pylock --input "$T/uppercase-radix-artifact-size.toml" --out "$T/uppercase-size.json" >/dev/null 2>&1
rc_uppercase_size=$?
set -e
[[ "$rc_uppercase_size" -eq 4 ]] || fail "non-TOML radix prefix must fail closed (got $rc_uppercase_size)"

echo "[pylock] local artifact hashes bind to audit and file bytes"
"$ROOT/build/rh_cli" pylock-observe \
  --audit "$ROOT/fixtures/packages/pylock-observation-audit.json" \
  --artifact 0 \
  --file "$ROOT/fixtures/packages/pylock-observation-artifact.whl" \
  --out "$T/observation-match.json" >/dev/null
cmp "$ROOT/fixtures/packages/pylock-artifact-observation-result.json" "$T/observation-match.json" || fail "artifact observation drifted from golden"
python3 - "$T/observation-match.json" "$ROOT/fixtures/packages/pylock-observation-audit.json" "$ROOT/fixtures/packages/pylock-observation-artifact.whl" <<'PY'
import hashlib, json, sys
report = json.load(open(sys.argv[1]))
audit_bytes = open(sys.argv[2], "rb").read()
artifact = open(sys.argv[3], "rb").read()
assert report["schema"] == "rh-pylock-artifact-observation-result/1", report
assert report["audit_sha256"] == hashlib.sha256(audit_bytes).hexdigest(), report
assert report["source_input_sha256"] == json.loads(audit_bytes)["input_sha256"], report
assert report["package_name"] == "attrs" and report["artifact_kind"] == "wheel", report
assert report["file_size_bytes"] == len(artifact), report
assert report["expected_size_bytes"] == len(artifact) and report["size_state"] == "match", report
assert report["observed_file_sha256"] == hashlib.sha256(artifact).hexdigest(), report
assert report["state"] == "match" and report["checked_hash_count"] == 3, report
assert [h["algorithm"] for h in report["hashes"]] == ["sha256", "sha384", "sha512"], report
assert all(h["state"] == "match" and h["observed"] == h["expected"] for h in report["hashes"]), report
serialized = json.dumps(report)
for locator in ["https://files.example.invalid/attrs-25.1.0.whl", "../wheelhouse/attrs-cp312.whl"]:
    assert locator not in serialized, report
print("[pylock] SHA-256/384/512 match and evidence binding OK")
PY

python3 - "$ROOT/fixtures/packages/pylock-observation-audit.json" "$T" <<'PY'
import json, os, sys
source, target = sys.argv[1:]
for state, hashes in (
    ("partial", [{"algorithm": "sha256", "value": json.load(open(source))["packages"][0]["artifacts"][0]["hashes"][0]["value"]}, {"algorithm": "blake2b_256", "value": "opaque"}]),
    ("unsupported", [{"algorithm": "blake2b_256", "value": "opaque"}]),
    ("malformed", []),
):
    audit = json.load(open(source))
    audit["packages"][0]["artifacts"][0]["hashes"] = hashes
    with open(os.path.join(target, state + "-audit.json"), "w") as f:
        json.dump(audit, f, separators=(",", ":"))
        f.write("\n")
size_mismatch = json.load(open(source))
size_mismatch["packages"][0]["artifacts"][0]["size_bytes"] += 1
with open(os.path.join(target, "size-mismatch-audit.json"), "w") as f:
    json.dump(size_mismatch, f, separators=(",", ":"))
    f.write("\n")
legacy = json.load(open(source))
legacy["packages"][0]["artifacts"][0].pop("size_bytes")
with open(os.path.join(target, "legacy-audit.json"), "w") as f:
    json.dump(legacy, f, separators=(",", ":"))
    f.write("\n")
bad_length = json.load(open(source))
bad_length["packages"][0]["artifacts"][0]["hashes"] = [{"algorithm": "sha256", "value": "0"}]
with open(os.path.join(target, "bad-length-audit.json"), "w") as f:
    json.dump(bad_length, f, separators=(",", ":"))
    f.write("\n")
PY
for state in partial unsupported; do
  "$ROOT/build/rh_cli" pylock-observe \
    --audit "$T/$state-audit.json" --artifact 0 \
    --file "$ROOT/fixtures/packages/pylock-observation-artifact.whl" \
    --out "$T/$state-result.json" >/dev/null
done
for state in size-mismatch legacy; do
  "$ROOT/build/rh_cli" pylock-observe \
    --audit "$T/$state-audit.json" --artifact 0 \
    --file "$ROOT/fixtures/packages/pylock-observation-artifact.whl" \
    --out "$T/$state-result.json" >/dev/null
done
printf 'modified artifact bytes\n' > "$T/changed.whl"
"$ROOT/build/rh_cli" pylock-observe \
  --audit "$ROOT/fixtures/packages/pylock-observation-audit.json" --artifact 0 \
  --file "$T/changed.whl" --out "$T/changed-result.json" >/dev/null
python3 - "$T" <<'PY'
import json, os, sys
root = sys.argv[1]
partial = json.load(open(os.path.join(root, "partial-result.json")))
unsupported = json.load(open(os.path.join(root, "unsupported-result.json")))
changed = json.load(open(os.path.join(root, "changed-result.json")))
size_mismatch = json.load(open(os.path.join(root, "size-mismatch-result.json")))
legacy = json.load(open(os.path.join(root, "legacy-result.json")))
assert partial["state"] == "partially_verified" and partial["checked_hash_count"] == 1 and partial["unsupported_hash_count"] == 1, partial
assert [h["state"] for h in partial["hashes"]] == ["match", "unsupported"], partial
assert unsupported["state"] == "unsupported" and unsupported["checked_hash_count"] == 0 and unsupported["unsupported_hash_count"] == 1, unsupported
assert unsupported["hashes"][0]["observed"] is None, unsupported
assert changed["state"] == "changed" and changed["checked_hash_count"] == 3, changed
assert all(h["state"] == "changed" for h in changed["hashes"]), changed
assert size_mismatch["state"] == "changed" and size_mismatch["size_state"] == "changed", size_mismatch
assert all(h["state"] == "match" for h in size_mismatch["hashes"]), size_mismatch
assert legacy["state"] == "match" and legacy["expected_size_bytes"] is None and legacy["size_state"] == "not_recorded", legacy
print("[pylock] changed, partial, and unsupported states remain distinct")
PY

for audit in "$T/malformed-audit.json" "$T/bad-length-audit.json"; do
  set +e
  "$ROOT/build/rh_cli" pylock-observe --audit "$audit" --artifact 0 \
    --file "$ROOT/fixtures/packages/pylock-observation-artifact.whl" \
    --out "$T/invalid-observation.json" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || fail "malformed artifact hashes must fail closed (got $rc)"
done
set +e
"$ROOT/build/rh_cli" pylock-observe --audit "$ROOT/fixtures/packages/pylock-observation-audit.json" \
  --artifact 999 --file "$ROOT/fixtures/packages/pylock-observation-artifact.whl" \
  --out "$T/missing-observation.json" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 4 ]] || fail "unknown artifact id must fail closed (got $rc)"

set +e
"$ROOT/build/rh_cli" pylock --input "$T/pylock.toml" --input "$T/pylock.toml" --out "$T/duplicate-option.json" >/dev/null 2>&1
rc_duplicate_option=$?
set -e
[[ "$rc_duplicate_option" -eq 2 ]] || fail "duplicate CLI options must be rejected (got $rc_duplicate_option)"

echo "test_pylock_cli OK"
