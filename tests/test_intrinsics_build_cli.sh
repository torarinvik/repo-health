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

cat > "$T/roles-input.json" <<'JSON'
{"schema":"rh-roles-input/1","authorization":{"state":"authorized"},"permission_inventory_complete":true,"as_of":1700001000,"declarations":[],"observed_actions":[{"actor_id":1,"actor_type":"human","kind":"release","at":1700000000},{"actor_id":2,"actor_type":"unknown","kind":"release","at":1700000010},{"actor_id":1,"actor_type":"bot","kind":"release","at":1700000015},{"actor_id":3,"actor_type":"bot","kind":"review","at":1700000020},{"actor_id":4,"actor_type":"human","kind":"review","at":1700000030},{"actor_id":3,"actor_type":"human","kind":"review","at":1700000035}],"queries":[],"permission_queries":[]}
JSON
cat > "$T/roles-unsupported-input.json" <<'JSON'
{"schema":"rh-roles-input/1","authorization":{"state":"not_requested"},"declarations":[],"queries":[],"permission_queries":[]}
JSON
"$ROOT/build/rh_cli" roles --input "$T/roles-input.json" --out "$T/roles.json" >/dev/null || fail "roles source"
"$ROOT/build/rh_cli" roles --input "$T/roles-unsupported-input.json" --out "$T/roles-unsupported.json" >/dev/null || fail "unsupported roles source"

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
         "continuity_metrics": json.loads((root / "windowed-continuity/continuity-metrics.json").read_bytes()),
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
assert actual["metrics"] == ["persistence.persistent_12m", "maintainer.observed_release_actors", "maintainer.observed_review_actors"], actual
assert actual["values"] == [
    {"id": 1, "mask": 7, "observations": [1, 2, 2]},
    {"id": 2, "mask": 0, "observations": [None, None, None]},
], actual
report = json.load(open(output + ".transformations.json"))
assert report["adapter"] == "independent-intrinsics-assembly", report
assert report["source_input_sha256"] == hashlib.sha256(open(source, "rb").read()).hexdigest(), report
assert report["normalized_output_sha256"] == hashlib.sha256(open(output, "rb").read()).hexdigest(), report
assert report["configuration_sha256"] == hashlib.sha256(b"repo-health/independent-intrinsics-assembly/1").hexdigest(), report
roles = json.load(open(source))["dependents"][0]["roles"]
assert roles["action_events_by_actor_type"]["release"]["human"] + roles["action_events_by_actor_type"]["release"]["bot"] + roles["action_events_by_actor_type"]["release"]["unknown"] == 3, roles
print("[intrinsics-build] independent source reports yield exact values and explicit missing coverage")
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
    "persistence.persistent_12m": 1,
    "maintainer.observed_release_actors": 1,
    "maintainer.observed_review_actors": 1,
}, coverage
assert coverage["persistence.persistent_12m"]["distribution"] == [1], coverage
assert coverage["maintainer.observed_release_actors"]["distribution"] == [2], coverage
assert coverage["maintainer.observed_review_actors"]["distribution"] == [2], coverage
print("[intrinsics-build] downstream reports metric-specific denominators and distributions")
PY

python3 - "$T/source-set.json" "$T/duplicate.json" "$T/overflow.json" "$T/duplicate-key.json" <<'PY'
import json, sys
source = json.load(open(sys.argv[1]))
duplicate = json.loads(json.dumps(source))
overflow = json.loads(json.dumps(source))
duplicate["dependents"].append(duplicate["dependents"][0])
json.dump(duplicate, open(sys.argv[2], "w"), separators=(",", ":"))
next(metric for metric in overflow["dependents"][0]["roles"]["metrics"]
     if metric["key"] == "maintainer.observed_release_actors")["value"] = 9223372036854775808
json.dump(overflow, open(sys.argv[3], "w"), separators=(",", ":"))
text = open(sys.argv[1]).read()
text = text.replace('"schema":"rh-roles-result/1"', '"schema":"rh-roles-result/1","schema":"rh-roles-result/1"', 1)
open(sys.argv[4], "w").write(text)
PY
set +e
"$ROOT/build/rh_cli" intrinsics-build --input "$T/duplicate.json" --out "$T/invalid-duplicate.json" >/dev/null 2>&1; duplicate_rc=$?
"$ROOT/build/rh_cli" intrinsics-build --input "$T/overflow.json" --out "$T/invalid-overflow.json" >/dev/null 2>&1; overflow_rc=$?
"$ROOT/build/rh_cli" intrinsics-build --input "$T/duplicate-key.json" --out "$T/invalid-key.json" >/dev/null 2>&1; duplicate_key_rc=$?
set -e
[[ "$duplicate_rc" -eq 4 && "$overflow_rc" -eq 4 && "$duplicate_key_rc" -eq 4 ]] || fail "malformed source sets must fail closed"
echo "[intrinsics-build] duplicate dependents/keys and out-of-range metric values fail closed"
echo "test_intrinsics_build_cli OK"
