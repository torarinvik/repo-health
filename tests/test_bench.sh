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
assert a["bench_version"] == "rh-bench/1", a
assert a["runs"], a
assert "machine-specific" in a["note"], a
def digests(m):
    return [(r["nodes"], r["seed"], r["digest"]) for r in m["runs"]]
assert digests(a) == digests(b), ("datasets not deterministic", digests(a), digests(b))
for r in a["runs"]:
    assert len(r["digest"]) == 16, r
    assert "nodes=" in r["output"] and "digest=" in r["output"], r
    assert r["elapsed_ms"] >= 0, r
print("[bench] manifest OK:", len(a["runs"]), "runs")
PY

echo "[bench] direct binary output stable across runs"
x="$("$ROOT/build/bench_runner" 300 9)"
y="$("$ROOT/build/bench_runner" 300 9)"
[[ "$x" == "$y" ]] || fail "binary output not deterministic"
[[ "$x" == *"digest="* ]] || fail "digest missing from output"
echo "[bench] sample: $x"

echo "test_bench OK"
