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
import json, os, subprocess, sys, time
root, out_dir = sys.argv[1], sys.argv[2]
binp = os.path.join(root, "build", "bench_runner")
configs = [(200, 42), (1000, 42), (5000, 7)]
runs = []
for nodes, seed in configs:
    t0 = time.perf_counter()
    out1 = subprocess.check_output([binp, str(nodes), str(seed)], text=True).strip()
    t1 = time.perf_counter()
    out2 = subprocess.check_output([binp, str(nodes), str(seed)], text=True).strip()
    if out1 != out2:
        raise SystemExit("benchmark dataset not deterministic for %s/%s" % (nodes, seed))
    digest = ""
    for tok in out1.split():
        if tok.startswith("digest="):
            digest = tok.split("=", 1)[1]
    runs.append({
        "nodes": nodes,
        "seed": seed,
        "elapsed_ms": round((t1 - t0) * 1000.0, 3),
        "digest": digest,
        "output": out1,
    })
manifest = {
    "bench_version": "rh-bench/1",
    "note": "elapsed_ms is machine-specific and noisy; dataset digest and counts are deterministic and are what tests assert",
    "toolchain": "Elisa stage1 snapshot (see TOOLCHAIN.md)",
    "reps": 1,
    "runs": runs,
}
path = os.path.join(out_dir, "bench-manifest.json")
with open(path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, sort_keys=True)
    fh.write("\n")
for r in runs:
    print("bench %5d nodes seed=%d %8.3f ms %s" % (r["nodes"], r["seed"], r["elapsed_ms"], r["digest"]))
print("bench-manifest OK:", path)
PY
