#!/usr/bin/env bash
# Reviewed graph-node to canonical project identity mapping (M05-03/10).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-project-map"
fail() { echo "[project-map] FAIL: $1" >&2; exit 1; }
echo "[project-map] build"
bash "$ROOT/tools/build.sh" >/dev/null
"$ROOT/build/test_project_map" >/dev/null || fail "project identity oracle"
rm -rf "$T"; mkdir -p "$T"
cat > "$T/graph.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"test","nodes":[{"id":0,"name":"focus","version":"1"},{"id":1,"name":"consumer","version":"2"}],"edges":[{"from":1,"to":0,"scope":"normal"}],"unresolved":[],"advisories":[]}
JSON
python3 - "$T/graph.json" "$T/map.json" <<'PY'
import hashlib, json, sys
graph = open(sys.argv[1], "rb").read()
doc = {"schema": "rh-project-node-map-input/1", "graph_sha256": hashlib.sha256(graph).hexdigest(), "revision": 12,
       "mappings": [{"node_id": 1, "project_id": "forge:acme/consumer", "family_id": "acme-consumer", "state": "accepted", "reviewer_id": 42, "reviewed_at": 1700000000, "evidence_sha256": "a" * 64}]}
json.dump(doc, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" project-map --graph "$T/graph.json" --input "$T/map.json" --out "$T/out.json" >/dev/null || fail "project map run"
python3 - "$T/graph.json" "$T/map.json" "$T/out.json" "$T/out.json.transformations.json" <<'PY'
import hashlib, json, sys
graph = open(sys.argv[1], "rb").read()
source = open(sys.argv[2], "rb").read()
out = json.load(open(sys.argv[3]))
assert out["schema"] == "rh-project-node-map/1" and out["graph_sha256"] == hashlib.sha256(graph).hexdigest(), out
assert out["revision"] == 12 and out["mappings"] == [{"node_id": 1, "project_id": "forge:acme/consumer", "family_id": "acme-consumer", "reviewer_id": 42, "reviewed_at": 1700000000, "evidence_sha256": "a" * 64}], out
report = json.load(open(sys.argv[4]))
assert report["adapter"] == "reviewed-project-node-map", report
assert report["source_input_sha256"] == hashlib.sha256(b"graph:" + str(len(graph)).encode() + b":" + graph + b"\nproject-map:" + str(len(source)).encode() + b":" + source).hexdigest(), report
assert report["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[3], "rb").read()).hexdigest(), report
assert report["configuration_sha256"] == hashlib.sha256(b"repo-health/project-node-map/1").hexdigest(), report
print("[project-map] graph-bound reviewed project identity OK")
PY
set +e
sed 's/"graph_sha256":"[0-9a-f]*/"graph_sha256":"0000000000000000000000000000000000000000000000000000000000000000/' "$T/map.json" > "$T/stale.json"
"$ROOT/build/rh_cli" project-map --graph "$T/graph.json" --input "$T/stale.json" --out "$T/x" >/dev/null 2>&1; stale=$?
python3 - "$T/map.json" "$T/ambiguous.json" <<'PY'
import sys
source = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(source.replace('"reviewer_id":42', '"reviewer_id":42,"reviewer_id":43', 1))
PY
"$ROOT/build/rh_cli" project-map --graph "$T/graph.json" --input "$T/ambiguous.json" --out "$T/x" >/dev/null 2>&1; ambiguous=$?
python3 - "$T/map.json" "$T/duplicate.json" "$T/unreviewed.json" "$T/bad-evidence.json" <<'PY'
import json, sys
base = json.load(open(sys.argv[1]))
duplicate = dict(base); duplicate["mappings"] = base["mappings"] * 2
json.dump(duplicate, open(sys.argv[2], "w"), separators=(",", ":"))
unreviewed = json.loads(json.dumps(base)); del unreviewed["mappings"][0]["reviewer_id"]
json.dump(unreviewed, open(sys.argv[3], "w"), separators=(",", ":"))
bad_evidence = json.loads(json.dumps(base)); bad_evidence["mappings"][0]["evidence_sha256"] = "z" * 64
json.dump(bad_evidence, open(sys.argv[4], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" project-map --graph "$T/graph.json" --input "$T/duplicate.json" --out "$T/x" >/dev/null 2>&1; duplicate=$?
"$ROOT/build/rh_cli" project-map --graph "$T/graph.json" --input "$T/unreviewed.json" --out "$T/x" >/dev/null 2>&1; unreviewed=$?
"$ROOT/build/rh_cli" project-map --graph "$T/graph.json" --input "$T/bad-evidence.json" --out "$T/x" >/dev/null 2>&1; bad_evidence=$?
set -e
[[ "$stale" -eq 4 && "$ambiguous" -eq 4 && "$duplicate" -eq 4 && "$unreviewed" -eq 4 && "$bad_evidence" -eq 4 ]] || fail "invalid project mapping must exit 4 (got $stale/$ambiguous/$duplicate/$unreviewed/$bad_evidence)"
echo "test_project_map_cli OK"
