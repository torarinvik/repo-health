#!/usr/bin/env bash
# tests/test_profile_bench.sh — M10 profiling manifest: graph, query, and
# metric stages retain one dataset digest while timings remain machine-specific.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-profile-bench"

fail() { echo "[profile-bench] FAIL: $1" >&2; exit 1; }

echo "[profile-bench] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/bench_runner" ]] || fail "bench_runner not built"

rm -rf "$T"; mkdir -p "$T/a" "$T/b"
bash "$ROOT/tools/profile.sh" "$T/a" >/dev/null || fail "profile run"
bash "$ROOT/tools/profile.sh" "$T/b" >/dev/null || fail "profile rerun"
python3 - "$T/a/profile-manifest.json" "$T/b/profile-manifest.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
assert a["profile"] == b["profile"] == "rh-profile/3", a
assert a["stages"] == ["graph", "query", "metrics", "ecosystem"], a
assert a["note"] and "machine-specific" in a["note"], a
assert a["cache_state"] == "fresh process per sample; operating-system caches uncontrolled", a
assert a["reps"] == 10 and a["warmup_runs_per_workload"] == 1, a
assert a["concurrent_jobs"] == "1", a
assert a["database_configuration"].startswith("not_applicable"), a
assert a["external_requests"] == 0 and a["hardware"]["logical_cpu_count"] > 0, a
assert a["code_revision"] and len(a["binary_sha256"]) == 64 and len(a["harness_sha256"]) == 64, a
assert isinstance(a["working_tree_dirty"], bool) and isinstance(a["working_tree_status"], list), a
def shape(d):
    return [(r["nodes"], r["seed"], r["distribution"], r["stage"], r["dataset_digest"], r["output"]) for r in d["runs"]]
assert shape(a) == shape(b), (shape(a), shape(b))
expected_workloads = [
    {"nodes": 100, "seed": 42, "distribution": "uniform", "stages": ["graph", "query", "metrics"]},
    {"nodes": 1000, "seed": 42, "distribution": "uniform", "stages": ["graph", "query", "metrics"]},
    {"nodes": 10000, "seed": 7, "distribution": "uniform", "stages": ["graph", "metrics"]},
    {"nodes": 1000, "seed": 17, "distribution": "long_tail", "stages": ["graph", "metrics"]},
    {"nodes": 1000, "seed": 23, "distribution": "central_hubs", "stages": ["graph", "query"]},
    {"nodes": 1000, "seed": 29, "distribution": "cycle", "stages": ["graph", "query"]},
    {"nodes": 1000, "seed": 31, "distribution": "ecosystem", "stages": ["ecosystem"]},
]
assert a["workloads"] == expected_workloads, a
assert len(a["runs"]) == sum(len(w["stages"]) for w in expected_workloads), a
assert all(len(r["latency"]["samples_ms"]) == 10 for r in a["runs"]), a
assert all(0 <= r["latency"]["median_ms"] <= r["latency"]["p95_ms"] <= r["latency"]["max_ms"] for r in a["runs"]), a
assert all(len(r["peak_rss"]["samples_bytes"]) == 10 and r["peak_rss"]["max_bytes"] > 0 for r in a["runs"]), a
assert all(r["concurrent_peak_rss_upper_bound"]["samples_bytes"] == r["peak_rss"]["samples_bytes"] for r in a["runs"]), a
for run in a["runs"]:
    sampled = run["sampled_concurrent_peak_rss"]
    bounds = run["concurrent_peak_rss_upper_bound"]["samples_bytes"]
    assert len(sampled["samples_bytes"]) == len(sampled["sample_counts_per_batch"]) == 10, sampled
    assert sampled["sampled_batches"] == sum(value is not None for value in sampled["samples_bytes"]), sampled
    assert all((value is None) == (count == 0) for value, count in zip(sampled["samples_bytes"], sampled["sample_counts_per_batch"])), sampled
    assert all(value is None or (0 < value <= bound) for value, bound in zip(sampled["samples_bytes"], bounds)), sampled
    assert sampled["sampling_interval_target_ms"] == 1, sampled
assert any(run["sampled_concurrent_peak_rss"]["sampled_batches"] > 0 for run in a["runs"]), a
assert all(r["throughput"]["nodes_per_second"] > 0 for r in a["runs"]), a
assert all(r["outcomes"]["successful_repetitions"] == 10 and r["outcomes"]["failed_repetitions"] == 0 for r in a["runs"]), a
assert all(r["outcomes"]["error_rate"] == 0 for r in a["runs"]), a
assert all(r["outcomes"]["query_repetitions"] == 0 and r["outcomes"]["transitive_truncation_rate"] is None for r in a["runs"] if r["stage"] == "graph" or r["stage"] == "metrics"), a
assert all(r["outcomes"]["query_repetitions"] == 10 and r["outcomes"]["transitive_truncation_rate"] in (0, 1) for r in a["runs"] if r["stage"] == "query"), a
for workload in expected_workloads:
    nodes, seed, distribution = workload["nodes"], workload["seed"], workload["distribution"]
    ds = {r["dataset_digest"] for r in a["runs"] if r["nodes"] == nodes and r["seed"] == seed and r["distribution"] == distribution}
    assert len(ds) == 1, (nodes, seed, ds)
    assert all("process wall clock" in r["scope"] for r in a["runs"] if r["nodes"] == nodes and r["seed"] == seed and r["distribution"] == distribution)
assert any(r["nodes"] == 10000 and r["stage"] == "metrics" for r in a["runs"]), a
ecosystem = [r for r in a["runs"] if r["stage"] == "ecosystem"]
assert len(ecosystem) == 1, a
fields = dict(token.split("=", 1) for token in ecosystem[0]["output"].split() if "=" in token)
assert fields["versions"] == "1000" and fields["packages"] == "500", fields
assert fields["corrections"] == "32" and fields["superseded"] == "64", fields
print("[profile-bench] stage manifest + deterministic digests OK")
PY

echo "test_profile_bench OK"
