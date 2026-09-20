#!/usr/bin/env bash
# tools/build.sh — compile every Elisa binary in src/ into build/.
#
# Toolchain pattern (mirrors elisa-engine): the installed stage1 snapshot
# (`elisac-stage1` on PATH, see TOOLCHAIN.md) compiles straight to
# executables with `-emit exe`. No wrapper scripts, no manual clang link.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Resolution order: explicit ELISA_COMPILER_BIN, else elisac-stage1 on PATH
# (the ~/.elisac snapshot shim), else the sibling-checkout wrapper.
# No absolute machine-specific paths are stored here.
if [[ -n "${ELISA_COMPILER_BIN:-}" ]]; then
  COMPILER="$ELISA_COMPILER_BIN"
elif command -v elisac-stage1 >/dev/null 2>&1; then
  COMPILER="$(command -v elisac-stage1)"
else
  SIBLING="${ELISA_COMPILER_ROOT:-$ROOT/../Elisa-compiler}"
  COMPILER="$SIBLING/scripts/elisac_stage1.sh"
  export ELISA_STAGE1_BIN="${ELISA_STAGE1_BIN:-$SIBLING/bin/elisac-stage1}"
  export ELISA_ALLOW_STALE_STAGE1=1
fi

mkdir -p "$ROOT/build"
compile() {
  local src="$1" name="$2"
  local out="$ROOT/build/$name"
  # Incremental: skip when the binary is newer than every source module and
  # than this script. Keeps the single local suite fast; delete build/ to
  # force a clean rebuild.
  if [[ -x "$out" && -z "$(find "$ROOT/src" -name '*.elisa' -newer "$out" -print -quit 2>/dev/null)" \
     && "$out" -nt "${BASH_SOURCE[0]}" ]]; then
    return 0
  fi
  echo "compile $src -> build/$name"
  if [[ "$COMPILER" == *.sh ]]; then
    bash "$COMPILER" -emit exe -o "$out" "$src"
  else
    "$COMPILER" -emit exe -o "$out" "$src"
  fi
}

compile "$ROOT/src/test_oracles.elisa" test_oracles
compile "$ROOT/src/test_forge.elisa" test_forge
compile "$ROOT/src/test_store.elisa" test_store
compile "$ROOT/src/test_package.elisa" test_package
compile "$ROOT/src/test_continuity.elisa" test_continuity
compile "$ROOT/src/test_continuity_scan.elisa" test_continuity_scan
compile "$ROOT/src/test_m05.elisa" test_m05
compile "$ROOT/src/test_m06.elisa" test_m06
compile "$ROOT/src/test_m06b.elisa" test_m06b
compile "$ROOT/src/test_m07.elisa" test_m07
compile "$ROOT/src/test_m07_sha.elisa" test_m07_sha
compile "$ROOT/src/test_m08.elisa" test_m08
compile "$ROOT/src/test_osv_query.elisa" test_osv_query
compile "$ROOT/src/test_properties.elisa" test_properties
compile "$ROOT/src/test_m04_roles.elisa" test_m04_roles
compile "$ROOT/src/test_m11.elisa" test_m11
compile "$ROOT/src/test_job.elisa" test_job
compile "$ROOT/src/test_reconcile.elisa" test_reconcile
compile "$ROOT/src/test_worker.elisa" test_worker
compile "$ROOT/src/test_http.elisa" test_http
# M01 entry point lands here once rh_cli.elisa exists (backlog item 9).
if [[ -f "$ROOT/src/rh_cli.elisa" ]]; then
  compile "$ROOT/src/rh_cli.elisa" rh_cli
fi
if [[ -f "$ROOT/src/bench_runner.elisa" ]]; then
  compile "$ROOT/src/bench_runner.elisa" bench_runner
fi
echo "build OK: $(ls "$ROOT/build" | tr '\n' ' ')"
