#!/usr/bin/env bash
# tests/test_vcs_cli.sh — M08 native-VCS / non-PR execution path (R025):
# `rh_cli vcs --format hg|patch`. Asserts native Mercurial ids are preserved
# (rev is local, author raw, tags not releases, malformed rejected not
# guessed) and that an mbox series collapses N revisions of one patch into
# ONE logical change, counts trailers with approver dedup, treats `Fixes:`
# as a claim, and never forces a non-patch message into a series.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-vcs"

fail() { echo "[vcs] FAIL: $1" >&2; exit 1; }

echo "[vcs] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/hg.json" <<'JSON'
[{"node":"0123456789abcdef0123456789abcdef01234567","rev":0,"user":"Ada Lovelace <ada@example.org>","date":[1609459200,-3600],"desc":"first change","branch":"default","tags":["tip"],"phase":"draft","parents":[]},{"node":"fedcba9876543210fedcba9876543210fedcba98","rev":1,"user":"Grace Hopper <grace@example.org>","date":[1612137600,7200],"desc":"second change","branch":"stable","tags":[],"phase":"public","parents":["0123456789abcdef0123456789abcdef01234567"]}]
JSON
"$ROOT/build/rh_cli" vcs --format hg --input "$T/hg.json" --out "$T/hg.out" >/dev/null || fail "hg run"
python3 - "$T/hg.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-vcs/1" and d["format"] == "hg", d
assert len(d["changes"]) == 2 and d["rejected"] == 0, d
c0, c1 = d["changes"]
assert c0["node"] == "0123456789abcdef0123456789abcdef01234567", c0
assert c0["rev"] == 0 and c0["branch"] == "default" and c0["phase"] == "draft", c0
assert c0["utc"] == 1609459200 and c0["tz_offset"] == -3600 and c0["has_date"] is True, c0
assert c0["author"] == "Ada Lovelace <ada@example.org>", c0
assert c0["tag_count"] == 1 and c1["tag_count"] == 0, (c0, c1)
assert c1["phase"] == "public" and c1["rev"] == 1, c1
assert "tags are not releases" in d["note"], d["note"]
print("[vcs] hg OK")
PY

echo "[vcs] hg: malformed node is rejected, not guessed"
printf '[{"node":"not-a-node","rev":0,"user":"x","date":[1,0],"desc":"d","branch":"default","tags":[],"phase":"draft"}]' > "$T/bad.json"
"$ROOT/build/rh_cli" vcs --format hg --input "$T/bad.json" --out "$T/bad.out" >/dev/null || fail "hg reject run"
python3 - "$T/bad.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["changes"] == [] and d["rejected"] == 1, d
print("[vcs] hg reject OK")
PY

cat > "$T/series.mbox" <<'MBOX'
From aaa Mon Sep 17 00:00:00 2001
From: Dev One <dev@example.org>
Subject: [PATCH 1/1] add widget

First cut.

Signed-off-by: Dev One
Reviewed-by: Reviewer A <a@example.org>

From bbb Mon Sep 17 00:00:01 2001
From: Dev One <dev@example.org>
Subject: [PATCH v2 1/1] add widget

Second cut.

Reviewed-by: Reviewer A <a@example.org>
Acked-by: Reviewer B <b@example.org>
Fixes: deadbeef

From ccc Mon Sep 17 00:00:02 2001
From: Dev One <dev@example.org>
Subject: [PATCH v3 1/1] add widget

Third cut.

Reviewed-by: Reviewer A <a@example.org>
Reviewed-by: Reviewer A <a@example.org>
Tested-by: CI <ci@example.org>
MBOX
"$ROOT/build/rh_cli" vcs --format patch --input "$T/series.mbox" --out "$T/patch.out" >/dev/null || fail "patch run"
python3 - "$T/patch.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-patch/1", d
m = d["messages"]
assert len(m) == 3, m
# three revisions of ONE patch base = ONE logical change
assert d["logical_changes"] == 1, d
assert [x["version"] for x in m] == [1, 2, 3], m
assert all(x["is_patch"] and x["series_index"] == 1 and x["series_total"] == 1 for x in m), m
assert m[1]["acked_by"] == 1 and m[1]["fixes_claims"] == 1, m[1]  # Fixes is a claim
assert m[2]["reviewed_by"] == 2 and m[2]["distinct_approvers"] == 1, m[2]  # approver dedup
assert m[2]["tested_by"] == 1, m[2]
assert "Fixes: is a claim" in d["note"], d["note"]
print("[vcs] patch OK")
PY

echo "[vcs] patch: a 2-part series is two logical changes; non-patch stays distinct"
cat > "$T/series2.mbox" <<'MBOX'
From x1 Mon Sep 17 00:00:00 2001
From: Dev One <dev@example.org>
Subject: [PATCH 1/2] part one

Body one.

From x2 Mon Sep 17 00:00:01 2001
From: Dev One <dev@example.org>
Subject: [PATCH 2/2] part two

Body two.

From x3 Mon Sep 17 00:00:02 2001
From: Someone <s@example.org>
Subject: Re: status update

Just an email, not a patch.
MBOX
"$ROOT/build/rh_cli" vcs --format patch --input "$T/series2.mbox" --out "$T/patch2.out" >/dev/null || fail "patch2 run"
python3 - "$T/patch2.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["logical_changes"] == 3, d   # two series changes + one non-patch message
assert [x["is_patch"] for x in d["messages"]] == [True, True, False], d["messages"]
print("[vcs] patch series/non-patch OK")
PY

echo "[vcs] svn: repository-global revisions preserved, actions counted"
cp "$ROOT/fixtures/vcs/svn-log.xml" "$T/svn-log.xml"
"$ROOT/build/rh_cli" vcs --format svn --input "$T/svn-log.xml" --out "$T/svn.out" >/dev/null || fail "svn run"
python3 - "$T/svn.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-vcs/1" and d["format"] == "svn", d
assert len(d["entries"]) == 3 and d["rejected"] == 0, d
e0 = d["entries"][0]
assert e0["revision"] == 1042 and e0["has_author"] is True and e0["has_date"] is True, e0
assert e0["author"] == "alice", e0
assert e0["msg"] == "fix: handle the & edge case <bounds>", e0   # entities decoded
assert e0["path_count"] == 3 and e0["add"] == 1 and e0["modify"] == 1 and e0["replace"] == 1, e0
e1 = d["entries"][1]
assert e1["revision"] == 1041 and e1["delete"] == 1, e1
e2 = d["entries"][2]
assert e2["revision"] == 1040 and e2["other"] == 1 and e2["add"] == 1, e2
assert "repository-global counter" in d["note"], d["note"]
print("[vcs] svn OK")
PY

echo "[vcs] svn: non-log / unterminated XML fail closed"
printf '<repository><entry/></repository>' > "$T/notlog.xml"
printf '<log><logentry revision="1">' > "$T/unterm.xml"
set +e
"$ROOT/build/rh_cli" vcs --format svn --input "$T/notlog.xml" --out "$T/x" >/dev/null 2>&1; rc_notlog=$?
"$ROOT/build/rh_cli" vcs --format svn --input "$T/unterm.xml" --out "$T/x" >/dev/null 2>&1; rc_unterm=$?
set -e
[[ "$rc_notlog" -eq 4 ]] || fail "non-log svn must exit 4 (got $rc_notlog)"
[[ "$rc_unterm" -eq 4 ]] || fail "unterminated svn must exit 4 (got $rc_unterm)"

echo "[vcs] fossil: native artifact ids, phases/tags counted, dates parsed"
cp "$ROOT/fixtures/vcs/fossil-timeline.txt" "$T/fossil-timeline.txt"
"$ROOT/build/rh_cli" vcs --format fossil --input "$T/fossil-timeline.txt" --out "$T/fossil.out" >/dev/null || fail "fossil run"
python3 - "$T/fossil.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-vcs/1" and d["format"] == "fossil", d
assert len(d["entries"]) == 3 and d["rejected"] == 0, d
e0 = d["entries"][0]
assert e0["artifact"] == "aa3f1e2d4c5b6a79887766554433221100ffee11", e0
assert e0["author"] == "alice" and e0["has_date"] is True, e0
assert e0["utc"] == 1748766600, e0
assert e0["branch"] == "trunk" and e0["tag_count"] == 2 and e0["phase_count"] == 1, e0
assert e0["comment"] == "fix the parser", e0
e2 = d["entries"][2]
assert e2["branch"] == "feature-x" and e2["tag_count"] == 1, e2
assert "never a Git hash" in d["note"], d["note"]
print("[vcs] fossil OK")
PY

echo "[vcs] fossil: invalid hash rejected; bad date not guessed"
printf 'not-a-hash|alice|2025-06-01T08:30:00|trunk|*LEAF*||x\n' > "$T/fossil-bad.txt"
"$ROOT/build/rh_cli" vcs --format fossil --input "$T/fossil-bad.txt" --out "$T/fossil-bad.out" >/dev/null || fail "fossil bad run"
python3 - "$T/fossil-bad.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["entries"] == [] and d["rejected"] == 1, d
print("[vcs] fossil invalid hash rejected OK")
PY
printf 'aa3f1e2d4c5b6a79887766554433221100ffee11|bob|not-a-date|trunk|*LEAF*||y\n' > "$T/fossil-baddate.txt"
"$ROOT/build/rh_cli" vcs --format fossil --input "$T/fossil-baddate.txt" --out "$T/fossil-baddate.out" >/dev/null || fail "fossil baddate run"
python3 - "$T/fossil-baddate.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert len(d["entries"]) == 1, d
assert d["entries"][0]["has_date"] is False and d["entries"][0]["utc"] == -1, d["entries"][0]
print("[vcs] fossil bad date not guessed OK")
PY

echo "[vcs] determinism + negatives"
"$ROOT/build/rh_cli" vcs --format hg --input "$T/hg.json" --out "$T/hg2.out" >/dev/null || fail "hg rerun"
cmp -s "$T/hg.out" "$T/hg2.out" || fail "hg not deterministic"
set +e
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" vcs --format hg --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
printf '{"a":1}' > "$T/obj.json"
"$ROOT/build/rh_cli" vcs --format hg --input "$T/obj.json" --out "$T/x" >/dev/null 2>&1; rc_shape=$?
"$ROOT/build/rh_cli" vcs --format cvs --input "$T/hg.json" --out "$T/x" >/dev/null 2>&1; rc_fmt=$?
"$ROOT/build/rh_cli" vcs --format hg --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
[[ "$rc_json" -eq 4 ]] || fail "invalid JSON must exit 4 (got $rc_json)"
[[ "$rc_shape" -eq 4 ]] || fail "wrong-shape JSON must exit 4 (got $rc_shape)"
[[ "$rc_fmt" -eq 3 ]] || fail "unknown format must exit 3 (got $rc_fmt)"
[[ "$rc_missing" -eq 4 ]] || fail "missing input must exit 4 (got $rc_missing)"

echo "[vcs] gerrit change folds N patch-sets into ONE logical change (R025)"
cp "$ROOT/fixtures/vcs/gerrit-changes.json" "$T/gerrit-changes.json"
"$ROOT/build/rh_cli" vcs --format gerrit --input "$T/gerrit-changes.json" --out "$T/g.out" >/dev/null || fail "gerrit run"
python3 - "$T/g.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-gerrit/1" and d["format"] == "gerrit", d
assert d["change_count"] == 2, d
assert d["revision_count"] == 4, d
by = {c["change_number"]: c for c in d["changes"]}
assert by[42]["revision_count"] == 3, by[42]
assert by[42]["created_at"] == 1704164645 and by[42]["updated_at"] == 1706782830, by[42]
assert by[43]["revision_count"] == 1, by[43]
assert "3x-revised is one change" in d["note"], d["note"]
print("[vcs] gerrit fold OK")
PY
"$ROOT/build/rh_cli" vcs --format gerrit --input "$T/gerrit-changes.json" --out "$T/g2.out" >/dev/null
cmp -s "$T/g.out" "$T/g2.out" || fail "gerrit not deterministic"
printf '[{"_number":1,"project":"p","branch":"main","subject":"s","status":"NEW","created":"not-a-time","updated":"2024-01-02 03:04:05.000000000"}]' > "$T/gbad.json"
set +e
"$ROOT/build/rh_cli" vcs --format gerrit --input "$T/gbad.json" --out "$T/x" >/dev/null 2>&1; rc_gbad=$?
set -e
[[ "$rc_gbad" -eq 4 ]] || fail "unparseable gerrit timestamp must exit 4 (got $rc_gbad)"

echo "test_vcs_cli OK"
