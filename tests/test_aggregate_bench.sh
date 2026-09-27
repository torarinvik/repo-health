#!/usr/bin/env bash
# Smoke-check the reproducible M10-02 aggregate benchmark and manifest.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="/tmp/rh-aggregate-bench-${PPID}-$$.json"
trap 'rm -f "$OUT"' EXIT
RH_AGG_BENCH_EVENTS=120 RH_AGG_BENCH_REPS=2 RH_AGG_BENCH_OUT="$OUT" \
  "$ROOT/tools/bench-aggregate.sh" >/dev/null
python3 - "$OUT" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
assert manifest["schema"] == "rh-aggregate-bench/1", manifest
assert manifest["event_count"] == 120, manifest
assert manifest["repetitions"] == 2 and manifest["warmup_repetitions"] == 1, manifest
assert manifest["correctness"]["byte_identical"] is True, manifest
assert manifest["full_recompute"]["successful_repetitions"] == 2, manifest
assert manifest["partial_cache"]["successful_repetitions"] == 2, manifest
assert all(value > 0 for value in manifest["partial_cache"]["reused_partition_rows"]), manifest
assert manifest["baseline_input_sha256"] != manifest["changed_input_sha256"], manifest
assert manifest["limits"].startswith("Local synthetic event workload"), manifest
print("test_aggregate_bench OK")
PY
