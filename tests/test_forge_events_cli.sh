#!/usr/bin/env bash
# tests/test_forge_events_cli.sh — M02-05 bounded workflow-event import.
# Public contracts: rh-forge-events-input/1 and rh-forge-events-result/1.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-forge-events"
fail() { echo "[forge-events] FAIL: $1" >&2; exit 1; }

echo "[forge-events] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/connectors/forge-events-input.json" "$T/input.json"
cp "$ROOT/fixtures/connectors/forge-events-gitlab-input.json" "$T/gitlab.json"
cp "$ROOT/fixtures/connectors/forge-events-forgejo-input.json" "$T/forgejo.json"
cp "$ROOT/fixtures/connectors/forge-events-gitea-input.json" "$T/gitea.json"
cp "$ROOT/fixtures/connectors/forge-events-bitbucket-input.json" "$T/bitbucket.json"
cp "$ROOT/fixtures/connectors/forge-events-result.json" "$T/expected.json"

echo "[forge-events] valid capture reproduces the checked-in result"
"$ROOT/build/rh_cli" forge events --input "$T/input.json" --out "$T/out.json" >/dev/null || fail "valid capture"
python3 - "$T/out.json" "$T/expected.json" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
expected = json.load(open(sys.argv[2]))
assert got == expected, (got, expected)
assert all(e["native_id"].startswith("github:") for e in got["events"])
assert all("title" not in e and "body" not in e for e in got["events"])
print("[forge-events] result and provider-native boundary OK")
PY

echo "[forge-events] additive provider fields survive schema evolution"
python3 - "$T/input.json" "$T/additive-fields.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["api_revision"] = "2026-09"
d["issues"][0]["reactions"] = {"total_count": 3}
d["issues"][0]["new_provider_flag"] = True
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/additive-fields.json" --out "$T/additive-fields.out" >/dev/null || fail "additive provider fields"
cmp -s "$T/additive-fields.out" "$T/expected.json" || fail "additive provider fields changed the canonical result"
echo "[forge-events] additive input fields are ignored without losing canonical output"

echo "[forge-events] replay is deterministic"
"$ROOT/build/rh_cli" forge events --input "$T/input.json" --out "$T/out2.json" >/dev/null || fail "replay"
cmp -s "$T/out.json" "$T/out2.json" || fail "replay changed bytes"

echo "[forge-events] GitLab native ids and release fallback remain distinct"
"$ROOT/build/rh_cli" forge events --input "$T/gitlab.json" --out "$T/gitlab.out" >/dev/null || fail "GitLab capture"
python3 - "$T/gitlab.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["provider"] == "gitlab" and d["authorization"]["state"] == "not_requested", d
assert [e["native_id"] for e in d["events"]] == ["gitlab:12", "gitlab:8", "gitlab:56", "gitlab:10"], d
assert d["events"][-1]["created_at"] == 1699900100 and d["events"][-1]["status"] == "published", d
assert d["events"][-1]["tag"] == "v2.0.0" and d["events"][-1]["url"].startswith("https://gitlab.com/"), d
print("[forge-events] GitLab boundary OK")
PY

echo "[forge-events] Forgejo keeps its own provider namespace"
"$ROOT/build/rh_cli" forge events --input "$T/forgejo.json" --out "$T/forgejo.out" >/dev/null || fail "Forgejo capture"
python3 - "$T/forgejo.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["provider"] == "forgejo" and d["authorization"]["state"] == "unknown", d
assert [e["native_id"] for e in d["events"]] == ["forgejo:21", "forgejo:11", "forgejo:66", "forgejo:12"], d
assert d["events"][-1]["status"] == "published" and d["events"][-1]["tag"] == "v3.0.0", d
print("[forge-events] Forgejo boundary OK")
PY

echo "[forge-events] Gitea keeps its own provider namespace and authorization"
"$ROOT/build/rh_cli" forge events --input "$T/gitea.json" --out "$T/gitea.out" >/dev/null || fail "Gitea capture"
python3 - "$T/gitea.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["provider"] == "gitea" and d["authorization"]["state"] == "unauthorized", d
assert [e["native_id"] for e in d["events"]] == ["gitea:31", "gitea:13", "gitea:76", "gitea:14"], d
assert d["events"][1]["status"] == "closed" and d["events"][3]["tag"] == "v4.0.0", d
print("[forge-events] Gitea boundary OK")
PY

echo "[forge-events] Bitbucket captured issues/proposals keep provider IDs"
"$ROOT/build/rh_cli" forge events --input "$T/bitbucket.json" --out "$T/bitbucket.out" >/dev/null || fail "Bitbucket capture"
python3 - "$T/bitbucket.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["provider"] == "bitbucket", d
assert d["capabilities"]["issues"] == {"status":"observed", "attempted":1, "normalized":1, "duplicate_replacements":0, "count":1, "rejected":0}, d
assert d["capabilities"]["proposals"] == {"status":"observed", "attempted":1, "normalized":1, "duplicate_replacements":0, "count":1, "rejected":0}, d
assert d["capabilities"]["reviews"]["status"] == "unsupported" and d["capabilities"]["releases"]["status"] == "unsupported", d
assert [e["native_id"] for e in d["events"]] == ["bitbucket:301", "bitbucket:17"], d["events"]
assert d["events"][1]["status"] == "MERGED", d["events"][1]
assert d["events"][0]["url"].startswith("https://bitbucket.org/"), d["events"][0]
print("[forge-events] Bitbucket provider identity + unsupported states OK")
PY

echo "[forge-events] rejected records are counted per capability"
python3 - "$T/input.json" "$T/malformed.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["issues"].append({"state": "open", "created_at": 1700000000})
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/malformed.json" --out "$T/malformed.out" >/dev/null || fail "malformed record capture"
python3 - "$T/malformed.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["issues"] == {"status":"observed", "attempted":2, "normalized":1, "duplicate_replacements":0, "count":1, "rejected":1}, d
assert d["capabilities"]["proposals"]["rejected"] == 0, d
assert len(d["events"]) == 4, d
print("[forge-events] per-capability rejection count OK")
PY

echo "[forge-events] duplicate page observations replace by provider-native identity"
python3 - "$T/input.json" "$T/duplicate-page.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["issues"].append({"number": 101, "state": "closed", "created_at": 1699000000, "updated_at": 1699999999, "closed_at": 1699999999, "html_url": "https://github.com/example/project/issues/101"})
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/duplicate-page.json" --out "$T/duplicate-page.out" >/dev/null || fail "duplicate page capture"
python3 - "$T/duplicate-page.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["issues"] == {"status":"observed", "attempted":2, "normalized":2, "duplicate_replacements":1, "count":1, "rejected":0}, d
assert len(d["events"]) == 4, d
issue = [e for e in d["events"] if e["kind"] == "issues"][0]
assert issue["status"] == "closed" and issue["updated_at"] == 1699999999, issue
print("[forge-events] duplicate replacement + count idempotence OK")
PY

echo "[forge-events] opaque pagination state is retained"
python3 - "$T/input.json" "$T/paginated.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["pagination"] = {
    "issues": {"next": "issues-page-2", "complete": False},
    "proposals": {"next": None, "complete": True},
    "reviews": {"next": "reviews-page-2", "complete": False},
    "releases": {"next": "", "complete": True},
}
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/paginated.json" --out "$T/paginated.out" >/dev/null || fail "pagination capture"
python3 - "$T/paginated.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["pagination"]["issues"] == {"next": "issues-page-2", "complete": False}, d
assert d["pagination"]["proposals"] == {"next": None, "complete": True}, d
assert d["pagination"]["releases"] == {"next": "", "complete": True}, d
print("[forge-events] pagination cursor + completion state OK")
PY

python3 - "$T/input.json" "$T/negative-time.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["issues"][0]["updated_at"] = -1
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/negative-time.json" --out "$T/negative-time.out" >/dev/null || fail "negative timestamp capture"
python3 - "$T/negative-time.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["issues"] == {"status":"observed", "attempted":1, "normalized":0, "duplicate_replacements":0, "count":0, "rejected":1}, d
print("[forge-events] negative timestamp rejection OK")
PY

echo "[forge-events] missing capabilities remain explicit unsupported"
python3 - "$T/input.json" "$T/partial.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d.pop("releases")
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/partial.json" --out "$T/partial.out" >/dev/null || fail "partial capture"
python3 - "$T/partial.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["releases"] == {"status":"unsupported", "attempted":None, "normalized":None, "duplicate_replacements":None, "count":None, "rejected":0}, d
print("[forge-events] unsupported boundary OK")
PY

echo "[forge-events] explicit empty response is observed, not unsupported"
python3 - "$T/input.json" "$T/empty-success.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["issues"] = []
d.pop("proposals")
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/empty-success.json" --out "$T/empty-success.out" >/dev/null || fail "empty success capture"
python3 - "$T/empty-success.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["issues"] == {"status":"observed", "attempted":0, "normalized":0, "duplicate_replacements":0, "count":0, "rejected":0}, d
assert d["capabilities"]["proposals"] == {"status":"unsupported", "attempted":None, "normalized":None, "duplicate_replacements":None, "count":None, "rejected":0}, d
print("[forge-events] empty observed and missing unsupported remain distinct")
PY

echo "[forge-events] record bound applies to attempts, including rejected rows"
python3 - "$T/input.json" "$T/over-limit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["issues"] = [None] * 10001
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
set +e
"$ROOT/build/rh_cli" forge events --input "$T/over-limit.json" --out "$T/over-limit.out" >/dev/null 2>&1
rc_records=$?
set -e
[[ "$rc_records" -eq 4 ]] || fail "record attempt cap must fail closed (got $rc_records)"
[[ ! -e "$T/over-limit.out" ]] || fail "over-limit capture wrote partial output"

echo "[forge-events] malformed envelopes fail closed"
set +e
printf '%s\n' '{"schema":"rh-forge-events-input/1","provider":"github","captured_at":1,"issues":{}}' > "$T/wrong-array-shape.json"
"$ROOT/build/rh_cli" forge events --input "$T/wrong-array-shape.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
printf '%s\n' '{"schema":"wrong","provider":"github","captured_at":1}' > "$T/wrong-schema.json"
"$ROOT/build/rh_cli" forge events --input "$T/wrong-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '%s\n' '{"schema":"rh-forge-events-input/1","provider":"bogus","captured_at":1}' > "$T/wrong-provider.json"
"$ROOT/build/rh_cli" forge events --input "$T/wrong-provider.json" --out "$T/x" >/dev/null 2>&1; rc_provider=$?
set -e
[[ "$rc_missing" -eq 4 ]] || fail "wrong capability array shape must exit 4 (got $rc_missing)"
[[ "$rc_schema" -eq 4 ]] || fail "wrong schema must exit 4 (got $rc_schema)"
[[ "$rc_provider" -eq 4 ]] || fail "wrong provider must exit 4 (got $rc_provider)"

echo "[forge-events] explicit not-attempted capabilities stay distinct from unsupported"
python3 - "$T/partial.json" "$T/not-attempted.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["capability_states"] = {"releases": "not_attempted"}
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/not-attempted.json" --out "$T/not-attempted.out" >/dev/null || fail "not-attempted capture"
python3 - "$T/not-attempted.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["releases"] == {"status":"not_attempted", "attempted":None, "normalized":None, "duplicate_replacements":None, "count":None, "rejected":0}, d
print("[forge-events] not-attempted state OK")
PY

echo "[forge-events] bounded live GitHub issue, pull-request, and release pages retain safe evidence"
mkdir -p "$T/bin"
python3 - "$T/live-page-1.json" "$T/live-empty.json" "$T/live-full-page.json" "$T/live-issues-page-1.json" "$T/live-issues-full-page.json" "$T/live-releases-page-1.json" "$T/live-releases-full-page.json" "$T/live-reviews-page-1.json" <<'PY'
import json, sys
pull = {"number": 7, "state": "closed", "created_at": "2023-11-14T22:13:20Z", "updated_at": "2023-11-15T22:13:20Z", "closed_at": "2023-11-16T22:13:20Z", "html_url": "https://github.com/example/project/pull/7"}
issue = {"number": 301, "state": "open", "created_at": "2023-11-14T22:13:20Z", "updated_at": "2023-11-15T22:13:20Z", "closed_at": None, "html_url": "https://github.com/example/project/issues/301"}
release = {"id": 1, "tag_name": "v1", "created_at": "2023-11-14T22:13:20Z", "published_at": "2023-11-14T22:13:20Z", "updated_at": "2023-11-15T22:13:20Z", "html_url": "https://github.com/example/project/releases/tag/v1", "draft": False}
json.dump([pull], open(sys.argv[1], "w", encoding="utf-8"), separators=(",", ":"))
open(sys.argv[2], "w", encoding="utf-8").write("[]\n")
json.dump([dict(pull, number=n, html_url=f"https://github.com/example/project/pull/{n}") for n in range(1, 101)], open(sys.argv[3], "w", encoding="utf-8"), separators=(",", ":"))
json.dump([issue], open(sys.argv[4], "w", encoding="utf-8"), separators=(",", ":"))
issue_rows = [dict(issue, number=n, html_url=f"https://github.com/example/project/issues/{n}") for n in range(201, 300)]
issue_rows.insert(0, dict(issue, number=999, pull_request={"url":"https://api.github.com/repos/example/project/pulls/999"}, html_url="https://github.com/example/project/pull/999"))
json.dump(issue_rows, open(sys.argv[5], "w", encoding="utf-8"), separators=(",", ":"))
json.dump([release], open(sys.argv[6], "w", encoding="utf-8"), separators=(",", ":"))
release_rows = [dict(release, id=n, tag_name=f"v{n}", html_url=f"https://github.com/example/project/releases/tag/v{n}") for n in range(1, 100)]
release_rows.insert(0, dict(release, id=999, tag_name="draft", published_at=None, draft=True, html_url="https://github.com/example/project/releases/tag/draft"))
json.dump(release_rows, open(sys.argv[7], "w", encoding="utf-8"), separators=(",", ":"))
review = {"id": 55, "state": "APPROVED", "submitted_at": "2023-11-14T22:13:20Z", "updated_at": "2023-11-15T22:13:20Z", "html_url": "https://github.com/example/project/pull/7#pullrequestreview-55"}
json.dump([review], open(sys.argv[8], "w", encoding="utf-8"), separators=(",", ":"))
PY
cat > "$T/bin/python3" <<'SH'
#!/usr/bin/env bash
printf '140.82.114.5\n'
SH
cat > "$T/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >> "$RH_CURL_LOG"
body_out=""
url=""
config_stdin=0
while (($#)); do
  case "$1" in
    -o) body_out="$2"; shift 2 ;;
    --config) [[ "$2" == "-" ]] || exit 20; config_stdin=1; shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
[[ -n "$body_out" && -n "$url" ]]
if [[ "$config_stdin" == "1" ]]; then cat > "$RH_CURL_CONFIG_LOG"; fi
if [[ "$url" == *"/issues?"* ]]; then
  body="$RH_CURL_ISSUES_PAGE1"
  [[ "$url" != *'page=2' ]] || body="$RH_CURL_PAGE2"
elif [[ "$url" == *"/reviews?"* ]]; then
  body="$RH_CURL_REVIEWS_PAGE1"
  [[ "$url" != *'page=2' ]] || body="$RH_CURL_PAGE2"
  [[ "$url" != *'page=3' ]] || body="$RH_CURL_PAGE3"
elif [[ "$url" == *"/pulls?"* ]]; then
  body="$RH_CURL_PULLS_PAGE1"
  [[ "$url" != *'page=2' ]] || body="$RH_CURL_PAGE2"
else
  body="$RH_CURL_RELEASES_PAGE1"
  [[ "$url" != *'page=2' ]] || body="$RH_CURL_PAGE2"
fi
cp "$body" "$body_out"
printf '%s' 200
SH
chmod +x "$T/bin/python3" "$T/bin/curl"

rm -f "$T/live.out" "$T/live.out.github-"* "$T/live-curl.args" "$T/live-curl.config"
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="ghp_fixture_token" RH_CURL_ISSUES_PAGE1="$T/live-issues-full-page.json" RH_CURL_PULLS_PAGE1="$T/live-full-page.json" RH_CURL_RELEASES_PAGE1="$T/live-releases-full-page.json" RH_CURL_PAGE2="$T/live-empty.json" \
  RH_CURL_LOG="$T/live-curl.args" RH_CURL_CONFIG_LOG="$T/live-curl.config" \
  "$ROOT/build/rh_cli" forge events --github-repo example/project --max-pages 2 --out "$T/live.out" >/dev/null || fail "live GitHub collection"
python3 - "$T/live.out" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["provider"] == "github" and d["authorization"]["state"] == "authorized", d
assert d["capabilities"]["issues"]["status"] == "observed" and d["capabilities"]["issues"]["count"] == 99, d
assert d["capabilities"]["proposals"]["status"] == "observed" and d["capabilities"]["proposals"]["count"] == 100, d
assert d["capabilities"]["releases"]["status"] == "observed" and d["capabilities"]["releases"]["count"] == 99, d
assert d["capabilities"]["reviews"]["status"] == "not_attempted", d
assert d["events"][0] == {"kind":"issues", "native_id":"github:201", "status":"open", "created_at":1700000000, "updated_at":1700086400, "closed_at":None, "url":"https://github.com/example/project/issues/201"}, d["events"][0]
assert len(d["events"]) == 298, d["events"]
assert d["events"][99]["native_id"] == "github:1", d["events"][99]
assert d["events"][199] == {"kind":"releases", "native_id":"github:1", "status":"published", "created_at":1700000000, "updated_at":1700086400, "closed_at":None, "tag":"v1", "url":"https://github.com/example/project/releases/tag/v1"}, d["events"][199]
assert d["pagination"]["issues"] == {"next":None, "complete":True}, d["pagination"]
assert d["pagination"]["proposals"] == {"next":None, "complete":True}, d["pagination"]
assert d["pagination"]["releases"] == {"next":None, "complete":True}, d["pagination"]
for suffix in ("json", "url", "status", "err"):
    assert (t / f"live.out.github-issues-page-1.{suffix}").exists(), suffix
    assert (t / f"live.out.github-pulls-page-1.{suffix}").exists(), suffix
    assert (t / f"live.out.github-releases-page-1.{suffix}").exists(), suffix
assert (t / "live.out.github-issues-page-2.status").read_text() == "200"
assert (t / "live.out.github-pulls-page-2.status").read_text() == "200"
assert (t / "live.out.github-releases-page-2.status").read_text() == "200"
assert (t / "live.out.github-issues-page-1.url").read_text().strip() == "https://api.github.com/repos/example/project/issues?state=all&sort=updated&direction=desc&per_page=100&page=1"
assert (t / "live.out.github-pulls-page-1.url").read_text().strip() == "https://api.github.com/repos/example/project/pulls?state=all&sort=updated&direction=desc&per_page=100&page=1"
assert (t / "live.out.github-releases-page-1.url").read_text().strip() == "https://api.github.com/repos/example/project/releases?per_page=100&page=1"
assert "ghp_fixture_token" not in open(sys.argv[1]).read()
print("[forge-events] live page normalization, pagination, and evidence OK")
PY
grep -Fxq 'header = "Authorization: Bearer ghp_fixture_token"' "$T/live-curl.config" || fail "live token header absent from curl stdin config"
! grep -Fq 'ghp_fixture_token' "$T/live-curl.args" || fail "live GitHub token leaked into curl arguments"
for evidence in "$T"/live.out.github-*; do
  [[ ! -f "$evidence" ]] || ! grep -Fq 'ghp_fixture_token' "$evidence" || fail "live token leaked into evidence"
done

echo "[forge-events] page limit preserves a resumable cursor"
rm -f "$T/partial-live.out" "$T/partial-live.out.github-"* "$T/partial-live-curl.args"
PATH="$T/bin:$PATH" RH_CURL_ISSUES_PAGE1="$T/live-issues-full-page.json" RH_CURL_PULLS_PAGE1="$T/live-full-page.json" RH_CURL_RELEASES_PAGE1="$T/live-releases-full-page.json" RH_CURL_PAGE2="$T/live-empty.json" \
  RH_CURL_LOG="$T/partial-live-curl.args" RH_CURL_CONFIG_LOG="$T/unused-config" \
  "$ROOT/build/rh_cli" forge events --github-repo example/project --max-pages 1 --out "$T/partial-live.out" >/dev/null || fail "page-limited GitHub collection"
python3 - "$T/partial-live.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["authorization"]["state"] == "not_requested", d["authorization"]
assert d["capabilities"]["issues"]["count"] == 99, d["capabilities"]["issues"]
assert d["capabilities"]["proposals"]["count"] == 100, d["capabilities"]["proposals"]
assert d["capabilities"]["releases"]["count"] == 99, d["capabilities"]["releases"]
assert d["pagination"]["issues"] == {"next":"page=2", "complete":False}, d["pagination"]
assert d["pagination"]["proposals"] == {"next":"page=2", "complete":False}, d["pagination"]
assert d["pagination"]["releases"] == {"next":"page=2", "complete":False}, d["pagination"]
print("[forge-events] bounded continuation cursor OK")
PY
[[ "$(grep -c 'page=1' "$T/partial-live-curl.args")" -eq 3 ]] || fail "collector exceeded max-pages"

echo "[forge-events] short pages terminate and unsafe routes fail before transport"
rm -f "$T/short-live.out" "$T/short-live.out.github-"* "$T/short-live-curl.args"
PATH="$T/bin:$PATH" RH_CURL_ISSUES_PAGE1="$T/live-issues-page-1.json" RH_CURL_PULLS_PAGE1="$T/live-page-1.json" RH_CURL_RELEASES_PAGE1="$T/live-releases-page-1.json" RH_CURL_PAGE2="$T/live-empty.json" \
  RH_CURL_LOG="$T/short-live-curl.args" RH_CURL_CONFIG_LOG="$T/unused-config" \
  "$ROOT/build/rh_cli" forge events --github-repo example/project --max-pages 2 --out "$T/short-live.out" >/dev/null || fail "short-page GitHub collection"
python3 - "$T/short-live.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["proposals"]["count"] == 1, d["capabilities"]["proposals"]
assert d["capabilities"]["issues"]["count"] == 1 and d["capabilities"]["releases"]["count"] == 1, d["capabilities"]
assert d["pagination"]["proposals"] == {"next":None, "complete":True}, d["pagination"]
assert d["pagination"]["issues"]["complete"] and d["pagination"]["releases"]["complete"], d["pagination"]
print("[forge-events] short-page completion OK")
PY
[[ "$(grep -c 'page=1' "$T/short-live-curl.args")" -eq 3 ]] || fail "collector requested a page after a short response"
[[ ! -e "$T/short-live.out.github-issues-page-2.status" && ! -e "$T/short-live.out.github-pulls-page-2.status" && ! -e "$T/short-live.out.github-releases-page-2.status" ]] || fail "collector requested a page after a short response"

echo "[forge-events] pull-request review collection stays scoped and paginated"
rm -f "$T/reviews.out" "$T/reviews.out.github-"* "$T/reviews-curl.args" "$T/reviews-curl.config"
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="ghp_review_fixture" RH_CURL_REVIEWS_PAGE1="$T/live-reviews-page-1.json" RH_CURL_PAGE2="$T/live-empty.json" \
  RH_CURL_LOG="$T/reviews-curl.args" RH_CURL_CONFIG_LOG="$T/reviews-curl.config" \
  "$ROOT/build/rh_cli" forge events --github-repo example/project --review-pull 7 --max-pages 2 --out "$T/reviews.out" >/dev/null || fail "scoped review collection"
python3 - "$T/reviews.out" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["scope"] == {"pull_request":7}, d
assert d["authorization"]["state"] == "authorized", d["authorization"]
assert d["capabilities"]["reviews"]["status"] == "observed" and d["capabilities"]["reviews"]["count"] == 1, d["capabilities"]
assert all(d["capabilities"][key]["status"] == "not_attempted" for key in ("issues", "proposals", "releases")), d["capabilities"]
assert d["events"] == [{"kind":"reviews", "native_id":"github:55", "status":"APPROVED", "created_at":1700000000, "updated_at":1700086400, "closed_at":None, "url":"https://github.com/example/project/pull/7#pullrequestreview-55"}], d["events"]
assert d["pagination"]["reviews"] == {"next":None, "complete":True}, d["pagination"]
assert (t / "reviews.out.github-reviews-pr-7-page-1.url").read_text().strip() == "https://api.github.com/repos/example/project/pulls/7/reviews?per_page=100&page=1"
assert (t / "reviews.out.github-reviews-pr-7-page-1.status").read_text() == "200"
assert "ghp_review_fixture" not in open(sys.argv[1]).read()
print("[forge-events] scoped review identity, authorization, and evidence OK")
PY
grep -Fxq 'header = "Authorization: Bearer ghp_review_fixture"' "$T/reviews-curl.config" || fail "review token header absent from curl stdin config"
! grep -Fq 'ghp_review_fixture' "$T/reviews-curl.args" || fail "review token leaked into curl arguments"
for evidence in "$T"/reviews.out.github-reviews-pr-*; do
  [[ ! -f "$evidence" ]] || ! grep -Fq 'ghp_review_fixture' "$evidence" || fail "review token leaked into evidence"
done

echo "[forge-events] scoped review cursor resumes at the exact numeric page"
python3 - "$T/review-full-page.json" "$T/review-page-3.json" <<'PY'
import json, sys
review = {"state":"COMMENTED", "submitted_at":"2023-11-14T22:13:20Z", "updated_at":"2023-11-15T22:13:20Z", "html_url":"https://github.com/example/project/pull/7#pullrequestreview-1"}
json.dump([dict(review, id=n, html_url=f"https://github.com/example/project/pull/7#pullrequestreview-{n}") for n in range(1, 101)], open(sys.argv[1], "w", encoding="utf-8"), separators=(",", ":"))
json.dump([dict(review, id=101, html_url="https://github.com/example/project/pull/7#pullrequestreview-101")], open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
rm -f "$T/review-page-2.out" "$T/review-page-2.out.github-"* "$T/review-page-2-curl.args"
PATH="$T/bin:$PATH" RH_CURL_REVIEWS_PAGE1="$T/live-empty.json" RH_CURL_PAGE2="$T/review-full-page.json" RH_CURL_PAGE3="$T/live-empty.json" \
  RH_CURL_LOG="$T/review-page-2-curl.args" RH_CURL_CONFIG_LOG="$T/unused-config" \
  "$ROOT/build/rh_cli" forge events --github-repo example/project --review-pull 7 --review-page 2 --max-pages 1 --out "$T/review-page-2.out" >/dev/null || fail "review page-2 continuation"
python3 - "$T/review-page-2.out" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["scope"] == {"pull_request":7}, d
assert d["capabilities"]["reviews"]["count"] == 100, d["capabilities"]
assert d["pagination"]["reviews"] == {"next":"page=3", "complete":False}, d["pagination"]
assert (t / "review-page-2.out.github-reviews-pr-7-page-2.url").read_text().strip().endswith("/reviews?per_page=100&page=2")
assert "page=2" in open(t / "review-page-2-curl.args").read(), open(t / "review-page-2-curl.args").read()
print("[forge-events] review page-2 cursor and scope preserved")
PY
rm -f "$T/review-page-3.out" "$T/review-page-3.out.github-"* "$T/review-page-3-curl.args"
PATH="$T/bin:$PATH" RH_CURL_REVIEWS_PAGE1="$T/live-empty.json" RH_CURL_PAGE2="$T/live-empty.json" RH_CURL_PAGE3="$T/review-page-3.json" \
  RH_CURL_LOG="$T/review-page-3-curl.args" RH_CURL_CONFIG_LOG="$T/unused-config" \
  "$ROOT/build/rh_cli" forge events --github-repo example/project --review-pull 7 --review-page 3 --max-pages 1 --out "$T/review-page-3.out" >/dev/null || fail "review page-3 continuation"
python3 - "$T/review-page-3.out" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["capabilities"]["reviews"]["count"] == 1, d["capabilities"]
assert d["events"][0]["native_id"] == "github:101", d["events"]
assert d["pagination"]["reviews"] == {"next":None, "complete":True}, d["pagination"]
assert (t / "review-page-3.out.github-reviews-pr-7-page-3.url").read_text().strip().endswith("/reviews?per_page=100&page=3")
assert "page=3" in open(t / "review-page-3-curl.args").read(), open(t / "review-page-3-curl.args").read()
print("[forge-events] review cursor continuation terminates on a short page")
PY

set +e
PATH="$T/bin:$PATH" RH_CURL_LOG="$T/invalid-route-curl.args" RH_CURL_CONFIG_LOG="$T/unused-config" \
  "$ROOT/build/rh_cli" forge events --github-repo 'example/../project' --out "$T/invalid-route.out" >/dev/null 2>&1
rc_route=$?
"$ROOT/build/rh_cli" forge events --github-repo example/project --max-pages 11 --out "$T/invalid-pages.out" >/dev/null 2>&1
rc_pages=$?
"$ROOT/build/rh_cli" forge events --github-repo example/project --review-page 2 --out "$T/invalid-review-page.out" >/dev/null 2>&1
rc_review_page=$?
set -e
[[ "$rc_route" -eq 4 && "$rc_pages" -eq 2 && "$rc_review_page" -eq 2 ]] || fail "unsafe repo or page bound was accepted (route=$rc_route pages=$rc_pages review-page=$rc_review_page)"
[[ ! -e "$T/invalid-route-curl.args" && ! -e "$T/invalid-route.out" ]] || fail "invalid repository reached transport or wrote a result"

echo "test_forge_events_cli OK"
