#!/usr/bin/env bash
# Live M10-01 PostgreSQL writer profile is opt-in because it starts a database.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${RH_PG_WRITE_BENCH:-0}" != "1" ]]; then
  echo "[pg-write-bench] skipped (set RH_PG_WRITE_BENCH=1 for the live profile)"
  exit 0
fi
OUT="${RH_PG_WRITE_BENCH_OUT:-$ROOT/build/pg-write-bench-test}"
bash "$ROOT/tools/bench-pg-writes.sh" "$OUT" >/dev/null
python3 - "$OUT/pg-write-bench-manifest.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
assert manifest["profile"] == "rh-pg-write-bench/1", manifest
assert "postgres:16" in manifest["database_configuration"], manifest
assert "PostgreSQL" in manifest["postgres_version"], manifest
assert manifest["external_requests"] == 0, manifest
assert manifest["warmup_runs_per_workload"] == 1, manifest
assert [row["events"] for row in manifest["workloads"]] == [10, 100, 1000], manifest
for row in manifest["workloads"]:
    assert row["events_json_bytes"] <= 1_048_576, row
    assert row["successful_repetitions"] == manifest["reps"] >= 2, row
    assert len(row["latency"]["samples_ms"]) == manifest["reps"], row
    assert len(row["peak_rss"]["samples_bytes"]) == manifest["reps"], row
    assert row["peak_rss"]["max_bytes"] > 0 and len(row["input_sha256"]) == 64, row
    assert "excludes PostgreSQL startup" in row["scope"], row
assert "not a deployment capacity claim" in manifest["note"], manifest
print("[pg-write-bench] live parameterized transaction profile and manifest bounds OK")
PY
echo "test_pg_write_bench OK"
