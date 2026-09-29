#!/usr/bin/env bash
# tests/test_population_cli.sh — RP-06 bounded focal-library population.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-population"

fail() { echo "[population] FAIL: $1" >&2; exit 1; }

echo "[population] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-population-input/1","focal_package":"acme-core","version_policy":"latest-published","discovery_source":"local-reverse-index","discovery_mode":"historical","discovery_context":"cargo registry snapshot; focal release 1.2.0","discovery_as_of":1700000000,"page_limit":100,"truncated":true,"provider_status":"rate_limit","replay_attempts":2,"mapping_revision":4,"deduplication_unit":"accepted-project-family","metric_definitions":[{"key":"history.months_active","version":"1"},{"key":"review.coverage","version":"2"}],"dependents":[{"id":"repo-a","family":"family-a","package":"acme-core","version":"1.2.0","relation":"direct","published_packages":["acme-core","acme-cli"],"path_witness":["app","acme-core"],"metrics":[{"key":"history.months_active","version":"1","status":"observed","value":12,"policy":"pass"},{"key":"review.coverage","version":"2","status":"unknown","value":null,"policy":"unknown"}]},{"id":"repo-b","family":"family-a","package":"acme-core","version":"1.1.0","relation":"transitive","path_witness":["tool","dep","acme-core"],"metrics":[{"key":"history.months_active","version":"1","status":"partial","value":null,"policy":"unknown"},{"key":"review.coverage","version":"2","status":"observed","value":3,"policy":"fail"}]},{"id":"repo-c","family":"family-c","package":"acme-core","version":"1.0.0","relation":"direct","path_witness":["service","acme-core"],"metrics":[{"key":"history.months_active","version":"1","status":"unavailable","value":null,"policy":"unknown"},{"key":"review.coverage","version":"2","status":"observed","value":5,"policy":"pass"}]}],"unresolved":[{"package":"unknown-pkg","reason":"mapping review required"}]}
JSON
"$ROOT/build/rh_cli" population --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "population run"
python3 - "$T/out.json" "$T/in.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-population-result/2", d
assert d["discovery"]["truncated"] is True and d["discovery"]["page_limit"] == 100, d
assert d["discovery"]["context"] == "cargo registry snapshot; focal release 1.2.0", d
assert d["discovery"]["provider_status"] == "rate_limit" and d["discovery"]["replay_attempts"] == 2, d
assert d["population"] == {"selected_dependents": 3, "distinct_families": 2, "unresolved": 1}, d
summary = {m["key"]: m for m in d["summary_metrics"]}
assert summary["population.selected_dependent_count"]["value"] == 3, summary
assert summary["population.distinct_family_count"]["value"] == 2, summary
assert summary["population.unresolved_mapping_count"]["value"] == 1, summary
assert d["dependents"][1]["path_witness"] == ["tool", "dep", "acme-core"], d
assert d["dependents"][0]["published_package_count"] == 2, d
assert d["population"]["selected_dependents"] == len(d["dependents"]), d
by = {(m["key"], m["version"]): m for m in d["metrics"]}
assert by[("history.months_active", "1")]["observed"] == 1, by
assert by[("history.months_active", "1")]["partial"] == 1, by
assert by[("history.months_active", "1")]["unavailable"] == 1, by
assert by[("history.months_active", "1")]["coverage"] == {"observed": 1, "selected_dependents": 3}, by
assert by[("review.coverage", "2")]["coverage"] == {"observed": 2, "selected_dependents": 3}, by
assert by[("review.coverage", "2")]["distribution"] == {"count": 2, "sum": 8, "min": 3, "max": 5}, by
assert by[("review.coverage", "2")]["policy_counts"] == {"pass": 1, "fail": 1, "unknown": 1}, by
assert "counts projects once" in d["note"], d
report = json.load(open(sys.argv[1] + ".transformations.json"))
assert report["schema"] == "rh-adapter-transformation-report/1", report
assert report["adapter"] == "focal-library-population", report
assert "context" in report["fields"][0]["target"], report
assert report["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), report
assert report["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), report
assert report["configuration_sha256"] == hashlib.sha256(b"repo-health/focal-library-population/3;dependents=1000;unresolved=1000;metrics=63").hexdigest(), report
assert all(field["state"] in {"preserved", "transformed", "inferred", "discarded", "unsupported", "unknown"} for field in report["fields"]), report
print("[population] bounded selection + per-metric coverage + witnesses OK")
PY

echo "[population] join reviewed project identities from the selected graph population"
cat > "$T/graph.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"test","nodes":[{"id":0,"name":"acme-core","version":"1.2.0"},{"id":1,"name":"consumer-a","version":"1"},{"id":2,"name":"consumer-b","version":"1"},{"id":3,"name":"consumer-c","version":"1"}],"edges":[{"from":1,"to":0,"scope":"normal"},{"from":2,"to":0,"scope":"normal"},{"from":3,"to":0,"scope":"normal"}],"unresolved":[],"advisories":[]}
JSON
python3 - "$T/graph.json" "$T/project-map.json" <<'PY'
import hashlib, json, sys
graph = open(sys.argv[1], "rb").read()
doc = {"schema":"rh-project-node-map-input/1", "graph_sha256":hashlib.sha256(graph).hexdigest(), "revision":21,
       "mappings":[
           {"node_id":1,"project_id":"forge:acme/repo-a","family_id":"canonical-family-a","state":"accepted","reviewer_id":91,"reviewed_at":1700000000,"evidence_sha256":"a"*64},
           {"node_id":3,"project_id":"forge:acme/repo-c","family_id":"canonical-family-a","state":"accepted","reviewer_id":92,"reviewed_at":1700000000,"evidence_sha256":"b"*64},
       ]}
json.dump(doc, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" downstream --graph "$T/graph.json" --subject 0 --out "$T/downstream" --project-map "$T/project-map.json" --known-as-of 1800000000 >/dev/null || fail "downstream identity source"
python3 - "$T/in.json" "$T/identity-in.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
for dependent, graph_node_id in zip(doc["dependents"], [1, 2, 3]):
    dependent["graph_node_id"] = graph_node_id
json.dump(doc, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" population --input "$T/identity-in.json" --downstream "$T/downstream/downstream.json" --out "$T/identity-out.json" >/dev/null || fail "population project identity join"
python3 - "$T/identity-in.json" "$T/downstream/downstream.json" "$T/identity-out.json" <<'PY'
import hashlib, json, pathlib, sys
population, downstream, output = [pathlib.Path(path) for path in sys.argv[1:]]
result = json.loads(output.read_bytes())
assert result["schema"] == "rh-population-result/2", result
assert result["project_identity_mapping"] == {"revision":21,"selected":3,"accepted":2,"unknown":1,"distinct_accepted_families":1}, result
rows = {row["graph_node_id"]: row["project_identity"] for row in result["dependents"]}
assert rows[1]["project_id"] == "forge:acme/repo-a" and rows[1]["reviewer_id"] == 91, rows
assert rows[2]["mapping_status"] == "unknown" and rows[2]["project_id"] is None, rows
assert rows[3]["family_id"] == "canonical-family-a" and rows[3]["evidence_sha256"] == "b"*64, rows
sidecar = json.loads(pathlib.Path(str(output)+".transformations.json").read_bytes())
population_raw, downstream_raw = population.read_bytes(), downstream.read_bytes()
framed = (b"rh-population-identity-input/1\npopulation:" + str(len(population_raw)).encode() + b":" + population_raw
          + b"\ndownstream:" + str(len(downstream_raw)).encode() + b":" + downstream_raw)
assert sidecar["source_input_sha256"] == hashlib.sha256(framed).hexdigest(), sidecar
assert sidecar["normalized_output_sha256"] == hashlib.sha256(output.read_bytes()).hexdigest(), sidecar
assert sidecar["output_schema"] == "rh-population-result/2", sidecar
assert sidecar["configuration_sha256"] == hashlib.sha256(b"repo-health/focal-library-population/4;dependents=1000;unresolved=1000;metrics=63;identity-join=true").hexdigest(), sidecar
print("[population] canonical identity, unknown coverage, and input binding OK")
PY
python3 - "$T/identity-in.json" "$T/missing-node-key.json" "$T/unselected-node-key.json" "$T/duplicate-node-key.json" "$T/bad-downstream.json" <<'PY'
import copy, json, sys
base = json.load(open(sys.argv[1]))
missing = copy.deepcopy(base); del missing["dependents"][0]["graph_node_id"]
unselected = copy.deepcopy(base); unselected["dependents"][0]["graph_node_id"] = 99
duplicate = copy.deepcopy(base); duplicate["dependents"][2]["graph_node_id"] = 1
for value, path in zip((missing, unselected, duplicate), sys.argv[2:5]):
    json.dump(value, open(path, "w"), separators=(",", ":"))
downstream = json.load(open("/tmp/rh-population/downstream/downstream.json"))
downstream["project_identities"]["coverage"]["accepted"] += 1
json.dump(downstream, open(sys.argv[5], "w"), separators=(",", ":"))
PY
set +e
"$ROOT/build/rh_cli" population --input "$T/missing-node-key.json" --downstream "$T/downstream/downstream.json" --out "$T/x.json" >/dev/null 2>&1; rc_missing_node=$?
"$ROOT/build/rh_cli" population --input "$T/unselected-node-key.json" --downstream "$T/downstream/downstream.json" --out "$T/x.json" >/dev/null 2>&1; rc_unselected_node=$?
"$ROOT/build/rh_cli" population --input "$T/duplicate-node-key.json" --downstream "$T/downstream/downstream.json" --out "$T/x.json" >/dev/null 2>&1; rc_duplicate_node=$?
"$ROOT/build/rh_cli" population --input "$T/identity-in.json" --downstream "$T/bad-downstream.json" --out "$T/x.json" >/dev/null 2>&1; rc_bad_downstream=$?
set -e
[[ "$rc_missing_node" -eq 4 && "$rc_unselected_node" -eq 4 && "$rc_duplicate_node" -eq 4 && "$rc_bad_downstream" -eq 4 ]] || fail "invalid project identity joins must exit 4 (got $rc_missing_node/$rc_unselected_node/$rc_duplicate_node/$rc_bad_downstream)"

echo "[population] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" population --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "population output not deterministic"
cmp -s "$T/out.json.transformations.json" "$T/out2.json.transformations.json" || fail "population transformation report not deterministic"
set +e
sed 's/"discovery_context":"cargo registry snapshot; focal release 1.2.0",//' "$T/in.json" > "$T/missing-context.json"
"$ROOT/build/rh_cli" population --input "$T/missing-context.json" --out "$T/x" >/dev/null 2>&1; rc_context=$?
sed 's/"truncated":true/"truncated":"yes"/' "$T/in.json" > "$T/bad-bool.json"
"$ROOT/build/rh_cli" population --input "$T/bad-bool.json" --out "$T/x" >/dev/null 2>&1; rc_bool=$?
sed 's/"mapping_revision":4/"mapping_revision":-1/' "$T/in.json" > "$T/bad-revision.json"
"$ROOT/build/rh_cli" population --input "$T/bad-revision.json" --out "$T/x" >/dev/null 2>&1; rc_revision=$?
sed 's/"path_witness":\["service","acme-core"\]/"path_witness":[]/' "$T/in.json" > "$T/bad-path.json"
"$ROOT/build/rh_cli" population --input "$T/bad-path.json" --out "$T/x" >/dev/null 2>&1; rc_path=$?
sed 's/"path_witness":\["service","acme-core"\]/"path_witness":["service","other-package"]/' "$T/in.json" > "$T/bad-path-target.json"
"$ROOT/build/rh_cli" population --input "$T/bad-path-target.json" --out "$T/x" >/dev/null 2>&1; rc_path_target=$?
sed 's/"id":"repo-c"/"id":"repo-a"/' "$T/in.json" > "$T/bad-duplicate.json"
"$ROOT/build/rh_cli" population --input "$T/bad-duplicate.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate=$?
sed 's/"status":"unknown","value":null/"status":"unknown","value":1/' "$T/in.json" > "$T/bad-value.json"
"$ROOT/build/rh_cli" population --input "$T/bad-value.json" --out "$T/x" >/dev/null 2>&1; rc_value=$?
sed 's/"status":"unknown","value":null,"policy":"unknown"/"status":"unknown","value":null,"policy":"pass"/' "$T/in.json" > "$T/bad-policy-state.json"
"$ROOT/build/rh_cli" population --input "$T/bad-policy-state.json" --out "$T/x" >/dev/null 2>&1; rc_policy_state=$?
python3 - "$T/in.json" "$T/bad-duplicate-root-key.json" "$T/bad-duplicate-cell-key.json" <<'PY'
import sys
source = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(source.replace('"truncated":true', '"truncated":true,"truncated":false', 1))
open(sys.argv[3], "w").write(source.replace('"status":"unknown","value":null', '"status":"unknown","status":"observed","value":null', 1))
PY
"$ROOT/build/rh_cli" population --input "$T/bad-duplicate-root-key.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate_root=$?
"$ROOT/build/rh_cli" population --input "$T/bad-duplicate-cell-key.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate_cell=$?
sed 's/"provider_status":"rate_limit"/"provider_status":"mystery"/' "$T/in.json" > "$T/bad-provider.json"
"$ROOT/build/rh_cli" population --input "$T/bad-provider.json" --out "$T/x" >/dev/null 2>&1; rc_provider=$?
sed 's/"relation":"direct"/"relation":"indirect"/' "$T/in.json" > "$T/bad-relation.json"
"$ROOT/build/rh_cli" population --input "$T/bad-relation.json" --out "$T/x" >/dev/null 2>&1; rc_relation=$?
sed 's/"path_witness":\["tool","dep","acme-core"\]/"path_witness":["tool","acme-core"]/' "$T/in.json" > "$T/bad-path-relation.json"
"$ROOT/build/rh_cli" population --input "$T/bad-path-relation.json" --out "$T/x" >/dev/null 2>&1; rc_path_relation=$?
sed 's/"path_witness":\["tool","dep","acme-core"\]/"path_witness":["tool","dep","tool","acme-core"]/' "$T/in.json" > "$T/bad-path-cycle.json"
"$ROOT/build/rh_cli" population --input "$T/bad-path-cycle.json" --out "$T/x" >/dev/null 2>&1; rc_path_cycle=$?
sed 's/"value":5/"value":-1/' "$T/in.json" > "$T/bad-negative-value.json"
"$ROOT/build/rh_cli" population --input "$T/bad-negative-value.json" --out "$T/x" >/dev/null 2>&1; rc_negative=$?
python3 - "$T/in.json" "$T/bad-overflow.json" "$T/bad-dependent-cap.json" "$T/bad-metric-cap.json" "$T/bad-unresolved-cap.json" <<'PY'
import copy, json, sys
base = json.load(open(sys.argv[1]))
overflow = copy.deepcopy(base)
overflow["dependents"][1]["metrics"][1]["value"] = 9223372036854775807
overflow["dependents"][2]["metrics"][1]["value"] = 1
json.dump(overflow, open(sys.argv[2], "w"), separators=(",", ":"))
too_many = copy.deepcopy(base)
template = too_many["dependents"][0]
too_many["dependents"] = [dict(template, id=f"repo-{i}", family=f"family-{i}") for i in range(1001)]
json.dump(too_many, open(sys.argv[3], "w"), separators=(",", ":"))
too_many_metrics = copy.deepcopy(base)
too_many_metrics["metric_definitions"] = [{"key":f"metric.{i}", "version":"1"} for i in range(64)]
json.dump(too_many_metrics, open(sys.argv[4], "w"), separators=(",", ":"))
too_many_unresolved = copy.deepcopy(base)
too_many_unresolved["unresolved"] = [{"package":f"unknown-{i}", "reason":"mapping review required"} for i in range(1001)]
json.dump(too_many_unresolved, open(sys.argv[5], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" population --input "$T/bad-overflow.json" --out "$T/x" >/dev/null 2>&1; rc_overflow=$?
"$ROOT/build/rh_cli" population --input "$T/bad-dependent-cap.json" --out "$T/x" >/dev/null 2>&1; rc_dependent_cap=$?
"$ROOT/build/rh_cli" population --input "$T/bad-metric-cap.json" --out "$T/x" >/dev/null 2>&1; rc_metric_cap=$?
"$ROOT/build/rh_cli" population --input "$T/bad-unresolved-cap.json" --out "$T/x" >/dev/null 2>&1; rc_unresolved_cap=$?
set -e
[[ "$rc_context" -eq 4 && "$rc_bool" -eq 4 && "$rc_revision" -eq 4 && "$rc_path" -eq 4 && "$rc_path_target" -eq 4 && "$rc_duplicate" -eq 4 && "$rc_value" -eq 4 && "$rc_policy_state" -eq 4 && "$rc_duplicate_root" -eq 4 && "$rc_duplicate_cell" -eq 4 && "$rc_provider" -eq 4 && "$rc_relation" -eq 4 && "$rc_path_relation" -eq 4 && "$rc_path_cycle" -eq 4 && "$rc_negative" -eq 4 && "$rc_overflow" -eq 4 && "$rc_dependent_cap" -eq 4 && "$rc_metric_cap" -eq 4 && "$rc_unresolved_cap" -eq 4 ]] || fail "invalid population must exit 4 (got context=$rc_context, bool=$rc_bool, revision=$rc_revision)"

echo "test_population_cli OK"
