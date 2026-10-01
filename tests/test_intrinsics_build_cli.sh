#!/usr/bin/env bash
# M05-06: assemble independent continuity/role reports for downstream joins.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/rh-intrinsics-build.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fail() { echo "[intrinsics-build] FAIL: $1" >&2; exit 1; }

bash "$ROOT/tools/build.sh" >/dev/null
python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/history" --history-commits 12
"$ROOT/build/rh_cli" scan --repo "$T/history/history/repo" --out "$T/full" --full-history >/dev/null || fail "full-history scan"
"$ROOT/build/rh_cli" scan --repo "$T/history/history/repo" --out "$T/windowed" --window-days 365 >/dev/null || fail "windowed scan"
"$ROOT/build/rh_cli" continuity --bundle "$T/full/bundle.manifest" --out "$T/full-continuity" >/dev/null || fail "full continuity"
"$ROOT/build/rh_cli" continuity --bundle "$T/windowed/bundle.manifest" --out "$T/windowed-continuity" >/dev/null || fail "windowed continuity"

python3 - "$T" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
window = json.load(open(root / "full-continuity/continuity-metrics.json"))["observation_window"]
base = {"schema":"rh-roles-input/1", "provider":"github", "scope":{"repository":"example/project"}, "as_of":1700001000,
        "linked_change_population":{"source":"github-review-chain","repository":"example/project","as_of":1700001000,
          "collection_status":"complete","status":"complete","atomic_snapshot":True,
          "source_sha256":"a"*64,"reason":""}, "observed_actions_window":window,
        "authorization":{"state":"authorized"}, "permission_inventory_complete":True,
        "as_of":1700001000, "declarations":[], "observed_actions":[
          {"actor_id":1,"actor_type":"human","kind":"release","at":1700000000},
          {"actor_id":2,"actor_type":"unknown","kind":"release","at":1700000010},
          {"actor_id":1,"actor_type":"bot","kind":"release","at":1700000015},
          {"actor_id":3,"actor_type":"bot","kind":"review","at":1700000020},
          {"actor_id":4,"actor_type":"human","kind":"review","at":1700000030},
          {"actor_id":3,"actor_type":"human","kind":"review","at":1700000035},
          {"actor_id":5,"kind":"merge","at":1700000040,"change_id":"pr-10"},
          {"actor_id":3,"kind":"review","at":1700000045,"change_id":"pr-10"}],
        "queries":[], "permission_queries":[]}
(root / "roles-input.json").write_text(json.dumps(base))
unsupported = {"schema":"rh-roles-input/1", "observed_actions_window":window,
               "authorization":{"state":"not_requested"}, "declarations":[],
               "queries":[], "permission_queries":[]}
(root / "roles-unsupported-input.json").write_text(json.dumps(unsupported))
partial = dict(base)
partial["linked_change_population"] = {"source":"github-review-chain","repository":"example/project","as_of":1700001000,
    "collection_status":"complete","status":"partial","atomic_snapshot":False,
    "source_sha256":"b"*64,"reason":"github-pull-list-pagination-non-atomic"}
(root / "roles-partial-input.json").write_text(json.dumps(partial))
PY
"$ROOT/build/rh_cli" roles --input "$T/roles-input.json" --out "$T/roles.json" >/dev/null || fail "roles source"
"$ROOT/build/rh_cli" roles --input "$T/roles-unsupported-input.json" --out "$T/roles-unsupported.json" >/dev/null || fail "unsupported roles source"
"$ROOT/build/rh_cli" roles --input "$T/roles-partial-input.json" --out "$T/roles-partial.json" >/dev/null || fail "partial roles source"

python3 - "$T" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
value = {
    "schema": "rh-intrinsics-source-set/1",
    "dependents": [
        {"id": 1,
         "continuity_metrics": json.loads((root / "full-continuity/continuity-metrics.json").read_bytes()),
         "roles": json.loads((root / "roles.json").read_bytes())},
        {"id": 2,
         "continuity_metrics": json.loads((root / "full-continuity/continuity-metrics.json").read_bytes()),
         "roles": json.loads((root / "roles-unsupported.json").read_bytes())},
    ],
}
(root / "source-set.json").write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
PY

"$ROOT/build/rh_cli" intrinsics-build --input "$T/source-set.json" --out "$T/intrinsics.json" >/dev/null || fail "build intrinsic observations"
python3 - "$T/source-set.json" "$T/intrinsics.json" <<'PY'
import hashlib, json, sys
source, output = sys.argv[1:]
actual = json.load(open(output))
assert actual["schema"] == "rh-intrinsics/2", actual
assert actual["metrics"] == ["persistence.persistent_12m", "maintainer.observed_release_actors", "maintainer.observed_review_actors", "maintainer.reviewed_merge_change_count", "maintainer.linked_merge_change_count"], actual
assert actual["values"] == [
    {"id": 1, "mask": 31, "observations": [1, 2, 2, 1, 1]},
    {"id": 2, "mask": 1, "observations": [1, None, None, None, None]},
], actual
report = json.load(open(output + ".transformations.json"))
assert report["adapter"] == "independent-intrinsics-assembly", report
assert report["source_input_sha256"] == hashlib.sha256(open(source, "rb").read()).hexdigest(), report
assert report["normalized_output_sha256"] == hashlib.sha256(open(output, "rb").read()).hexdigest(), report
assert report["configuration_sha256"] == hashlib.sha256(b"repo-health/independent-intrinsics-assembly/2").hexdigest(), report
roles = json.load(open(source))["dependents"][0]["roles"]
assert roles["action_events_by_actor_type"]["release"]["human"] + roles["action_events_by_actor_type"]["release"]["bot"] + roles["action_events_by_actor_type"]["release"]["unknown"] == 3, roles
print("[intrinsics-build] independent source reports yield exact values and explicit missing coverage")
PY

python3 - "$T/full-continuity/continuity-metrics.json" "$T/roles-partial.json" "$T/partial-source-set.json" <<'PY'
import json, sys
continuity, roles, target = sys.argv[1:]
value = {"schema":"rh-intrinsics-source-set/1", "dependents":[
    {"id":3, "continuity_metrics":json.load(open(continuity)), "roles":json.load(open(roles))}]}
json.dump(value, open(target,"w"), sort_keys=True, separators=(",",":"))
PY
"$ROOT/build/rh_cli" intrinsics-build --input "$T/partial-source-set.json" --out "$T/partial-intrinsics.json" >/dev/null || fail "build partial intrinsic observations"
python3 - "$T/partial-intrinsics.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
assert value["values"] == [{"id":3,"mask":7,"observations":[1,2,2,None,None]}], value
print("[intrinsics-build] partial change populations stay out of exact pooled count pairs")
PY

cat > "$T/graph.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"fixture","nodes":[{"id":0,"name":"subject","version":"1"},{"id":1,"name":"dependent-a","version":"1"},{"id":2,"name":"dependent-b","version":"1"}],"edges":[{"from":1,"to":0,"scope":"normal"},{"from":2,"to":0,"scope":"normal"}],"unresolved":[],"advisories":[]}
JSON
"$ROOT/build/rh_cli" downstream --graph "$T/graph.json" --subject 0 --out "$T/downstream" --intrinsics "$T/intrinsics.json" >/dev/null || fail "downstream join"
python3 - "$T/downstream/downstream.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
assert report["intrinsics"]["dependent_total"] == 2, report["intrinsics"]
coverage = {item["key"]: item for item in report["intrinsics"]["covered"]}
assert {key: value["observed"] for key, value in coverage.items()} == {
    "persistence.persistent_12m": 2,
    "maintainer.observed_release_actors": 1,
    "maintainer.observed_review_actors": 1,
    "maintainer.reviewed_merge_change_count": 1,
    "maintainer.linked_merge_change_count": 1,
}, coverage
assert coverage["persistence.persistent_12m"]["distribution"] == [1, 1], coverage
assert coverage["maintainer.observed_release_actors"]["distribution"] == [2], coverage
assert coverage["maintainer.observed_review_actors"]["distribution"] == [2], coverage
assert coverage["maintainer.reviewed_merge_change_count"]["distribution"] == [1], coverage
assert coverage["maintainer.linked_merge_change_count"]["distribution"] == [1], coverage
print("[intrinsics-build] downstream reports metric-specific denominators and distributions")
PY

python3 - "$T/source-set.json" "$T/duplicate.json" "$T/overflow.json" "$T/duplicate-key.json" "$T/window-mismatch.json" "$T/bad-review-count.json" "$T/missing-review-denominator.json" "$T/not-applicable-review-denominator.json" "$T/unproven-review.json" <<'PY'
import json, sys
source = json.load(open(sys.argv[1]))
duplicate = json.loads(json.dumps(source))
overflow = json.loads(json.dumps(source))
bad_review_count = json.loads(json.dumps(source))
missing_review_denominator = json.loads(json.dumps(source))
not_applicable_review_denominator = json.loads(json.dumps(source))
duplicate["dependents"].append(duplicate["dependents"][0])
json.dump(duplicate, open(sys.argv[2], "w"), separators=(",", ":"))
next(metric for metric in overflow["dependents"][0]["roles"]["metrics"]
     if metric["key"] == "maintainer.observed_release_actors")["value"] = 9223372036854775808
json.dump(overflow, open(sys.argv[3], "w"), separators=(",", ":"))
text = open(sys.argv[1]).read()
text = text.replace('"schema":"rh-roles-result/1"', '"schema":"rh-roles-result/1","schema":"rh-roles-result/1"', 1)
open(sys.argv[4], "w").write(text)
mismatch = json.loads(json.dumps(source))
mismatch["dependents"][0]["roles"]["observed_actions_window"]["end"] += 1
json.dump(mismatch, open(sys.argv[5], "w"), separators=(",", ":"))
bad_review_count["dependents"][0]["roles"]["change_review"]["numerator"] = 2
json.dump(bad_review_count, open(sys.argv[6], "w"), separators=(",", ":"))
del missing_review_denominator["dependents"][0]["roles"]["change_review"]["denominator"]
json.dump(missing_review_denominator, open(sys.argv[7], "w"), separators=(",", ":"))
not_applicable_review_denominator["dependents"][0]["roles"]["change_review"] = {"status":"not_applicable","numerator":None,"denominator":5}
json.dump(not_applicable_review_denominator, open(sys.argv[8], "w"), separators=(",", ":"))
unproven_review = json.loads(json.dumps(source))
unproven_review["dependents"][0]["roles"].pop("change_review_source", None)
json.dump(unproven_review, open(sys.argv[9], "w"), separators=(",", ":"))
PY
set +e
"$ROOT/build/rh_cli" intrinsics-build --input "$T/duplicate.json" --out "$T/invalid-duplicate.json" >/dev/null 2>&1; duplicate_rc=$?
"$ROOT/build/rh_cli" intrinsics-build --input "$T/overflow.json" --out "$T/invalid-overflow.json" >/dev/null 2>&1; overflow_rc=$?
"$ROOT/build/rh_cli" intrinsics-build --input "$T/duplicate-key.json" --out "$T/invalid-key.json" >/dev/null 2>&1; duplicate_key_rc=$?
"$ROOT/build/rh_cli" intrinsics-build --input "$T/window-mismatch.json" --out "$T/invalid-window.json" >/dev/null 2>&1; window_rc=$?
"$ROOT/build/rh_cli" intrinsics-build --input "$T/bad-review-count.json" --out "$T/invalid-review-count.json" >/dev/null 2>&1; review_count_rc=$?
"$ROOT/build/rh_cli" intrinsics-build --input "$T/missing-review-denominator.json" --out "$T/invalid-review-denominator.json" >/dev/null 2>&1; review_denominator_rc=$?
"$ROOT/build/rh_cli" intrinsics-build --input "$T/not-applicable-review-denominator.json" --out "$T/invalid-not-applicable-review-denominator.json" >/dev/null 2>&1; not_applicable_review_denominator_rc=$?
"$ROOT/build/rh_cli" intrinsics-build --input "$T/unproven-review.json" --out "$T/invalid-unproven-review.json" >/dev/null 2>&1; unproven_review_rc=$?
set -e
[[ "$duplicate_rc" -eq 4 && "$overflow_rc" -eq 4 && "$duplicate_key_rc" -eq 4 && "$window_rc" -eq 4 && "$review_count_rc" -eq 4 && "$review_denominator_rc" -eq 4 && "$not_applicable_review_denominator_rc" -eq 4 && "$unproven_review_rc" -eq 4 ]] || fail "malformed source sets must fail closed"
echo "[intrinsics-build] duplicate dependents/keys, mismatched windows, out-of-range values, and unproven linked populations fail closed"
echo "test_intrinsics_build_cli OK"
