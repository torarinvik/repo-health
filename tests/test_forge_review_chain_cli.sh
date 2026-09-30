#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
T="$(mktemp -d /tmp/rh-forge-review-chain.XXXXXX)"
trap 'rm -rf "$T"' EXIT

tools/build.sh >/dev/null
"$ROOT/build/rh_cli" forge review-chain --input fixtures/forge-review-chain/input.json --out "$T/single-result.json" >/dev/null
cmp fixtures/forge-review-chain/result.json "$T/single-result.json"

python3 - "$T" <<'PY'
import copy, hashlib, json, pathlib, sys
t = pathlib.Path(sys.argv[1])
base = json.load(open("fixtures/connectors/forge-events-repository-reviews-result.json"))

def write(name, value):
    path = t / name
    path.write_text(json.dumps(value, separators=(",", ":")) + "\n")
    return path

first = copy.deepcopy(base)
first["captured_at"] = 1700000000
first["capabilities"]["reviews"].update(attempted=2, normalized=2, count=2)
first["pagination"]["reviews"]["complete"] = False
first["events"].append({"kind":"reviews","native_id":"github:56","status":"CHANGES_REQUESTED","created_at":1700000001,"updated_at":None,"closed_at":None,"pull_request":8})
first["review_collection"] = {
    "pending_pull_requests":[{"number":7,"next_review_page":2}],
    "batch_request":{"resumed_from_sha256":None,"pull_page":1,"review_pages":[]},
    "batch_pull_requests":[{"number":7,"merged_at":1700172800},{"number":8,"merged_at":None}],
    "next_pull_page":2,"pulls_complete":False,"complete":False
}
p1 = write("one.json", first)

second = copy.deepcopy(first)
second["captured_at"] = 1700000001
second["capabilities"]["reviews"].update(attempted=2, normalized=2, count=2)
second["events"] = [
    {"kind":"reviews","native_id":"github:55","status":"APPROVED","created_at":1700000002,"updated_at":None,"closed_at":None,"pull_request":7},
    {"kind":"reviews","native_id":"github:101","status":"COMMENTED","created_at":1700000003,"updated_at":None,"closed_at":None,"pull_request":7},
]
second["review_collection"] = {
    "pending_pull_requests":[],
    "batch_request":{"resumed_from_sha256":hashlib.sha256(p1.read_bytes()).hexdigest(),"pull_page":None,"review_pages":[{"number":7,"next_review_page":2}]},
    "batch_pull_requests":[],
    "next_pull_page":2,"pulls_complete":False,"complete":False
}
p2 = write("two.json", second)

third = copy.deepcopy(first)
third["captured_at"] = 1700000002
third["capabilities"]["reviews"].update(attempted=1, normalized=1, count=1)
third["events"] = [{"kind":"reviews","native_id":"github:301","status":"APPROVED","created_at":1700000004,"updated_at":None,"closed_at":None,"pull_request":9}]
third["review_collection"] = {
    "pending_pull_requests":[],
    "batch_request":{"resumed_from_sha256":hashlib.sha256(p2.read_bytes()).hexdigest(),"pull_page":2,"review_pages":[]},
    "batch_pull_requests":[{"number":9,"merged_at":1700172800}],
    "next_pull_page":None,"pulls_complete":True,"complete":True
}
p3 = write("three.json", third)

for name, paths in {
    "one-input.json":[p1],
    "chain.json":[p1,p2,p3],
    "gap.json":[p1,p3],
    "reordered.json":[p2,p1,p3],
}.items():
    write(name, {"schema":"rh-forge-review-chain-input/1","segments":[str(p) for p in paths]})

wrong_scope = copy.deepcopy(third)
wrong_scope["scope"]["repository"] = "other/project"
p4 = write("wrong-scope.json", wrong_scope)
write("wrong-scope-input.json", {"schema":"rh-forge-review-chain-input/1","segments":[str(p) for p in (p1,p2,p4)]})

cursor_jump = copy.deepcopy(second)
cursor_jump["review_collection"]["batch_request"]["review_pages"][0]["next_review_page"] = 3
p5 = write("cursor-jump.json", cursor_jump)
write("cursor-jump-input.json", {"schema":"rh-forge-review-chain-input/1","segments":[str(p1),str(p5),str(p3)]})

bad_review_id = copy.deepcopy(first)
bad_review_id["events"][0]["native_id"] = "github:not-an-id"
p6 = write("bad-review-id.json", bad_review_id)
write("bad-review-id-input.json", {"schema":"rh-forge-review-chain-input/1","segments":[str(p6)]})

time_reversal = copy.deepcopy(second)
time_reversal["captured_at"] = 1699999999
p7 = write("time-reversal.json", time_reversal)
write("time-reversal-input.json", {"schema":"rh-forge-review-chain-input/1","segments":[str(p1),str(p7)]})

mixed_capabilities = copy.deepcopy(first)
mixed_capabilities["capabilities"]["issues"]["status"] = "observed"
p8 = write("mixed-capabilities.json", mixed_capabilities)
write("mixed-capabilities-input.json", {"schema":"rh-forge-review-chain-input/1","segments":[str(p8)]})
PY

"$ROOT/build/rh_cli" forge review-chain --input "$T/chain.json" --out "$T/chain-result.json" >/dev/null
[[ -s "$T/chain-result.json.transformations.json" ]] || {
  echo "review chain did not write its transformation report" >&2
  exit 1
}
"$ROOT/build/rh_cli" forge review-chain --input "$T/one-input.json" --out "$T/partial-result.json" >/dev/null
python3 - "$T/partial-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-forge-review-chain-result/1", d
assert d["status"] == "partial" and d["complete"] is False, d
assert d["segment_count"] == 1 and d["pull_request_count"] == 2, d
print("[forge-review-chain] valid unfinished chain remains partial")
PY
python3 - "$T/chain-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-forge-review-chain-result/1", d
assert d["status"] == "complete" and d["complete"] is True, d
assert d["segment_count"] == 3, d
assert d["pull_request_count"] == 3 and d["merged_pull_request_count"] == 2, d
assert [row["number"] for row in d["pull_requests"]] == [7,8,9], d
assert d["review_event_count"] == 4 and len(d["review_events"]) == 4, d
review = next(row for row in d["review_events"] if row["native_id"] == "github:55")
assert review["status"] == "APPROVED" and review["submitted_at"] == 1700000002, review
print("[forge-review-chain] exact cursor chain, merged denominator, and event replacement OK")
PY

set +e
"$ROOT/build/rh_cli" forge review-chain --input "$T/gap.json" --out "$T/gap-result.json" >/dev/null 2>&1
rc_gap=$?
"$ROOT/build/rh_cli" forge review-chain --input "$T/reordered.json" --out "$T/reordered-result.json" >/dev/null 2>&1
rc_order=$?
"$ROOT/build/rh_cli" forge review-chain --input "$T/wrong-scope-input.json" --out "$T/wrong-scope-result.json" >/dev/null 2>&1
rc_scope=$?
"$ROOT/build/rh_cli" forge review-chain --input "$T/cursor-jump-input.json" --out "$T/cursor-jump-result.json" >/dev/null 2>&1
rc_cursor=$?
"$ROOT/build/rh_cli" forge review-chain --input "$T/bad-review-id-input.json" --out "$T/bad-review-id-result.json" >/dev/null 2>&1
rc_id=$?
"$ROOT/build/rh_cli" forge review-chain --input "$T/time-reversal-input.json" --out "$T/time-reversal-result.json" >/dev/null 2>&1
rc_time=$?
"$ROOT/build/rh_cli" forge review-chain --input "$T/mixed-capabilities-input.json" --out "$T/mixed-capabilities-result.json" >/dev/null 2>&1
rc_capabilities=$?
set -e
[[ "$rc_gap" -eq 4 && "$rc_order" -eq 4 && "$rc_scope" -eq 4 && "$rc_cursor" -eq 4 && "$rc_id" -eq 4 && "$rc_time" -eq 4 && "$rc_capabilities" -eq 4 ]] || {
  echo "expected gap/order/scope/cursor/id/time/capability failures: $rc_gap/$rc_order/$rc_scope/$rc_cursor/$rc_id/$rc_time/$rc_capabilities" >&2
  exit 1
}
[[ ! -e "$T/gap-result.json" && ! -e "$T/reordered-result.json" && ! -e "$T/wrong-scope-result.json" && ! -e "$T/cursor-jump-result.json" && ! -e "$T/bad-review-id-result.json" && ! -e "$T/time-reversal-result.json" && ! -e "$T/mixed-capabilities-result.json" ]] || {
  echo "invalid review chain wrote a result" >&2
  exit 1
}
echo "test_forge_review_chain_cli OK"
