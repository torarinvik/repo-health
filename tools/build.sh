#!/usr/bin/env bash
# tools/build.sh — compile every Elisa binary in src/ into build/.
#
# Toolchain pattern (mirrors elisa-engine): the installed stage1 snapshot
# (`elisac-stage1` on PATH, see TOOLCHAIN.md) compiles straight to
# executables with `-emit exe`. No wrapper scripts, no manual clang link.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
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
PROCESS_OBJECT="$ROOT/build/rh_process.o"
if [[ ! -f "$PROCESS_OBJECT" || "$ROOT/src/rh_process.c" -nt "$PROCESS_OBJECT" ]]; then
  clang -std=c11 -O2 -Wall -Wextra -Werror -c "$ROOT/src/rh_process.c" -o "$PROCESS_OBJECT"
fi
PROCESS_TREE_TEST="$ROOT/build/test_process_tree"
if [[ ! -x "$PROCESS_TREE_TEST" || "$ROOT/src/test_process_tree.c" -nt "$PROCESS_TREE_TEST" ]]; then
  clang -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/src/test_process_tree.c" -o "$PROCESS_TREE_TEST"
fi
BASE_LINK_FLAGS="${ELISA_STAGE1_LINK:-}"
BASE_LINK_FLAGS="${BASE_LINK_FLAGS:+$BASE_LINK_FLAGS }build/rh_process.o"
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
  if [[ "$name" == "rh_cli" ]]; then
    local link_flags="$BASE_LINK_FLAGS"
    link_flags="${link_flags:+$link_flags }-lz"
    if [[ "$COMPILER" == *.sh ]]; then
      ELISA_STAGE1_LINK="$link_flags" bash "$COMPILER" -emit exe -o "$out" "$src"
    else
      ELISA_STAGE1_LINK="$link_flags" "$COMPILER" -emit exe -o "$out" "$src"
    fi
    return 0
  fi
  if [[ "$COMPILER" == *.sh ]]; then
    ELISA_STAGE1_LINK="$BASE_LINK_FLAGS" bash "$COMPILER" -emit exe -o "$out" "$src"
  else
    ELISA_STAGE1_LINK="$BASE_LINK_FLAGS" "$COMPILER" -emit exe -o "$out" "$src"
  fi
}

compile "$ROOT/src/test_oracles.elisa" test_oracles
compile "$ROOT/src/test_process.elisa" test_process
compile "$ROOT/src/test_forge.elisa" test_forge
compile "$ROOT/src/test_store.elisa" test_store
compile "$ROOT/src/test_package.elisa" test_package
compile "$ROOT/src/test_continuity.elisa" test_continuity
compile "$ROOT/src/test_continuity_scan.elisa" test_continuity_scan
compile "$ROOT/src/test_m05.elisa" test_m05
compile "$ROOT/src/test_project_map.elisa" test_project_map
compile "$ROOT/src/test_m06.elisa" test_m06
compile "$ROOT/src/test_m06b.elisa" test_m06b
compile "$ROOT/src/test_m07.elisa" test_m07
compile "$ROOT/src/test_m07_sha.elisa" test_m07_sha
compile "$ROOT/src/test_m08.elisa" test_m08
compile "$ROOT/src/test_osv_query.elisa" test_osv_query
compile "$ROOT/src/test_ecosystem_lookup.elisa" test_ecosystem_lookup
compile "$ROOT/src/test_properties.elisa" test_properties
compile "$ROOT/src/test_m04_roles.elisa" test_m04_roles
compile "$ROOT/src/test_m11.elisa" test_m11
compile "$ROOT/src/test_job.elisa" test_job
compile "$ROOT/src/test_reconcile.elisa" test_reconcile
compile "$ROOT/src/test_worker.elisa" test_worker
compile "$ROOT/src/test_http.elisa" test_http
compile "$ROOT/src/test_postgres.elisa" test_postgres
compile "$ROOT/src/test_postgres_live.elisa" test_postgres_live
# M01 entry point lands here once rh_cli.elisa exists (backlog item 9).
if [[ -f "$ROOT/src/rh_cli.elisa" ]]; then
  compile "$ROOT/src/rh_cli.elisa" rh_cli
fi
if [[ -f "$ROOT/src/bench_runner.elisa" ]]; then
  compile "$ROOT/src/bench_runner.elisa" bench_runner
fi
echo "build OK: $(ls "$ROOT/build" | tr '\n' ' ')"
