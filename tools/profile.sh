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
import json, os, platform, subprocess, sys, time
root, out_dir = sys.argv[1], sys.argv[2]
binp = os.path.join(root, "build", "bench_runner")
configs = [(200, 42), (1000, 42), (5000, 7)]
stages = ("graph", "query", "metrics")
runs = []
for nodes, seed in configs:
    structural = {}
    for stage in stages:
        t0 = time.perf_counter()
        out1 = subprocess.check_output([binp, str(nodes), str(seed), stage], text=True).strip()
        elapsed_ms = round((time.perf_counter() - t0) * 1000.0, 3)
        out2 = subprocess.check_output([binp, str(nodes), str(seed), stage], text=True).strip()
        if out1 != out2:
            raise SystemExit("profile stage is not deterministic for %s/%s/%s" % (nodes, seed, stage))
        digest = next((tok.split("=", 1)[1] for tok in out1.split() if tok.startswith("digest=")), "")
        if len(digest) != 16:
            raise SystemExit("missing dataset digest for %s/%s/%s" % (nodes, seed, stage))
        structural[stage] = out1
        runs.append({
            "nodes": nodes,
            "seed": seed,
            "stage": stage,
            "elapsed_ms": elapsed_ms,
            "dataset_digest": digest,
            "output": out1,
            "scope": "process wall clock including deterministic dataset construction",
        })
    digests = {next(tok.split("=", 1)[1] for tok in value.split() if tok.startswith("digest=")) for value in structural.values()}
    if len(digests) != 1:
        raise SystemExit("stage digests disagree for %s/%s" % (nodes, seed))
manifest = {
    "profile": "rh-profile/1",
    "note": "elapsed_ms is machine-specific and noisy; stage output and dataset digests are deterministic",
    "toolchain": "Elisa stage1 snapshot (see TOOLCHAIN.md)",
    "git_revision": subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip(),
    "platform": platform.platform(),
    "cache_state": "process-started",
    "reps": 1,
    "stages": ["graph", "query", "metrics"],
    "runs": runs,
}
path = os.path.join(out_dir, "profile-manifest.json")
with open(path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, sort_keys=True)
    fh.write("\n")
for r in runs:
    print("profile %5d seed=%d %-7s %8.3f ms %s" % (r["nodes"], r["seed"], r["stage"], r["elapsed_ms"], r["dataset_digest"]))
print("profile-manifest OK:", path)
PY
