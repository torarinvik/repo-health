#!/usr/bin/env bash
# tests/test_snapshot_cli.sh — M10-05 rebuildable columnar graph snapshot.
# The export is content-digested, deterministic, row-order preserving, and
# explicitly input-scoped so it cannot become a second source of truth.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-snapshot"

fail() { echo "[snapshot] FAIL: $1" >&2; exit 1; }

echo "[snapshot] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/graph.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"test","nodes":[{"id":0,"name":"root","version":"1.0.0"},{"id":1,"name":"left","version":"2.0.0"},{"id":2,"name":"right","version":"3.0.0"}],"edges":[{"from":0,"to":1,"scope":"normal"},{"from":0,"to":2,"scope":"dev"}],"unresolved":[],"advisories":[]}
JSON
"$ROOT/build/rh_cli" snapshot --input "$T/graph.json" --out "$T/out.json" >/dev/null || fail "snapshot run"
python3 - "$T/graph.json" "$T/out.json" <<'PY'
import hashlib, json, sys
raw = open(sys.argv[1], 'rb').read()
d = json.load(open(sys.argv[2]))
assert d["schema"] == "rh-columnar-snapshot/1", d
assert d["source_schema"] == "rh-dep-graph/1", d
assert d["source_sha256"] == hashlib.sha256(raw).hexdigest(), d
assert d["rights_scope"] == "input-scoped" and d["rebuildable"] is True, d
assert d["row_counts"] == {"nodes": 3, "edges": 2}, d
assert d["columns"]["nodes"] == {"id": [0, 1, 2], "name": ["root", "left", "right"], "version": ["1.0.0", "2.0.0", "3.0.0"]}, d
assert d["columns"]["edges"] == {"from": [0, 0], "to": [1, 2], "scope": ["normal", "dev"]}, d
assert "canonical input" in d["note"], d
print("[snapshot] digest + columnar rows OK")
PY

echo "[snapshot] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" snapshot --input "$T/graph.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "snapshot output not deterministic"
sed 's/"schema":"rh-dep-graph\/1"/"schema":"rh-dep-graph\/2"/' "$T/graph.json" > "$T/bad-schema.json"
set +e
"$ROOT/build/rh_cli" snapshot --input "$T/bad-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf 'not json\n' > "$T/notjson"
"$ROOT/build/rh_cli" snapshot --input "$T/notjson" --out "$T/x" >/dev/null 2>&1; rc_json=$?
sed 's/"id":1/"id":7/' "$T/graph.json" > "$T/bad-id.json"
"$ROOT/build/rh_cli" snapshot --input "$T/bad-id.json" --out "$T/x" >/dev/null 2>&1; rc_id=$?
set -e
[[ "$rc_schema" -eq 4 && "$rc_json" -eq 4 && "$rc_id" -eq 4 ]] || fail "invalid snapshot must exit 4 (got $rc_schema/$rc_json/$rc_id)"

echo "test_snapshot_cli OK"
