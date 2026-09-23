#!/usr/bin/env bash
# M05-08 accepted role-evidence shared-maintenance overlap.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-maintenance-exposure"
fail() { echo "[maintenance-exposure] FAIL: $1" >&2; exit 1; }

echo "[maintenance-exposure] build"
bash "$ROOT/tools/build.sh" >/dev/null
rm -rf "$T"; mkdir -p "$T/evidence-store"
for evidence in focus direct independent; do
  cp "$ROOT/fixtures/packages/maintenance-evidence-$evidence.json" "$T/$evidence.json"
  "$ROOT/build/rh_cli" store put --root "$T/evidence-store" --file "$T/$evidence.json" >/dev/null || fail "store mapping evidence"
done
cat > "$T/input.json" <<'JSON'
{"schema":"rh-maintenance-exposure-input/1","subject_node":0,"mapping_revision":7,"graph":{"schema":"rh-dep-graph/1","ecosystem":"npm","nodes":[{"id":0,"name":"focus","version":"1"},{"id":1,"name":"direct","version":"1"},{"id":2,"name":"independent","version":"1"},{"id":3,"name":"transitive","version":"1"}],"edges":[{"from":1,"to":0,"scope":"normal"},{"from":2,"to":0,"scope":"normal"},{"from":3,"to":1,"scope":"normal"}],"unresolved":[],"advisories":[]},"mappings":[{"node":0,"state":"accepted","reviewed_by":"reviewer-1","reviewed_at":100,"complete":true,"evidence_ref":"96d3200798f3edf1","role_evidence":{"schema":"rh-role-grain-result/1","identity_revision":3,"current_event_ledger":[{"id":"e1","actor":"alice","role":"author","at":1},{"id":"e2","actor":"bob","role":"reviewer","at":2},{"id":"e3","actor":"alice","role":"releaser","at":3}]}},{"node":1,"state":"accepted","reviewed_by":"reviewer-2","reviewed_at":101,"complete":true,"evidence_ref":"740acca16a077aeb","role_evidence":{"schema":"rh-role-grain-result/1","identity_revision":4,"current_event_ledger":[{"id":"e4","actor":"bob","role":"committer","at":4},{"id":"e5","actor":"carol","role":"reviewer","at":5}]}},{"node":2,"state":"accepted","reviewed_by":"reviewer-2","reviewed_at":102,"complete":true,"evidence_ref":"0bb9f1ee129e3809","role_evidence":{"schema":"rh-role-grain-result/1","identity_revision":4,"current_event_ledger":[{"id":"e6","actor":"dave","role":"committer","at":6}]}}]}
JSON
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
assert pairs[1]["subject_evidence_ref"] == "96d3200798f3edf1" and pairs[1]["dependent_evidence_ref"] == "740acca16a077aeb", pairs[1]
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
    ("bad-role", lambda x: x["mappings"][0]["role_evidence"].update(schema="rh-role-grain-result/2")),
    ("bad-ledger", lambda x: x["mappings"][0]["role_evidence"]["current_event_ledger"][0].update(role="maintainer")),
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
for bad in unaccepted bad-evidence missing-evidence bad-role bad-ledger duplicate; do
  set +e
  "$ROOT/build/rh_cli" maintenance-exposure --input "$T/$bad.json" --out "$T/$bad.out" --evidence-store "$T/evidence-store" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 4 && ! -e "$T/$bad.out" ]] || fail "$bad mapping must fail closed (got $rc)"
done
cp "$T/evidence-store/96d3200798f3edf1" "$T/evidence-backup"
printf 'corrupted evidence\n' > "$T/evidence-store/96d3200798f3edf1"
set +e
"$ROOT/build/rh_cli" maintenance-exposure --input "$T/input.json" --out "$T/corrupt.out" --evidence-store "$T/evidence-store" >/dev/null 2>&1
corrupt_rc=$?
set -e
cp "$T/evidence-backup" "$T/evidence-store/96d3200798f3edf1"
[[ "$corrupt_rc" -eq 4 && ! -e "$T/corrupt.out" ]] || fail "corrupt content-addressed evidence must fail closed (got $corrupt_rc)"
echo "test_maintenance_exposure_cli OK"
