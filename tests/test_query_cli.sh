#!/usr/bin/env bash
# tests/test_query_cli.sh — M06-01 query execution path: `rh_cli query`
# turns an rh-query-input/1 request into rh-query-result/1 with cursor
# pagination (idempotent for a replayed cursor), a per-capability scan-status
# breakdown, and a fenced bounded-job lease sequence. Malformed requests fail
# closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-query"

fail() { echo "[query] FAIL: $1" >&2; exit 1; }

echo "[query] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-query-input/1","kind":"metrics","ids":[10,20,30,40,50],"cursor":-1,"limit":2,"scan_states":["observed","stale","partial","observed","error","unavailable"],"job":{"job_id":7,"ops":[{"op":"claim","owner":1,"now":1000,"ttl":100},{"op":"claim","owner":2,"now":1050,"ttl":100},{"op":"renew","token":0,"now":1050,"ttl":100},{"op":"renew","token":1,"now":1050,"ttl":100},{"op":"claim","owner":2,"now":1200,"ttl":100},{"op":"finish","token":1,"phase":"succeeded"},{"op":"finish","token":2,"phase":"succeeded"},{"op":"claim","owner":3,"now":1300,"ttl":100},{"op":"budget","visited_nodes":10,"deadline":5000,"now":2000,"max_nodes":100},{"op":"budget","visited_nodes":101,"deadline":5000,"now":2000,"max_nodes":100}]}}
JSON
"$ROOT/build/rh_cli" query --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "query run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-query-result/1" and d["kind"] == "metrics", d
assert d["page"] == {"ids": [10, 20], "next_cursor": 20, "complete": False}, d["page"]
assert d["scan_status"] == {"observed": 2, "stale": 1, "partial": 1,
                            "unavailable": 1, "unauthorized": 0, "other": 1}, d["scan_status"]
res = d["job"]["ops"]
assert res[0]["result"] == {"outcome": "claimed", "token": 1, "phase": "leased"}, res[0]
assert res[1]["result"] == {"outcome": "held"}, res[1]
assert res[2]["result"]["applied"] is False, res[2]   # stale token cannot renew
assert res[3]["result"]["applied"] is True and res[3]["result"]["phase"] == "running", res[3]
assert res[4]["result"]["outcome"] == "claimed" and res[4]["result"]["token"] == 2, res[4]
assert res[5]["result"]["applied"] is False, res[5]   # old token cannot finish
assert res[6]["result"]["applied"] is True and res[6]["result"]["phase"] == "succeeded", res[6]
assert res[7]["result"]["outcome"] == "terminal", res[7]
assert res[8]["result"] == {"within": True}, res[8]
assert res[9]["result"] == {"within": False}, res[9]
assert "never one project verdict" in d["note"], d["note"]
print("[query] page + scan-status + job lease OK")
PY

echo "[query] pagination completes and a replayed cursor is idempotent"
cat > "$T/p2.json" <<'JSON'
{"schema":"rh-query-input/1","kind":"downstream","ids":[10,20,30,40,50],"cursor":20,"limit":2}
JSON
"$ROOT/build/rh_cli" query --input "$T/p2.json" --out "$T/p2.out" >/dev/null || fail "p2"
cat > "$T/p3.json" <<'JSON'
{"schema":"rh-query-input/1","kind":"scan_status","ids":[10,20,30,40,50],"cursor":40,"limit":2}
JSON
"$ROOT/build/rh_cli" query --input "$T/p3.json" --out "$T/p3.out" >/dev/null || fail "p3"
python3 - "$T/p2.out" "$T/p3.out" <<'PY'
import json, sys
p2 = json.load(open(sys.argv[1]))
p3 = json.load(open(sys.argv[2]))
assert p2["page"] == {"ids": [30, 40], "next_cursor": 40, "complete": False}, p2["page"]
assert p3["page"] == {"ids": [50], "next_cursor": None, "complete": True}, p3["page"]
assert p2["kind"] == "downstream" and p3["kind"] == "scan_status", (p2["kind"], p3["kind"])
print("[query] pagination completion OK")
PY
# replaying the same cursor returns the same page
"$ROOT/build/rh_cli" query --input "$T/p2.json" --out "$T/p2b.out" >/dev/null || fail "p2 replay"
cmp -s "$T/p2.out" "$T/p2b.out" || fail "replayed cursor is not idempotent"

echo "[query] bounded graph operation traverses both directions and reports truncation"
cat > "$T/graph-down.json" <<'JSON'
{"schema":"rh-query-input/1","kind":"downstream","ids":[1,2,3,4],"cursor":-1,"limit":10,"graph":{"direction":"downstream","subject":1,"nodes":[1,2,3,4],"edges":[{"from":2,"to":1},{"from":3,"to":2},{"from":4,"to":3}],"max_nodes":2,"max_depth":8}}
JSON
cat > "$T/graph-up.json" <<'JSON'
{"schema":"rh-query-input/1","kind":"upstream","ids":[1,2,3,4],"cursor":-1,"limit":10,"graph":{"direction":"upstream","subject":4,"nodes":[1,2,3,4],"edges":[{"from":2,"to":1},{"from":3,"to":2},{"from":4,"to":3}],"max_nodes":2,"max_depth":8}}
JSON
"$ROOT/build/rh_cli" query --input "$T/graph-down.json" --out "$T/graph-down.out" >/dev/null || fail "graph downstream"
"$ROOT/build/rh_cli" query --input "$T/graph-up.json" --out "$T/graph-up.out" >/dev/null || fail "graph upstream"
python3 - "$T/graph-down.out" "$T/graph-up.out" <<'PY'
import json, sys
down = json.load(open(sys.argv[1]))["graph"]
up = json.load(open(sys.argv[2]))["graph"]
assert down == {"direction": "downstream", "nodes": [2, 3], "truncated": True, "complete": False}, down
assert up == {"direction": "upstream", "nodes": [3, 2], "truncated": True, "complete": False}, up
print("[query] graph direction + bounded truncation OK")
PY

cat > "$T/graph-up-fanout.json" <<'JSON'
{"schema":"rh-query-input/1","kind":"upstream","ids":[1,2,3],"cursor":-1,"limit":10,"graph":{"direction":"upstream","subject":1,"nodes":[1,2,3],"edges":[{"from":1,"to":2},{"from":1,"to":3}],"max_nodes":1,"max_depth":8}}
JSON
"$ROOT/build/rh_cli" query --input "$T/graph-up-fanout.json" --out "$T/graph-up-fanout.out" >/dev/null || fail "graph upstream fanout budget"
python3 - "$T/graph-up-fanout.out" <<'PY'
import json, sys
graph = json.load(open(sys.argv[1]))["graph"]
assert graph == {"direction": "upstream", "nodes": [2], "truncated": True, "complete": False}, graph
print("[query] upstream fanout respects node budget")
PY

echo "[query] determinism"
"$ROOT/build/rh_cli" query --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "query output not deterministic"

echo "[query] malformed requests fail closed"
set +e
printf '{"schema":"rh-query-input/2","kind":"metrics","ids":[]}' > "$T/badschema.json"
"$ROOT/build/rh_cli" query --input "$T/badschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-query-input/1","kind":"telepathy","ids":[]}' > "$T/badkind.json"
"$ROOT/build/rh_cli" query --input "$T/badkind.json" --out "$T/x" >/dev/null 2>&1; rc_kind=$?
printf '{"schema":"rh-query-input/1","kind":"metrics","ids":[1,"two"]}' > "$T/badids.json"
"$ROOT/build/rh_cli" query --input "$T/badids.json" --out "$T/x" >/dev/null 2>&1; rc_ids=$?
printf '{"schema":"rh-query-input/1","kind":"metrics","ids":[],"scan_states":["vibes"]}' > "$T/badstate.json"
"$ROOT/build/rh_cli" query --input "$T/badstate.json" --out "$T/x" >/dev/null 2>&1; rc_state=$?
printf '{"schema":"rh-query-input/1","kind":"metrics","ids":[],"job":{"ops":[{"op":"finish","token":1,"phase":"goodbye"}]}}' > "$T/badphase.json"
"$ROOT/build/rh_cli" query --input "$T/badphase.json" --out "$T/x" >/dev/null 2>&1; rc_phase=$?
printf '{"schema":"rh-query-input/1","kind":"metrics","ids":[],"graph":{"subject":1,"nodes":[1],"edges":[{"from":1,"to":2}]}}' > "$T/badgraph.json"
"$ROOT/build/rh_cli" query --input "$T/badgraph.json" --out "$T/x" >/dev/null 2>&1; rc_graph=$?
"$ROOT/build/rh_cli" query --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_kind" "$rc_ids" "$rc_state" "$rc_phase" "$rc_graph" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed query input must exit 4 (got $rc)"
done

echo "test_query_cli OK"
