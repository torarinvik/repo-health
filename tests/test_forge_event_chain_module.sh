#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tools/build.sh --only test_forge_event_chain >/dev/null
RH_FORGE_EVENT_CHAIN_BIN="$ROOT/build/test_forge_event_chain" \
  "$ROOT/tests/test_forge_event_chain_cli.sh"
