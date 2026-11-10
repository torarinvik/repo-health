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
  # Incremental: skip when the binary is newer than every Elisa source,
  # the linked process bridge, and this script. Keeps local suites fast;
  # delete build/ to force a clean rebuild.
  if [[ -x "$out" && -z "$(find "$ROOT/src" -name '*.elisa' -newer "$out" -print -quit 2>/dev/null)" \
     && "$out" -nt "$PROCESS_OBJECT" && "$out" -nt "${BASH_SOURCE[0]}" ]]; then
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

BUILD_TARGETS=(
  test_oracles test_process test_forge test_store test_package
  test_continuity test_continuity_scan test_m05 test_project_map
  test_m06 test_m06b test_m07 test_m07_sha test_m08 test_osv_query
  test_ecosystem_lookup test_properties test_m04_roles test_m11
  test_job test_reconcile test_worker test_http test_postgres
  test_postgres_live rh_cli bench_runner
)
compile_target() {
  local name="$1"
  local src="$ROOT/src/$name.elisa"
  [[ -f "$src" ]] || { echo "unknown build target: $name" >&2; return 2; }
  compile "$src" "$name"
}

if [[ "${1:-}" == "--only" ]]; then
  shift
  (( $# > 0 )) || { echo "usage: $0 [--only target [target ...]]" >&2; exit 2; }
  for target in "$@"; do
    case " ${BUILD_TARGETS[*]} " in
      *" $target "*) compile_target "$target" ;;
      *) echo "unknown build target: $target" >&2; exit 2 ;;
    esac
  done
else
  (( $# == 0 )) || { echo "usage: $0 [--only target [target ...]]" >&2; exit 2; }
  for target in "${BUILD_TARGETS[@]}"; do
    [[ -f "$ROOT/src/$target.elisa" ]] && compile_target "$target"
  done
fi
echo "build OK: $(ls "$ROOT/build" | tr '\n' ' ')"
