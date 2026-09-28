#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d /tmp/rh-process-capacity.XXXXXX)"
trap 'rm -rf "$T"' EXIT
clang -std=c11 -O2 -Wall -Wextra -Werror -pthread \
  "$ROOT/src/rh_process.c" "$ROOT/tests/test_process_capacity.c" \
  -o "$T/test_process_capacity"
"$T/test_process_capacity"
