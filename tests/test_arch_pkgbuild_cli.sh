#!/usr/bin/env bash
# tests/test_arch_pkgbuild_cli.sh — bounded Arch PKGBUILD metadata path.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-arch-pkgbuild"

fail() { echo "[arch-pkgbuild] FAIL: $1" >&2; exit 1; }

echo "[arch-pkgbuild] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/PKGBUILD" <<'EOF'
pkgname=demo
pkgver=1.2.3
pkgrel=4
epoch=1
pkgdesc='Demo package; prose is not public metadata'
url='https://example.invalid/demo'
license=('MIT')
arch=('x86_64' 'aarch64')
source=("https://example.invalid/demo-${pkgver}.tar.gz" 'demo.patch')
sha256sums=('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'SKIP')
depends=('libfoo>=2' 'libbar')
makedepends=('gcc')
checkdepends=('pytest')
optdepends=('docs: documentation')
provides=('demo-api')
conflicts=('old-demo')
unknown_field='retained'
prepare() {
  echo no execution
}
EOF

"$ROOT/build/rh_cli" arch-pkgbuild --input "$T/PKGBUILD" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" "$T/PKGBUILD" "$T/out.json.transformations.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-arch-pkgbuild-result/1" and d["format"] == "arch-pkgbuild", d
tr = json.load(open(sys.argv[3]))
assert tr["adapter"] == "arch-pkgbuild" and tr["output_schema"] == d["schema"], tr
assert tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/arch-pkgbuild/1").hexdigest(), tr
assert {f["state"] for f in tr["fields"]} == {"preserved", "transformed", "unknown", "unsupported", "discarded"}, tr
assert d["name"] == "demo" and d["pkgver"] == "1.2.3" and d["pkgrel"] == "4", d
assert d["licenses"] == ["MIT"] and d["architectures"] == ["x86_64", "aarch64"], d
assert d["sources"][0] == "https://example.invalid/demo-${pkgver}.tar.gz", d
assert d["checksums"][1] == "SKIP", d
assert [(r["name"], r["scope"], r["state"]) for r in d["relations"]] == [
    ("libfoo>=2", "runtime", "declared"), ("libbar", "runtime", "declared"),
    ("gcc", "build", "declared"), ("pytest", "check", "declared"),
    ("docs: documentation", "optional", "declared"), ("demo-api", "provide", "declared"),
    ("old-demo", "conflict", "declared")
], d["relations"]
assert d["unknown_fields"] == 1 and d["unresolved_relations"] == 0, d
assert "Demo package" not in open(sys.argv[1]).read(), d
assert "not executed or expanded" in d["note"], d["note"]
print("[arch-pkgbuild] declaration fields and shell boundary OK")
PY

echo "[arch-pkgbuild] unresolved shell relation remains visible"
cat > "$T/unresolved" <<'EOF'
pkgname=macro-demo
pkgver=${pkgver:-1}
pkgrel=1
license=('GPL')
depends=('${pkgname}-runtime')
build() { :; }
EOF
"$ROOT/build/rh_cli" arch-pkgbuild --input "$T/unresolved" --out "$T/unresolved.json" >/dev/null || fail "unresolved run"
python3 - "$T/unresolved.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["relations"] == [{"name": "${pkgname}-runtime", "scope": "runtime", "state": "unresolved"}], d
assert d["pkgver"] == "${pkgver:-1}", d
print("[arch-pkgbuild] unresolved substitution state OK")
PY

echo "[arch-pkgbuild] deterministic output and malformed negatives"
"$ROOT/build/rh_cli" arch-pkgbuild --input "$T/PKGBUILD" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "output not deterministic"
set +e
printf 'pkgname=demo\npkgrel=1\n' > "$T/missing-version"
"$ROOT/build/rh_cli" arch-pkgbuild --input "$T/missing-version" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
printf 'pkgname demo\npkgver=1\npkgrel=1\n' > "$T/bad-assignment"
"$ROOT/build/rh_cli" arch-pkgbuild --input "$T/bad-assignment" --out "$T/x" >/dev/null 2>&1; rc_assignment=$?
printf 'pkgname=demo\npkgver=1\npkgrel=1\ndepends=(\"unterminated)\n' > "$T/bad-array"
"$ROOT/build/rh_cli" arch-pkgbuild --input "$T/bad-array" --out "$T/x" >/dev/null 2>&1; rc_array=$?
set -e
for rc in "$rc_missing" "$rc_assignment" "$rc_array"; do
  [[ "$rc" -eq 4 ]] || fail "malformed PKGBUILD must exit 4 (got $rc)"
done

echo "test_arch_pkgbuild_cli OK"
