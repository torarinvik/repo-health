#!/usr/bin/env bash
# tests/test_distribution_cli.sh — bounded Debian control metadata execution.
# Source links and declared relations remain assertions; maintainer identity
# and free-form descriptions never enter the public result.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-distribution"

fail() { echo "[distribution] FAIL: $1" >&2; exit 1; }

echo "[distribution] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/control" <<'EOF'
Source: example-parser
Version: 1.2.3-4
Section: devel
Maintainer: Alice <alice@example.org>
Homepage: https://example.org/example-parser
Vcs-Git: https://git.example.org/example-parser.git
Build-Depends: debhelper-compat (= 13), libfoo-dev (>= 2.0) | libfoo-legacy
Build-Depends-Indep: python3-all
X-Local-Note: private source note

Package: example-parser
Architecture: any
Section: devel
Source: example-parser (1.2.3-4)
Depends: ${shlibs:Depends}, libfoo2 (>= 2.0), ${misc:Depends}
Recommends: parser-doc
Description: example parser
 long description is retained only as source text

Package: example-parser-tools
Architecture: all
Depends: example-parser (= 1.2.3-4)
Provides: parser-tools
EOF

"$ROOT/build/rh_cli" distribution --input "$T/control" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" "$T/control" "$T/out.json.transformations.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-distribution-result/1" and d["format"] == "debian-control", d
tr = json.load(open(sys.argv[3]))
assert tr["adapter"] == "debian-control" and tr["output_schema"] == d["schema"], tr
assert tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/debian-control/1").hexdigest(), tr
assert {f["state"] for f in tr["fields"]} == {"preserved", "transformed", "unknown", "unsupported", "discarded"}, tr
print("[distribution] rh-adapter-transformation-report/1 verified")
assert len(d["source_stanzas"]) == 1 and len(d["binary_packages"]) == 2, d
s = d["source_stanzas"][0]
assert s["name"] == "example-parser" and s["version"] == "1.2.3-4", s
assert len(s["build_relations"]) == 3, s["build_relations"]
assert any(r["alternatives"] and r["state"] == "unresolved" for r in s["build_relations"]), s
assert [a["kind"] for a in s["source_assertions"]] == ["vcs-git", "homepage"], s
b = d["binary_packages"]
assert b[0]["name"] == "example-parser" and b[0]["architecture"] == "any", b[0]
assert b[1]["provides"] == "parser-tools", b[1]
assert any(r["name"] == "libfoo2" for r in b[0]["relations"]), b[0]
assert d["unknown_fields"] == 1 and d["unresolved_relations"] == 3, d
assert "Alice" not in open(sys.argv[1]).read() and "alice@example.org" not in open(sys.argv[1]).read(), d
assert "Description" not in open(sys.argv[1]).read(), d
print("[distribution] source/package observations + relation states OK")
PY

echo "[distribution] deterministic output"
"$ROOT/build/rh_cli" distribution --input "$T/control" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "distribution output not deterministic"

echo "[distribution] malformed stanzas fail closed and preserve the prior output"
cp "$T/out.json" "$T/sentinel.json"
set +e
printf 'Package example-parser\nVersion: 1\n' > "$T/no-colon"
"$ROOT/build/rh_cli" distribution --input "$T/no-colon" --out "$T/sentinel.json" >/dev/null 2>&1; rc_colon=$?
printf ' continuation before field\n' > "$T/continuation"
"$ROOT/build/rh_cli" distribution --input "$T/continuation" --out "$T/sentinel.json" >/dev/null 2>&1; rc_cont=$?
printf 'Package: one\nPackage: two\n' > "$T/duplicate"
"$ROOT/build/rh_cli" distribution --input "$T/duplicate" --out "$T/sentinel.json" >/dev/null 2>&1; rc_dup=$?
set -e
for rc in "$rc_colon" "$rc_cont" "$rc_dup"; do
  [[ "$rc" -eq 4 ]] || fail "malformed distribution input must exit 4 (got $rc)"
done
cmp -s "$T/out.json" "$T/sentinel.json" || fail "malformed input replaced prior output"

echo "test_distribution_cli OK"
