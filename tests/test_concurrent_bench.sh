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
    upper = run["concurrent_peak_rss_upper_bound"]
    assert len(upper["samples_bytes"]) == 2, run
    assert upper["max_bytes"] == max(upper["samples_bytes"]), upper
    assert all(total >= individual for total, individual in zip(upper["samples_bytes"], run["peak_rss"]["samples_bytes"])), run
    assert "sum of each child peak RSS" in upper["basis"], upper
    assert "not simultaneous aggregate memory" in upper["basis"], upper
    sampled = run["sampled_concurrent_peak_rss"]
    assert len(sampled["samples_bytes"]) == len(sampled["sample_counts_per_batch"]) == 2, sampled
    assert sampled["sampled_batches"] == sum(value is not None for value in sampled["samples_bytes"]), sampled
    assert all((value is None) == (count == 0) for value, count in zip(sampled["samples_bytes"], sampled["sample_counts_per_batch"])), sampled
    assert all(value is None or (0 < value <= bound) for value, bound in zip(sampled["samples_bytes"], upper["samples_bytes"])), sampled
    assert sampled["sampling_interval_target_ms"] == 1, sampled
    assert "sum of child RSS reads collected in one driver poll pass" in sampled["basis"], sampled
    assert "brief peaks may be missed" in sampled["basis"], sampled
    assert run["outcomes"]["concurrent_processes_per_repetition"] == 2, run
    assert "per concurrent batch" in run["throughput"]["basis"], run
    assert "not aggregate batch memory" in run["peak_rss"]["basis"], run
assert any(run["sampled_concurrent_peak_rss"]["sampled_batches"] > 0 for run in manifest["runs"]), manifest
print("[concurrent-bench] sampled concurrent RSS + conservative upper bounds OK")
PY

echo "[concurrent-bench] concurrency bound fails closed"
set +e
RH_BENCH_CONCURRENT_JOBS=33 RH_BENCH_REPS=2 bash "$ROOT/tools/bench.sh" "$T/invalid" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "concurrency above 32 must fail"
echo "test_concurrent_bench OK"
