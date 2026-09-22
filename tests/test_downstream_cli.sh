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
{"schema":"rh-dep-graph/1","ecosystem":"npm","nodes":[{"id":0,"name":"iso","version":"1"},{"id":1,"name":"top","version":"1"},{"id":2,"name":"mid-a","version":"1"},{"id":3,"name":"mid-b","version":"1"},{"id":4,"name":"leaf","version":"1"}],"edges":[{"from":1,"to":2,"scope":"normal"},{"from":1,"to":3,"scope":"normal"},{"from":2,"to":4,"scope":"normal"},{"from":3,"to":4,"scope":"normal"}],"unresolved":[],"advisories":[]}
JSON

# Bitemporal edge evidence: introduced/removed are valid time; first_seen is
# collector knowledge time. The two axes must remain independently queryable.
cat > "$T/temporal.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"npm","nodes":[{"id":0,"name":"focus","version":"1"},{"id":1,"name":"known-normal","version":"1"},{"id":2,"name":"late-dev","version":"2"},{"id":3,"name":"removed-normal","version":"3"},{"id":4,"name":"new-normal","version":"4"}],"edges":[{"from":1,"to":0,"scope":"normal","platform":1,"introduced":100,"first_seen":300},{"from":2,"to":0,"scope":"dev","platform":2,"introduced":100,"first_seen":400},{"from":3,"to":0,"scope":"normal","platform":1,"introduced":100,"removed":200,"first_seen":100},{"from":4,"to":0,"scope":"normal","platform":1,"introduced":250,"first_seen":100}],"unresolved":[],"advisories":[]}
JSON

echo "[downstream] valid time, known time, scope, and platform form an explicit v2 projection"
"$ROOT/build/rh_cli" downstream --graph "$T/temporal.json" --subject 0 --out "$T/time-a" --valid-as-of 300 --known-as-of 350 --scope normal --platform 1 >/dev/null || fail "temporal projection run"
python3 - "$T/time-a/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-downstream/2", d
p = d["projection"]
assert (p["edge_scope"], p["platform"], p["valid_as_of"], p["known_as_of"]) == ("normal", 1, 300, 350), p
assert p["visible_edge_count"] == 2, p
assert d["direct_count"] == 2 and {n["id"] for n in d["direct"]} == {1, 4}, d
print("[downstream] explicit projection OK")
PY
"$ROOT/build/rh_cli" downstream --graph "$T/temporal.json" --subject 0 --out "$T/time-b" --valid-as-of 300 --known-as-of 450 >/dev/null || fail "later-known projection run"
python3 - "$T/time-b/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-downstream/2", d
assert d["direct_count"] == 3 and {n["id"] for n in d["direct"]} == {1, 2, 4}, d
assert d["projection"]["visible_edge_count"] == 3, d["projection"]
print("[downstream] later-known evidence is visible retrospectively only when requested")
PY
"$ROOT/build/rh_cli" downstream --graph "$T/temporal.json" --subject 0 --out "$T/time-c" --valid-as-of 150 --known-as-of 450 >/dev/null || fail "earlier-valid projection run"
python3 - "$T/time-c/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["direct_count"] == 3 and {n["id"] for n in d["direct"]} == {1, 2, 3}, d
assert d["projection"]["valid_as_of"] == 150 and d["projection"]["known_as_of"] == 450, d["projection"]
print("[downstream] removed/new edges obey valid time independently")
PY
"$ROOT/build/rh_cli" downstream --graph "$T/temporal.json" --subject 0 --out "$T/time-snapshot-a" --snapshot-root "$T/time-snapshots" --valid-as-of 300 --known-as-of 350 --scope normal --platform 1 >/dev/null || fail "temporal snapshot run"
time_sid_a=$(python3 - "$T/time-snapshot-a/downstream.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["projection"]["snapshot_id"])
PY
)
"$ROOT/build/rh_cli" downstream --graph "$T/temporal.json" --subject 0 --out "$T/time-snapshot-b" --snapshot-root "$T/time-snapshots" --valid-as-of 300 --known-as-of 350 --scope normal --platform 1 >/dev/null || fail "temporal snapshot replay"
time_sid_b=$(python3 - "$T/time-snapshot-b/downstream.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["projection"]["snapshot_id"])
PY
)
"$ROOT/build/rh_cli" downstream --graph "$T/temporal.json" --subject 0 --out "$T/time-snapshot-c" --snapshot-root "$T/time-snapshots" --valid-as-of 150 --known-as-of 350 --scope normal --platform 1 >/dev/null || fail "changed temporal snapshot run"
time_sid_c=$(python3 - "$T/time-snapshot-c/downstream.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["projection"]["snapshot_id"])
PY
)
[[ "$time_sid_a" == "$time_sid_b" ]] || fail "identical temporal projections must replay the same snapshot"
[[ "$time_sid_a" != "$time_sid_c" ]] || fail "a changed valid-time projection must create a new snapshot"
echo "[downstream] temporal projection snapshot identity OK"

echo "[downstream] identity revision is explicit and part of snapshot identity"
"$ROOT/build/rh_cli" downstream --graph "$T/temporal.json" --subject 0 --out "$T/identity-snapshot-a" --snapshot-root "$T/identity-snapshots" --valid-as-of 300 --known-as-of 350 --identity-revision 7 >/dev/null || fail "identity revision snapshot run"
identity_sid_a=$(python3 - "$T/identity-snapshot-a/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["projection"]["identity_revision"] == 7, d["projection"]
print(d["projection"]["snapshot_id"])
PY
)
"$ROOT/build/rh_cli" downstream --graph "$T/temporal.json" --subject 0 --out "$T/identity-snapshot-b" --snapshot-root "$T/identity-snapshots" --valid-as-of 300 --known-as-of 350 --identity-revision 7 >/dev/null || fail "identity revision replay"
identity_sid_b=$(python3 - "$T/identity-snapshot-b/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["projection"]["identity_revision"] == 7, d["projection"]
print(d["projection"]["snapshot_id"])
PY
)
"$ROOT/build/rh_cli" downstream --graph "$T/temporal.json" --subject 0 --out "$T/identity-snapshot-c" --snapshot-root "$T/identity-snapshots" --valid-as-of 300 --known-as-of 350 --identity-revision 8 >/dev/null || fail "changed identity revision snapshot"
identity_sid_c=$(python3 - "$T/identity-snapshot-c/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["projection"]["identity_revision"] == 8, d["projection"]
print(d["projection"]["snapshot_id"])
PY
)
[[ "$identity_sid_a" == "$identity_sid_b" ]] || fail "identical identity revision must replay the same snapshot"
[[ "$identity_sid_a" != "$identity_sid_c" ]] || fail "a changed identity revision must create a new snapshot"
if "$ROOT/build/rh_cli" downstream --graph "$T/temporal.json" --subject 0 --out "$T/identity-revision-invalid" --identity-revision -1 >/dev/null 2>&1; then
  fail "negative identity revision must be rejected"
fi
echo "[downstream] identity revision snapshot identity OK"

# Cycle: 1->2, 2->1 (plus an isolated node 0).
cat > "$T/cycle.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"npm","nodes":[{"id":0,"name":"iso","version":"1"},{"id":1,"name":"a","version":"1"},{"id":2,"name":"b","version":"1"}],"edges":[{"from":1,"to":2,"scope":"normal"},{"from":2,"to":1,"scope":"normal"}],"unresolved":[],"advisories":[]}
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
assert metrics["graph.strongly_connected_components"]["value"] == 4, metrics
assert metrics["graph.reverse_reachability_count"]["value"] == 3, metrics
assert metrics["graph.cyclic_node_share"]["value"] == {"num": 0, "den": 5}, metrics
assert metrics["graph.traversal_truncated"]["value"] is False, metrics
assert metrics["graph.scenario_affected_count"]["status"] == "not_applicable", metrics
assert metrics["downstream_condition.intrinsic_coverage_share"]["status"] == "not_applicable", metrics
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

echo "[downstream] shared snapshot stores only the sanitized public graph"
cat > "$T/private-snapshot.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"npm","nodes":[{"id":0,"name":"public-root","version":"1","custom":"PUBLIC-UNKNOWN-SECRET"},{"id":1,"name":"scope-node","version":"9","token":"PRIVATE-UNKNOWN-SECRET"},{"id":2,"name":"public-leaf","version":null}],"edges":[{"from":1,"to":2,"scope":"normal","custom":"PRIVATE-EDGE-SECRET"},{"from":2,"to":0,"scope":"PUBLIC-SCOPE-UNKNOWN-SECRET","introduced":10,"first_seen":20,"custom":"PUBLIC-EDGE-UNKNOWN-SECRET"}],"unresolved":[{"from":1,"name":"PRIVATE-UNRESOLVED-SECRET"}],"advisories":[{"advisory":"PRIVATE-ADVISORY-SECRET","node":1,"witness":[0,1]}]}
JSON
"$ROOT/build/rh_cli" downstream --graph "$T/private-snapshot.json" --subject 0 --out "$T/private-snapshot-report" --private 1 --snapshot-root "$T/private-snapshots" >/dev/null || fail "private snapshot run"
python3 - "$T/private-snapshot-report/downstream.json" "$T/private-snapshots" <<'PY'
import json, pathlib, sys
report = json.load(open(sys.argv[1]))
snapshot_id = report["projection"]["snapshot_id"]
snapshot_path = pathlib.Path(sys.argv[2]) / snapshot_id
raw = snapshot_path.read_text()
snapshot = json.loads(raw)
assert snapshot["schema"] == "rh-projection-snapshot/2", snapshot["schema"]
graph = snapshot["graph"]
assert [node["id"] for node in graph["nodes"]] == [0, 1], graph["nodes"]
assert [node["name"] for node in graph["nodes"]] == ["public-root", "public-leaf"], graph["nodes"]
assert graph["nodes"][1]["version"] is None, graph["nodes"]
assert graph["edges"] == [{"from": 1, "to": 0, "scope": "normal", "introduced": 10, "first_seen": 20}], graph["edges"]
assert graph["unresolved"] == [] and graph["advisories"] == [], graph
for secret in ("scope-node", "PRIVATE-UNKNOWN-SECRET", "PRIVATE-EDGE-SECRET", "PRIVATE-UNRESOLVED-SECRET", "PRIVATE-ADVISORY-SECRET", "PUBLIC-UNKNOWN-SECRET", "PUBLIC-EDGE-UNKNOWN-SECRET", "PUBLIC-SCOPE-UNKNOWN-SECRET"):
    assert secret not in raw, secret
print("[downstream] public projection snapshot excludes private payloads")
PY
"$ROOT/build/rh_cli" downstream --graph "$T/private-snapshot.json" --subject 0 --out "$T/other-private-snapshot-report" --private 2 --snapshot-root "$T/private-snapshots" >/dev/null || fail "shared-root second visibility run"
python3 - "$T/private-snapshot-report/downstream.json" "$T/other-private-snapshot-report/downstream.json" "$T/private-snapshots" <<'PY'
import json, pathlib, sys
first, second = (json.load(open(path)) for path in sys.argv[1:3])
root = pathlib.Path(sys.argv[3])
first_id = first["projection"]["snapshot_id"]
second_id = second["projection"]["snapshot_id"]
assert first_id != second_id, (first_id, second_id)
first_graph = json.loads((root / first_id).read_text())["graph"]
second_graph = json.loads((root / second_id).read_text())["graph"]
assert [node["name"] for node in first_graph["nodes"]] == ["public-root", "public-leaf"], first_graph
assert [node["name"] for node in second_graph["nodes"]] == ["public-root", "scope-node"], second_graph
assert all(set(node) == {"id", "name", "version"} for node in second_graph["nodes"]), second_graph
print("[downstream] shared cache keeps visibility-specific projections isolated")
PY

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
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["downstream_condition.intrinsic_coverage_share"]["value"] == {"num": 5, "den": 9}, metrics
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

echo "[downstream] reviewed mappings obey known-time cutoffs"
cat > "$T/mapping.json" <<'JSON'
{"schema":"rh-mapping-input/1","revision":7,"assertions":[{"a":2,"b":3,"state":"accepted","relation":"migration","source":"operator","reviewed_at":100,"evidence":[]}]}
JSON
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/map-before" --mapping "$T/mapping.json" --known-as-of 50 >/dev/null || fail "pre-review mapping projection"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/map-after" --mapping "$T/mapping.json" --known-as-of 100 >/dev/null || fail "post-review mapping projection"
python3 - "$T/map-before/downstream.json" "$T/map-after/downstream.json" <<'PY'
import json, sys
before, after = [json.load(open(p)) for p in sys.argv[1:]]
assert before["projection"]["mapping_revision"] == after["projection"]["mapping_revision"] == 7, (before, after)
assert before["grouping"]["accepted_assertions"] == 0, before["grouping"]
assert before["direct_count"] == 2, before
assert after["grouping"]["accepted_assertions"] == 1, after["grouping"]
assert after["direct_count"] == 1, after
print("[downstream] mapping known-time cutoff OK")
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
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["graph.cyclic_node_share"]["value"] == {"num": 2, "den": 3}, metrics
print("[downstream] cycle OK")
PY

echo "[downstream] budget exhaustion flags truncation, not a total"
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/t" --max-nodes 1 >/dev/null || fail "truncation run"
python3 - "$T/t/downstream.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["truncated"] is True, d
assert d["transitive_count"] < 3, d
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["graph.traversal_truncated"]["value"] is True, metrics
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
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/bad-time" --valid-as-of nope >/dev/null 2>&1
rc_time=$?
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/bad-scope" --scope unknown >/dev/null 2>&1
rc_scope=$?
"$ROOT/build/rh_cli" downstream --graph "$T/diamond.json" --subject 4 --out "$T/bad-platform" --platform 0 >/dev/null 2>&1
rc_platform=$?
printf '%s' '{"schema":"rh-dep-graph/1","ecosystem":"npm","nodes":[{"id":0,"name":"a","version":"1"}],"edges":[{"from":0,"to":0,"introduced":100,"removed":99}],"unresolved":[],"advisories":[]}' > "$T/bad-interval.json"
"$ROOT/build/rh_cli" downstream --graph "$T/bad-interval.json" --subject 0 --out "$T/bad-interval" >/dev/null 2>&1
rc_interval=$?
set -e
[[ "$rc_subj" -eq 3 ]] || fail "missing subject must exit 3 (got $rc_subj)"
[[ "$rc_bad" -eq 4 ]] || fail "malformed graph must exit 4 (got $rc_bad)"
[[ "$rc_nofile" -eq 4 ]] || fail "missing graph must exit 4 (got $rc_nofile)"
[[ "$rc_pair" -eq 2 ]] || fail "malformed --mirror must exit 2 (got $rc_pair)"
[[ "$rc_pair2" -eq 2 ]] || fail "non-numeric --mirror must exit 2 (got $rc_pair2)"
[[ "$rc_intr" -eq 4 ]] || fail "bad intrinsics schema must exit 4 (got $rc_intr)"
[[ "$rc_intrmiss" -eq 4 ]] || fail "missing intrinsics file must exit 4 (got $rc_intrmiss)"
[[ "$rc_time" -eq 2 ]] || fail "malformed valid-time filter must exit 2 (got $rc_time)"
[[ "$rc_scope" -eq 2 ]] || fail "unknown scope filter must exit 2 (got $rc_scope)"
[[ "$rc_platform" -eq 2 ]] || fail "invalid platform filter must exit 2 (got $rc_platform)"
[[ "$rc_interval" -eq 4 ]] || fail "invalid edge validity interval must exit 4 (got $rc_interval)"

echo "test_downstream_cli OK"
