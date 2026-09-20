#!/usr/bin/env bash
# Bounded local smoke run for the instrumented coverage-guided Elisa parser target.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m07-fuzz-test] FAIL: $1" >&2; exit 1; }

RUNS="${M07_FUZZ_TEST_RUNS:-1000}"
WORK_ROOT="$ROOT/build/tmp_m07_fuzz_$$"
mkdir -p "$WORK_ROOT"
trap 'rm -rf "$WORK_ROOT"' EXIT

output="$(ELISA_M07_FUZZ_WORK="$WORK_ROOT" bash "$ROOT/tools/fuzz-m07.sh" "$RUNS" 2>&1)" \
  || fail "coverage-guided parser campaign failed: $output"
[[ "$output" == *"Loaded "*"inline 8-bit counters"* ]] || fail "sanitizer coverage counters were not loaded"
[[ "$output" == *"22 files found"* ]] || fail "checked-in parser seed corpus was not loaded"
[[ "$output" == *"Done $RUNS runs"* ]] || fail "libFuzzer did not complete $RUNS runs"
[[ "$output" == *"cov:"* ]] || fail "libFuzzer coverage summary missing"
initial_cov="$(sed -n 's/.*INITED cov: \([0-9][0-9]*\).*/\1/p' <<<"$output" | head -n 1)"
final_cov="$(sed -n 's/.*DONE.*cov: \([0-9][0-9]*\).*/\1/p' <<<"$output" | tail -n 1)"
[[ -n "$initial_cov" && -n "$final_cov" ]] || fail "libFuzzer coverage counts missing"
(( final_cov > initial_cov )) || fail "coverage did not increase ($initial_cov -> $final_cov)"
printf '%s\n' "$output" | grep -E 'Loaded .*inline 8-bit counters|files found|INITED cov:|DONE.*cov:|^Done '
echo "test_m07_fuzz OK"
