#!/usr/bin/env python3
"""Repeatable correctness and performance comparison for M10-02 aggregates."""

from __future__ import annotations

import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(131072), b""):
            digest.update(chunk)
    return digest.hexdigest()


def positive_env(name: str, default: int, minimum: int = 1) -> int:
    try:
        value = int(os.environ.get(name, str(default)))
    except ValueError as exc:
        raise SystemExit(f"{name} must be an integer >= {minimum}") from exc
    if value < minimum:
        raise SystemExit(f"{name} must be an integer >= {minimum}")
    return value


def write_corpus(path: Path, event_count: int, seed: int, changed: bool) -> tuple[str, int, int]:
    rng = random.Random(seed)
    events = [
        {
            "id": f"event-{index:07}",
            "actor": f"actor-{rng.randrange(400):04}",
            "kind": ("commit", "review", "release")[index % 3],
            "role": ("author", "reviewer", "maintainer", "releaser")[index % 4],
            "at": 1_700_000_000 + rng.randrange(90 * 86400),
        }
        for index in range(event_count)
    ]
    rng.shuffle(events)
    if changed:
        events[0]["actor"] = "actor-corrected"
    document = {"schema": "rh-aggregate-input/1", "events": events, "corrections": []}
    with path.open("w", encoding="utf-8") as stream:
        json.dump(document, stream, separators=(",", ":"))
        stream.write("\n")
    return sha256(path), len({event["at"] // 86400 for event in events}), len({event["at"] // 604800 for event in events})


def run_seed(cli: Path, source: Path, state: Path, output: Path) -> float:
    started = time.perf_counter()
    subprocess.run(
        [str(cli), "aggregate", "--input", str(source), "--out", str(output), "--state-store", str(state)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    return (time.perf_counter() - started) * 1000.0


def output_digest(paths: list[Path]) -> str:
    outputs = [path.read_bytes() for path in paths]
    if not outputs or any(output != outputs[0] for output in outputs[1:]):
        raise SystemExit("aggregate benchmark output changed between repetitions")
    json.loads(outputs[0])
    return hashlib.sha256(outputs[0]).hexdigest()


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    cli = root / "build" / "rh_cli"
    if not cli.is_file():
        raise SystemExit("build/rh_cli is missing; run tools/build.sh first")

    event_count = positive_env("RH_AGG_BENCH_EVENTS", 10_000, 120)
    reps = positive_env("RH_AGG_BENCH_REPS", 5, 2)
    concurrent_jobs = positive_env("RH_AGG_BENCH_CONCURRENT_JOBS", 1, 1)
    if concurrent_jobs > 32:
        raise SystemExit("RH_AGG_BENCH_CONCURRENT_JOBS must not exceed 32")
    seed = positive_env("RH_AGG_BENCH_SEED", 1447)

    sys.path.insert(0, str(root / "tools"))
    from bench_support import environment_metadata, measure

    out_path = Path(os.environ.get("RH_AGG_BENCH_OUT", root / "build" / "aggregate-bench.json"))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    compiler = os.environ.get("RH_COMPILER") or os.environ.get("ELISA_COMPILER_BIN") or shutil.which("elisac-stage1") or "unknown"

    with tempfile.TemporaryDirectory(prefix="rh-aggregate-bench-", dir="/tmp") as temporary:
        work = Path(temporary)
        baseline = work / "baseline.json"
        changed = work / "changed.json"
        baseline_sha, daily_count, weekly_count = write_corpus(baseline, event_count, seed, False)
        changed_sha, _, _ = write_corpus(changed, event_count, seed, True)

        full_outputs = [work / f"full-{index}.json" for index in range((reps + 1) * concurrent_jobs)]
        full_commands = iter(full_outputs)

        def full_command() -> list[str]:
            output = next(full_commands)
            return [str(cli), "aggregate", "--input", str(changed), "--out", str(output)]

        full_sample = measure(full_command, reps, concurrent_jobs)

        partial_states = [work / f"state-{index}" for index in range((reps + 1) * concurrent_jobs)]
        partial_outputs = [work / f"partial-{index}.json" for index in range((reps + 1) * concurrent_jobs)]
        seed_ms: list[float] = []
        for index, state in enumerate(partial_states):
            seed_ms.append(run_seed(cli, baseline, state, work / f"seed-{index}.json"))
        partial_pairs = iter(zip(partial_states, partial_outputs))
        def partial_command() -> list[str]:
            state, output = next(partial_pairs)
            return [str(cli), "aggregate", "--input", str(changed), "--out", str(output), "--state-store", str(state)]

        partial_sample = measure(partial_command, reps, concurrent_jobs)
        full_digest = output_digest(full_outputs)
        partial_digest = output_digest(partial_outputs)
        if full_digest != partial_digest:
            raise SystemExit("partial aggregate cache output differs from full recomputation")

        match = re.search(r"partition-reuse=(\d+)", partial_sample["output"])
        if not match:
            raise SystemExit("partial aggregate run did not report partition reuse")
        reused_count = int(match.group(1))
        reused = [reused_count] * (reps * concurrent_jobs)
        if reused_count <= 0:
            raise SystemExit("partial aggregate runs did not reuse a stable nonzero partition count")

    metadata = environment_metadata(str(root), str(cli), compiler, concurrent_jobs)
    harness_digest = hashlib.sha256()
    for path in (Path(__file__), Path(__file__).with_name("bench_support.py")):
        harness_digest.update(path.name.encode("utf-8"))
        harness_digest.update(path.read_bytes())
    full_median = full_sample["latency"]["median_ms"]
    partial_median = partial_sample["latency"]["median_ms"]
    report = {
        **metadata,
        "schema": "rh-aggregate-bench/1",
        "harness_sha256": harness_digest.hexdigest(),
        "event_count": event_count,
        "seed": seed,
        "daily_partitions": daily_count,
        "weekly_partitions": weekly_count,
        "baseline_input_sha256": baseline_sha,
        "changed_input_sha256": changed_sha,
        "changed_event_count": 1,
        "repetitions": reps,
        "warmup_repetitions": 1,
        "cache_seeding_ms": {"median": round(sorted(seed_ms)[len(seed_ms) // 2], 3), "samples": [round(value, 3) for value in seed_ms]},
        "full_recompute": full_sample,
        "partial_cache": {**partial_sample, "reused_partition_rows": reused},
        "relative_partial_median": round(partial_median / full_median, 6) if full_median else None,
        "correctness": {"full_and_partial_output_sha256": full_digest, "byte_identical": True},
        "limits": "Local synthetic event workload; OS cache and other host activity are uncontrolled. This is not a deployment capacity claim.",
    }
    out_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"aggregate bench: events={event_count} daily={daily_count} weekly={weekly_count} reused={reused[0]}")
    print(f"full median={full_median:.3f} ms partial median={partial_median:.3f} ms ratio={report['relative_partial_median']}")
    print(f"aggregate benchmark manifest: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
