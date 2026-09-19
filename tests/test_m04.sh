#!/usr/bin/env bash
# tests/test_m04.sh — M04 gate: continuity, retention censoring,
# concentration, reversible identity links. Deterministic, offline.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m04] FAIL: $1" >&2; exit 1; }

echo "[m04] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_continuity" ]] || fail "test_continuity not built"

echo "[m04] oracles + fixtures A-E + revocation + report fields"
out="$("$ROOT/build/test_continuity")" || fail "test_continuity: $out"
[[ "$out" == *"CONTINUITY OK"* ]] || fail "test_continuity: $out"
echo "$out"

echo "[m04] R013: declared roles vs observed actions"
outr="$("$ROOT/build/test_m04_roles")" || fail "test_m04_roles: $outr"
[[ "$outr" == *"M04R OK"* ]] || fail "test_m04_roles: $outr"
echo "$outr"
grep -q "Declarations do NOT become observed facts" "$ROOT/src/rh_roles.elisa" || fail "declared-vs-observed caveat missing"
grep -q "never guessed into maintainer" "$ROOT/src/rh_roles.elisa" || fail "no-role-guess caveat missing"

echo "[m04] S008: destructive merge is reversible; raw ledger untouched"
grep -q "id-full-revoke-restores" "$ROOT/src/test_continuity.elisa" || fail "S008 full-revoke-restores check missing"
grep -q "id-revision-back-to-1" "$ROOT/src/test_continuity.elisa" || fail "S008 revision-revert check missing"

echo "[m04] structural guarantee: identity layer cannot mutate raw events"
# rh_identity.elisa is the only module allowed to map accounts->clusters,
# and it takes no event ledger at all: revocation therefore cannot touch
# raw evidence, it can only change derived cluster maps.
if grep -qE "event|commit|release|review" "$ROOT/src/rh_identity.elisa"; then
  fail "rh_identity.elisa references raw events; revocation could contaminate the ledger"
fi
echo "[m04] raw ledger isolation OK"

echo "[m04] no universal score language in continuity modules (R030)"
if grep -riE "health_score|trust_score|trustworthy|reputation" "$ROOT/src/rh_continuity.elisa" "$ROOT/src/rh_identity.elisa"; then
  fail "score language in continuity modules"
fi
echo "[m04] R030 language OK"

echo "[m04] honesty: STATUS.md marks M04 in progress"
grep -q "M04 continuity/identity.*in_progress" "$ROOT/STATUS.md" || fail "STATUS.md misstates M04"

echo "test_m04 OK"
