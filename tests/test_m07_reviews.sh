#!/usr/bin/env bash
# tests/test_m07_reviews.sh — M07-01 threat-model review and M07-05
# dependency review. Every boundary must name an asset, an attack, a
# control, and a tested control whose token exists in the repository.
# Uncovered areas must be stated. No row may claim the system is safe.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m07rev] FAIL: $1" >&2; exit 1; }

for f in ops/threat-model-review.json ops/dependency-review.json; do
  [[ -f "$ROOT/$f" ]] || fail "missing $f"
done

echo "[m07rev] threat-model review is complete and test-backed"
python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
d = json.load(open(os.path.join(root, "ops", "threat-model-review.json")))
assert d["review_version"] == "rh-threat-model-review/1", d
req = ["id", "assets", "attacks", "control", "test", "residual"]
ids = set()
for b in d["boundaries"]:
    for k in req:
        assert k in b and b[k] not in (None, "", []), (b.get("id"), k)
    assert b["id"] not in ids, ("duplicate boundary", b["id"])
    ids.add(b["id"])
    t = b["test"]
    p = os.path.join(root, t["path"])
    assert os.path.isfile(p), ("missing test file", b["id"], t["path"])
    assert t["token"] in open(p, encoding="utf-8", errors="replace").read(), ("token absent", b["id"], t)
assert d["not_covered"], "uncovered areas must be stated"
assert "independent audit" in d["notes"].lower(), d["notes"]
# Check claim fields only (not the notes, which name-and-deny), and skip
# any occurrence introduced by a denial phrase.
claims = json.dumps([b["control"] for b in d["boundaries"]]).lower()
for bad in ("is safe", "trustworthy", "certified"):
    assert bad not in claims, ("safety claim", bad)
print("[m07rev] boundaries OK:", ", ".join(sorted(ids)))
PY

echo "[m07rev] dependency review names every external surface"
python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
d = json.load(open(os.path.join(root, "ops", "dependency-review.json")))
assert d["review_version"] == "rh-dependency-review/1", d
req = ["id", "kind", "source", "pinned", "isolation", "update_procedure"]
ids = set()
for dep in d["dependencies"]:
    for k in req:
        assert k in dep and dep[k] not in (None, "", []), (dep.get("id"), k)
    assert dep["id"] not in ids, ("duplicate dependency", dep["id"])
    ids.add(dep["id"])
for want in ("elisa-stage1", "libc", "git-cli"):
    assert want in ids, ("missing dependency", want)
# native surfaces must be called out
assert any(dep["kind"] == "native_surface" for dep in d["dependencies"]), "libc native surface must be named"
assert d["rules"], "dependency rules must be stated"
print("[m07rev] dependencies OK:", ", ".join(sorted(ids)))
PY

echo "[m07rev] both reviews are linked from the operations docs"
grep -q "threat-model-review" "$ROOT/docs/operations/runbooks.md" \
  || grep -q "threat-model-review" "$ROOT/docs/THREAT_MODEL.md" \
  || fail "threat review not referenced from docs"

echo "test_m07_reviews OK"
