#!/usr/bin/env bash
# tools/check.sh — single safe local suite entry (no credentials, no network
# beyond approved local fixture remotes). Fails closed on missing toolchain.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Same resolution as tools/build.sh: explicit bin, PATH shim, else sibling.
if [[ -n "${ELISA_COMPILER_BIN:-}" ]]; then
  COMPILER="$ELISA_COMPILER_BIN"
elif command -v elisac-stage1 >/dev/null 2>&1; then
  COMPILER="$(command -v elisac-stage1)"
else
  SIBLING="${ELISA_COMPILER_ROOT:-$ROOT/../Elisa-compiler}"
  COMPILER="$SIBLING/scripts/elisac_stage1.sh"
fi

fail() { echo "check FAIL: $1" >&2; exit 1; }

[[ -n "$COMPILER" ]] || fail "no Elisa compiler (elisac-stage1 on PATH or ELISA_COMPILER_BIN)"
[[ -x "$COMPILER" ]] || [[ "$COMPILER" == *.sh && -f "$COMPILER" ]] || fail "compiler not executable: $COMPILER"
command -v git >/dev/null || fail "git not found"

echo "toolchain OK:"
echo "  compiler: $COMPILER"
git --version

# Deterministic local suite only. Networked connector tests are opt-in and
# live under tests/ with RH_LIVE_TESTS=1 (never in this default gate).
export RH_COMPILER="$COMPILER"
PASS=0
for t in "$ROOT"/tests/test_*.sh; do
  [[ -x "$t" ]] || continue
  echo "--- $(basename "$t")"
  bash "$t"
  PASS=$((PASS + 1))
done
echo "check OK: $PASS test harness(es) passed (deterministic, local only)"
