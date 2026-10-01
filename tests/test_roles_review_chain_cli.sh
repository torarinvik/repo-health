#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
T="$(mktemp -d /tmp/rh-roles-review-chain.XXXXXX)"
trap 'rm -rf "$T"' EXIT
fail() { echo "[roles-review-chain] FAIL: $1" >&2; exit 1; }

bash "$ROOT/tools/build.sh" >/dev/null
"$ROOT/build/rh_cli" roles-review-chain \
  --input "fixtures/roles-review-chain/source-result.json" \
  --out "$T/roles-input.json" >/dev/null || fail "normalize review-chain result"
cmp "$ROOT/fixtures/roles-review-chain/input.json" "$T/roles-input.json" || fail "canonical roles input changed"

python3 - "$T/roles-input.json" "$T/roles-input.json.transformations.json" "$ROOT/fixtures/roles-review-chain/source-result.json" <<'PY'
import hashlib, json, sys
roles_path, sidecar_path, source_path = sys.argv[1:]
roles = json.load(open(roles_path))
sidecar = json.load(open(sidecar_path))
assert roles["provider"] == "github" and roles["scope"] == {"repository":"example/project"}, roles
assert roles["linked_change_population"] == {
    "source":"github-review-chain", "repository":"example/project", "as_of":1700000100,
    "collection_status":"complete", "status":"partial", "atomic_snapshot":False,
    "source_sha256":hashlib.sha256(open(source_path,"rb").read()).hexdigest(),
    "reason":"github-pull-list-pagination-non-atomic",
}, roles
assert [(row["kind"], row["change_id"]) for row in roles["observed_actions"]] == [
    ("merge","7"), ("merge","9"), ("review","7"), ("review","7")
], roles
assert all(row["actor_id"] is None for row in roles["observed_actions"]), roles
assert "github:55" not in open(roles_path).read(), "reviewer identity leaked"
assert sidecar["adapter"] == "github-review-chain-roles", sidecar
assert sidecar["source_input_sha256"] == hashlib.sha256(open(source_path,"rb").read()).hexdigest(), sidecar
assert sidecar["normalized_output_sha256"] == hashlib.sha256(open(roles_path,"rb").read()).hexdigest(), sidecar
assert sidecar["fields"][2]["state"] == "partial", sidecar
print("[roles-review-chain] bounded projection preserves linkage and source limits")
PY

"$ROOT/build/rh_cli" roles --input "$T/roles-input.json" --out "$T/roles-report.json" >/dev/null || fail "roles report from projected input"
python3 - "$T/roles-report.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
assert report["change_review_source"]["status"] == "partial", report
assert report["change_review"]["status"] == "partial", report
assert report["change_review"]["numerator"] is None and report["change_review"]["denominator"] is None, report
assert report["change_review"]["observed_lower_bound"] == {"numerator":1,"denominator":2}, report
metrics = {row["key"]: row for row in report["metrics"]}
for key, count in (("maintainer.reviewed_merge_change_count",1), ("maintainer.linked_merge_change_count",2)):
    assert metrics[key]["status"] == "partial" and metrics[key]["value"] == count, metrics[key]
print("[roles-review-chain] reports lower bounds without asserting a full-population ratio")
PY

python3 - "$T" "$ROOT/fixtures/roles-review-chain/source-result.json" <<'PY'
import copy, json, pathlib, sys
target = pathlib.Path(sys.argv[1])
base = json.load(open(sys.argv[2]))
def write(name, value):
    (target / name).write_text(json.dumps(value, separators=(",",":")))
partial = copy.deepcopy(base)
partial.update(status="partial", complete=False)
write("partial.json", partial)
future = copy.deepcopy(base)
future["pull_requests"][0]["merged_at"] = future["as_of"] + 1
write("future.json", future)
unknown = copy.deepcopy(base)
unknown["review_events"].append({"native_id":"github:999","pull_request":999,"submitted_at":1700000000,"status":"APPROVED"})
unknown["review_event_count"] += 1
write("unknown-pull.json", unknown)
bad_count = copy.deepcopy(base)
bad_count["merged_pull_request_count"] += 1
write("bad-count.json", bad_count)
duplicate = copy.deepcopy(base)
duplicate["pull_requests"][2]["number"] = duplicate["pull_requests"][0]["number"]
write("duplicate-pull.json", duplicate)
oversized = copy.deepcopy(base)
oversized["pull_requests"] = [{"number":n,"merged_at":1700000000} for n in range(1,4002)]
oversized["pull_request_count"] = len(oversized["pull_requests"])
oversized["merged_pull_request_count"] = len(oversized["pull_requests"])
oversized["review_events"] = []
oversized["review_event_count"] = 0
write("oversized.json", oversized)
PY

"$ROOT/build/rh_cli" roles-review-chain --input "$T/partial.json" --out "$T/partial-input.json" >/dev/null || fail "partial review chain"
python3 - "$T/partial-input.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["linked_change_population"]["collection_status"] == "partial", d
assert d["linked_change_population"]["status"] == "partial", d
assert d["linked_change_population"]["reason"] == "review-chain-cursor-incomplete", d
print("[roles-review-chain] cursor incompleteness remains explicit")
PY

set +e
for name in future unknown-pull bad-count duplicate-pull oversized; do
  "$ROOT/build/rh_cli" roles-review-chain --input "$T/$name.json" --out "$T/invalid-$name.json" >/dev/null 2>&1
  rc=$?
  [[ "$rc" -eq 4 ]] || { set -e; fail "$name source must fail closed (got $rc)"; }
done
set -e
echo "[roles-review-chain] malformed, temporally inconsistent, and oversized sources fail closed"
echo "test_roles_review_chain_cli OK"
