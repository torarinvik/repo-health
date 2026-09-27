"""Profile bounded production PostgreSQL page commits on local PostgreSQL."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from bench_support import environment_metadata, percentile, run_process


root, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
image = os.environ.get("RH_PG_IMAGE", "postgres:16-alpine")
reps = int(os.environ.get("RH_PG_WRITE_BENCH_REPS", "5"))
if reps < 2:
    raise SystemExit("RH_PG_WRITE_BENCH_REPS must be at least 2")
docker = shutil.which("docker")
if not docker:
    raise SystemExit("docker is required")
subprocess.run([docker, "info"], check=True, stdout=subprocess.DEVNULL)
subprocess.run([docker, "image", "inspect", image], check=True, stdout=subprocess.DEVNULL)
container = "rh-pg-write-bench-%d" % os.getpid()
cli = root / "build" / "rh_cli"
compiler = os.environ.get("RH_COMPILER") or os.environ.get("ELISA_COMPILER_BIN") or shutil.which("elisac-stage1") or "unknown"
metadata = environment_metadata(str(root), str(cli), compiler, 1)


def docker_exec(*args: str, input_text: str | None = None) -> str:
    result = subprocess.run(
        [docker, "exec", "-i", container, *args], input=input_text,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode:
        raise RuntimeError("docker exec failed: " + result.stderr.strip())
    return result.stdout.strip()


subprocess.run([
    docker, "run", "--rm", "-d", "--name", container,
    "-e", "POSTGRES_PASSWORD=repo-health-test", "-e", "POSTGRES_DB=repo_health",
    "-p", "127.0.0.1::5432", image,
], check=True, stdout=subprocess.DEVNULL)
try:
    ready = False
    for _ in range(60):
        check = subprocess.run([docker, "exec", container, "pg_isready", "-U", "postgres", "-d", "repo_health"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if check.returncode == 0:
            ready = True
            break
        time.sleep(1)
    if not ready:
        raise RuntimeError("PostgreSQL did not become ready")
    docker_exec("mkdir", "-p", "/tmp/rh-bench")
    subprocess.run([docker, "cp", str(root / "db/migrations/001_initial.sql"), container + ":/tmp/rh-bench/001_initial.sql"], check=True, stdout=subprocess.DEVNULL)
    docker_exec("psql", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "repo_health", "-f", "/tmp/rh-bench/001_initial.sql")
    port = subprocess.check_output([docker, "port", container, "5432/tcp"], text=True).strip().rsplit(":", 1)[1]
    conninfo = "host=127.0.0.1 port=%s dbname=repo_health user=postgres password=repo-health-test sslmode=disable" % port
    postgres_version = docker_exec("psql", "-At", "-U", "postgres", "-d", "repo_health", "-c", "SELECT version()")
    with tempfile.TemporaryDirectory(prefix="rh-pg-write-bench-", dir="/tmp") as temporary:
        work = Path(temporary)
        seed = json.loads((root / "fixtures/postgres/begin-collection-run-command.json").read_text())
        (work / "seed.json").write_text(json.dumps(seed, separators=(",", ":")))
        env = dict(os.environ, RH_DATABASE_URL=conninfo)
        if os.environ.get("RH_LIBPQ_PATH"):
            env["RH_LIBPQ_PATH"] = os.environ["RH_LIBPQ_PATH"]
        else:
            env.pop("RH_LIBPQ_PATH", None)
        env["RH_EVIDENCE_ROOT"] = str(work / "evidence")
        seed_result = subprocess.run([str(cli), "postgres", "--input", str(work / "seed.json"), "--out", str(work / "seed-result.json")], env=env, capture_output=True, text=True)
        if seed_result.returncode:
            raise RuntimeError("seed collection source/run failed: " + seed_result.stderr.strip())
        docker_exec("psql", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "repo_health", input_text="""
INSERT INTO job (id, source_instance_id, kind, visibility_scope, state, priority,
 next_attempt_at, attempt_count, fencing_token, worker_id, lease_expires_at,
 created_at, input_manifest)
VALUES ('00000000-0000-0000-0000-000000000002',
 '00000000-0000-0000-0000-000000000001', 'collection', 'public', 'running', 1,
 '2026-01-01T00:00:00Z', 1, 1, 'bench-worker', '2099-01-01T00:00:00Z',
 '2026-01-01T00:00:00Z', '{"collection_run_id":"00000000-0000-0000-0000-000000000003"}');
INSERT INTO entity (id, entity_kind, visibility_scope, created_at)
VALUES ('00000000-0000-0000-0000-000000000005', 'issue', 'public', '2026-01-01T00:00:00Z');
INSERT INTO evidence_object (id, visibility_scope, digest_algorithm, digest_value,
 media_type, byte_length, storage_key, retention_class, transformation_kind, created_at)
VALUES ('00000000-0000-0000-0000-000000000006', 'public', 'sha256', repeat('a', 64),
 'application/json', 1, 'fnv1a64:0000000000000006', 'standard', 'captured', '2026-01-01T00:00:00Z');
""")

        workloads = []
        page_number = 0
        for event_count in (10, 100, 1000):
            inputs: list[bytes] = []
            latencies: list[float] = []
            rss: list[int] = []
            for sample_index in range(reps + 1):
                events = [{
                    "source_object_type": "issue", "source_object_id": "bench:%d:%d:%d" % (event_count, sample_index, i),
                    "source_revision": "r1", "event_kind": "observed",
                    "subject_id": "00000000-0000-0000-0000-000000000005",
                    "actor_account_id": None, "occurred_at": None,
                    "observed_at": "2026-01-01T00:00:00Z", "time_basis": "unknown",
                    "evidence_id": "00000000-0000-0000-0000-000000000006",
                    "parser_version": "bench/1", "payload": {"n": i},
                } for i in range(event_count)]
                command = {
                    "schema": "rh-postgres-command/1", "operation": "page_commit_events",
                    "run_id": seed["run_id"], "job_id": "00000000-0000-0000-0000-000000000002",
                    "fencing_token": 1, "page_number": page_number, "scope_hash": "pg-write-bench",
                    "cursor_before": "", "cursor_after": json.dumps({"page": page_number + 1}, separators=(",", ":")),
                    "completeness": "complete", "record_count": event_count, "evidence_id": "",
                    "events_json": json.dumps(events, separators=(",", ":")), "subjects_json": "[]", "actors_json": "[]",
                    "now": "2026-01-01T00:01:00Z",
                }
                encoded = (json.dumps(command, separators=(",", ":")) + "\n").encode()
                if len(command["events_json"].encode()) > 1_048_576:
                    raise RuntimeError("workload exceeds the adapter's 1 MiB event JSON bound")
                input_path = work / "command.json"
                output_path = work / "result.json"
                input_path.write_bytes(encoded)
                inputs.append(encoded)
                run_env = ["env"] + ["%s=%s" % (key, value) for key, value in env.items() if key.startswith("RH_")]
                _, elapsed, peak = run_process([*run_env, str(cli), "postgres", "--input", str(input_path), "--out", str(output_path)])
                result = json.loads(output_path.read_text())
                if result.get("status") != "committed":
                    raise RuntimeError("page commit did not return committed: %r" % result)
                page_number += 1
                if sample_index:
                    latencies.append(round(elapsed, 3))
                    rss.append(peak)
            if len({hashlib.sha256(item).hexdigest() for item in inputs}) != reps + 1:
                # Unique page IDs/cursors make each operation distinct; input identity is expected to vary.
                raise RuntimeError("benchmark page commands unexpectedly repeated")
            ordered = sorted(latencies)
            workloads.append({
                "events": event_count, "payload_bytes": len(inputs[0]),
                "events_json_bytes": len(json.loads(inputs[0])["events_json"].encode()),
                "input_sha256": hashlib.sha256(inputs[0]).hexdigest(),
                "latency": {"median_ms": sorted(latencies)[len(latencies) // 2], "p95_ms": percentile(latencies, 0.95), "samples_ms": latencies},
                "peak_rss": {"max_bytes": max(rss), "samples_bytes": rss},
                "successful_repetitions": reps, "warmup_runs": 1,
                "scope": "fresh rh_cli postgres process wall clock; includes command JSON parsing, libpq connection, parameterized page transaction, and result write; excludes PostgreSQL startup, migration, source/run/job seeding, and input generation",
            })
        committed_count = int(docker_exec("psql", "-At", "-U", "postgres", "-d", "repo_health", "-c", "SELECT count(*) FROM canonical_event WHERE source_instance_id = '00000000-0000-0000-0000-000000000001'::uuid AND source_object_id LIKE 'bench:%'"))
        expected_count = sum(workload["events"] * (reps + 1) for workload in workloads)
        if committed_count != expected_count:
            raise RuntimeError("database contains %d benchmark events; expected %d" % (committed_count, expected_count))
finally:
    subprocess.run([docker, "rm", "-f", container], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

manifest = {
    **metadata, "profile": "rh-pg-write-bench/1", "database_configuration": image,
    "postgres_version": postgres_version, "external_requests": 0, "reps": reps,
    "warmup_runs_per_workload": 1, "workloads": workloads,
    "note": "Local synthetic transaction profile; bounded by the production adapter's 1 MiB per-argument limit and not a deployment capacity claim.",
}
manifest_path = out_dir / "pg-write-bench-manifest.json"
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
for workload in workloads:
    print("pg-write-bench events=%d payload=%d median=%8.3f ms peak_rss=%d sha256=%s" % (
        workload["events"], workload["events_json_bytes"], workload["latency"]["median_ms"],
        workload["peak_rss"]["max_bytes"], workload["input_sha256"]))
print("pg-write-bench-manifest OK:", manifest_path)
