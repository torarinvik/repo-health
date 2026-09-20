#!/usr/bin/env bash
# tools/profile.sh — bounded stage profile for the deterministic benchmark
# runner. Timings are machine-specific process wall-clock observations; every
# structural output and dataset digest is deterministic. Usage:
#   tools/profile.sh [out_dir]
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
mkdir -p "$OUT_DIR"

[[ -x "$ROOT/build/bench_runner" ]] || bash "$ROOT/tools/build.sh" >/dev/null

python3 - "$ROOT" "$OUT_DIR" <<'PY'
import json, os, shutil, sys
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, "tools"))
from bench_support import environment_metadata, measure, output_fields, throughput_and_outcomes
root, out_dir = sys.argv[1], sys.argv[2]
binp = os.path.join(root, "build", "bench_runner")
reps = int(os.environ.get("RH_BENCH_REPS", "10"))
if reps < 2:
    raise SystemExit("RH_BENCH_REPS must be at least 2")
compiler = os.environ.get("RH_COMPILER") or os.environ.get("ELISA_COMPILER_BIN") or shutil.which("elisac-stage1")
if not compiler:
    compiler_root = os.environ.get("ELISA_COMPILER_ROOT", os.path.join(root, "..", "Elisa-compiler"))
    compiler = os.path.join(compiler_root, "scripts", "elisac_stage1.sh")
metadata = environment_metadata(root, binp, compiler)
workloads = [
    (100, 42, "uniform", ("graph", "query", "metrics")),
    (1000, 42, "uniform", ("graph", "query", "metrics")),
    (10000, 7, "uniform", ("graph", "metrics")),
    (1000, 17, "long_tail", ("graph", "metrics")),
    (1000, 23, "central_hubs", ("graph", "query")),
    (1000, 29, "cycle", ("graph", "query")),
    (1000, 31, "ecosystem", ("ecosystem",)),
]
runs = []
for nodes, seed, distribution, stages in workloads:
    structural = {}
    for stage in stages:
        sample = measure([binp, str(nodes), str(seed), stage, distribution], reps)
        out1 = sample["output"]
        fields = output_fields(out1)
        digest = fields.get("digest", "")
        if len(digest) != 16:
            raise SystemExit("missing dataset digest for %s/%s/%s" % (nodes, seed, stage))
        if "nodes" not in fields or "edges" not in fields:
            raise SystemExit("profile output lacks structural fields for %s/%s/%s" % (nodes, seed, stage))
        structural[stage] = out1
        runs.append({
            "nodes": nodes,
            "seed": seed,
            "distribution": distribution,
            "stage": stage,
            "elapsed_ms": sample["latency"]["median_ms"],
            "latency": sample["latency"],
            "peak_rss": sample["peak_rss"],
            **throughput_and_outcomes(sample, fields),
            "dataset_digest": digest,
            "output": out1,
            "scope": "process wall clock including deterministic dataset construction",
        })
    digests = {output_fields(value).get("digest", "") for value in structural.values()}
    if len(digests) != 1:
        raise SystemExit("stage digests disagree for %s/%s" % (nodes, seed))
manifest = {
    **metadata,
    "profile": "rh-profile/3",
    "note": "timings and peak RSS are machine-specific; distribution, stage output, and dataset digests are deterministic",
    "reps": reps,
    "stages": ["graph", "query", "metrics", "ecosystem"],
    "workloads": [
        {"nodes": nodes, "seed": seed, "distribution": distribution, "stages": list(stages)}
        for nodes, seed, distribution, stages in workloads
    ],
    "runs": runs,
}
path = os.path.join(out_dir, "profile-manifest.json")
with open(path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, sort_keys=True)
    fh.write("\n")
for r in runs:
    print("profile %5d seed=%d %-12s %-7s median=%8.3f ms p95=%8.3f ms nodes/s=%9.3f rss=%d %s" % (r["nodes"], r["seed"], r["distribution"], r["stage"], r["latency"]["median_ms"], r["latency"]["p95_ms"], r["throughput"]["nodes_per_second"], r["peak_rss"]["max_bytes"], r["dataset_digest"]))
print("profile-manifest OK:", path)
PY
