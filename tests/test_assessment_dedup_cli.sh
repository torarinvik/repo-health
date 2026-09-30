#!/usr/bin/env bash
# rh-assessment-dedup-input/1 -> rh-assessment-dedup-result/1; origin key binds tool/version/revision/run/time/result digest.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-assessment-dedup"
fail() { echo "[assessment-dedup] FAIL: $1" >&2; exit 1; }
expect() {
  local want="$1"; shift
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  [[ "$got" == "$want" ]] || fail "expected exit $want, got $got: $*"
}

bash "$ROOT/tools/build.sh" >/dev/null
CLI="$ROOT/build/rh_cli"
rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/lineage/assessment-dedup-input.json" "$T/input.json"
"$CLI" assessment-dedup --input "$T/input.json" --out "$T/result.json" >/dev/null || fail "batch dedup"
cmp "$ROOT/fixtures/lineage/assessment-dedup-result.json" "$T/result.json" || fail "canonical output differs from golden"
"$CLI" assessment-dedup --input "$T/input.json" --out "$T/result2.json" >/dev/null || fail "deterministic rerun"
cmp "$T/result.json" "$T/result2.json" || fail "output is not deterministic"
cmp "$T/result.json.transformations.json" "$T/result2.json.transformations.json" || fail "transformation report is not deterministic"
python3 - "$T/input.json" "$T/result.json" <<'PY'
import hashlib, json, sys
source_path, output_path = sys.argv[1:]
source = json.load(open(source_path))
result = json.load(open(output_path))
report = json.load(open(output_path + ".transformations.json"))
assert report["schema"] == "rh-adapter-transformation-report/1", report
assert report["adapter"] == "origin-assessment-dedup" and report["output_schema"] == "rh-assessment-dedup-result/1", report
assert report["configuration_sha256"] == hashlib.sha256(b"repo-health/origin-assessment-dedup/1").hexdigest(), report
assert report["source_input_sha256"] == hashlib.sha256(open(source_path, "rb").read()).hexdigest(), report
assert report["normalized_output_sha256"] == hashlib.sha256(open(output_path, "rb").read()).hexdigest(), report
assert {field["state"] for field in report["fields"]} == {"preserved", "transformed", "unknown", "unsupported"}, report
rows = result["deliveries"]
assert result["counts"] == {
    "delivery_count": 5,
    "unique_complete_origin_assessments": 2,
    "additional_deliveries_of_same_assessment": 1,
    "possible_duplicate_deliveries": 2,
}, result
assert [row["group_id"] for row in rows] == [0, 0, 1, None, None], rows
assert rows[0]["assessment_key"] == rows[1]["assessment_key"]
assert rows[0]["assessment_key"] != rows[2]["assessment_key"]
assert all(row["deduplication_state"] == "possible_duplicate" for row in rows[3:])
origin = source["deliveries"][0]
material = bytearray()
for key in ("tool", "tool_version"):
    value = origin[key].encode()
    material.extend(str(len(value)).encode() + b":" + value + b"\n")
material.extend(str(origin["subject_revision"]).encode() + b"\n")
value = origin["original_run"].encode()
material.extend(str(len(value)).encode() + b":" + value + b"\n")
material.extend(str(origin["original_time"]).encode() + b"\n")
value = origin["result_digest"].encode()
material.extend(str(len(value)).encode() + b":" + value + b"\n")
assert rows[0]["assessment_key"] == hashlib.sha256(material).hexdigest()
print("[assessment-dedup] exact origin keys, repeated deliveries, and uncertain rows OK")
PY
python3 - "$T/input.json" "$CLI" "$T" <<'PY'
import json, pathlib, subprocess, sys
source_path, cli, temp = sys.argv[1:]
cases = {
    "tool": "different-tool",
    "tool_version": "different-version",
    "subject_revision": 8,
    "original_run": "different-run",
    "original_time": 1699999901,
    "result_digest": "e" * 64,
}
for field, value in cases.items():
    payload = json.load(open(source_path))
    payload["deliveries"][1][field] = value
    variant = pathlib.Path(temp) / ("variant-" + field + ".json")
    result = pathlib.Path(temp) / ("variant-" + field + "-result.json")
    json.dump(payload, open(variant, "w"), separators=(",", ":"))
    subprocess.run([cli, "assessment-dedup", "--input", str(variant), "--out", str(result)], check=True, stdout=subprocess.DEVNULL)
    report = json.load(open(result))
    assert report["counts"]["unique_complete_origin_assessments"] == 3, (field, report)
    assert report["counts"]["additional_deliveries_of_same_assessment"] == 0, (field, report)
print("[assessment-dedup] each origin-identity component independently separates groups")
PY

python3 - "$ROOT/fixtures/lineage/assessment-dedup-input.json" "$T/bad-digest.json" "$T/duplicate-delivery.json" "$T/negative-revision.json" "$T/too-many.json" <<'PY'
import json, sys
source = json.load(open(sys.argv[1]))
bad = json.loads(json.dumps(source)); bad["deliveries"][1]["result_digest"] = "bad"
json.dump(bad, open(sys.argv[2], "w"))
duplicate = json.loads(json.dumps(source)); duplicate["deliveries"][1]["delivery_id"] = duplicate["deliveries"][0]["delivery_id"]
json.dump(duplicate, open(sys.argv[3], "w"))
negative = json.loads(json.dumps(source)); negative["deliveries"][0]["subject_revision"] = -1
json.dump(negative, open(sys.argv[4], "w"))
large = json.loads(json.dumps(source)); large["deliveries"] = large["deliveries"] * 820
large["deliveries"] = large["deliveries"][:4097]
for index, row in enumerate(large["deliveries"]):
    row["delivery_id"] = f"delivery-{index}"
json.dump(large, open(sys.argv[5], "w"), separators=(",", ":"))
PY
expect 4 "$CLI" assessment-dedup --input "$T/bad-digest.json" --out "$T/rejected.json"
expect 4 "$CLI" assessment-dedup --input "$T/duplicate-delivery.json" --out "$T/rejected.json"
expect 4 "$CLI" assessment-dedup --input "$T/negative-revision.json" --out "$T/rejected.json"
expect 4 "$CLI" assessment-dedup --input "$T/too-many.json" --out "$T/rejected.json"
echo "[assessment-dedup] malformed identities, duplicate delivery IDs, and row bound fail closed"
echo "test_assessment_dedup_cli OK"
