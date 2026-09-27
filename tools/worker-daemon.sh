#!/usr/bin/env bash
# tools/worker-daemon.sh — bounded process wrapper for the Elisa worker pass.
#
# The input document is an externally refreshed rh-worker-input/1 contract.
# A tick is run only after its bytes change, so an unchanged source table is
# not repeatedly scheduled. --max-cycles makes pilots and tests finite;
# omitting it keeps the process alive until SIGTERM/SIGINT.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
CLI="$ROOT/build/rh_cli"
INPUT=""
OUTPUT=""
INTERVAL=30
MAX_CYCLES=0

usage() {
  echo "usage: tools/worker-daemon.sh --input <worker-input.json> --out <worker-plan.json> [--interval-secs N] [--max-cycles N]" >&2
  exit 2
}

while (($#)); do
  case "$1" in
    --input) (($# >= 2)) || usage; INPUT="$2"; shift 2 ;;
    --out) (($# >= 2)) || usage; OUTPUT="$2"; shift 2 ;;
    --interval-secs) (($# >= 2)) || usage; INTERVAL="$2"; shift 2 ;;
    --max-cycles) (($# >= 2)) || usage; MAX_CYCLES="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$INPUT" && -n "$OUTPUT" ]] || usage
[[ -x "$CLI" ]] || { echo "worker-daemon: rh_cli not built: $CLI" >&2; exit 4; }
[[ -r "$INPUT" ]] || { echo "worker-daemon: input is not readable: $INPUT" >&2; exit 4; }
[[ "$INTERVAL" =~ ^[0-9]+$ && "$MAX_CYCLES" =~ ^[0-9]+$ ]] || { echo "worker-daemon: interval/max-cycles must be non-negative integers" >&2; exit 2; }

running=1
trap 'running=0' INT TERM
last_digest=""
cycles=0
runs=0
state_dir="$(mktemp -d "${TMPDIR:-/tmp}/rh-worker-daemon.XXXXXX")"
trap 'rm -rf "$state_dir"' EXIT

while ((running)); do
  digest="$(cksum < "$INPUT")"
  if [[ "$digest" != "$last_digest" ]]; then
    # Carry the previous plan's cursor unless the producer explicitly owns it.
    # Invalid input is copied unchanged so the CLI remains the validation gate.
    python3 - "$INPUT" "$OUTPUT" "$state_dir/input.json" <<'PY'
import json, pathlib, sys
source, previous, target = map(pathlib.Path, sys.argv[1:])
raw = source.read_bytes()
try:
    document = json.loads(raw)
except (UnicodeDecodeError, json.JSONDecodeError):
    target.write_bytes(raw)
    raise SystemExit(0)
if isinstance(document, dict) and "rotation_cursor" not in document:
    try:
        plan = json.loads(previous.read_bytes())
        cursor = plan.get("next_rotation_cursor") if isinstance(plan, dict) else None
        if isinstance(cursor, int) and not isinstance(cursor, bool) and cursor >= 0:
            document["rotation_cursor"] = cursor
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        pass
target.write_text(json.dumps(document, separators=(",", ":")) + "\n")
PY
    "$CLI" worker tick --input "$state_dir/input.json" --out "$OUTPUT"
    last_digest="$digest"
    runs=$((runs + 1))
  fi
  cycles=$((cycles + 1))
  if ((MAX_CYCLES > 0 && cycles >= MAX_CYCLES)); then
    break
  fi
  sleep "$INTERVAL"
done

echo "worker-daemon: cycles=$cycles runs=$runs"
