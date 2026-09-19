#!/usr/bin/env bash
# tests/test_experimental_cli.sh — M11 experimental isolation execution path
# (R024): `rh_cli experimental` turns rh-experimental-input/1 into
# rh-experimental-result/1. A spec is admissible only when opt-in, in wave G,
# costed, and explicitly limited; the sample discontinuity metric is an
# observable horizon outcome, labelled experimental, with censored subjects
# excluded from the denominator and zero-observable reported not_applicable.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-experimental"

fail() { echo "[experimental] FAIL: $1" >&2; exit 1; }

echo "[experimental] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-experimental-input/1","specs":[{"key":"discontinuity.no_qualifying_release_in_horizon","wave":7,"cost":"low","limits":["a","b"],"opt_in":true},{"key":"x.wrongwave","wave":1,"cost":"high","limits":["x"],"opt_in":true},{"key":"x.nooptin","wave":7,"cost":"low","limits":["x"],"opt_in":false},{"key":"x.nocost","wave":7,"limits":["x"],"opt_in":true},{"key":"x.nolimits","wave":7,"cost":"low","limits":[],"opt_in":true}],"observations":[{"follow_up_complete":true,"qualifying_release_in_horizon":true},{"follow_up_complete":true,"qualifying_release_in_horizon":false},{"follow_up_complete":false,"qualifying_release_in_horizon":false}]}
JSON
"$ROOT/build/rh_cli" experimental --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-experimental-result/1", d
by = {s["key"]: s for s in d["specs"]}
assert by["discontinuity.no_qualifying_release_in_horizon"]["admissible"] is True, by
assert by["x.wrongwave"]["reason"] == "wrong-wave", by
assert by["x.nooptin"]["reason"] == "not-opt-in", by
assert by["x.nocost"]["reason"] == "no-cost", by
assert by["x.nolimits"]["reason"] == "no-limits", by
v = d["metric"]["value"]
assert d["metric"]["status"] == "observed", d["metric"]
assert v == {"with_release": 1, "without_release": 1, "censored": 1,
             "denominator": 2, "rate": {"num": 1, "den": 2}}, v
assert d["label"] == "experimental: observable horizon outcome, not a reliability or abandonment label", d["label"]
assert "excluded from the default policy path" in d["note"], d["note"]
assert "not a claim about the project" in d["note"], d["note"]
print("[experimental] admissibility + outcome OK")
PY

echo "[experimental] all-censored -> not_applicable; no admissible spec -> unsupported"
printf '{"schema":"rh-experimental-input/1","specs":[{"key":"discontinuity.no_qualifying_release_in_horizon","wave":7,"cost":"low","limits":["a"],"opt_in":true}],"observations":[{"follow_up_complete":false,"qualifying_release_in_horizon":false}]}' > "$T/censored.json"
"$ROOT/build/rh_cli" experimental --input "$T/censored.json" --out "$T/censored.out" >/dev/null || fail "censored run"
printf '{"schema":"rh-experimental-input/1","specs":[{"key":"discontinuity.no_qualifying_release_in_horizon","wave":1,"cost":"low","limits":["a"],"opt_in":true}],"observations":[{"follow_up_complete":true,"qualifying_release_in_horizon":false}]}' > "$T/inadm.json"
"$ROOT/build/rh_cli" experimental --input "$T/inadm.json" --out "$T/inadm.out" >/dev/null || fail "inadm run"
python3 - "$T/censored.out" "$T/inadm.out" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
i = json.load(open(sys.argv[2]))
assert c["metric"]["status"] == "not_applicable" and c["metric"]["value"] is None, c["metric"]
assert i["metric"]["status"] == "unsupported" and i["metric"]["reason"] == "no-admissible-experimental-spec", i["metric"]
print("[experimental] not_applicable/unsupported OK")
PY

echo "[experimental] determinism + fail-closed negatives"
"$ROOT/build/rh_cli" experimental --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "experimental output not deterministic"
set +e
printf '{"schema":"rh-experimental-input/2","specs":[]}' > "$T/bschema.json"
"$ROOT/build/rh_cli" experimental --input "$T/bschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-experimental-input/1","specs":42}' > "$T/bsp.json"
"$ROOT/build/rh_cli" experimental --input "$T/bsp.json" --out "$T/x" >/dev/null 2>&1; rc_specs=$?
printf '{"schema":"rh-experimental-input/1","specs":[{"key":"k","wave":7,"cost":"free","limits":["a"],"opt_in":true}]}' > "$T/bcost.json"
"$ROOT/build/rh_cli" experimental --input "$T/bcost.json" --out "$T/x" >/dev/null 2>&1; rc_cost=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" experimental --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" experimental --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_specs" "$rc_cost" "$rc_json" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed experimental input must exit 4 (got $rc)"
done

echo "test_experimental_cli OK"
