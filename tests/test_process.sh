#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
rm -f /tmp/rh-process-literal.out /tmp/rh-process-literal.err /tmp/rh-process-must-not-exist
bash "$ROOT/tools/build.sh" >/dev/null
"$ROOT/build/test_process" | grep -qx 'PROCESS OK'
test "$(cat /tmp/rh-process-literal.out)" = 'literal ; $(touch /tmp/rh-process-must-not-exist)'
test ! -e /tmp/rh-process-must-not-exist
echo 'test_process OK'
