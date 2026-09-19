#!/usr/bin/env bash
# tests/test_homebrew_cli.sh — bounded Homebrew formula metadata.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-homebrew"

fail() { echo "[homebrew] FAIL: $1" >&2; exit 1; }

echo "[homebrew] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-homebrew-formula/1","name":"wget","homepage":"https://www.gnu.org/software/wget/","revision":2,"stable":{"version":"1.25.0","url":"https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz","sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","dependencies":["libidn2"],"build_dependencies":["pkg-config"],"optional_dependencies":["gnutls"],"test_dependencies":["perl"]}}
JSON
"$ROOT/build/rh_cli" homebrew --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
d = json.loads(raw)
assert d["schema"] == "rh-homebrew-result/1", d
assert d["name"] == "wget" and d["stable_version"] == "1.25.0" and d["revision"] == 2, d
assert d["counts"] == {"dependencies": 4, "runtime": 1, "build": 1, "optional": 1, "test": 1}, d
assert d["stable_digest"].startswith("sha256:"), d
assert [x["scope"] for x in d["dependencies"]] == ["runtime", "build", "optional", "test"], d
assert "description" not in raw.split('"note"', 1)[0] and "install" not in raw.split('"note"', 1)[0], raw
assert "dependencies are not resolved" in d["note"], d
print("[homebrew] formula assertions + scoped requirements OK")
PY

echo "[homebrew] deterministic output"
"$ROOT/build/rh_cli" homebrew --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "homebrew output not deterministic"

echo "[homebrew] malformed, unsafe, and bad-digest inputs fail closed"
set +e
printf '{"schema":"rh-homebrew-formula/2"}' > "$T/badschema.json"
"$ROOT/build/rh_cli" homebrew --input "$T/badschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
sed 's#https://ftp.gnu.org#http://ftp.gnu.org#' "$T/in.json" > "$T/badurl.json"
"$ROOT/build/rh_cli" homebrew --input "$T/badurl.json" --out "$T/x" >/dev/null 2>&1; rc_url=$?
sed 's/0123456789abcdef/zzzzzzzzzzzzzzzzzz/g' "$T/in.json" > "$T/baddigest.json"
"$ROOT/build/rh_cli" homebrew --input "$T/baddigest.json" --out "$T/x" >/dev/null 2>&1; rc_digest=$?
printf 'not json' > "$T/notjson"
"$ROOT/build/rh_cli" homebrew --input "$T/notjson" --out "$T/x" >/dev/null 2>&1; rc_json=$?
set -e
for rc in "$rc_schema" "$rc_url" "$rc_digest" "$rc_json"; do
  [[ "$rc" -eq 4 ]] || fail "malformed Homebrew input must exit 4 (got $rc)"
done

echo "test_homebrew_cli OK"
