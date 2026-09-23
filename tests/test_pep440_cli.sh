#!/usr/bin/env bash
# tests/test_pep440_cli.sh — M08 PEP 440 version-semantics execution path:
# `rh_cli pep440` parses a version list and emits per-version details plus
# an ascending order over VALID versions only. Asserts Python ordering
# (epoch, release, a/b/rc pre with dev, post) and that invalid versions are
# reported but never compared or sorted.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-pep440"

fail() { echo "[pep440] FAIL: $1" >&2; exit 1; }

echo "[pep440] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-pep440-input/1","versions":["1.0.post1","1.0","1.0rc1","1.0b1","1.0a1","1.0a1.dev1","2.0","1!0.1","1.0.1","1.0+local","v1.0","1..2"]}
JSON
"$ROOT/build/rh_cli" pep440 --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" "$T/in.json" "$T/out.json.transformations.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-pep440-result/1", d
tr = json.load(open(sys.argv[3]))
assert tr["schema"] == "rh-adapter-transformation-report/1" and tr["adapter"] == "python-pep440-version-order", tr
assert tr["output_schema"] == d["schema"], tr
assert tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/python-pep440/1").hexdigest(), tr
assert {f["state"] for f in tr["fields"]} == {"preserved", "transformed", "unsupported", "discarded"}, tr
assert d["sorted"] == ["1.0a1.dev1", "1.0a1", "1.0b1", "1.0rc1", "1.0", "1.0+local",
                       "1.0.post1", "1.0.1", "2.0", "1!0.1"], d["sorted"]
by = {v["version"]: v for v in d["versions"]}
# invalid versions are reported but never compared/sorted
assert by["v1.0"]["valid"] is False and by["1..2"]["valid"] is False, by
assert "v1.0" not in d["sorted"] and "1..2" not in d["sorted"], d["sorted"]
# dev-of-pre sorts below the pre, which sorts below the release
assert by["1.0a1.dev1"]["pre_rank"] == "a" and by["1.0a1.dev1"]["dev"] == 1, by["1.0a1.dev1"]
assert by["1.0a1"]["pre_num"] == 1 and by["1.0a1"]["dev"] is None, by["1.0a1"]
assert by["1.0"]["pre_num"] is None and by["1.0"]["post"] is None, by["1.0"]
assert by["1.0.post1"]["post"] == 1, by["1.0.post1"]
assert by["1.0+local"]["has_local"] is True, by["1.0+local"]
# epoch dominates release
assert by["1!0.1"]["epoch"] == 1 and by["2.0"]["epoch"] == 0, (by["1!0.1"], by["2.0"])
assert "not SemVer" in d["note"], d["note"]
print("[pep440] ordering + validity OK")
PY

echo "[pep440] determinism"
"$ROOT/build/rh_cli" pep440 --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "pep440 output not deterministic"

echo "[pep440] malformed input fails closed"
set +e
printf '{"schema":"rh-pep440-input/2","versions":[]}' > "$T/badschema.json"
"$ROOT/build/rh_cli" pep440 --input "$T/badschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-pep440-input/1","versions":42}' > "$T/badarr.json"
"$ROOT/build/rh_cli" pep440 --input "$T/badarr.json" --out "$T/x" >/dev/null 2>&1; rc_arr=$?
printf '{"schema":"rh-pep440-input/1","versions":[1,2]}' > "$T/badstr.json"
"$ROOT/build/rh_cli" pep440 --input "$T/badstr.json" --out "$T/x" >/dev/null 2>&1; rc_str=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" pep440 --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" pep440 --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_arr" "$rc_str" "$rc_json" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed pep440 input must exit 4 (got $rc)"
done

echo "test_pep440_cli OK"
