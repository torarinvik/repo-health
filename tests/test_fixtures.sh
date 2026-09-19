#!/usr/bin/env bash
# tests/test_fixtures.sh — F001-F040 catalog gate. The catalog must cover
# all forty ids, every covered/partial entry must resolve to a real test
# token, and the honest covered/partial/planned split must be reported.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[fixtures] FAIL: $1" >&2; exit 1; }

echo "[fixtures] lint catalog"
out="$(bash "$ROOT/tools/fixture-lint.sh")" || fail "fixture-lint"
echo "$out"

echo "[fixtures] all forty ids present and ordered"
python3 - "$ROOT/fixtures/fixture-catalog.json" <<'PY'
import json, sys
cat = json.load(open(sys.argv[1]))
ids = [f["id"] for f in cat["fixtures"]]
assert ids == ["F%03d" % i for i in range(1, 41)], ids
by = {f["id"]: f for f in cat["fixtures"]}
# Spot-check honesty: these are genuinely not implemented yet and must not
# be claimed as covered.
# No fixture is allowed to claim covered without evidence, and any that
# regress to planned must be caught here.
planned = [f["id"] for f in cat["fixtures"] if f["status"] == "planned"]
assert planned == [], ("unexpected planned fixtures", planned)
# Every fixture is covered; a regression to partial would fail here.
partial = [f["id"] for f in cat["fixtures"] if f["status"] == "partial"]
assert partial == [], ("unexpected partial fixtures", partial)
# These are the security-critical ones and must be covered.
for covered in ("F006", "F007", "F012", "F014", "F015", "F017", "F021", "F004", "F023", "F024", "F033", "F027", "F028", "F030", "F031", "F032", "F034", "F035", "F036", "F038", "F040"):
    assert by[covered]["status"] == "covered", (covered, by[covered]["status"])
counts = {}
for f in cat["fixtures"]:
    counts[f["status"]] = counts.get(f["status"], 0) + 1
assert sum(counts.values()) == 40, counts
print("[fixtures] honest split:", counts)
PY

echo "[fixtures] every reference file exists"
python3 - "$ROOT/fixtures/fixture-catalog.json" "$ROOT" <<'PY'
import json, os, sys
cat = json.load(open(sys.argv[1]))
root = sys.argv[2]
for f in cat["fixtures"]:
    for e in f.get("evidence", []):
        assert os.path.isfile(os.path.join(root, e["path"])), (f["id"], e["path"])
print("[fixtures] reference files OK")
PY

echo "test_fixtures OK"
