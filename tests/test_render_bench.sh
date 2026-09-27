#!/usr/bin/env bash
# tests/test_render_bench.sh — M10-01 real report parse/render resource profile.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$ROOT/build/tmp_render_bench"

fail() { echo "[render-bench] FAIL: $1" >&2; exit 1; }

echo "[render-bench] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
rm -rf "$T"; mkdir -p "$T/a" "$T/b"
RH_RENDER_BENCH_REPS=2 RH_BENCH_CONCURRENT_JOBS=2 "$ROOT/tools/bench-render.sh" "$T/a" >/dev/null || fail "first renderer profile"
RH_RENDER_BENCH_REPS=2 RH_BENCH_CONCURRENT_JOBS=2 "$ROOT/tools/bench-render.sh" "$T/b" >/dev/null || fail "replayed renderer profile"

python3 - "$T/a/render-bench-manifest.json" "$T/b/render-bench-manifest.json" <<'PY'
import json, sys
a, b = (json.load(open(path)) for path in sys.argv[1:])
assert a["profile"] == b["profile"] == "rh-render-bench/1", a
assert a["reps"] == b["reps"] == 2 and a["warmup_runs_per_workload"] == 1, a
assert a["concurrent_jobs"] == b["concurrent_jobs"] == "2", a
assert a["external_requests"] == b["external_requests"] == 0, a
assert "machine-specific" in a["note"] and a["database_configuration"].startswith("not_applicable"), a
assert [r["metric_rows"] for r in a["runs"]] == [10, 1000, 10000], a
assert [r["metric_rows"] for r in a["runs"]] == [r["metric_rows"] for r in b["runs"]], b
for left, right in zip(a["runs"], b["runs"]):
    assert left["input_sha256"] == right["input_sha256"], (left, right)
    assert left["output_sha256"] == right["output_sha256"], (left, right)
    assert left["input_bytes"] > 0 and left["output_bytes"] > 0, left
    assert left["elapsed_ms"] == left["latency"]["median_ms"], left
    assert len(left["latency"]["samples_ms"]) == 2, left
    assert len(left["peak_rss"]["samples_bytes"]) == 2 and left["peak_rss"]["max_bytes"] > 0, left
    assert left["outcomes"] == {"successful_repetitions": 2, "failed_repetitions": 0, "concurrent_processes_per_repetition": 2}, left
assert [r["output_bytes"] for r in a["runs"]] == sorted(r["output_bytes"] for r in a["runs"]), a
print("[render-bench] scaled parse/render profiles are deterministic and resource-bound")
PY

echo "test_render_bench OK"
