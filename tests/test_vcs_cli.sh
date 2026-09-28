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
python3 - "$T/hg.out" "$T/hg.json" "$T/hg.out.transformations.json" <<'PY'
import hashlib, json, sys
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
tr = json.load(open(sys.argv[3]))
assert tr["schema"] == "rh-adapter-transformation-report/1" and tr["adapter"] == "native-vcs", tr
assert tr["output_schema"] == "rh-vcs/1", tr
assert tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/native-vcs/1:hg:captured-input").hexdigest(), tr
assert {field["state"] for field in tr["fields"]} == {"preserved", "transformed", "unsupported", "unknown", "discarded"}, tr
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
printf 'aa3f1e2d4c5b6a79887766554433221100ffee11|bob|2025-02-30T08:30:00|trunk|*LEAF*||z\n' > "$T/fossil-invalid-calendar-date.txt"
"$ROOT/build/rh_cli" vcs --format fossil --input "$T/fossil-invalid-calendar-date.txt" --out "$T/fossil-invalid-calendar-date.out" >/dev/null || fail "fossil invalid calendar date run"
python3 - "$T/fossil-invalid-calendar-date.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert len(d["entries"]) == 1 and d["entries"][0]["has_date"] is False and d["entries"][0]["utc"] == -1, d
print("[vcs] fossil impossible calendar date remains unknown")
PY

echo "[vcs] SourceHut GraphQL page keeps native identity, authored/committed time, and cursor completeness"
cp "$ROOT/fixtures/vcs/sourcehut-git-page.json" "$T/sourcehut.json"
"$ROOT/build/rh_cli" vcs --format sourcehut --input "$T/sourcehut.json" --out "$T/sourcehut.out" >/dev/null || fail "SourceHut run"
cmp "$ROOT/fixtures/vcs/sourcehut-git-page-result.json" "$T/sourcehut.out" || fail "SourceHut golden output mismatch"
python3 - "$T/sourcehut.out" "$T/sourcehut.json" "$T/sourcehut.out.transformations.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-vcs/1" and d["format"] == "sourcehut-git", d
assert d["repository_id"] == "opaque/repository-id" and d["repository_name"] == "sourcehut-demo", d
assert len(d["entries"]) == 2, d
a, b = d["entries"]
assert a["source_native_id"] == "opaque-commit-1" and a["author"]["utc"] == 1609459200, a
assert a["committer"]["utc"] == 1609459260 and a["message"] == 'first "change"' and a["parent_count"] == 0, a
assert b["author"]["utc"] == 1609556645 and b["parent_count"] == 1, b
assert a["parents"] == [] and b["parents"] == ["opaque-commit-1"], (a, b)
assert d["pagination"] == {"complete": False, "next_cursor": "opaque cursor/next"}, d
assert "source-native" in d["note"] and "incomplete" in d["note"], d["note"]
tr = json.load(open(sys.argv[3]))
assert tr["output_schema"] == "rh-vcs/1" and tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/native-vcs/1:sourcehut:captured-input").hexdigest(), tr
print("[vcs] SourceHut native IDs, separate time axes, page cursor, and transformation binding OK")
PY
python3 - "$T/sourcehut.json" "$T/sourcehut-complete.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["data"]["repository"]["log"]["cursor"] = None
json.dump(d, open(sys.argv[2], "w"))
PY
"$ROOT/build/rh_cli" vcs --format sourcehut --input "$T/sourcehut-complete.json" --out "$T/sourcehut-complete.out" >/dev/null || fail "SourceHut complete-page run"
python3 - "$T/sourcehut-complete.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["pagination"] == {"complete": True, "next_cursor": None}, d
print("[vcs] SourceHut null cursor is complete")
PY
python3 - "$T/sourcehut.json" "$T/sourcehut-chain.json" <<'PY'
import json, sys
source = json.load(open(sys.argv[1]))
repository = source["data"]["repository"]
commits = repository["log"]["results"]
pages = []
for index, commit in enumerate(commits):
    response = {"data":{"repository":{
        "rid":repository["rid"], "name":repository["name"],
        "log":{"results":[commit], "cursor":"cursor-two" if index == 0 else None}}}}
    pages.append({"request_cursor":None if index == 0 else "cursor-two",
                  "response_json":json.dumps(response, separators=(",", ":"))})
json.dump({"schema":"rh-sourcehut-page-chain-input/1", "pages":pages},
          open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" vcs --format sourcehut-pages --input "$T/sourcehut-chain.json" --out "$T/sourcehut-chain.out" >/dev/null || fail "SourceHut cursor-chain run"
python3 - "$T/sourcehut-chain.json" "$T/sourcehut-chain.out" "$T/sourcehut-chain.out.transformations.json" <<'PY'
import hashlib, json, pathlib, sys
source, output = map(pathlib.Path, sys.argv[1:3])
d = json.loads(output.read_bytes())
assert d["schema"] == "rh-vcs-pages/1" and d["format"] == "sourcehut-git", d
assert d["repository_id"] == "opaque/repository-id" and d["repository_name"] == "sourcehut-demo", d
assert len(d["pages"]) == 2 and d["pagination"] == {"complete":True,"next_cursor":None}, d
assert [p["request_cursor"] for p in d["pages"]] == [None, "cursor-two"], d
assert [p["result"]["entries"][0]["source_native_id"] for p in d["pages"]] == ["opaque-commit-1", "opaque-commit-2"], d
assert d["pages"][0]["result"]["pagination"] == {"complete":False,"next_cursor":"cursor-two"}, d
assert d["pages"][1]["result"]["pagination"] == {"complete":True,"next_cursor":None}, d
tr = json.loads(pathlib.Path(sys.argv[3]).read_bytes())
assert tr["output_schema"] == "rh-vcs-pages/1", tr
assert tr["source_input_sha256"] == hashlib.sha256(source.read_bytes()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(output.read_bytes()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/native-vcs/1:sourcehut-pages:captured-input").hexdigest(), tr
print("[vcs] SourceHut captured cursor chain validates and preserves page boundaries")
PY
cp "$ROOT/fixtures/vcs/sourcehut-git-pages-input.json" "$T/sourcehut-pages-golden.input"
"$ROOT/build/rh_cli" vcs --format sourcehut-pages --input "$T/sourcehut-pages-golden.input" --out "$T/sourcehut-pages-golden.out" >/dev/null || fail "SourceHut checked-in page-chain fixture run"
cmp "$ROOT/fixtures/vcs/sourcehut-git-pages-result.json" "$T/sourcehut-pages-golden.out" || fail "SourceHut page-chain golden output mismatch"
python3 - "$T/sourcehut-chain.json" "$T/sourcehut-chain-bad-cursor.json" "$T/sourcehut-chain-duplicate.json" "$T/sourcehut-chain-cursor-cycle.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
bad = json.loads(json.dumps(d)); bad["pages"][1]["request_cursor"] = "wrong-cursor"
duplicate = json.loads(json.dumps(d))
duplicate["pages"][1]["response_json"] = duplicate["pages"][1]["response_json"].replace("opaque-commit-2", "opaque-commit-1")
cycle = json.loads(json.dumps(d))
page = json.loads(cycle["pages"][1]["response_json"])
page["data"]["repository"]["log"]["cursor"] = "cursor-two"
cycle["pages"][1]["response_json"] = json.dumps(page, separators=(",", ":"))
json.dump(bad, open(sys.argv[2], "w"), separators=(",", ":"))
json.dump(duplicate, open(sys.argv[3], "w"), separators=(",", ":"))
json.dump(cycle, open(sys.argv[4], "w"), separators=(",", ":"))
PY
for bad_chain in "$T/sourcehut-chain-bad-cursor.json" "$T/sourcehut-chain-duplicate.json" "$T/sourcehut-chain-cursor-cycle.json"; do
  if "$ROOT/build/rh_cli" vcs --format sourcehut-pages --input "$bad_chain" --out "$bad_chain.out" >/dev/null 2>&1; then
    fail "malformed or duplicate SourceHut page chain must fail closed"
  fi
  [[ ! -e "$bad_chain.out" ]] || fail "invalid SourceHut chain wrote output"
done
echo "[vcs] SourceHut cursor discontinuities and duplicate native IDs fail closed"

echo "[vcs] native --repo collection retains source and stderr evidence"
mkdir -p "$T/bin" "$T/repo"
cat > "$T/bin/hg" <<'SH'
#!/usr/bin/env bash
cat "$RH_HG_FIXTURE"
SH
cat > "$T/bin/svn" <<'SH'
#!/usr/bin/env bash
cat "$RH_SVN_FIXTURE"
SH
cat > "$T/bin/fossil" <<'SH'
#!/usr/bin/env bash
cat "$RH_FOSSIL_FIXTURE"
SH
chmod +x "$T/bin/hg" "$T/bin/svn" "$T/bin/fossil"
PATH="$T/bin:$PATH" RH_HG_FIXTURE="$T/hg.json" \
  "$ROOT/build/rh_cli" vcs --format hg --repo "$T/repo" --out "$T/hg-live.out" >/dev/null || fail "native hg run"
PATH="$T/bin:$PATH" RH_SVN_FIXTURE="$T/svn-log.xml" \
  "$ROOT/build/rh_cli" vcs --format svn --repo "$T/repo" --out "$T/svn-live.out" >/dev/null || fail "native svn run"
PATH="$T/bin:$PATH" RH_FOSSIL_FIXTURE="$T/fossil-timeline.txt" \
  "$ROOT/build/rh_cli" vcs --format fossil --repo "$T/repo" --out "$T/fossil-live.out" >/dev/null || fail "native fossil run"
cmp -s "$T/hg.json" "$T/hg-live.out.source" || fail "native hg source evidence mismatch"
cmp -s "$T/svn-log.xml" "$T/svn-live.out.source" || fail "native svn source evidence mismatch"
cmp -s "$T/fossil-timeline.txt" "$T/fossil-live.out.source" || fail "native fossil source evidence mismatch"
[[ -f "$T/hg-live.out.source.err" && ! -s "$T/hg-live.out.source.err" ]] || fail "native hg stderr evidence"
[[ -f "$T/svn-live.out.source.err" && ! -s "$T/svn-live.out.source.err" ]] || fail "native svn stderr evidence"
[[ -f "$T/fossil-live.out.source.err" && ! -s "$T/fossil-live.out.source.err" ]] || fail "native fossil stderr evidence"
cmp -s "$T/hg.out" "$T/hg-live.out" || fail "native hg normalization mismatch"
cmp -s "$T/svn.out" "$T/svn-live.out" || fail "native svn normalization mismatch"
cmp -s "$T/fossil.out" "$T/fossil-live.out" || fail "native fossil normalization mismatch"
echo "[vcs] native --repo evidence OK"

echo "[vcs] determinism + negatives"
"$ROOT/build/rh_cli" vcs --format hg --input "$T/hg.json" --out "$T/hg2.out" >/dev/null || fail "hg rerun"
cmp -s "$T/hg.out" "$T/hg2.out" || fail "hg not deterministic"
set +e
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" vcs --format hg --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
printf '{"a":1}' > "$T/obj.json"
"$ROOT/build/rh_cli" vcs --format hg --input "$T/obj.json" --out "$T/x" >/dev/null 2>&1; rc_shape=$?
python3 - "$T/sourcehut.json" "$T/sourcehut-bad-time.json" "$T/sourcehut-errors.json" "$T/sourcehut-bad-parent.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["data"]["repository"]["log"]["results"][0]["author"]["time"] = "2021-02-30T00:00:00Z"
json.dump(d, open(sys.argv[2], "w"))
json.dump({"errors": [{"message": "forbidden"}], "data": None}, open(sys.argv[3], "w"))
d = json.load(open(sys.argv[1])); d["data"]["repository"]["log"]["results"][1]["parents"] = [{"id": ""}]
json.dump(d, open(sys.argv[4], "w"))
PY
"$ROOT/build/rh_cli" vcs --format sourcehut --input "$T/sourcehut-bad-time.json" --out "$T/sourcehut-bad-time.out" >/dev/null 2>&1; rc_sourcehut_time=$?
"$ROOT/build/rh_cli" vcs --format sourcehut --input "$T/sourcehut-errors.json" --out "$T/sourcehut-errors.out" >/dev/null 2>&1; rc_sourcehut_errors=$?
"$ROOT/build/rh_cli" vcs --format sourcehut --input "$T/sourcehut-bad-parent.json" --out "$T/sourcehut-bad-parent.out" >/dev/null 2>&1; rc_sourcehut_parent=$?
"$ROOT/build/rh_cli" vcs --format cvs --input "$T/hg.json" --out "$T/x" >/dev/null 2>&1; rc_fmt=$?
"$ROOT/build/rh_cli" vcs --format hg --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
"$ROOT/build/rh_cli" vcs --format hg --out "$T/x" >/dev/null 2>&1; rc_neither=$?
"$ROOT/build/rh_cli" vcs --format hg --input "$T/hg.json" --repo "$T/repo" --out "$T/x" >/dev/null 2>&1; rc_both=$?
"$ROOT/build/rh_cli" vcs --format patch --repo "$T/repo" --out "$T/x" >/dev/null 2>&1; rc_patch_repo=$?
set -e
[[ "$rc_json" -eq 4 ]] || fail "invalid JSON must exit 4 (got $rc_json)"
[[ "$rc_shape" -eq 4 ]] || fail "wrong-shape JSON must exit 4 (got $rc_shape)"
[[ "$rc_sourcehut_time" -eq 4 ]] || fail "invalid SourceHut calendar time must exit 4 (got $rc_sourcehut_time)"
[[ "$rc_sourcehut_errors" -eq 4 ]] || fail "GraphQL errors must exit 4 (got $rc_sourcehut_errors)"
[[ "$rc_sourcehut_parent" -eq 4 ]] || fail "empty SourceHut parent ID must exit 4 (got $rc_sourcehut_parent)"
[[ ! -e "$T/sourcehut-bad-time.out" && ! -e "$T/sourcehut-errors.out" && ! -e "$T/sourcehut-bad-parent.out" ]] || fail "failed SourceHut page must not publish a partial report"
[[ "$rc_fmt" -eq 3 ]] || fail "unknown format must exit 3 (got $rc_fmt)"
[[ "$rc_missing" -eq 4 ]] || fail "missing input must exit 4 (got $rc_missing)"
[[ "$rc_neither" -eq 2 ]] || fail "missing input/repo must exit 2 (got $rc_neither)"
[[ "$rc_both" -eq 2 ]] || fail "input and repo together must exit 2 (got $rc_both)"
[[ "$rc_patch_repo" -eq 3 ]] || fail "patch repo mode must exit 3 (got $rc_patch_repo)"

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
