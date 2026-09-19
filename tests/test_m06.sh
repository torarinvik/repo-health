#!/usr/bin/env bash
# tests/test_m06.sh — M06 gate: four-valued policy evaluator, exact
# comparisons, freshness/sample gates, precedence, exceptions, TOCTOU,
# agent contract, correction invalidation/replay. Deterministic, offline.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m06] FAIL: $1" >&2; exit 1; }

echo "[m06] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_m06" ]] || fail "test_m06 not built"

echo "[m06] policy truth tables + precedence + exceptions + TOCTOU + corrections"
out="$("$ROOT/build/test_m06")" || fail "test_m06: $out"
[[ "$out" == *"M06 OK"* ]] || fail "test_m06: $out"
echo "$out"

echo "[m06] notification policy + query contract"
outb="$("$ROOT/build/test_m06b")" || fail "test_m06b: $outb"
[[ "$outb" == *"M06B OK"* ]] || fail "test_m06b: $outb"
echo "$outb"

echo "[m06] S011: signatures/tests/popularity never satisfy a measurement rule"
grep -q "s011-signature-not-allow" "$ROOT/src/test_m06.elisa" || fail "S011 signature check missing"
grep -q "s011-popularity-not-deny" "$ROOT/src/test_m06.elisa" || fail "S011 popularity check missing"
grep -q "s011-incomplete-unknown" "$ROOT/src/test_m06.elisa" || fail "S011 completeness check missing"

echo "[m06] no-unsolicited-accusations rule present in notification policy"
grep -q "never a valid destination unless they explicitly subscribed" "$ROOT/src/rh_notify.elisa" || fail "upstream authorization rule missing"
grep -q "outage != abandonment" "$ROOT/src/rh_query.elisa" || fail "capability localization rule missing"

echo "[m06] exactness: policy module carries no floating point"
if grep -qE "f32|f64" "$ROOT/src/rh_policy.elisa"; then
  fail "float in policy comparisons"
fi
echo "[m06] exact rational comparisons OK"

echo "[m06] no-unknown-to-allow: lattice order is deny > unknown > warn > allow"
grep -q "deny > unknown > warn > allow" "$ROOT/src/rh_policy.elisa" || fail "lattice contract missing"
grep -q "unknown can never be spent as permission" "$ROOT/src/rh_policy.elisa" || fail "fail-closed contract missing"

echo "[m06] honesty: STATUS.md marks M06 in progress"
grep -q "M06 API/policy/corrections.*in_progress" "$ROOT/STATUS.md" || fail "STATUS.md misstates M06"

echo "test_m06 OK"
