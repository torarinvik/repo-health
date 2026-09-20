#!/usr/bin/env bash
# tools/bench.sh — M10 benchmark runner. Generates deterministic datasets
# with bench_runner and records a machine-readable perf manifest. Timing is
# measured AROUND the process and is machine-specific; the dataset digest is
# stable and is what tests assert. Usage: tools/bench.sh [out_dir]
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
mkdir -p "$OUT_DIR"

[[ -x "$ROOT/build/bench_runner" && -x "$ROOT/build/rh_cli" ]] || bash "$ROOT/tools/build.sh" >/dev/null

python3 - "$ROOT" "$OUT_DIR" <<'PY'
import hashlib, json, os, shutil, subprocess, sys, tempfile
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
        "concurrent_peak_rss_upper_bound": sample["concurrent_peak_rss_upper_bound"],
        "sampled_concurrent_peak_rss": sample["sampled_concurrent_peak_rss"],
        **throughput_and_outcomes(sample, fields),
        "digest": digest,
        "output": out1,
    })

def storage_disk_profile() -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="rh-bench-storage-", dir="/tmp") as work_dir:
        return storage_disk_profile_at(work_dir)

def storage_disk_profile_at(work_dir: str) -> dict[str, object]:
    source_dir = os.path.join(work_dir, "sources")
    store_dir = os.path.join(work_dir, "objects")
    os.makedirs(source_dir)
    os.makedirs(store_dir)
    cli = os.path.join(root, "build", "rh_cli")

    def payload(label: str, size: int) -> bytes:
        seed = hashlib.sha256(label.encode("utf-8")).digest()
        chunks = []
        length = 0
        ordinal = 0
        while length < size:
            block = hashlib.sha256(seed + ordinal.to_bytes(8, "big")).digest()
            chunks.append(block)
            length += len(block)
            ordinal += 1
        return b"".join(chunks)[:size]

    unique = [payload("small-%d" % i, 4096) for i in range(8)]
    unique.extend(payload("medium-%d" % i, 65536) for i in range(4))
    unique.append(payload("large-0", 1048576))
    corpus = unique + [unique[0], unique[3], unique[8], unique[12]]
    corpus_digest = hashlib.sha256()
    source_bytes = 0
    for index, content in enumerate(corpus):
        source_path = os.path.join(source_dir, "evidence-%04d.bin" % index)
        with open(source_path, "wb") as stream:
            stream.write(content)
        source_bytes += len(content)
        corpus_digest.update(index.to_bytes(8, "big"))
        corpus_digest.update(content)
        subprocess.run([cli, "store", "put", "--root", store_dir, "--file", source_path], check=True, stdout=subprocess.DEVNULL)

    names = sorted(os.listdir(store_dir))
    if len(names) != len(unique):
        raise SystemExit("content-addressed store did not deduplicate identical evidence")
    object_stats = [os.stat(os.path.join(store_dir, name)) for name in names]
    stored_bytes = sum(stat.st_size for stat in object_stats)
    allocated = [stat.st_blocks * 512 for stat in object_stats if hasattr(stat, "st_blocks")]
    verified = 0
    for name in names:
        subprocess.run([cli, "store", "verify", "--root", store_dir, "--name", name], check=True, stdout=subprocess.DEVNULL)
        verified += 1
    return {
        "profile": "rh-store-disk/1",
        "dataset_sha256": corpus_digest.hexdigest(),
        "source_files": len(corpus),
        "unique_objects": len(names),
        "verified_objects": verified,
        "source_bytes": source_bytes,
        "stored_logical_bytes": stored_bytes,
        "deduplicated_source_bytes": source_bytes - stored_bytes,
        "stored_allocated_bytes": sum(allocated) if len(allocated) == len(object_stats) else None,
        "allocation_basis": "sum of st_blocks * 512" if len(allocated) == len(object_stats) else None,
    }

disk_workload = storage_disk_profile()
manifest = {
    **metadata,
    "bench_version": "rh-bench/3",
    "note": "timings, peak RSS, sampled concurrent RSS, and concurrent RSS upper bounds are machine-specific; graph distributions, store corpus, stage output, dataset digests, and counts are deterministic",
    "reps": reps,
    "disk_workload": disk_workload,
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
