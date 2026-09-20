#!/usr/bin/env bash
# tests/test_bench.sh — M10 gate: deterministic benchmark datasets + a
# machine-readable perf manifest. Timing is NOT asserted (machine-specific);
# dataset digests and counts are.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[bench] FAIL: $1" >&2; exit 1; }

echo "[bench] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/bench_runner" ]] || fail "bench_runner not built"

echo "[bench] deterministic dataset + manifest"
A="$ROOT/build/tmp_bench_a"; B="$ROOT/build/tmp_bench_b"
rm -rf "$A" "$B"; mkdir -p "$A" "$B"
bash "$ROOT/tools/bench.sh" "$A" >/dev/null || fail "bench.sh failed"
bash "$ROOT/tools/bench.sh" "$B" >/dev/null || fail "bench.sh rerun failed"

python3 - "$A/bench-manifest.json" "$B/bench-manifest.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
assert a["bench_version"] == "rh-bench/3", a
assert a["runs"], a
assert "machine-specific" in a["note"], a
assert a["reps"] == 10, a
assert a["concurrent_jobs"] == "1", a
assert a["warmup_runs_per_workload"] == 1, a
assert a["code_revision"] and len(a["binary_sha256"]) == 64 and len(a["harness_sha256"]) == 64, a
assert isinstance(a["working_tree_dirty"], bool) and isinstance(a["working_tree_status"], list), a
assert a["toolchain_revision"] and a["compiler_path"] and a["compiler_settings"], a
assert a["database_configuration"].startswith("not_applicable"), a
assert a["external_requests"] == 0 and "cache" in a["cache_state"], a
assert a["hardware"]["machine"] and a["disk_context"]["free_bytes"] >= 0, a
disk = a["disk_workload"]
assert disk["dataset_sha256"] == b["disk_workload"]["dataset_sha256"], (disk, b["disk_workload"])
assert disk["profile"] == "rh-store-disk/1" and len(disk["dataset_sha256"]) == 64, disk
assert disk["source_files"] == 17 and disk["unique_objects"] == disk["verified_objects"] == 13, disk
assert disk["source_bytes"] == 2465792 and disk["stored_logical_bytes"] == 1343488, disk
assert disk["deduplicated_source_bytes"] == 1122304, disk
assert disk["stored_allocated_bytes"] is None or disk["stored_allocated_bytes"] >= 0, disk
def digests(m):
    return [(r["nodes"], r["seed"], r["stage"], r["distribution"], r["digest"]) for r in m["runs"]]
assert digests(a) == digests(b), ("datasets not deterministic", digests(a), digests(b))
expected = {
    (100, 42, "all", "uniform"),
    (1000, 42, "all", "uniform"),
    (10000, 7, "metrics", "uniform"),
    (1000, 17, "graph", "long_tail"),
    (1000, 23, "graph", "central_hubs"),
    (1000, 29, "graph", "cycle"),
    (1000, 31, "ecosystem", "ecosystem"),
}
assert {(r["nodes"], r["seed"], r["stage"], r["distribution"]) for r in a["runs"]} == expected, a
assert len({r["digest"] for r in a["runs"] if r["nodes"] == 1000}) == 5, a
for r in a["runs"]:
    assert len(r["digest"]) == 16, r
    assert "nodes=" in r["output"] and "digest=" in r["output"], r
    assert "distribution=" + r["distribution"] in r["output"], r
    assert len(r["latency"]["samples_ms"]) == 10, r
    assert r["elapsed_ms"] == r["latency"]["median_ms"], r
    assert 0 <= r["latency"]["median_ms"] <= r["latency"]["p95_ms"] <= r["latency"]["max_ms"], r
    assert r["latency"]["variance_ms2"] >= 0, r
    assert len(r["peak_rss"]["samples_bytes"]) == 10, r
    assert r["peak_rss"]["max_bytes"] >= r["peak_rss"]["median_bytes"] > 0, r
    assert r["throughput"]["nodes_per_second"] > 0 and r["throughput"]["edges_per_second"] > 0, r
    assert "aggregate resulting dataset counts" in r["throughput"]["basis"], r
    assert "not aggregate batch memory" in r["peak_rss"]["basis"], r
    assert r["outcomes"]["successful_repetitions"] == 10 and r["outcomes"]["failed_repetitions"] == 0, r
    assert r["outcomes"]["error_rate"] == 0, r
    if r["stage"] == "all":
        assert r["outcomes"]["query_repetitions"] == 10, r
        assert r["outcomes"]["transitive_truncation_rate"] in (0, 1), r
    else:
        assert r["outcomes"]["query_repetitions"] == 0
        assert r["outcomes"]["transitive_truncation_rate"] is None
    if r["stage"] == "ecosystem":
        fields = dict(token.split("=", 1) for token in r["output"].split() if "=" in token)
        assert fields["versions"] == "1000" and fields["packages"] == "500", fields
        assert fields["mirror_groups"] == "250" and fields["mirror_families"] == "250", fields
        assert fields["coverage_projects"] == "500", fields
        assert fields["history_covered"] == "250" and fields["review_covered"] == "250", fields
        assert 0 < int(fields["historical_edges"]) <= int(fields["edges"]), fields
        assert 0 < int(fields["current_edges"]) <= int(fields["edges"]), fields
        assert 0 < int(fields["runtime_linux_edges"]) <= int(fields["current_edges"]), fields
        assert fields["corrections"] == "32" and fields["superseded"] == "64", fields
        assert int(fields["replay_sum"]) > 0, fields
print("[bench] manifest OK:", len(a["runs"]), "runs")
PY

echo "[bench] direct binary output stable across runs"
x="$("$ROOT/build/bench_runner" 300 9)"
y="$("$ROOT/build/bench_runner" 300 9)"
[[ "$x" == "$y" ]] || fail "binary output not deterministic"
[[ "$x" == *"digest="* ]] || fail "digest missing from output"
echo "[bench] sample: $x"

echo "[bench] ecosystem stage rejects mismatched workload"
set +e
"$ROOT/build/bench_runner" 100 1 ecosystem uniform >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "ecosystem stage must reject a non-ecosystem distribution (got $rc)"

echo "test_bench OK"
