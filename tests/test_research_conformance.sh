#!/usr/bin/env bash
# tests/test_research_conformance.sh — RP-01 Appendix C crosswalk.
# This is an honest coverage ledger: partial rows remain visible and are not
# treated as executed paper fixtures.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"

fail() { echo "[research-conformance] FAIL: $1" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
path = os.path.join(root, "ops", "research-conformance.json")
d = json.load(open(path))
assert d["schema"] == "rh-research-conformance/1", d
cases = d["cases"]
assert len(cases) == 48, len(cases)
expected = {f"RP-F{i:02d}" for i in range(1, 49)}
assert {c["id"] for c in cases} == expected, "case ids"
assert {c["paper_fixture"] for c in cases} == {f"F{i:02d}" for i in range(1, 49)}, "paper ids"
assert all(c["status"] in ("covered", "partial", "planned") for c in cases)
covered = partial = planned = 0
for c in cases:
    assert c["owning_work_packages"] and c["paths"] and c["tests"], c["id"]
    for rel in c["paths"] + c["tests"]:
        assert os.path.isfile(os.path.join(root, rel)), (c["id"], rel)
    if c["status"] == "partial":
        partial += 1
        assert c["unresolved_assertions"], (c["id"], "partial without open assertion")
    elif c["status"] == "planned":
        planned += 1
        assert c["unresolved_assertions"], (c["id"], "planned without open assertion")
    else:
        covered += 1
        assert not c["unresolved_assertions"], (c["id"], "covered with unresolved assertion")
print(f"[research-conformance] 48 cases mapped: {covered} covered, {partial} partial, {planned} planned")
PY

echo "test_research_conformance OK"
