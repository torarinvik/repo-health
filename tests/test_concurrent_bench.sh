#!/usr/bin/env bash
# M10 controlled concurrency runs independent identical local workload batches.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-concurrent-bench"

fail() { echo "[concurrent-bench] FAIL: $1" >&2; exit 1; }

echo "[concurrent-bench] build"
bash "$ROOT/tools/build.sh" >/dev/null
rm -rf "$T"; mkdir -p "$T"
RH_BENCH_REPS=2 RH_BENCH_CONCURRENT_JOBS=2 bash "$ROOT/tools/bench.sh" "$T" >/dev/null || fail "concurrent benchmark"

python3 - "$T/bench-manifest.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
assert manifest["concurrent_jobs"] == "2", manifest
assert manifest["reps"] == 2, manifest
for run in manifest["runs"]:
    assert len(run["latency"]["samples_ms"]) == 2, run
    assert len(run["peak_rss"]["samples_bytes"]) == 2, run
    assert run["outcomes"]["concurrent_processes_per_repetition"] == 2, run
    assert "per concurrent batch" in run["throughput"]["basis"], run
    assert "not aggregate batch memory" in run["peak_rss"]["basis"], run
print("[concurrent-bench] two-process batches + honest resource basis OK")
PY

echo "[concurrent-bench] concurrency bound fails closed"
set +e
RH_BENCH_CONCURRENT_JOBS=33 RH_BENCH_REPS=2 bash "$ROOT/tools/bench.sh" "$T/invalid" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "concurrency above 32 must fail"
echo "test_concurrent_bench OK"
