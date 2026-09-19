#!/usr/bin/env bash
# tools/fixture-lint.sh — verify the F001-F040 fixture catalog is honest.
# Every 'covered'/'partial' entry must point at a real token in the named
# file; 'planned' entries must carry no evidence. A green test suite
# therefore cannot imply fixture coverage that does not exist.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import json, sys
root = sys.argv[1]
cat = json.load(open(root + "/fixtures/fixture-catalog.json"))
assert cat["catalog_version"] == "rh-fixture-catalog/1"
fx = cat["fixtures"]

want = ["F%03d" % i for i in range(1, 41)]
got = [f["id"] for f in fx]
assert got == want, ("fixture ids must be exactly F001..F040 in order", got)

counts = {"covered": 0, "partial": 0, "planned": 0}
for f in fx:
    st = f["status"]
    assert st in counts, ("bad status", f["id"], st)
    counts[st] += 1
    ev = f.get("evidence", [])
    if st == "planned":
        assert ev == [], ("planned fixture must have no evidence", f["id"])
        continue
    assert ev, ("covered/partial fixture needs evidence", f["id"])
    for e in ev:
        p = root + "/" + e["path"]
        try:
            body = open(p, encoding="utf-8").read()
        except FileNotFoundError:
            raise SystemExit("missing evidence file for %s: %s" % (f["id"], e["path"]))
        assert e["token"] in body, ("token not found", f["id"], e["path"], e["token"])

print("fixture-lint OK: %d covered, %d partial, %d planned"
      % (counts["covered"], counts["partial"], counts["planned"]))
PY
