#!/usr/bin/env bash
# tests/test_downstream_cli.sh — M05 execution path: `rh_cli downstream`
# turns an rh-dep-graph/1 document into an rh-downstream/1 report. Asserts
# exact direct/transitive counts for diamond and cycle graphs, truncation
# flagged (never a total), private-node exclusion under a public projection
# (S007/F030), a simulated-unavailability scenario, and end-to-end use of a
# real `deps` graph.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-downstream"

fail() { echo "[downstream] FAIL: $1" >&2; exit 1; }

echo "[downstream] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"

# Diamond: consumers point at dependencies. 1->2, 1->3, 2->4, 3->4.
cat > "$T/diamond.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"test","nodes":[{"id":0,"name":"iso","version":"1"},{"id":1,"name":"top","version":"1"},{"id":2,"name":"mid-a","version":"1"},{"id":3,"name":"mid-b","version":"1"},{"id":4,"name":"leaf","version":"1"}],"edges":[{"from":1,"to":2,"scope":"normal"},{"from":1,"to":3,"scope":"normal"},{"from":2,"to":4,"scope":"normal"},{"from":3,"to":4,"scope":"normal"}],"unresolved":[],"advisories":[]}
JSON

# Cycle: 1->2, 2->1 (plus an isolated node 0).
cat > "$T/cycle.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"test","nodes":[{"id":0,"name":"iso","version":"1"},{"id":1,"name":"a","version":"1"},{"id":2,"name":"b","version":"1"}],"edges":[{"from":1,"to":2,"scope":"normal"},{"from":2,"to":1,"scope":"normal"}],"unresolved":[],"advisories":[]}
JSON

echo "[downstream] diamond direct=2 transitive=3"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/d" >/dev/null || fail "diamond run"
python3 - "$T/d/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-downstream/1"
assert d["direct_count"] == 2, d
assert d["transitive_count"] == 3, d
assert d["truncated"] is False, d
assert {n["id"] for n in d["direct"]} == {2, 3}, d["direct"]
assert {n["id"] for n in d["transitive"]} == {1, 2, 3}, d["transitive"]
assert any(n["name"] == "top" for n in d["transitive"]), d["transitive"]
assert "NOT a total" in d["note"], d["note"]
assert d["grouping"]["family_dedup"] is False, d["grouping"]
assert d["intrinsics"] is None, d["intrinsics"]
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["graph.direct_dependents_count"]["value"] == 2, metrics
assert metrics["graph.transitive_dependents_count"]["value"] == 3, metrics
assert metrics["graph.scc_component_count"]["value"] == 4, metrics
assert metrics["graph.scenario_affected_count"]["status"] == "not_applicable", metrics
print("[downstream] diamond OK")
PY

echo "[downstream] persist labeled projection and replay its snapshot ID"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/snapshot-a" --snapshot-root "$T/snapshots" >/dev/null || fail "snapshot run"
sid_a=$(python3 - "$T/snapshot-a/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
sid = d["projection"]["snapshot_id"]
assert isinstance(sid, str) and len(sid) == 16 and all(c in "0123456789abcdef" for c in sid), sid
print(sid)
PY
)
"$ROOT/build/rh_cli" store verify --root "$T/snapshots" --name "$sid_a" >/dev/null || fail "snapshot verification"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/snapshot-b" --snapshot-root "$T/snapshots" >/dev/null || fail "snapshot replay"
sid_b=$(python3 - "$T/snapshot-b/downstream.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["projection"]["snapshot_id"])
PY
)
[[ "$sid_a" == "$sid_b" ]] || fail "identical graph/projection must replay the same snapshot ID"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/snapshot-c" --snapshot-root "$T/snapshots" --max-depth 1 >/dev/null || fail "changed projection snapshot"
sid_c=$(python3 - "$T/snapshot-c/downstream.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["projection"]["snapshot_id"])
PY
)
[[ "$sid_a" != "$sid_c" ]] || fail "changed projection must create a new snapshot ID"
echo "[downstream] projection snapshot OK"

echo "[downstream] per-metric intrinsic join has its own denominators (R011)"
cat > "$T/intr.json" <<'JSON'
{"schema":"rh-intrinsics/1","metrics":["history.months_active","review.count","release.count"],"values":[{"id":1,"mask":1},{"id":2,"mask":3},{"id":3,"mask":5}]}
JSON
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/i" --intrinsics "$T/intr.json" >/dev/null || fail "intrinsics run"
python3 - "$T/i/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
intr = d["intrinsics"]
assert intr["dependent_total"] == 3, intr
# dependents are {1,2,3}: history present for all 3, review only for 2,
# release only for 3 -- never collapsed into one coverage number.
got = {c["key"]: c["observed"] for c in intr["covered"]}
assert got == {"history.months_active": 3, "review.count": 1, "release.count": 1}, got
assert "independent of downstream inputs" in intr["note"], intr["note"]
print("[downstream] intrinsic join OK")
PY

echo "[downstream] accepted mirror assertion collapses a family (R012)"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/m" --mirror 2:3 >/dev/null || fail "mirror run"
python3 - "$T/m/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["grouping"]["accepted_assertions"] == 1, d["grouping"]
assert d["grouping"]["family_dedup"] is True, d["grouping"]
# mid-a (2) and mid-b (3) are one accepted family -> one direct group.
assert d["direct_count"] == 1, d
assert {n["id"] for n in d["direct"]} == {2}, d["direct"]
assert d["transitive_count"] == 2, d
assert {n["id"] for n in d["transitive"]} == {1, 2}, d["transitive"]
assert "ACCEPTED assertions" in d["note"], d["note"]
print("[downstream] mirror dedup OK")
PY

echo "[downstream] forks stay distinct without an accepted assertion"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/n" >/dev/null || fail "no-mirror run"
python3 - "$T/n/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["grouping"]["accepted_assertions"] == 0, d["grouping"]
assert {n["id"] for n in d["direct"]} == {2, 3}, d["direct"]
print("[downstream] fork distinctness OK")
PY

echo "[downstream] cycle terminates and reports SCCs"
"$ROOT/build/rh_cli" downstream --graph "$T/cycle.json" --subject 1 --out "$T/c" >/dev/null || fail "cycle run"
python3 - "$T/c/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["direct_count"] == 1, d
assert d["transitive_count"] == 1, d
assert {n["id"] for n in d["transitive"]} == {2}, d["transitive"]
# subject 1 is excluded from its own dependent set
assert all(n["id"] != 1 for n in d["transitive"]), d["transitive"]
assert d["scc_components"] == 2, d["scc_components"]  # {0} and {1,2}
print("[downstream] cycle OK")
PY

echo "[downstream] budget exhaustion flags truncation, not a total"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/t" --max-nodes 1 >/dev/null || fail "truncation run"
python3 - "$T/t/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["truncated"] is True, d
assert d["transitive_count"] < 3, d
print("[downstream] truncation OK")
PY

echo "[downstream] private dependent excluded from public projection"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/p" --private 1 >/dev/null || fail "private run"
python3 - "$T/p/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["direct_count"] == 2, d
assert d["transitive_count"] == 2, d
assert all(n["id"] != 1 for n in d["transitive"]), d["transitive"]
print("[downstream] private exclusion OK")
PY

echo "[downstream] simulated unavailability scenario present"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/s" --unavailable 2 >/dev/null || fail "scenario run"
python3 - "$T/s/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["scenario"] is not None, d
assert d["scenario"]["unavailable"] == 2, d["scenario"]
assert "affected_count" in d["scenario"], d["scenario"]
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["graph.scenario_affected_count"]["value"] == d["scenario"]["affected_count"], metrics
print("[downstream] scenario OK")
PY

echo "[downstream] end-to-end from a real deps graph"
mkdir -p "$T/src"
cp "$ROOT/fixtures/packages/cargo-diamond.lock" "$T/src/Cargo.lock"
"$ROOT/build/rh_cli" deps --repo "$T/src" --out "$T/deps" >/dev/null || fail "deps run"
"$ROOT/build/rh_cli" downstream --graph "$T/deps/deps-cargo-graph.json" --subject 3 --out "$T/e2e" >/dev/null || fail "e2e run"
python3 - "$T/e2e/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["direct_count"] == 1, d
assert d["direct"][0]["name"] == "left", d["direct"]
print("[downstream] end-to-end OK")
PY

echo "[downstream] negatives fail closed"
set +e
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 99 --out "$T/miss" >/dev/null 2>&1
rc_subj=$?
printf 'not json\n' > "$T/bad.json"
"$ROOT/build/rh_cli" downstream --graph "$T/bad.json" --subject 0 --out "$T/bad" >/dev/null 2>&1
rc_bad=$?
"$ROOT/build/rh_cli" downstream --graph "$T/nope.json" --subject 0 --out "$T/nope" >/dev/null 2>&1
rc_nofile=$?
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/badpair" --mirror 2 >/dev/null 2>&1
rc_pair=$?
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/badpair2" --mirror a:b >/dev/null 2>&1
rc_pair2=$?
printf '{"schema":"rh-intrinsics/2","metrics":[],"values":[]}' > "$T/badintr.json"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/badintr" --intrinsics "$T/badintr.json" >/dev/null 2>&1
rc_intr=$?
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/nointr" --intrinsics "$T/does-not-exist.json" >/dev/null 2>&1
rc_intrmiss=$?
set -e
[[ "$rc_subj" -eq 3 ]] || fail "missing subject must exit 3 (got $rc_subj)"
[[ "$rc_bad" -eq 4 ]] || fail "malformed graph must exit 4 (got $rc_bad)"
[[ "$rc_nofile" -eq 4 ]] || fail "missing graph must exit 4 (got $rc_nofile)"
[[ "$rc_pair" -eq 2 ]] || fail "malformed --mirror must exit 2 (got $rc_pair)"
[[ "$rc_pair2" -eq 2 ]] || fail "non-numeric --mirror must exit 2 (got $rc_pair2)"
[[ "$rc_intr" -eq 4 ]] || fail "bad intrinsics schema must exit 4 (got $rc_intr)"
[[ "$rc_intrmiss" -eq 4 ]] || fail "missing intrinsics file must exit 4 (got $rc_intrmiss)"

echo "test_downstream_cli OK"
