#!/usr/bin/env bash
# Opt-in real-browser profile for deterministic report pages.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
mkdir -p "$OUT_DIR"
[[ "${RH_BROWSER_BENCH:-0}" == "1" ]] || { echo "set RH_BROWSER_BENCH=1 to run the browser render profile" >&2; exit 2; }
[[ -n "${RH_PLAYWRIGHT_CLI:-}" && -x "$RH_PLAYWRIGHT_CLI" ]] || { echo "set RH_PLAYWRIGHT_CLI to an executable playwright-cli wrapper" >&2; exit 2; }
[[ -x "$ROOT/build/rh_cli" ]] || bash "$ROOT/tools/build.sh" >/dev/null
exec python3 "$ROOT/tools/bench_browser_render.py" "$ROOT" "$OUT_DIR" "$RH_PLAYWRIGHT_CLI"
