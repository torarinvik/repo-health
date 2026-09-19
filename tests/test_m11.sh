#!/usr/bin/env bash
# tests/test_m11.sh — M11 experimental isolation gate (R024):
# admissibility (wave/cost/limits/opt-in), observable-outcome semantics,
# censoring, not_applicable, and the mandatory experimental label.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m11] FAIL: $1" >&2; exit 1; }

echo "[m11] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_m11" ]] || fail "test_m11 not built"

echo "[m11] admissibility + observable outcome + censoring"
out="$("$ROOT/build/test_m11")" || fail "test_m11: $out"
[[ "$out" == *"M11 OK"* ]] || fail "test_m11: $out"
echo "$out"

echo "[m11] experimental metric is defined, wave G, costed, limited"
python3 - "$ROOT/metrics/definitions/experimental_discontinuity.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["group"] == "experimental", d
assert d["wave"] == "G", d
assert d["cost_class"] in ("medium", "high"), d
assert d["limits"], d
assert d["implementation_status"] != "implemented", d
assert d["output"]["unit"] == "ratio" and d["output"]["numerator"] and d["output"]["denominator"], d
print("[m11] definition OK:", d["key"])
PY

echo "[m11] cadence anomaly adapter is defined, wave G, costed, limited"
python3 - "$ROOT/metrics/definitions/experimental_anomaly_cadence.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["group"] == "experimental", d
assert d["wave"] == "G", d
assert d["cost_class"] in ("medium", "high"), d
assert d["limits"], d
assert d["implementation_status"] != "implemented", d
assert d["output"]["unit"] == "count" and d["output"]["numerator"] and d["output"]["denominator"], d
assert "baseline_windows" in d["params"], d
assert any("score" in l or "score" in l for l in d["limits"]) or any("concrete" in l for l in d["limits"]), d
print("[m11] anomaly definition OK:", d["key"])
PY
# The anomaly adapter must also carry a name-and-deny caveat and avoid a verdict.
grep -q "not a maliciousness" "$ROOT/src/rh_experimental.elisa" || fail "anomaly caveat missing"

echo "[m11] caveats may name-and-deny; assertions may not carry a verdict"
# A caveat line that explicitly denies a judgement is allowed (it is the
# honest form). Only a line that asserts such a verdict is rejected. This
# mirrors the allowed-caveat logic in tools/publication-review.sh.
violations="$(grep -riE "abandon|unreliab|unhealth|unstable|at risk" "$ROOT/src/rh_experimental.elisa" \
  | grep -viE "never|not a|no |without|do not|does not|isn't|label" || true)"
if [[ -n "$violations" ]]; then
  echo "$violations"
  fail "experimental module asserts a judgement label"
fi
grep -q "never called abandonment" "$ROOT/src/rh_experimental.elisa" || fail "caveat missing"

echo "[m11] negative control: an asserting line is rejected"
tmp="$ROOT/src/_m11_bad.elisa"
cp "$ROOT/src/rh_experimental.elisa" "$tmp"
printf '\n# This project is abandoned and unreliable.\n' >> "$tmp"
viol="$(grep -riE "abandon|unreliab|unhealth|unstable|at risk" "$tmp" \
  | grep -viE "never|not a|no |without|do not|does not|isn't|label" || true)"
rm -f "$tmp"
[[ -n "$viol" ]] || fail "negative control: asserting label was not detected"
echo "[m11] negative control OK"

echo "[m11] lint enforces experimental isolation"
bash "$ROOT/tools/metric-lint.sh" | tail -n 1

echo "test_m11 OK"
