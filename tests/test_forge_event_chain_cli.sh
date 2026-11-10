#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
T="$(mktemp -d /tmp/rh-forge-event-chain.XXXXXX)"
trap 'rm -rf "$T"' EXIT

tools/build.sh >/dev/null
CLI="$ROOT/build/rh_cli"
FIXTURE="$ROOT/fixtures/forge-event-chain"

"$CLI" forge events-chain --input "$FIXTURE/input.json" --out "$T/complete.json" >/dev/null
python3 - "$FIXTURE" "$T/complete.json" "$T" <<'PY'
import copy, hashlib, json, pathlib, sys
fixture = pathlib.Path(sys.argv[1])
result_path = pathlib.Path(sys.argv[2])
t = pathlib.Path(sys.argv[3])
result = json.loads(result_path.read_text())
first_path = fixture / "segment-1.json"
second_path = fixture / "segment-2.json"
first = json.loads(first_path.read_text())
second = json.loads(second_path.read_text())
assert result["schema"] == "rh-forge-events-result/1", result
assert result["provider"] == "bitbucket" and result["scope"] == {"repository":"example/project"}, result
assert result["authorization"] == {"state":"not_requested"}, result
assert result["segment_chain"] == {
    "segment_count": 2,
    "complete": True,
    "segment_sha256": [
        hashlib.sha256(first_path.read_bytes()).hexdigest(),
        hashlib.sha256(second_path.read_bytes()).hexdigest(),
    ],
}, result["segment_chain"]
assert result["capabilities"]["issues"] == {
    "status":"observed", "attempted":2, "normalized":2,
    "duplicate_replacements":1, "count":1, "rejected":0,
}, result["capabilities"]["issues"]
assert result["capabilities"]["proposals"] == {
    "status":"observed", "attempted":2, "normalized":2,
    "duplicate_replacements":0, "count":2, "rejected":0,
}, result["capabilities"]["proposals"]
assert [(event["kind"], event["native_id"]) for event in result["events"]] == [
    ("issues", "bitbucket:301"), ("proposals", "bitbucket:17"), ("proposals", "bitbucket:18")
], result["events"]
assert result["events"][0]["status"] == "closed" and result["events"][0]["updated_at"] == 1700000001, result["events"][0]
assert result["pagination"]["issues"] == {"next":None,"complete":True}, result["pagination"]
assert result["pagination"]["proposals"] == {"next":None,"complete":True}, result["pagination"]
sidecar = json.loads(pathlib.Path(str(result_path) + ".transformations.json").read_text())
assert sidecar["adapter"] == "bitbucket-event-chain", sidecar

def write_input(name, segments):
    path = t / name
    path.write_text(json.dumps({"schema":"rh-forge-event-chain-input/1","segments":segments}, separators=(",", ":")) + "\n")
    return path

first_only = write_input("first-only.json", [str(first_path)])
for name, changed in {
    "wrong-scope": (lambda d: d["scope"].update(repository="other/project")),
    "cursor-jump": (lambda d: d["segment"]["consumed"].update(issues="https://api.bitbucket.org/2.0/repositories/example/project/issues?page=9")),
    "digest-mismatch": (lambda d: d["segment"].update(resumed_from_sha256="0" * 64)),
    "time-reversal": (lambda d: d.update(captured_at=1699999999)),
    "invalid-id": (lambda d: d["events"][0].update(native_id="github:301")),
}.items():
    variant = copy.deepcopy(second)
    changed(variant)
    path = t / f"{name}.json"
    path.write_text(json.dumps(variant, separators=(",", ":")) + "\n")
    globals()[name] = path

cases = {
    "gap.json": [str(second_path)],
    "reordered.json": [str(second_path), str(first_path)],
    "wrong-scope-input.json": [str(first_path), str(globals()["wrong-scope"])],
    "cursor-jump-input.json": [str(first_path), str(globals()["cursor-jump"])],
    "digest-mismatch-input.json": [str(first_path), str(globals()["digest-mismatch"])],
    "time-reversal-input.json": [str(first_path), str(globals()["time-reversal"])],
    "invalid-id-input.json": [str(first_path), str(globals()["invalid-id"])],
}
for name, segments in cases.items():
    write_input(name, segments)
PY

"$CLI" forge events-chain --input "$T/first-only.json" --out "$T/partial.json" >/dev/null
python3 - "$FIXTURE/segment-1.json" "$T/partial.json" <<'PY'
import json, sys
source = json.load(open(sys.argv[1]))
result = json.load(open(sys.argv[2]))
assert result["segment_chain"]["complete"] is False, result
assert result["pagination"]["issues"] == source["pagination"]["issues"], result
assert result["pagination"]["proposals"] == source["pagination"]["proposals"], result
print("[forge-event-chain] unfinished segment remains partial with opaque cursors")
PY

set +e
for name in gap reordered wrong-scope cursor-jump digest-mismatch time-reversal invalid-id; do
  "$CLI" forge events-chain --input "$T/$name-input.json" --out "$T/$name-result.json" >/dev/null 2>&1
  status=$?
  [[ "$status" -eq 4 ]] || { echo "[forge-event-chain] FAIL: accepted $name chain (exit $status)" >&2; exit 1; }
done
"$CLI" forge events-chain --input "$FIXTURE/input.json" --out "$FIXTURE/input.json" >/dev/null 2>&1
same_path_status=$?
"$CLI" forge events --bitbucket-repo example/project --max-pages 1 --resume-from "$FIXTURE/segment-1.json" --out "$FIXTURE/segment-1.json" >/dev/null 2>&1
same_resume_status=$?
set -e
[[ "$same_path_status" -eq 3 ]] || { echo "[forge-event-chain] FAIL: input/output alias accepted ($same_path_status)" >&2; exit 1; }
[[ "$same_resume_status" -eq 3 ]] || { echo "[forge-event-chain] FAIL: resume/output alias accepted ($same_resume_status)" >&2; exit 1; }

echo "test_forge_event_chain_cli OK"
