#!/usr/bin/env bash
# Real-browser M10-01 profile is opt-in; ordinary checks do not install browsers.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${RH_BROWSER_BENCH:-0}" != "1" ]]; then
  echo "[browser-render-bench] skipped (set RH_BROWSER_BENCH=1 for the live profile)"
  exit 0
fi
[[ -n "${RH_PLAYWRIGHT_CLI:-}" && -x "$RH_PLAYWRIGHT_CLI" ]] || {
  echo "[browser-render-bench] RH_PLAYWRIGHT_CLI must name an executable playwright-cli" >&2
  exit 1
}
OUT="${RH_BROWSER_BENCH_OUT:-$ROOT/build/browser-render-bench-test}"
bash "$ROOT/tools/bench-browser-render.sh" "$OUT" >/dev/null
python3 - "$OUT/browser-render-bench-manifest.json" <<'PY'
import json, re, sys
m = json.load(open(sys.argv[1]))
assert m["profile"] == "rh-browser-render-bench/1", m
assert "HeadlessChrome/" in m["browser_user_agent"], m
assert m["external_requests"] == 0 and m["loopback_http_requests"] > 0, m
assert m["warmup_runs_per_workload"] == 1 and m["reps"] >= 2, m
assert [run["metric_rows"] for run in m["workloads"]] == [10, 1000, 10000], m
for run in m["workloads"]:
    assert run["output_bytes"] > 0 and re.fullmatch(r"[0-9a-f]{64}", run["output_sha256"]), run
    assert run["successful_repetitions"] == m["reps"], run
    assert run["warmup"]["metric_rows"] == run["metric_rows"] + 2, run
    for phase in ("dom_content_loaded", "dom_interactive", "load", "first_contentful_paint"):
        measured = run["browser_timings"][phase]
        assert measured is not None and len(measured["samples_ms"]) == m["reps"], (run, phase)
        assert measured["median_ms"] >= 0 and measured["p95_ms"] >= 0, (run, phase)
    assert "excludes CLI report generation" in run["scope"], run
assert "not deployment capacity" in m["note"], m
print("[browser-render-bench] real-browser timings, DOM cardinality, and manifest bounds OK")
PY
echo "test_browser_render_bench OK"
