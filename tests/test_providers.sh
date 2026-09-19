#!/usr/bin/env bash
# tests/test_providers.sh — M07-09 provider-dependency review gate. The
# review must exist, cover every named dependency with a lifecycle and a
# failure mode, and must not claim a retired/not-enabled feed is in use.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[providers] FAIL: $1" >&2; exit 1; }

reg="$ROOT/ops/provider-dependency-review.json"
[[ -f "$reg" ]] || fail "provider-dependency review missing"

echo "[providers] schema + required dependencies"
python3 - "$reg" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["review_version"] == "rh-provider-dependency-review/1", d
required = ["id", "kind", "reference", "lifecycle", "reviewed_at",
            "used_for", "failure_mode", "assumption", "rights"]
ids = set()
for dep in d["dependencies"]:
    for k in required:
        assert k in dep and dep[k] not in (None, "", []), (dep.get("id"), k)
    assert dep["id"] not in ids, ("duplicate", dep["id"])
    ids.add(dep["id"])
    assert dep["lifecycle"] in ("active", "not_enabled", "retired", "deprecated"), dep
for want in ("git-cli", "osv-data", "deps-dev", "criticality-score",
             "ecosyste-ms", "reproducible-builds"):
    assert want in ids, ("missing dependency review", want)
print("[providers] dependencies OK:", ", ".join(sorted(ids)))
PY

echo "[providers] retired/not-enabled feeds are not claimed used"
python3 - "$reg" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
by = {x["id"]: x for x in d["dependencies"]}
cs = by["criticality-score"]
assert cs["lifecycle"] == "retired", cs
assert any("NOT used" in str(u) for u in cs["used_for"]), cs["used_for"]
assert "popularity/safety" in cs["failure_mode"] or "claim" in cs["failure_mode"], cs
dd = by["deps-dev"]
assert dd["lifecycle"] == "not_enabled", dd
assert "not enabled here" in dd["failure_mode"], dd
print("[providers] lifecycle honesty OK")
PY

echo "[providers] failure modes state stale/unknown, not silent success"
python3 - "$reg" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
blob = json.dumps(d).lower()
assert "unknown" in blob, "a failure mode must mention unknown"
assert "stale" in blob or "fail" in blob, "a failure mode must mention stale/fail-closed"
print("[providers] failure modes OK")
PY

echo "test_providers OK"
