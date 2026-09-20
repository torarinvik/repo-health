#!/usr/bin/env bash
# tests/test_pg_adapter.sh — parameterized libpq page-commit adapter boundary.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-pg-adapter"

fail() { echo "[pg-adapter] FAIL: $1" >&2; exit 1; }

echo "[pg-adapter] build Elisa adapter probe"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_postgres" ]] || fail "test_postgres not built"
command -v cc >/dev/null 2>&1 || fail "C compiler unavailable for libpq ABI fixture"
mkdir -p "$T"
if [[ "$(uname -s)" == "Darwin" ]]; then
  cc -dynamiclib -o "$T/libpq.dylib" "$ROOT/tests/fixtures/fake_libpq.c" || fail "compile fake libpq"
else
  cc -shared -fPIC -o "$T/libpq.so" "$ROOT/tests/fixtures/fake_libpq.c" || fail "compile fake libpq"
fi
LIBPQ="$T/libpq.so"
[[ "$(uname -s)" == "Darwin" ]] && LIBPQ="$T/libpq.dylib"

for operation in page heartbeat finish claim; do
  for mode in committed duplicate failure connect_failure; do
    if [[ "$mode" == "connect_failure" ]]; then
      RH_FAKE_PG_OPERATION="$operation" RH_FAKE_PG_CONNECT_FAIL=1 RH_FAKE_PG_EXPECT="$mode" RH_LIBPQ_PATH="$LIBPQ" "$ROOT/build/test_postgres" || fail "$operation $mode result"
    else
      RH_FAKE_PG_OPERATION="$operation" RH_FAKE_PG_EXPECT="$mode" RH_LIBPQ_PATH="$LIBPQ" "$ROOT/build/test_postgres" || fail "$operation $mode result"
    fi
  done
done
RH_FAKE_PG_OPERATION=page RH_FAKE_PG_EXPECT=missing RH_LIBPQ_PATH="$T/no-libpq-here.dylib" "$ROOT/build/test_postgres" || fail "missing libpq result"
echo "[pg-adapter] bound page and lease operations, claim outputs, fencing outcomes, and failure paths OK"
