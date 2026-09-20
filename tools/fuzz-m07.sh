#!/usr/bin/env bash
# Build an Elisa parser target with sanitizer coverage and run libFuzzer.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m07-fuzz] FAIL: $1" >&2; exit 1; }

RUNS="${1:-1000}"
SEED="${ELISA_M07_FUZZ_SEED:-20260920}"
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || fail "run count must be a positive integer"
[[ "$SEED" =~ ^[0-9]+$ ]] || fail "fuzzer seed must be a non-negative integer"
[[ "$#" -le 1 ]] || fail "usage: tools/fuzz-m07.sh [runs]"

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

if [[ -n "${ELISA_CLANG:-}" ]]; then
  CLANG="$ELISA_CLANG"
elif [[ -n "${ELISA_LLVM_BIN_DIR:-}" && -x "$ELISA_LLVM_BIN_DIR/clang" ]]; then
  CLANG="$ELISA_LLVM_BIN_DIR/clang"
elif command -v clang >/dev/null 2>&1; then
  CLANG="$(command -v clang)"
else
  fail "clang with libFuzzer support is required"
fi
[[ -x "$CLANG" ]] || fail "clang unavailable: $CLANG"

WORK_ROOT="${ELISA_M07_FUZZ_WORK:-$ROOT/build/m07-fuzz-$$}"
CORPUS="$WORK_ROOT/corpus"
ARTIFACTS="$WORK_ROOT/artifacts"
mkdir -p "$WORK_ROOT" "$ARTIFACTS"
if [[ ! -d "$CORPUS" ]]; then
  cp -R "$ROOT/fixtures/fuzz/m07" "$CORPUS"
fi
[[ -n "$(find "$CORPUS" -type f -print -quit)" ]] || fail "fuzz corpus is empty: $CORPUS"

IR="$WORK_ROOT/fuzz_m07.ll"
OBJECT="$WORK_ROOT/fuzz_m07.o"
FUZZER="$WORK_ROOT/fuzz_m07"
echo "[m07-fuzz] compile Elisa target with $COMPILER"
if [[ "$COMPILER" == *.sh ]]; then
  bash "$COMPILER" -emit llvm -o "$IR" "$ROOT/src/fuzz_m07.elisa"
else
  "$COMPILER" -emit llvm -o "$IR" "$ROOT/src/fuzz_m07.elisa"
fi
[[ -s "$IR" ]] || fail "LLVM IR output missing"

echo "[m07-fuzz] instrument and link with $CLANG"
CLANG_VERSION="$("$CLANG" --version | head -n 1)"
echo "[m07-fuzz] clang=$CLANG_VERSION"
"$CLANG" -c -fsanitize=fuzzer-no-link,address,undefined -fno-omit-frame-pointer -fno-builtin -o "$OBJECT" "$IR"
"$CLANG" -fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer -fno-builtin \
  -o "$FUZZER" "$OBJECT" "$ROOT/tests/support/elisa_fuzz_fallback.c" -lz -lpthread
[[ -x "$FUZZER" ]] || fail "libFuzzer binary missing"

echo "[m07-fuzz] runs=$RUNS corpus=$CORPUS artifacts=$ARTIFACTS"
# macOS libFuzzer keeps a process-lifetime RSS-monitor thread that LeakSanitizer
# reports at shutdown; the independent deterministic sanitizer gate retains LSan.
ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1}" \
UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}" \
  "$FUZZER" "-runs=$RUNS" "-seed=$SEED" -max_len=65536 "-artifact_prefix=$ARTIFACTS/" "$CORPUS"
