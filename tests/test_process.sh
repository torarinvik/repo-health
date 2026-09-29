#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
rm -f /tmp/rh-process-literal.out /tmp/rh-process-literal.err /tmp/rh-process-stdin.out /tmp/rh-process-stdin.err /tmp/rh-process-bytes.out /tmp/rh-process-overflow.out /tmp/rh-process-descendant-survived /tmp/rh-process-must-not-exist
bash "$ROOT/tools/build.sh" >/dev/null
"$ROOT/build/test_process" | grep -qx 'PROCESS OK'
test "$(cat /tmp/rh-process-literal.out)" = 'literal ; $(touch /tmp/rh-process-must-not-exist)'
test ! -e /tmp/rh-process-must-not-exist
test "$(wc -c < /tmp/rh-process-overflow.out | tr -d ' ')" -le 128
echo 'test_process OK'
