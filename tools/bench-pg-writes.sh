#!/usr/bin/env bash
# Opt-in PostgreSQL page-write profile for the real rh_cli adapter.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
mkdir -p "$OUT_DIR"
[[ "${RH_PG_WRITE_BENCH:-0}" == "1" ]] || { echo "set RH_PG_WRITE_BENCH=1 to start the PostgreSQL write benchmark" >&2; exit 2; }
[[ -x "$ROOT/build/rh_cli" ]] || bash "$ROOT/tools/build.sh" >/dev/null
exec python3 "$ROOT/tools/bench_pg_writes.py" "$ROOT" "$OUT_DIR"
