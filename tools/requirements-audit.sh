#!/usr/bin/env bash
# tools/requirements-audit.sh — R/S evidence audit.
#
# Reads ops/requirements-index.json and verifies that every evidence entry
# points at a real file containing the named token. This makes the
# requirement-to-evidence mapping falsifiable: deleting an implementation
# or test fails the audit, and a partial requirement must carry a `gap`.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
d = json.load(open(os.path.join(root, "ops", "requirements-index.json"), encoding="utf-8"))
assert d["index_version"] == "rh-requirements-index/1", d
reqs = d["requirements"]
safety = d["safety"]

want_r = ["R%03d" % i for i in range(1, 31)]
assert [r["id"] for r in reqs] == want_r, "requirements must be R001..R030 in order"
want_s = ["S%03d" % i for i in range(1, 13)]
assert [s["id"] for s in safety] == want_s, "safety must be S001..S012 in order"

counts = {}
for section in ("requirements", "safety"):
    for e in d[section]:
        if section == "safety":
            continue
        st = e.get("status", "implemented")
        counts[st] = counts.get(st, 0) + 1
        ev = e.get("evidence", [])
        assert ev, ("no evidence", e["id"])
        for item in ev:
            p = os.path.join(root, item["path"])
            assert os.path.isfile(p), ("missing evidence file", e["id"], item["path"])
            body = open(p, encoding="utf-8", errors="replace").read()
            assert item["token"] in body, ("evidence token absent", e["id"], item["path"], item["token"])
        if st == "partial":
            assert e.get("gap"), ("partial requirement needs a gap", e["id"])
        if st == "deferred":
            assert e.get("gap"), ("deferred requirement needs a gap", e["id"])

print("requirements-audit OK: %d requirements (%s), %d safety rules"
      % (len(reqs), ", ".join("%s=%d" % (k, counts[k]) for k in sorted(counts)), len(safety)))
PY

echo "requirements-audit OK"
