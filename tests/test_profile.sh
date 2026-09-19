#!/usr/bin/env bash
# tests/test_profile.sh — metric availability profile gate: the reachable
# set is derived mechanically from definitions, the checked-in profile
# matches, and not-available metrics are never advertised as reachable.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[profile] FAIL: $1" >&2; exit 1; }

echo "[profile] generate from definitions"
bash "$ROOT/tools/metric-profile.sh" "$ROOT/build/metric-profile.json" >/dev/null || fail "generator"
grep -q "metric-profile OK" <(bash "$ROOT/tools/metric-profile.sh" "$ROOT/build/metric-profile.json")

echo "[profile] reachable == implemented only; nothing else published"
python3 - "$ROOT" <<'PY'
import glob, json, os, sys
root = sys.argv[1]
built = json.load(open(os.path.join(root, "build", "metric-profile.json")))
checked = json.load(open(os.path.join(root, "metrics", "profiles", "per-project.json")))
assert built["profile"] == checked["profile"] == "rh-metric-profile/1"
assert built["catalog_target"] == 360
def reach(m):
    return sorted((x["key"], x["version"]) for x in m["reachable"]["metrics"])
def notav(m):
    return sorted((x["key"], x["version"]) for x in m["not_available"]["metrics"])
assert reach(built) == reach(checked), "profile out of date; regenerate"
assert notav(built) == notav(checked), "profile out of date; regenerate"
impl = 0
for p in glob.glob(os.path.join(root, "metrics", "definitions", "*.json")):
    d = json.load(open(p))
    if d["implementation_status"] == "implemented":
        impl += 1
assert built["reachable"]["count"] == impl, (built["reachable"]["count"], impl)
assert built["not_available"]["count"] == built["definitions"] - impl
# no not-available metric may appear in the reachable list
r = set(reach(built))
for k in notav(built):
    assert k not in r, ("not-available metric advertised as reachable", k)
for m in built["not_available"]["metrics"]:
    assert m["status"] != "implemented"
    assert m["status_note"], m
assert built["note"], built
print("[profile] OK: %d reachable, %d not available" % (built["reachable"]["count"], built["not_available"]["count"]))
PY

echo "[profile] source availability matrix present"
python3 - "$ROOT/metrics/profiles/per-project.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d["sources"]
for want in ("generic-git", "github", "gitlab", "forgejo", "gitea", "mercurial", "release-feed"):
    assert want in s, want
assert s["github"]["unauthorized"] == ["traffic"], s["github"]
assert "history" in s["release-feed"]["unsupported"], s["release-feed"]
print("[profile] sources OK")
PY

echo "test_profile OK"
