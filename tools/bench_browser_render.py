"""Profile real Chromium page work for the deterministic report renderer."""

from __future__ import annotations

import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
from urllib.parse import urlsplit

from bench_support import environment_metadata, percentile


root, out_dir, playwright_cli = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
reps = int(os.environ.get("RH_BROWSER_BENCH_REPS", "5"))
if reps < 2:
    raise SystemExit("RH_BROWSER_BENCH_REPS must be at least 2")
rh_cli = root / "build" / "rh_cli"
compiler = os.environ.get("RH_COMPILER") or os.environ.get("ELISA_COMPILER_BIN") or shutil.which("elisac-stage1") or "unknown"
metadata = environment_metadata(str(root), str(rh_cli), compiler, 1)
TIMING_EXPRESSION = """JSON.stringify((() => {
 const navigation = performance.getEntriesByType('navigation')[0];
 const paint = performance.getEntriesByName('first-contentful-paint')[0];
 return {
  dom_content_loaded_ms: navigation.domContentLoadedEventEnd - navigation.startTime,
  load_ms: navigation.loadEventEnd - navigation.startTime,
  dom_interactive_ms: navigation.domInteractive - navigation.startTime,
  first_contentful_paint_ms: paint ? paint.startTime : null,
  metric_rows: document.querySelectorAll('tbody tr').length,
  user_agent: navigator.userAgent
 };
})())"""


def run_cli(*args: str) -> str:
    result = subprocess.run([playwright_cli, *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("playwright-cli %s failed: %s" % (args[0], result.stderr.strip() or result.stdout.strip()))
    return result.stdout.strip()


def browser_timing() -> dict[str, object]:
    # --raw preserves the eval result, itself a JSON string.
    decoded = json.loads(run_cli("--raw", "eval", TIMING_EXPRESSION))
    return json.loads(decoded) if isinstance(decoded, str) else decoded


class LocalHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: object, directory: str, requests: list[str], **kwargs: object):
        self.requests = requests
        super().__init__(*args, directory=directory, **kwargs)

    def log_message(self, format: str, *args: object) -> None:
        return

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:")
        super().end_headers()

    def do_GET(self) -> None:
        self.requests.append(urlsplit(self.path).path)
        super().do_GET()


def build_report(row_count: int, work: Path) -> tuple[Path, bytes, bytes]:
    report = {
        "report": "repo-health-m01", "source": "deterministic-browser-benchmark", "source_kind": "synthetic",
        "metrics": [{
            "key": "benchmark.metric_%05d" % index, "version": "1.0.0",
            "status": "observed" if index % 5 else "unknown",
            "value": index if index % 5 else None,
            "reason": None if index % 5 else "synthetic_missing",
            "evidence": ["evidence/object-%05d" % (index % 128)],
        } for index in range(row_count)],
        "capabilities": {"history": "observed", "browser_render_benchmark": "synthetic"},
        "timeline": [], "neighborhood": [],
    }
    report_bytes = (json.dumps(report, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
    input_path, output_path = work / ("report-%d.json" % row_count), work / ("report-%d.html" % row_count)
    input_path.write_bytes(report_bytes)
    result = subprocess.run([str(rh_cli), "render", "--report", str(input_path), "--out", str(output_path)], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("rh_cli render failed: " + result.stderr.strip())
    html_bytes = output_path.read_bytes()
    # Keep the page self-contained so the browser workload cannot contact a provider.
    if b"<script" in html_bytes or b"<link" in html_bytes or b"<img" in html_bytes or re.search(rb"https?://", html_bytes, re.IGNORECASE):
        raise RuntimeError("synthetic report unexpectedly contains active or external page resources")
    return output_path, report_bytes, html_bytes


with tempfile.TemporaryDirectory(prefix="rh-browser-render-bench-", dir="/tmp") as temporary:
    work = Path(temporary)
    requests: list[str] = []
    handler = lambda *args, **kwargs: LocalHandler(*args, directory=str(work), requests=requests, **kwargs)
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    port = server.server_address[1]
    runs = []
    browser_user_agent = None
    opened = False
    try:
        for row_count in (10, 1000, 10000):
            output_path, report_bytes, html_bytes = build_report(row_count, work)
            output_path.relative_to(work)
            # Prevent an expected icon probe from introducing a noisy 404 request.
            (work / "favicon.ico").write_bytes(b"")
            url = "http://127.0.0.1:%d/%s?sample=0" % (port, output_path.name)
            load_samples, dom_samples, fcp_samples, interactive_samples = [], [], [], []
            warmup = None
            for sample_index in range(reps + 1):
                if not opened:
                    run_cli("open", url)
                    opened = True
                else:
                    run_cli("goto", url.rsplit("=", 1)[0] + "=" + str(sample_index + len(load_samples)))
                sample = browser_timing()
                expected_rows = row_count + 2
                if sample["metric_rows"] != expected_rows:
                    raise RuntimeError("browser exposed %s metric rows for %d input metrics (expected %d including standard observations)" % (sample["metric_rows"], row_count, expected_rows))
                if browser_user_agent is None:
                    browser_user_agent = sample["user_agent"]
                elif browser_user_agent != sample["user_agent"]:
                    raise RuntimeError("browser user-agent changed during the benchmark")
                if sample_index == 0:
                    warmup = sample
                else:
                    load_samples.append(float(sample["load_ms"]))
                    dom_samples.append(float(sample["dom_content_loaded_ms"]))
                    interactive_samples.append(float(sample["dom_interactive_ms"]))
                    if sample["first_contentful_paint_ms"] is not None:
                        fcp_samples.append(float(sample["first_contentful_paint_ms"]))
            runs.append({
                "metric_rows": row_count, "input_bytes": len(report_bytes), "input_sha256": hashlib.sha256(report_bytes).hexdigest(),
                "output_bytes": len(html_bytes), "output_sha256": hashlib.sha256(html_bytes).hexdigest(),
                "warmup": warmup,
                "browser_timings": {
                    "dom_content_loaded": {"median_ms": round(statistics.median(dom_samples), 3), "p95_ms": round(percentile(dom_samples, .95), 3), "samples_ms": dom_samples},
                    "dom_interactive": {"median_ms": round(statistics.median(interactive_samples), 3), "p95_ms": round(percentile(interactive_samples, .95), 3), "samples_ms": interactive_samples},
                    "load": {"median_ms": round(statistics.median(load_samples), 3), "p95_ms": round(percentile(load_samples, .95), 3), "samples_ms": load_samples},
                    "first_contentful_paint": {"median_ms": round(statistics.median(fcp_samples), 3), "p95_ms": round(percentile(fcp_samples, .95), 3), "samples_ms": fcp_samples} if fcp_samples else None,
                },
                "successful_repetitions": len(load_samples),
                "scope": "browser-reported navigation and paint timings for the self-contained report, served from loopback; excludes CLI report generation, browser startup, and browser-command orchestration overhead",
            })
    finally:
        if opened:
            subprocess.run([playwright_cli, "close"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=5)

manifest = {
    **metadata, "profile": "rh-browser-render-bench/1", "browser_user_agent": browser_user_agent,
    "browser_runtime": "Playwright CLI with Chromium; exact build is identified by user_agent",
    "reps": reps, "warmup_runs_per_workload": 1, "external_requests": 0,
    "loopback_http_requests": len(requests), "workloads": runs,
    "note": "Synthetic self-contained report pages measured in a local browser; machine-specific rendering evidence, not deployment capacity.",
}
manifest_path = out_dir / "browser-render-bench-manifest.json"
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
for run in runs:
    print("browser-render-bench rows=%d html=%d DOM=%8.3f ms FCP=%8.3f ms load=%8.3f ms sha256=%s" % (
        run["metric_rows"], run["output_bytes"], run["browser_timings"]["dom_content_loaded"]["median_ms"],
        run["browser_timings"]["first_contentful_paint"]["median_ms"], run["browser_timings"]["load"]["median_ms"], run["output_sha256"]))
print("browser-render-bench-manifest OK:", manifest_path)
