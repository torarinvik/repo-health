#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-coverage-continuity"
fail() { echo "[coverage-continuity] FAIL: $1" >&2; exit 1; }

echo "[coverage-continuity] build"
bash "$ROOT/tools/build.sh" >/dev/null
rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-coverage-continuity-input/1","capability":"review_events","as_of":200,"reports":[{"schema":"rh-coverage-result/1","source":"forge-a","source_instance":"a.example/org/repo","capabilities":[{"capability":"review_events","state":"observed","reason":"bounded capture","valid_start":0,"valid_end":100,"known_as_of":100}]},{"schema":"rh-coverage-result/1","source":"forge-b","source_instance":"b.example/org/repo","capabilities":[{"capability":"review_events","state":"observed","reason":"bounded capture","valid_start":100,"valid_end":200,"known_as_of":200}]}]}
JSON
"$ROOT/build/rh_cli" coverage-continuity --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "adjacent source intervals"
cmp -s "$T/out.json" "$ROOT/fixtures/coverage-continuity/result.json" || fail "golden result changed"
python3 - "$T/out.json" "$T/in.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-coverage-continuity-result/1", d
assert d["status"] == "continuous" and d["covered_seconds"] == 200, d
assert d["gap_count"] == 0 and d["gap_seconds"] == 0, d
assert [s["source"] for s in d["sources"]] == ["forge-a", "forge-b"], d
side = json.load(open(sys.argv[1] + ".transformations.json"))
assert side["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), side
assert side["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), side
print("[coverage-continuity] adjacent half-open intervals remain continuous across source instances")
PY

python3 - "$T/in.json" "$T/gap.json" "$T/unknown.json" "$T/overlap.json" "$T/future.json" "$T/bad-state.json" <<'PY'
import copy, json, sys
base = json.load(open(sys.argv[1]))
gap = copy.deepcopy(base); gap["reports"][1]["capabilities"][0]["valid_start"] = 110
unknown = copy.deepcopy(base); unknown["reports"][1]["capabilities"][0].update(state="partial", valid_start=None, valid_end=200)
overlap = copy.deepcopy(base); overlap["reports"][1]["capabilities"][0]["valid_start"] = 99
future = copy.deepcopy(base); future["reports"][1]["capabilities"][0]["known_as_of"] = 201
bad_state = copy.deepcopy(base); bad_state["reports"][0]["capabilities"][0]["state"] = "complete-ish"
for path, value in zip(sys.argv[2:], [gap, unknown, overlap, future, bad_state]):
    json.dump(value, open(path, "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" coverage-continuity --input "$T/gap.json" --out "$T/gap-out.json" >/dev/null || fail "gapped source intervals"
"$ROOT/build/rh_cli" coverage-continuity --input "$T/unknown.json" --out "$T/unknown-out.json" >/dev/null || fail "unknown source interval"
python3 - "$T/gap-out.json" "$T/unknown-out.json" <<'PY'
import json, sys
gap, unknown = [json.load(open(p)) for p in sys.argv[1:]]
assert gap["status"] == "gapped" and gap["gap_count"] == 1 and gap["gap_seconds"] == 10, gap
assert unknown["status"] == "unknown" and unknown["covered_seconds"] is None and unknown["gap_count"] is None, unknown
assert unknown["sources"][1]["state"] == "partial", unknown
assert unknown["sources"][1]["valid_start"] is None and unknown["sources"][1]["valid_end"] == 200, unknown
print("[coverage-continuity] gaps are measured; partial evidence withholds continuity totals")
PY
set +e
"$ROOT/build/rh_cli" coverage-continuity --input "$T/overlap.json" --out "$T/overlap-out.json" >/dev/null 2>&1; overlap_rc=$?
"$ROOT/build/rh_cli" coverage-continuity --input "$T/future.json" --out "$T/future-out.json" >/dev/null 2>&1; future_rc=$?
"$ROOT/build/rh_cli" coverage-continuity --input "$T/bad-state.json" --out "$T/bad-state-out.json" >/dev/null 2>&1; bad_state_rc=$?
set -e
[[ "$overlap_rc" -eq 4 && "$future_rc" -eq 4 && "$bad_state_rc" -eq 4 ]] || fail "overlap, future-known, and invalid-state reports fail closed"
echo "test_coverage_continuity_cli OK"
