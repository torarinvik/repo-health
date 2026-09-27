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
    if tick_output="$(python3 - "$CLI" "$INPUT" "$OUTPUT" "$state_dir/input.json" <<'PY'
import fcntl, hashlib, json, os, pathlib, subprocess, sys, tempfile
cli, source_name, output_name, prepared_name = sys.argv[1:]
source, output = pathlib.Path(source_name), pathlib.Path(output_name)
state = pathlib.Path(output_name + ".worker-state.json")
lock_path = pathlib.Path(output_name + ".worker.lock")
input_bytes = source.read_bytes()
input_digest = hashlib.sha256(input_bytes).hexdigest()
with lock_path.open("a+b") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    previous = {}
    try:
        value = json.loads(state.read_bytes())
        if isinstance(value, dict) and value.get("schema") == "rh-worker-daemon-state/1":
            previous = value
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        pass
    if previous.get("input_sha256") == input_digest:
        print("worker-daemon-tick:unchanged")
        raise SystemExit(0)
    try:
        document = json.loads(input_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError):
        prepared = input_bytes
    else:
        if isinstance(document, dict) and "rotation_cursor" not in document:
            cursor = previous.get("next_rotation_cursor")
            if isinstance(cursor, int) and not isinstance(cursor, bool) and cursor >= 0:
                document["rotation_cursor"] = cursor
        prepared = (json.dumps(document, separators=(",", ":")) + "\n").encode()
    pathlib.Path(prepared_name).write_bytes(prepared)
    result = subprocess.run([cli, "worker", "tick", "--input", prepared_name, "--out", output_name], capture_output=True, text=True)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode:
        raise SystemExit(result.returncode)
    try:
        plan = json.loads(output.read_bytes())
        cursor = plan.get("next_rotation_cursor") if isinstance(plan, dict) else None
        if not isinstance(cursor, int) or isinstance(cursor, bool) or cursor < 0:
            raise ValueError("worker plan omitted a valid next_rotation_cursor")
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        print(f"worker-daemon: cannot persist scheduling state: {error}", file=sys.stderr)
        raise SystemExit(4)
    state_bytes = json.dumps({"schema":"rh-worker-daemon-state/1", "input_sha256":input_digest, "next_rotation_cursor":cursor}, separators=(",", ":")).encode() + b"\n"
    with tempfile.NamedTemporaryFile(dir=state.parent, prefix=state.name + ".", delete=False) as staged:
        staged.write(state_bytes)
        staged.flush()
        os.fsync(staged.fileno())
        staged_name = staged.name
    os.replace(staged_name, state)
    print("worker-daemon-tick:scheduled")
PY
    )"; then
      printf '%s\n' "$tick_output"
    else
      tick_rc=$?
      printf '%s\n' "$tick_output" >&2
      exit "$tick_rc"
    fi
    last_digest="$digest"
    [[ "$tick_output" == *"worker-daemon-tick:scheduled"* ]] && runs=$((runs + 1))
  fi
  cycles=$((cycles + 1))
  if ((MAX_CYCLES > 0 && cycles >= MAX_CYCLES)); then
    break
  fi
  sleep "$INTERVAL"
done

echo "worker-daemon: cycles=$cycles runs=$runs"
