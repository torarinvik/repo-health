#!/usr/bin/env bash
# tools/bench-render.sh — deterministic report-rendering profile (M10-01).
# Measures the real rh_cli parse/render/write path on bounded synthetic reports.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
mkdir -p "$OUT_DIR"

[[ -x "$ROOT/build/rh_cli" ]] || bash "$ROOT/tools/build.sh" >/dev/null

python3 - "$ROOT" "$OUT_DIR" <<'PY'
import hashlib, json, os, shutil, sys, tempfile, threading
root, out_dir = sys.argv[1:]
sys.path.insert(0, os.path.join(root, "tools"))
from bench_support import configured_concurrent_jobs, environment_metadata, measure

cli = os.path.join(root, "build", "rh_cli")
reps = int(os.environ.get("RH_RENDER_BENCH_REPS", os.environ.get("RH_BENCH_REPS", "10")))
if reps < 2:
    raise SystemExit("RH_RENDER_BENCH_REPS must be at least 2")
concurrent_jobs = configured_concurrent_jobs()
metadata = environment_metadata(root, cli, os.environ.get("RH_COMPILER") or os.environ.get("ELISA_COMPILER_BIN") or shutil.which("elisac-stage1") or "unknown", concurrent_jobs)
workloads = (10, 1000, 10000)
runs = []

with tempfile.TemporaryDirectory(prefix="rh-render-bench-", dir="/tmp") as work:
    for row_count in workloads:
        source = {
            "report": "repo-health-m01",
            "source": "deterministic-render-benchmark",
            "source_kind": "synthetic",
            "metrics": [
                {
                    "key": "benchmark.metric_%05d" % index,
                    "version": "1.0.0",
                    "status": "observed" if index % 5 else "unknown",
                    "value": index if index % 5 else None,
                    "reason": None if index % 5 else "synthetic_missing",
                    "evidence": ["evidence/object-%05d" % (index % 128)],
                }
                for index in range(row_count)
            ],
            "capabilities": {"history": "observed", "render_benchmark": "synthetic"},
            "timeline": [],
            "neighborhood": [],
        }
        source_path = os.path.join(work, "report-%d.json" % row_count)
        encoded = (json.dumps(source, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")
        with open(source_path, "wb") as stream:
            stream.write(encoded)
        source_digest = hashlib.sha256(encoded).hexdigest()
        output_paths = []
        ordinal = [0]
        lock = threading.Lock()

        def render_command() -> list[str]:
            with lock:
                output_path = os.path.join(work, "render-%d-%05d.html" % (row_count, ordinal[0]))
                ordinal[0] += 1
                output_paths.append(output_path)
            return [cli, "render", "--report", source_path, "--out", output_path]

        sample = measure(render_command, reps, concurrent_jobs)
        output_digests = set()
        output_sizes = set()
        for path in output_paths:
            with open(path, "rb") as stream:
                output = stream.read()
            output_digests.add(hashlib.sha256(output).hexdigest())
            output_sizes.add(len(output))
        if len(output_digests) != 1 or len(output_sizes) != 1:
            raise SystemExit("render output changed across repetitions for %d rows" % row_count)
        if len(output_paths) != (reps + 1) * concurrent_jobs:
            raise SystemExit("render workload sample count is inconsistent")
        runs.append({
            "metric_rows": row_count,
            "input_bytes": len(encoded),
            "input_sha256": source_digest,
            "output_bytes": next(iter(output_sizes)),
            "output_sha256": next(iter(output_digests)),
            "elapsed_ms": sample["latency"]["median_ms"],
            "latency": sample["latency"],
            "peak_rss": sample["peak_rss"],
            "concurrent_peak_rss_upper_bound": sample["concurrent_peak_rss_upper_bound"],
            "sampled_concurrent_peak_rss": sample["sampled_concurrent_peak_rss"],
            "outcomes": {
                "successful_repetitions": sample["successful_repetitions"],
                "failed_repetitions": sample["failed_repetitions"],
                "concurrent_processes_per_repetition": sample["concurrent_processes_per_repetition"],
            },
            "scope": "fresh-process wall clock for rh_cli render; includes process startup, JSON parsing, HTML generation, and file write",
        })

manifest = {
    **metadata,
    "database_configuration": "not_applicable; renderer reads a local report file and performs no database access",
    "profile": "rh-render-bench/1",
    "note": "synthetic report rows are deterministic; timings and memory are machine-specific and do not establish deployment capacity",
    "reps": reps,
    "warmup_runs_per_workload": 1,
    "external_requests": 0,
    "workloads": list(workloads),
    "runs": runs,
}
path = os.path.join(out_dir, "render-bench-manifest.json")
with open(path, "w", encoding="utf-8") as stream:
    json.dump(manifest, stream, indent=2, sort_keys=True)
    stream.write("\n")
for run in runs:
    print("render-bench rows=%d input=%d output=%d median=%8.3f ms p95=%8.3f ms rss=%d sha256=%s" % (
        run["metric_rows"], run["input_bytes"], run["output_bytes"],
        run["latency"]["median_ms"], run["latency"]["p95_ms"],
        run["peak_rss"]["max_bytes"], run["output_sha256"]))
print("render-bench-manifest OK:", path)
PY
