#!/usr/bin/env bash
# tools/bench.sh — M10 benchmark runner. Generates deterministic datasets
# with bench_runner and records a machine-readable perf manifest. Timing is
# measured AROUND the process and is machine-specific; the dataset digest is
# stable and is what tests assert. Usage: tools/bench.sh [out_dir]
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
mkdir -p "$OUT_DIR"

[[ -x "$ROOT/build/bench_runner" ]] || bash "$ROOT/tools/build.sh" >/dev/null

python3 - "$ROOT" "$OUT_DIR" <<'PY'
import json, os, shutil, sys
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, "tools"))
from bench_support import configured_concurrent_jobs, environment_metadata, measure, output_fields, throughput_and_outcomes
root, out_dir = sys.argv[1], sys.argv[2]
binp = os.path.join(root, "build", "bench_runner")
reps = int(os.environ.get("RH_BENCH_REPS", "10"))
if reps < 2:
    raise SystemExit("RH_BENCH_REPS must be at least 2")
concurrent_jobs = configured_concurrent_jobs()
compiler = os.environ.get("RH_COMPILER") or os.environ.get("ELISA_COMPILER_BIN") or shutil.which("elisac-stage1")
if not compiler:
    compiler_root = os.environ.get("ELISA_COMPILER_ROOT", os.path.join(root, "..", "Elisa-compiler"))
    compiler = os.path.join(compiler_root, "scripts", "elisac_stage1.sh")
metadata = environment_metadata(root, binp, compiler, concurrent_jobs)
workloads = [
    (100, 42, "all", "uniform"),
    (1000, 42, "all", "uniform"),
    (10000, 7, "metrics", "uniform"),
    (1000, 17, "graph", "long_tail"),
    (1000, 23, "graph", "central_hubs"),
    (1000, 29, "graph", "cycle"),
    (1000, 31, "ecosystem", "ecosystem"),
]
runs = []
for nodes, seed, stage, distribution in workloads:
    sample = measure([binp, str(nodes), str(seed), stage, distribution], reps, concurrent_jobs)
    out1 = sample["output"]
    fields = output_fields(out1)
    digest = fields.get("digest", "")
    if not digest or "nodes" not in fields or "edges" not in fields:
        raise SystemExit("benchmark output lacks structural fields for %s/%s/%s" % (nodes, seed, distribution))
    runs.append({
        "nodes": nodes,
        "seed": seed,
        "stage": stage,
        "distribution": distribution,
        "elapsed_ms": sample["latency"]["median_ms"],
        "latency": sample["latency"],
        "peak_rss": sample["peak_rss"],
        **throughput_and_outcomes(sample, fields),
        "digest": digest,
        "output": out1,
    })
manifest = {
    **metadata,
    "bench_version": "rh-bench/3",
    "note": "timings and peak RSS are machine-specific; graph distributions, stage output, dataset digests, and counts are deterministic",
    "reps": reps,
    "runs": runs,
}
path = os.path.join(out_dir, "bench-manifest.json")
with open(path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, sort_keys=True)
    fh.write("\n")
for r in runs:
    print("bench %5d nodes seed=%d %-12s %-7s median=%8.3f ms p95=%8.3f ms nodes/s=%9.3f rss=%d %s" % (r["nodes"], r["seed"], r["distribution"], r["stage"], r["latency"]["median_ms"], r["latency"]["p95_ms"], r["throughput"]["nodes_per_second"], r["peak_rss"]["max_bytes"], r["digest"]))
print("bench-manifest OK:", path)
PY
