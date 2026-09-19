#!/usr/bin/env bash
# tools/metric-profile.sh — emit the per-project availability profile.
#
# Derived from metrics/definitions: catalog size, the implemented set with
# its denominator rule, and everything explicitly NOT available. A metric
# counts as reachable ONLY when implementation_status == "implemented".
# Usage: tools/metric-profile.sh [out_file]
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build/metric-profile.json}"

python3 - "$ROOT" "$OUT" <<'PY'
import glob, json, os, sys
root, out = sys.argv[1], sys.argv[2]
defs = []
for p in sorted(glob.glob(os.path.join(root, "metrics", "definitions", "*.json"))):
    d = json.load(open(p))
    defs.append({
        "key": d["key"],
        "version": d["version"],
        "status": d["implementation_status"],
        "denominator_rule": d["denominator_rule"],
        "status_note": d.get("status_note", ""),
    })
implemented = [m for m in defs if m["status"] == "implemented"]
not_available = [m for m in defs if m["status"] != "implemented"]
profile = {
    "profile": "rh-metric-profile/1",
    "name": "per-project",
    "catalog_target": 360,
    "definitions": len(defs),
    "reachable": {"count": len(implemented), "metrics": implemented},
    "not_available": {"count": len(not_available), "metrics": not_available},
    "note": "reachable means implementation_status == 'implemented' (computed on the real scan path); not_available entries are never published as project health",
}
# Preserve the reviewed source-availability matrix when regenerating in place.
checked = os.path.join(root, "metrics", "profiles", "per-project.json")
if os.path.exists(checked):
    prev = json.load(open(checked))
    if "sources" in prev:
        profile["sources"] = prev["sources"]
with open(out, "w", encoding="utf-8") as fh:
    json.dump(profile, fh, indent=2, sort_keys=True)
    fh.write("\n")
print("metric-profile OK: %d reachable, %d not available, catalog target 360"
      % (len(implemented), len(not_available)))
PY
