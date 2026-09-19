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
assert a["profile"] == b["profile"] == "rh-profile/1", a
assert a["stages"] == ["graph", "query", "metrics"], a
assert a["note"] and "machine-specific" in a["note"], a
assert a["cache_state"] == "process-started", a
def shape(d):
    return [(r["nodes"], r["seed"], r["stage"], r["dataset_digest"], r["output"]) for r in d["runs"]]
assert shape(a) == shape(b), (shape(a), shape(b))
assert len(a["runs"]) == 9, a
assert all(r["elapsed_ms"] >= 0 for r in a["runs"]), a
for nodes, seed in ((200, 42), (1000, 42), (5000, 7)):
    ds = {r["dataset_digest"] for r in a["runs"] if r["nodes"] == nodes and r["seed"] == seed}
    assert len(ds) == 1, (nodes, seed, ds)
    assert all("process wall clock" in r["scope"] for r in a["runs"] if r["nodes"] == nodes and r["seed"] == seed)
print("[profile-bench] stage manifest + deterministic digests OK")
PY

echo "test_profile_bench OK"
