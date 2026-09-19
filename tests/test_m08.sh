#!/usr/bin/env bash
# tests/test_m08.sh — M08 native-VCS lane: Mercurial `hg log -Tjson`
# parsing (node preserved, rev local, author raw, tags != releases,
# malformed rejected, payload bounded). Deterministic, offline.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m08] FAIL: $1" >&2; exit 1; }

echo "[m08] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_m08" ]] || fail "test_m08 not built"

echo "[m08] mercurial parse/normalize + adversarial payloads"
out="$("$ROOT/build/test_m08")" || fail "test_m08: $out"
[[ "$out" == *"M08 OK"* ]] || fail "test_m08: $out"
echo "$out"

echo "[m08] capability manifest: history only, other caps unsupported"
python3 - "$ROOT/connectors/manifests/mercurial.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["connector_id"] == "mercurial", d
assert d["connector_version"] == "1.0.0", d
assert d["capabilities"]["history"] == "mercurial", d
for cap in ("issues", "reviews", "releases", "traffic", "permissions"):
    assert d["capabilities"][cap] == "unsupported", (cap, d)
assert d["auth_scopes"] == [], d
print("[m08] manifest OK")
PY

echo "[m08] native ids: never a Git hash, no invented equivalence"
grep -q "never invents a Git hash" "$ROOT/src/rh_vcs_hg.elisa" || fail "git-hash caveat missing"
grep -q "never converted to a Git hash" "$ROOT/connectors/manifests/mercurial.json" || fail "manifest git-hash caveat missing"
grep -q "repository-local, not identity" "$ROOT/connectors/manifests/mercurial.json" || fail "rev-locality caveat missing"
if grep -qiE "git_hash|git-revision|sha1\b" "$ROOT/src/rh_vcs_hg.elisa"; then
  fail "mercurial module appears to reference Git hashes"
fi

echo "[m08] non-PR workflow: patch revisions collapse, series do not"
grep -q "trailer-distinct-approvers-2" "$ROOT/src/test_m08.elisa" || fail "trailer role check missing"
grep -q "CLAIM, not confirmed reachability" "$ROOT/src/rh_patch.elisa" || fail "Fixes claim caveat missing"
grep -q "never execute or interpolate the body" "$ROOT/src/rh_patch.elisa" || fail "no-exec body caveat missing"
grep -q "3x-revised patch series != 3 changes" "$ROOT/src/rh_patch.elisa" || fail "patch-series contract missing"
grep -q "never forced" "$ROOT/src/rh_patch.elisa" || fail "non-patch honesty note missing"

echo "[m08] release-only source: releases yes, history never invented"
python3 - "$ROOT/connectors/manifests/release-feed.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["connector_id"] == "release-feed", d
assert d["capabilities"]["releases"] == "release-feed", d
for cap in ("history", "issues", "reviews", "traffic", "permissions"):
    assert d["capabilities"][cap] == "unsupported", (cap, d)
print("[m08] release-feed manifest OK")
PY
grep -q "never invents commits" "$ROOT/src/rh_release_feed.elisa" || fail "no-history caveat missing"

echo "[m08] ecosystem: PEP 440 ordering, not SemVer, with declared subset"
grep -q "SemVer rules must NOT be applied here" "$ROOT/src/rh_pep440.elisa" || fail "pep440 semver-independence note missing"
grep -q "local versions are compared by presence only" "$ROOT/src/rh_pep440.elisa" || fail "pep440 local-version subset not declared"

echo "[m08] rights register records the mercurial source"
python3 - "$ROOT/ops/source-review-register.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = [s for s in d["sources"] if s["id"] == "mercurial"]
assert len(m) == 1, "mercurial missing from register"
s = m[0]
assert s["kind"] == "vcs" and s["redistribution"] == "none", s
assert "changes" in s["capabilities"], s
assert "reviews" in s["unauthorized"], s
r = [s for s in d["sources"] if s["id"] == "release-feed"]
assert len(r) == 1, "release-feed missing from register"
assert r[0]["kind"] == "release_feed", r[0]
assert "releases" in r[0]["capabilities"], r[0]
assert "history" in r[0]["unsupported"], r[0]
sv = [s for s in d["sources"] if s["id"] == "subversion"]
assert len(sv) == 1, "subversion missing from register"
assert sv[0]["kind"] == "vcs" and "changes" in sv[0]["capabilities"], sv[0]
assert "reviews" in sv[0]["unauthorized"], sv[0]
fo = [s for s in d["sources"] if s["id"] == "fossil"]
assert len(fo) == 1, "fossil missing from register"
assert fo[0]["kind"] == "vcs" and "changes" in fo[0]["capabilities"], fo[0]
print("[m08] register OK")
PY

echo "[m08] honesty: STATUS.md marks M08 in progress"
grep -q "M08 expanded coverage.*in_progress" "$ROOT/STATUS.md" || fail "STATUS.md misstates M08"

echo "test_m08 OK"
