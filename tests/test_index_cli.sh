#!/usr/bin/env bash
# tests/test_index_cli.sh — M10-03 deterministic CSR query indexes.
# Incoming and outgoing offsets address the same canonical edge order and are
# content-bound to the graph input.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-index"

fail() { echo "[index] FAIL: $1" >&2; exit 1; }

echo "[index] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/graph.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"test","nodes":[{"id":0,"name":"root","version":"1"},{"id":1,"name":"left","version":"1"},{"id":2,"name":"right","version":"1"},{"id":3,"name":"leaf","version":"1"}],"edges":[{"from":0,"to":1,"scope":"normal"},{"from":0,"to":2,"scope":"normal"},{"from":1,"to":3,"scope":"normal"},{"from":2,"to":3,"scope":"normal"}],"unresolved":[],"advisories":[]}
JSON
"$ROOT/build/rh_cli" index --input "$T/graph.json" --out "$T/out.json" >/dev/null || fail "index run"
python3 - "$T/graph.json" "$T/out.json" <<'PY'
import hashlib, json, sys
raw = open(sys.argv[1], 'rb').read()
d = json.load(open(sys.argv[2]))
assert d["schema"] == "rh-index-manifest/1", d
assert d["source_sha256"] == hashlib.sha256(raw).hexdigest(), d
assert d["node_count"] == 4 and d["edge_count"] == 4, d
assert d["outgoing"] == {"offsets": [0, 2, 3, 4, 4], "edge_ids": [0, 1, 2, 3]}, d["outgoing"]
assert d["incoming"] == {"offsets": [0, 0, 1, 2, 4], "edge_ids": [0, 1, 2, 3]}, d["incoming"]
assert d["degree_summary"] == {"max_out": 2, "max_out_node": 0, "max_in": 2, "max_in_node": 3}, d["degree_summary"]
assert d["rebuildable"] is True and "canonical edge order" in d["note"], d
print("[index] digest + incoming/outgoing CSR layout OK")
PY

echo "[index] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" index --input "$T/graph.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "index output not deterministic"
sed 's/"to":3/"to":9/' "$T/graph.json" > "$T/bad-edge.json"
printf 'not json\n' > "$T/notjson"
set +e
"$ROOT/build/rh_cli" index --input "$T/bad-edge.json" --out "$T/x" >/dev/null 2>&1; rc_edge=$?
"$ROOT/build/rh_cli" index --input "$T/notjson" --out "$T/x" >/dev/null 2>&1; rc_json=$?
set -e
[[ "$rc_edge" -eq 4 && "$rc_json" -eq 4 ]] || fail "invalid index must exit 4 (got $rc_edge/$rc_json)"

echo "test_index_cli OK"
