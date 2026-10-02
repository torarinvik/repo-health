#!/usr/bin/env bash
# tests/test_alpine_apkindex_cli.sh — bounded Alpine APKINDEX v2 text adapter.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-alpine-apkindex"

fail() { echo "[alpine-apkindex] FAIL: $1" >&2; exit 1; }

echo "[alpine-apkindex] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
INPUT="$T/input.txt"
cp "$ROOT/fixtures/distribution/alpine-apkindex.txt" "$INPUT"
"$ROOT/build/rh_cli" apkindex --input "$INPUT" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" "$INPUT" "$T/out.json.transformations.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-alpine-apkindex-result/1" and d["format"] == "alpine-apkindex-v2-text", d
tr = json.load(open(sys.argv[3]))
assert tr["adapter"] == "alpine-apkindex-v2-text" and tr["output_schema"] == d["schema"], tr
assert tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/alpine-apkindex-v2-text/1").hexdigest(), tr
assert {f["state"] for f in tr["fields"]} == {"preserved", "transformed", "unknown", "unsupported", "discarded"}, tr
assert len(d["packages"]) == 2, d
p, docs = d["packages"]
assert (p["name"], p["version"], p["architecture"]) == ("example-parser", "1.2.3-r4", "x86_64"), p
assert (p["package_size"], p["installed_size"], p["license"], p["origin"]) == (2048, 8192, "MIT", "example-parser"), p
assert (p["build_time"], p["commit"], p["provider_priority"]) == (1735689600, "abcdef0123456789", 2), p
assert p["checksum_claim"] == "Q1wJGovczsw4N4jw/k9uOuekSaOEw=", p
assert p["relations"] == [
    {"kind": "depends", "expression": "so:libc.musl-x86_64.so.1 libfoo>=2"},
    {"kind": "provides", "expression": "example-parser-api=1"},
], p
assert docs["name"] == "example-parser-docs" and docs["architecture"] == "noarch", docs
assert docs["relations"] == [{"kind": "install-if", "expression": "example-parser"}], docs
assert docs["license"] == "", docs
assert d["unknown_lowercase_fields"] == 2 and d["omitted_free_text_fields"] == 3, d
out = open(sys.argv[1]).read()
assert "Private description" not in out and "Maintainer Name" not in out and "secret@" not in out, out
assert "not verified" in d["note"], d
print("[alpine-apkindex] package declarations, omission, and transformation binding OK")
PY

"$ROOT/build/rh_cli" apkindex --input "$INPUT" --out "$T/out2.json" >/dev/null || fail "deterministic rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "output not deterministic"

echo "[alpine-apkindex] malformed and unsupported input fails closed"
cp "$T/out.json" "$T/sentinel.json"
set +e
printf 'P:missing-version\n' > "$T/missing-version"
"$ROOT/build/rh_cli" apkindex --input "$T/missing-version" --out "$T/sentinel.json" >/dev/null 2>&1; rc_missing=$?
printf 'P:missing-checksum\nV:1\n' > "$T/missing-checksum"
"$ROOT/build/rh_cli" apkindex --input "$T/missing-checksum" --out "$T/sentinel.json" >/dev/null 2>&1; rc_checksum=$?
printf 'P:duplicate\nP:again\nV:1\n' > "$T/duplicate"
"$ROOT/build/rh_cli" apkindex --input "$T/duplicate" --out "$T/sentinel.json" >/dev/null 2>&1; rc_duplicate=$?
printf 'P:bad-size\nV:1\nS:999999999999999999999999999999999999\n' > "$T/bad-size"
"$ROOT/build/rh_cli" apkindex --input "$T/bad-size" --out "$T/sentinel.json" >/dev/null 2>&1; rc_size=$?
printf 'P:future\nV:1\nZ:required-by-newer-apk\n' > "$T/unknown-uppercase"
"$ROOT/build/rh_cli" apkindex --input "$T/unknown-uppercase" --out "$T/sentinel.json" >/dev/null 2>&1; rc_upper=$?
printf 'P:bad-utf8\nV:\377\n' > "$T/bad-utf8"
"$ROOT/build/rh_cli" apkindex --input "$T/bad-utf8" --out "$T/sentinel.json" >/dev/null 2>&1; rc_utf8=$?
set -e
for rc in "$rc_missing" "$rc_checksum" "$rc_duplicate" "$rc_size" "$rc_upper" "$rc_utf8"; do
  [[ "$rc" -eq 4 ]] || fail "malformed APKINDEX must exit 4 (got $rc)"
done
cmp -s "$T/out.json" "$T/sentinel.json" || fail "malformed input replaced prior output"

echo "test_alpine_apkindex_cli OK"
