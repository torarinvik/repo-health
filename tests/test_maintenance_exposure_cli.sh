#!/usr/bin/env bash
# M05-08 accepted role-evidence shared-maintenance overlap.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-maintenance-exposure"
fail() { echo "[maintenance-exposure] FAIL: $1" >&2; exit 1; }

echo "[maintenance-exposure] build"
bash "$ROOT/tools/build.sh" >/dev/null
rm -rf "$T"; mkdir -p "$T/evidence-store"
for role in focus direct independent; do
  cp "$ROOT/fixtures/packages/maintenance-role-$role-input.json" "$T/$role-input.json"
  "$ROOT/build/rh_cli" role-grain --input "$T/$role-input.json" --out "$T/$role.role.json" >/dev/null || fail "role-grain evidence generation"
  "$ROOT/build/rh_cli" store put --root "$T/evidence-store" --file "$T/$role.role.json" | awk '{print $3}' > "$T/$role.ref" || fail "store role evidence"
done
python3 - "$T" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
graph = {"schema":"rh-dep-graph/1","ecosystem":"npm","nodes":[{"id":0,"name":"focus","version":"1"},{"id":1,"name":"direct","version":"1"},{"id":2,"name":"independent","version":"1"},{"id":3,"name":"transitive","version":"1"}],"edges":[{"from":1,"to":0,"scope":"normal"},{"from":2,"to":0,"scope":"normal"},{"from":3,"to":1,"scope":"normal"}],"unresolved":[],"advisories":[]}
mappings = []
for node, name, reviewer, reviewed_at in ((0,"focus","reviewer-1",100),(1,"direct","reviewer-2",101),(2,"independent","reviewer-2",102)):
    mappings.append({"node":node,"state":"accepted","reviewed_by":reviewer,"reviewed_at":reviewed_at,"complete":True,"evidence_ref":(root / (name + ".ref")).read_text().strip()})
result = {"schema":"rh-maintenance-exposure-input/1","subject_node":0,"mapping_revision":7,"graph":graph,"mappings":mappings}
(root / "input.json").write_text(json.dumps(result, separators=(",", ":")) + "\n")
PY
cmp "$ROOT/fixtures/packages/maintenance-exposure-input.json" "$T/input.json" || fail "input fixture drifted"
"$ROOT/build/rh_cli" maintenance-exposure --input "$T/input.json" --out "$T/out.json" --evidence-store "$T/evidence-store" >/dev/null || fail "valid exposure run"
cmp "$ROOT/fixtures/packages/maintenance-exposure-result.json" "$T/out.json" || fail "result fixture drifted"
python3 - "$T/input.json" "$T/out.json" <<'PY'
import hashlib, json, sys
source = open(sys.argv[1], "rb").read()
result = json.load(open(sys.argv[2]))
assert result["schema"] == "rh-maintenance-exposure-result/1", result
assert result["source_input_sha256"] == hashlib.sha256(source).hexdigest(), result
assert result["mapping_revision"] == 7 and result["subject_node"] == 0, result
pairs = {item["node"]: item for item in result["dependents"]}
assert pairs[1]["state"] == "known" and pairs[1]["shared_actor_count"] == 1, pairs[1]
assert pairs[2]["state"] == "known" and pairs[2]["shared_actor_count"] == 0, pairs[2]
assert pairs[3]["state"] == "unknown" and pairs[3]["shared_actor_count"] is None, pairs[3]
assert pairs[1]["subject_evidence_ref"] == "a8bfd272b8cf084f" and pairs[1]["dependent_evidence_ref"] == "2e0553b6fc918815", pairs[1]
assert result["known_pair_count"] == 2 and result["unknown_pair_count"] == 1, result
serialized = open(sys.argv[2], "rb").read().decode()
for actor in ("alice", "bob", "carol", "dave"):
    assert actor not in serialized, serialized
print("[maintenance-exposure] accepted evidence, overlap, unknowns, privacy, and lineage OK")
PY

python3 - "$T/input.json" "$T" <<'PY'
import json, os, sys
src, out = sys.argv[1:]
data = json.load(open(src))
for name, change in (
    ("unaccepted", lambda x: x["mappings"][0].update(state="proposed")),
    ("bad-evidence", lambda x: x["mappings"][0].update(evidence_ref="../secret")),
    ("missing-evidence", lambda x: x["mappings"][0].update(evidence_ref="1111111111111111")),
    ("duplicate", lambda x: x["mappings"].append(x["mappings"][0])),
):
    changed = json.loads(json.dumps(data))
    change(changed)
    with open(os.path.join(out, name + ".json"), "w") as f:
        json.dump(changed, f, separators=(",", ":"))
        f.write("\n")
PY
python3 - "$T/input.json" "$T/incomplete.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["mappings"][0]["complete"] = False
with open(sys.argv[2], "w") as f:
    json.dump(data, f, separators=(",", ":"))
    f.write("\n")
PY
"$ROOT/build/rh_cli" maintenance-exposure --input "$T/incomplete.json" --out "$T/incomplete.out" --evidence-store "$T/evidence-store" >/dev/null || fail "incomplete evidence should preserve unknown state"
python3 - "$T/incomplete.out" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
pairs = {item["node"]: item for item in result["dependents"]}
assert pairs[1]["state"] == "unknown" and pairs[1]["shared_actor_count"] is None, pairs[1]
assert result["unknown_pair_count"] == 3, result
print("[maintenance-exposure] incomplete accepted evidence remains unknown")
PY
for bad in unaccepted bad-evidence missing-evidence duplicate; do
  set +e
  "$ROOT/build/rh_cli" maintenance-exposure --input "$T/$bad.json" --out "$T/$bad.out" --evidence-store "$T/evidence-store" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 4 && ! -e "$T/$bad.out" ]] || fail "$bad mapping must fail closed (got $rc)"
done
python3 - "$T/focus.role.json" "$T/bad-schema.role.json" "$T/bad-role.role.json" <<'PY'
import json, sys
source = json.load(open(sys.argv[1]))
bad_schema = dict(source)
bad_schema["schema"] = "rh-role-grain-result/2"
bad_role = json.loads(json.dumps(source))
bad_role["current_event_ledger"][0]["role"] = "maintainer"
for path, result in zip(sys.argv[2:], (bad_schema, bad_role)):
    with open(path, "w") as f:
        json.dump(result, f, separators=(",", ":"))
        f.write("\n")
PY
bad_schema_ref="$("$ROOT/build/rh_cli" store put --root "$T/evidence-store" --file "$T/bad-schema.role.json" | awk '{print $3}')"
bad_role_ref="$("$ROOT/build/rh_cli" store put --root "$T/evidence-store" --file "$T/bad-role.role.json" | awk '{print $3}')"
python3 - "$T/input.json" "$T/bad-schema.json" "$bad_schema_ref" "$T/bad-role.json" "$bad_role_ref" <<'PY'
import json, sys
source = json.load(open(sys.argv[1]))
for target, ref in ((sys.argv[2], sys.argv[3]), (sys.argv[4], sys.argv[5])):
    data = json.loads(json.dumps(source))
    data["mappings"][0]["evidence_ref"] = ref
    with open(target, "w") as f:
        json.dump(data, f, separators=(",", ":"))
        f.write("\n")
PY
for bad in bad-schema bad-role; do
  set +e
  "$ROOT/build/rh_cli" maintenance-exposure --input "$T/$bad.json" --out "$T/$bad.out" --evidence-store "$T/evidence-store" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 4 && ! -e "$T/$bad.out" ]] || fail "malformed stored role report must fail closed (got $rc)"
done
focus_ref="$(cat "$T/focus.ref")"
cp "$T/evidence-store/$focus_ref" "$T/evidence-backup"
printf 'corrupted evidence\n' > "$T/evidence-store/$focus_ref"
set +e
"$ROOT/build/rh_cli" maintenance-exposure --input "$T/input.json" --out "$T/corrupt.out" --evidence-store "$T/evidence-store" >/dev/null 2>&1
corrupt_rc=$?
set -e
cp "$T/evidence-backup" "$T/evidence-store/$focus_ref"
[[ "$corrupt_rc" -eq 4 && ! -e "$T/corrupt.out" ]] || fail "corrupt content-addressed evidence must fail closed (got $corrupt_rc)"
echo "test_maintenance_exposure_cli OK"
