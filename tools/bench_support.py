"""Shared deterministic workload measurement helpers for bench.sh/profile.sh."""

from __future__ import annotations

import hashlib
from concurrent.futures import ThreadPoolExecutor
import math
import os
import platform
import shutil
import statistics
import subprocess
import sys
import time
from typing import Sequence


def run_process(command: Sequence[str]) -> tuple[str, float, int]:
    """Run one small-output workload and return output, wall ms, peak RSS bytes."""
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    started = time.perf_counter()
    while True:
        try:
            pid, status, usage = os.wait4(process.pid, 0)
            break
        except InterruptedError:
            continue
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    if pid != process.pid:
        raise RuntimeError("wait4 returned an unexpected child")
    process.returncode = os.waitstatus_to_exitcode(status)
    stdout = process.stdout.read().decode("utf-8")
    stderr = process.stderr.read().decode("utf-8")
    process.stdout.close()
    process.stderr.close()
    if process.returncode != 0:
        raise RuntimeError("workload exited %d: %s" % (process.returncode, stderr.strip()))
    rss_bytes = int(usage.ru_maxrss if sys.platform == "darwin" else usage.ru_maxrss * 1024)
    return stdout.strip(), elapsed_ms, rss_bytes


def percentile(values: Sequence[float], fraction: float) -> float:
    """Linearly interpolated percentile using the inclusive (Type 7) method."""
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def configured_concurrent_jobs() -> int:
    """Read and bound the number of simultaneously launched workload processes."""
    try:
        jobs = int(os.environ.get("RH_BENCH_CONCURRENT_JOBS", "1"))
    except ValueError as exc:
        raise SystemExit("RH_BENCH_CONCURRENT_JOBS must be an integer from 1 to 32") from exc
    if not 1 <= jobs <= 32:
        raise SystemExit("RH_BENCH_CONCURRENT_JOBS must be an integer from 1 to 32")
    return jobs


def measure(command: Sequence[str], reps: int, concurrent_jobs: int = 1) -> dict[str, object]:
    """Warm once, then time fresh processes in batches with identical output."""
    if reps < 2:
        raise ValueError("at least two repetitions are required")
    if not 1 <= concurrent_jobs <= 32:
        raise ValueError("concurrent_jobs must be from 1 to 32")

    def run_batch(executor: ThreadPoolExecutor | None) -> tuple[str, float, list[int]]:
        if executor is None:
            output, elapsed_ms, rss_bytes = run_process(command)
            return output, elapsed_ms, [rss_bytes]
        started = time.perf_counter()
        results = list(executor.map(run_process, [command] * concurrent_jobs))
        elapsed_ms = (time.perf_counter() - started) * 1000.0
        outputs = {result[0] for result in results}
        if len(outputs) != 1:
            raise RuntimeError("concurrent workload output changed within a batch")
        return outputs.pop(), elapsed_ms, [result[2] for result in results]

    elapsed_samples = []
    rss_samples = []
    rss_sum_bounds = []
    with ThreadPoolExecutor(max_workers=concurrent_jobs) if concurrent_jobs > 1 else _NullExecutor() as executor:
        expected, _, _ = run_batch(executor)
        for _ in range(reps):
            output, elapsed_ms, process_rss = run_batch(executor)
            if output != expected:
                raise RuntimeError("workload output changed between repetitions")
            elapsed_samples.append(round(elapsed_ms, 3))
            rss_samples.append(max(process_rss))
            rss_sum_bounds.append(sum(process_rss))
    latency = {
        "min_ms": min(elapsed_samples),
        "median_ms": round(statistics.median(elapsed_samples), 3),
        "p95_ms": round(percentile(elapsed_samples, 0.95), 3),
        "max_ms": max(elapsed_samples),
        "variance_ms2": round(statistics.variance(elapsed_samples), 6),
        "samples_ms": elapsed_samples,
    }
    memory = {
        "median_bytes": int(statistics.median(rss_samples)),
        "p95_bytes": int(percentile(rss_samples, 0.95)),
        "max_bytes": max(rss_samples),
        "samples_bytes": rss_samples,
        "basis": "largest individual child peak RSS per concurrent batch; not aggregate batch memory",
    }
    concurrent_memory_bound = {
        "median_bytes": int(statistics.median(rss_sum_bounds)),
        "p95_bytes": int(percentile(rss_sum_bounds, 0.95)),
        "max_bytes": max(rss_sum_bounds),
        "samples_bytes": rss_sum_bounds,
        "basis": "sum of each child peak RSS within a concurrent batch; conservative upper bound, not simultaneous aggregate memory",
    }
    return {
        "output": expected,
        "latency": latency,
        "peak_rss": memory,
        "concurrent_peak_rss_upper_bound": concurrent_memory_bound,
        "successful_repetitions": reps,
        "failed_repetitions": 0,
        "concurrent_processes_per_repetition": concurrent_jobs,
    }


def output_fields(output: str) -> dict[str, str]:
    return dict(token.split("=", 1) for token in output.split() if "=" in token)


def throughput_and_outcomes(sample: dict[str, object], fields: dict[str, str]) -> dict[str, object]:
    elapsed_seconds = sample["latency"]["median_ms"] / 1000.0
    repetitions = sample["successful_repetitions"]
    concurrent_jobs = sample["concurrent_processes_per_repetition"]
    truncation = fields.get("trans_truncated")
    query_repetitions = repetitions if truncation is not None else 0
    truncated_repetitions = query_repetitions if truncation == "1" else 0
    return {
        "throughput": {
            "nodes_per_second": round(int(fields["nodes"]) * concurrent_jobs / elapsed_seconds, 3),
            "edges_per_second": round(int(fields["edges"]) * concurrent_jobs / elapsed_seconds, 3),
            "basis": "aggregate resulting dataset counts per concurrent batch wall-clock; includes process startup and dataset construction",
        },
        "outcomes": {
            "successful_repetitions": repetitions,
            "failed_repetitions": sample["failed_repetitions"],
            "error_rate": sample["failed_repetitions"] / repetitions,
            "query_repetitions": query_repetitions,
            "transitive_truncated_repetitions": truncated_repetitions,
            "transitive_truncation_rate": truncated_repetitions / query_repetitions if query_repetitions else None,
            "concurrent_processes_per_repetition": concurrent_jobs,
        },
    }


class _NullExecutor:
    """Context manager sentinel that preserves the single-process timing path."""

    def __enter__(self) -> None:
        return None

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        return None


def environment_metadata(root: str, binary_path: str, compiler: str, concurrent_jobs: int) -> dict[str, object]:
    disk = shutil.disk_usage(root)
    memory_total = None
    if sys.platform == "darwin":
        try:
            memory_total = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True).strip())
        except (OSError, subprocess.CalledProcessError, ValueError):
            memory_total = None
    elif sys.platform.startswith("linux"):
        try:
            with open("/proc/meminfo", encoding="ascii") as stream:
                line = next(line for line in stream if line.startswith("MemTotal:"))
            memory_total = int(line.split()[1]) * 1024
        except (OSError, StopIteration, ValueError):
            memory_total = None
    revision = subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip()
    working_tree = subprocess.check_output(["git", "-C", root, "status", "--porcelain"], text=True)
    harness_hash = hashlib.sha256()
    for relative_path in ("tools/bench.sh", "tools/profile.sh", "tools/bench_support.py"):
        path = os.path.join(root, relative_path)
        harness_hash.update(relative_path.encode("utf-8"))
        with open(path, "rb") as stream:
            for chunk in iter(lambda: stream.read(131072), b""):
                harness_hash.update(chunk)
    binary_hash = hashlib.sha256()
    with open(binary_path, "rb") as stream:
        for chunk in iter(lambda: stream.read(131072), b""):
            binary_hash.update(chunk)
    binary_sha256 = binary_hash.hexdigest()
    toolchain_revision = None
    with open(os.path.join(root, "TOOLCHAIN.md"), encoding="utf-8") as stream:
        for line in stream:
            marker = "snapshot rev `"
            if marker in line:
                toolchain_revision = line.split(marker, 1)[1].split("`", 1)[0]
                break
    return {
        "code_revision": revision,
        "working_tree_dirty": bool(working_tree),
        "working_tree_status": working_tree.splitlines(),
        "binary_sha256": binary_sha256,
        "harness_sha256": harness_hash.hexdigest(),
        "toolchain": "Elisa stage1 snapshot (see TOOLCHAIN.md)",
        "toolchain_revision": toolchain_revision,
        "compiler_path": compiler,
        "compiler_settings": "prebuilt executable from tools/build.sh using -emit exe; compilation excluded from timing",
        "database_configuration": "not_applicable; synthetic graph is held in process memory",
        "external_requests": 0,
        "hardware": {
            "platform": platform.platform(),
            "machine": platform.machine(),
            "processor": platform.processor() or None,
            "logical_cpu_count": os.cpu_count(),
            "memory_total_bytes": memory_total,
        },
        "disk_context": {"total_bytes": disk.total, "free_bytes": disk.free},
        "concurrent_jobs": str(concurrent_jobs),
        "warmup_runs_per_workload": 1,
        "cache_state": "fresh process per sample; operating-system caches uncontrolled",
    }
