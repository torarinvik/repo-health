#!/usr/bin/env bash
# tests/test_registry_meta_cli.sh — M03-05 registry enrichment execution
# path: `rh_cli registry-meta` turns an rh-registry-meta/1 document into
# rh-registry-meta-result/1. Asserts yanked versions are retained, an absent
# yank field is null (unknown, not false), numeric and ISO published times
# are preserved, a declared repository link is an assertion (not identity),
# declared dependency counts are exact, and malformed input fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-registry-meta"

fail() { echo "[registry-meta] FAIL: $1" >&2; exit 1; }

echo "[registry-meta] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/packages/registry-meta.json" "$T/in.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-registry-meta-result/1", d
assert d["counts"] == {"versions": 3, "yanked": 1, "unknown_yank": 1, "with_repo": 1,
                       "declared_deps": 3, "optional_deps": 1, "dev_deps": 1}, d["counts"]
v = d["versions"]
assert v[0] == {"version": "1.0.0", "yanked": False, "published_at": 1609459200,
                "repository": "https://example.invalid/serde",
                "dep_count": 3, "optional_dep_count": 1, "dev_dep_count": 1}, v[0]
assert v[1]["yanked"] is True and v[1]["published_at"] == "2024-03-10T12:00:00Z", v[1]
# retained, not deleted: the yanked version is still present
assert len(v) == 3 and v[1]["version"] == "1.0.1", v
# absent yank -> null (unknown), never false
assert v[2]["yanked"] is None and v[2]["published_at"] is None, v[2]
assert "assertion, not identity" in d["note"], d["note"]
assert "retained, not deleted" in d["note"], d["note"]
print("[registry-meta] counts + honest states OK")
PY

echo "[registry-meta] yank false/true/absent map to false/true/null"
cat > "$T/yanks.json" <<'JSON'
{"versions":[{"num":"1","yanked":false},{"num":"2","yanked":true},{"num":"3"}]}
JSON
"$ROOT/build/rh_cli" registry-meta --input "$T/yanks.json" --out "$T/yanks.out" >/dev/null || fail "yanks"
python3 - "$T/yanks.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert [x["yanked"] for x in d["versions"]] == [False, True, None], d["versions"]
assert d["counts"]["yanked"] == 1 and d["counts"]["unknown_yank"] == 1, d["counts"]
print("[registry-meta] yank tri-state OK")
PY

echo "[registry-meta] determinism"
"$ROOT/build/rh_cli" registry-meta --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "registry-meta output not deterministic"

echo "[registry-meta] malformed input fails closed"
set +e
printf '{"versions":42}' > "$T/shape.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/shape.json" --out "$T/x" >/dev/null 2>&1; rc_shape=$?
printf '[{"versions":[]}]' > "$T/arr.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/arr.json" --out "$T/x" >/dev/null 2>&1; rc_arr=$?
printf '{"noversions":[]}' > "$T/novers.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/novers.json" --out "$T/x" >/dev/null 2>&1; rc_novers=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" registry-meta --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_shape" "$rc_arr" "$rc_novers" "$rc_json" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed registry-meta input must exit 4 (got $rc)"
done

echo "test_registry_meta_cli OK"
