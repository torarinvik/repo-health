#!/usr/bin/env bash
# Repeatable M10-02 full versus incremental aggregate benchmark.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -x "$ROOT/build/rh_cli" ]] || bash "$ROOT/tools/build.sh" >/dev/null
exec python3 "$ROOT/tools/bench_aggregate.py"
