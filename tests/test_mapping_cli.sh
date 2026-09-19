#!/usr/bin/env bash
# tests/test_mapping_cli.sh — M05-03 reviewed mapping assertions. The
# normalized result retains relation/state/source evidence, while downstream
# grouping consumes only accepted mirror/migration assertions and carries the
# mapping revision in its projection label.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-mapping"

fail() { echo "[mapping] FAIL: $1" >&2; exit 1; }

echo "[mapping] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/graph.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"test","nodes":[{"id":0,"name":"iso","version":"1"},{"id":1,"name":"top","version":"1"},{"id":2,"name":"mid-a","version":"1"},{"id":3,"name":"mid-b","version":"1"},{"id":4,"name":"leaf","version":"1"}],"edges":[{"from":1,"to":2,"scope":"normal"},{"from":1,"to":3,"scope":"normal"},{"from":2,"to":4,"scope":"normal"},{"from":3,"to":4,"scope":"normal"}],"unresolved":[],"advisories":[]}
JSON
cat > "$T/mapping.json" <<'JSON'
{"schema":"rh-mapping-input/1","revision":7,"assertions":[{"a":2,"b":3,"state":"accepted","relation":"mirror","source":"operator","reviewed_at":100,"evidence":["review/1"]},{"a":1,"b":2,"state":"proposed","relation":"migration","source":"file","reviewed_at":101,"evidence":["map.md"]},{"a":4,"b":2,"state":"rejected","relation":"component","source":"provider","reviewed_at":102,"evidence":[]}]}
JSON
"$ROOT/build/rh_cli" mapping --input "$T/mapping.json" --out "$T/mapping.out" >/dev/null || fail "mapping run"
python3 - "$T/mapping.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-mapping-result/1", d
assert d["revision"] == 7, d
assert d["state_counts"] == {"proposed": 1, "accepted": 1, "rejected": 1, "revoked": 0}, d
assert d["assertions"][0]["evidence_count"] == 1, d
assert "only accepted mirror/migration" in d["note"], d
print("[mapping] normalized reviewed assertions OK")
PY

echo "[mapping] downstream uses accepted mirror and carries revision"
"$ROOT/build/rh_cli" downstream --graph "$T/graph.json" --subject 4 --mapping "$T/mapping.json" --out "$T/downstream" >/dev/null || fail "downstream mapping run"
python3 - "$T/downstream/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["projection"]["mapping_revision"] == 7, d
assert d["grouping"]["accepted_assertions"] == 1, d
assert d["direct_count"] == 1 and d["transitive_count"] == 2, d
print("[mapping] downstream projection integration OK")
PY

echo "[mapping] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" mapping --input "$T/mapping.json" --out "$T/mapping2.out" >/dev/null || fail "rerun"
cmp -s "$T/mapping.out" "$T/mapping2.out" || fail "mapping output not deterministic"
set +e
printf '{"schema":"rh-mapping-input/2","revision":1,"assertions":[]}' > "$T/bad-schema.json"
"$ROOT/build/rh_cli" mapping --input "$T/bad-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-mapping-input/1","revision":1,"assertions":[{"a":1,"b":2,"state":"accepted","relation":"mirror","source":"vibes","reviewed_at":1,"evidence":[]}]}' > "$T/bad-source.json"
"$ROOT/build/rh_cli" mapping --input "$T/bad-source.json" --out "$T/x" >/dev/null 2>&1; rc_source=$?
printf 'not json' > "$T/notjson"
"$ROOT/build/rh_cli" mapping --input "$T/notjson" --out "$T/x" >/dev/null 2>&1; rc_json=$?
set -e
[[ "$rc_schema" -eq 4 && "$rc_source" -eq 4 && "$rc_json" -eq 4 ]] || fail "invalid mapping must exit 4 (got $rc_schema/$rc_source/$rc_json)"

echo "test_mapping_cli OK"
