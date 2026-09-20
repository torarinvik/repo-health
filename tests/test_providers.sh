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
osv = by["osv-data"]
assert osv["lifecycle"] == "active", osv
assert any("full commit-hash" in u for u in osv["used_for"]), osv
assert "more_available" in osv["failure_mode"] and "unknown" in osv["failure_mode"], osv
assert "complete lockfile coverage" in osv["assumption"] and "four pages" in osv["assumption"], osv
assert "fuzzi" in osv["assumption"] and "feed freshness" in osv["assumption"], osv
assert "four rounds" in osv["assumption"] and "only outstanding query items" in osv["assumption"], osv
assert "public redistribution is not enabled" in osv["rights"], osv
print("[providers] lifecycle honesty OK")
PY

echo "[providers] OSV live scope matches the source review"
python3 - "$reg" "$ROOT/ops/source-review-register.json" <<'PY'
import json, sys
provider = json.load(open(sys.argv[1]))
source = json.load(open(sys.argv[2]))
osv = {x["id"]: x for x in provider["dependencies"]}["osv-data"]
src = {x["id"]: x for x in source["sources"]}["osv-data"]
assert src["base_url"] == "https://api.osv.dev/v1/", src
assert set(src["capabilities"]) == {"package_version_string_query", "full_commit_hash_query", "bounded_pagination", "bounded_graph_batch_query"}, src
assert "complete_lockfile_coverage" in src["unauthorized"], src
assert "pagination_continuation" not in src["unauthorized"], src
assert "at most four pages" in src["notes"] and "partial" in src["notes"], src
assert "at most 64" in src["notes"] and "summaries, not full advisory records" in src["notes"], src
assert "only results with cursors" in src["notes"] and "four rounds" in src["notes"], src
assert "uniform_underlying_data_license" in src["unsupported"], src
assert "feed_freshness" in src["unsupported"], src
assert "source IDs and links" in osv["rights"], osv
assert src["redistribution"] == "none", src
print("[providers] bounded OSV source scope OK")
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
