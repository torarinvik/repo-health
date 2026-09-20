#!/usr/bin/env bash
# Compile the deterministic M07 parser mutation harness with native sanitizers.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m07-sanitizer] FAIL: $1" >&2; exit 1; }

if [[ -n "${ELISA_COMPILER_BIN:-}" ]]; then
  COMPILER="$ELISA_COMPILER_BIN"
elif [[ -n "${RH_COMPILER:-}" ]]; then
  COMPILER="$RH_COMPILER"
elif command -v elisac-stage1 >/dev/null 2>&1; then
  COMPILER="$(command -v elisac-stage1)"
else
  SIBLING="${ELISA_COMPILER_ROOT:-$ROOT/../Elisa-compiler}"
  COMPILER="$SIBLING/scripts/elisac_stage1.sh"
  export ELISA_STAGE1_BIN="${ELISA_STAGE1_BIN:-$SIBLING/bin/elisac-stage1}"
  export ELISA_ALLOW_STALE_STAGE1=1
fi
[[ -x "$COMPILER" ]] || [[ "$COMPILER" == *.sh && -f "$COMPILER" ]] || fail "compiler unavailable: $COMPILER"

SANITIZER_BINARY="$ROOT/build/test_m07_sanitized"
SANITIZER_FLAGS="${ELISA_STAGE1_LINK:-}"
SANITIZER_FLAGS="${SANITIZER_FLAGS:+$SANITIZER_FLAGS }-fsanitize=address,undefined -fno-omit-frame-pointer"
echo "[m07-sanitizer] compile with AddressSanitizer + UndefinedBehaviorSanitizer"
if [[ "$COMPILER" == *.sh ]]; then
  ELISA_STAGE1_LINK="$SANITIZER_FLAGS" bash "$COMPILER" -emit exe -o "$SANITIZER_BINARY" "$ROOT/src/test_m07.elisa"
else
  ELISA_STAGE1_LINK="$SANITIZER_FLAGS" "$COMPILER" -emit exe -o "$SANITIZER_BINARY" "$ROOT/src/test_m07.elisa"
fi
[[ -x "$SANITIZER_BINARY" ]] || fail "sanitized test binary missing"

RUN_ROOT="$ROOT/build/m07-sanitizer-run-$$"
mkdir -p "$RUN_ROOT/build/tmp_m07/store/evidence" "$RUN_ROOT/build/tmp_m07/restore/evidence"
output="$(cd "$RUN_ROOT" && ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=1:halt_on_error=1}" UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}" "$SANITIZER_BINARY")" || fail "sanitized M07 harness failed: $output"
[[ "$output" == *"M07 OK"* ]] || fail "sanitized M07 harness did not report success: $output"
echo "$output"
echo "[m07-sanitizer] compiler=$COMPILER host=$(uname -srm) flags=address,undefined"
echo "test_m07_sanitizer OK"
