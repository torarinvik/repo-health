#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER_ROOT="$ROOT/../Elisa-compiler"
cd "$ROOT"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/bin"
cat > "$T/bin/python3" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$RH_TEST_DNS_ADDRESSES" | tr ',' '\n'
SH
cat > "$T/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >> "$RH_CURL_LOG"
body_out=""
url="${!#}"
while (($#)); do
  case "$1" in
    -o) body_out="$2"; shift 2 ;;
    --config) [[ "$2" == "-" ]] || exit 20; cat > "$RH_CURL_CONFIG_LOG"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$body_out" && -n "$url" ]]
case "$url" in
  */api/v1/settings/api) body="$RH_CURL_SELFHOSTED_SETTINGS" ;;
  */issues?*page=1) body="$RH_CURL_SELFHOSTED_ISSUES_PAGE1" ;;
  */issues?*page=2) body="$RH_CURL_SELFHOSTED_ISSUES_PAGE2" ;;
  */pulls?*page=1) body="$RH_CURL_SELFHOSTED_PULLS_PAGE1" ;;
  */releases?*page=1) body="$RH_CURL_SELFHOSTED_RELEASES_PAGE1" ;;
  */releases?*page=2) body="$RH_CURL_SELFHOSTED_RELEASES_PAGE2" ;;
  *) exit 21 ;;
esac
cp "$body" "$body_out"
printf '%s' "${RH_CURL_HTTP_STATUS:-200}"
SH
chmod +x "$T/bin/python3" "$T/bin/curl"

ELISA_COMPILER_BIN="$COMPILER_ROOT/scripts/elisac_stage1.sh" \
ELISA_STAGE1_BIN="$COMPILER_ROOT/bin/elisac-stage1" \
tools/build.sh --only test_forge_instance_events >/dev/null

printf '%s\n' '{"max_response_items":2,"default_paging_num":2}' > "$T/settings.json"
printf '%s\n' '{"max_response_items":3,"default_paging_num":3}' > "$T/settings-3.json"
printf '%s\n' '[{"number":1,"state":"open","created_at":"2023-11-14T22:13:20Z","updated_at":"2023-11-15T22:13:20Z","closed_at":null,"html_url":"https://forge.example.org/owner/project/issues/1"},{"number":2,"state":"closed","created_at":"2023-11-14T22:13:20Z","updated_at":"2023-11-16T22:13:20Z","closed_at":"2023-11-16T22:13:20Z","html_url":"https://forge.example.org/owner/project/issues/2"}]' > "$T/issues-1.json"
printf '%s\n' '[{"number":3,"state":"open","created_at":"2023-11-14T22:13:20Z","updated_at":"2023-11-17T22:13:20Z","closed_at":null,"html_url":"https://forge.example.org/owner/project/issues/3"}]' > "$T/issues-2.json"
printf '%s\n' '[{"number":7,"state":"closed","created_at":"2023-11-13T22:13:20Z","updated_at":"2023-11-16T22:13:20Z","closed_at":"2023-11-17T22:13:20Z","html_url":"https://forge.example.org/owner/project/pulls/7"}]' > "$T/pulls-1.json"
printf '%s\n' '[{"id":9,"created_at":"2023-11-14T22:13:20Z","published_at":"2023-11-15T22:13:20Z","tag_name":"v1.0.0","html_url":"https://forge.example.org/owner/project/releases/tag/v1.0.0"},{"id":10,"created_at":"2023-11-14T22:13:20Z","published_at":"2023-11-16T22:13:20Z","tag_name":"v2.0.0","html_url":"https://forge.example.org/owner/project/releases/tag/v2.0.0"}]' > "$T/releases-1.json"
printf '%s\n' '[]' > "$T/empty.json"
printf '%s\n' '{"schema":"rh-connector-instance/1","connector_id":"gitea","base_url":"https://forge.example.org/gitea","approved":true}' > "$T/gitea.json"
printf '%s\n' '{"schema":"rh-connector-instance/1","connector_id":"forgejo","base_url":"https://forge.example.org/forgejo","approved":true}' > "$T/forgejo.json"
printf '%s\n' '{"schema":"rh-connector-instance/1","connector_id":"gitea","base_url":"https://forge.example.org/other","approved":true}' > "$T/different-base.json"
printf '%s\n' '{"schema":"rh-connector-instance/1","connector_id":"gitea","base_url":"https://forge.example.org/gitea","approved":false}' > "$T/unapproved.json"
printf '%s\n' '{"schema":"rh-connector-instance/1","connector_id":"forgejo","base_url":"https://127.0.0.1/forgejo","approved":true}' > "$T/loopback.json"
printf '%s\n' '{"default_paging_num":2}' > "$T/bad-settings.json"

export RH_TEST_DNS_ADDRESSES="93.184.216.34"
export RH_CURL_LOG="$T/curl.args"
export RH_CURL_CONFIG_LOG="$T/curl.config"
export RH_CURL_SELFHOSTED_SETTINGS="$T/settings.json"
export RH_CURL_SELFHOSTED_ISSUES_PAGE1="$T/issues-1.json"
export RH_CURL_SELFHOSTED_ISSUES_PAGE2="$T/issues-2.json"
export RH_CURL_SELFHOSTED_PULLS_PAGE1="$T/pulls-1.json"
export RH_CURL_SELFHOSTED_RELEASES_PAGE1="$T/releases-1.json"
export RH_CURL_SELFHOSTED_RELEASES_PAGE2="$T/empty.json"
export RH_GITEA_TOKEN="gitea_fixture_secret"
export RH_FORGEJO_TOKEN="forgejo_fixture_secret"
run_capture() {
  PATH="$T/bin:$PATH" "$ROOT/build/test_forge_instance_events" "$@"
}

echo "[forge-instance-events] approved Gitea and Forgejo instances collect bounded pages"
run_capture --instance "$T/gitea.json" --max-pages 2 "$T/gitea.out" || exit 1
python3 - "$T/gitea.out" "$T" <<'PY'
import json, pathlib, sys
result = json.load(open(sys.argv[1]))
directory = pathlib.Path(sys.argv[2])
assert result["provider"] == "gitea", result
assert result["scope"] == {"repository":"owner/project"}, result
assert result["authorization"]["state"] == "authorized", result
assert [row["native_id"] for row in result["events"]] == ["gitea:1", "gitea:2", "gitea:3", "gitea:7", "gitea:9", "gitea:10"], result["events"]
assert result["pagination"]["issues"] == {"next":None,"complete":True}, result["pagination"]
assert result["pagination"]["proposals"] == {"next":None,"complete":True}, result["pagination"]
assert result["pagination"]["releases"] == {"next":None,"complete":True}, result["pagination"]
assert (directory / "gitea.out.gitea-events-settings-page-0.json").exists()
assert (directory / "gitea.out.gitea-events-issues-page-2.url").read_text().strip().endswith("&limit=2&page=2")
published = (directory / "gitea.out").read_text()
assert "gitea_fixture_secret" not in published
PY
grep -q '^header = "Authorization: token gitea_fixture_secret"$' "$T/curl.config"
if rg -q 'gitea_fixture_secret|forgejo_fixture_secret' "$T/curl.args"; then
  echo "credential leaked into curl argv" >&2
  exit 1
fi

echo "[forge-instance-events] numeric page cursors resume with exact predecessor lineage"
run_capture --instance "$T/gitea.json" --max-pages 1 "$T/gitea-partial.out" || exit 1
pulls_before="$(python3 - "$T/curl.args" <<'PY'
import pathlib, sys
print(sum('/pulls?state=all' in line for line in pathlib.Path(sys.argv[1]).read_text().splitlines()))
PY
)"
run_capture --instance "$T/gitea.json" --max-pages 1 --resume-from "$T/gitea-partial.out" "$T/gitea-resumed.out" || exit 1
pulls_after="$(python3 - "$T/curl.args" <<'PY'
import pathlib, sys
print(sum('/pulls?state=all' in line for line in pathlib.Path(sys.argv[1]).read_text().splitlines()))
PY
)"
[[ "$pulls_before" == "$pulls_after" ]] || { echo "completed proposal capability was unexpectedly fetched during resume" >&2; exit 1; }
python3 - "$T/gitea-partial.out" "$T/gitea-resumed.out" <<'PY'
import hashlib, json, pathlib, sys
previous_path = pathlib.Path(sys.argv[1])
result = json.load(open(sys.argv[2]))
previous = previous_path.read_bytes()
assert result["segment"]["resumed_from_sha256"] == hashlib.sha256(previous).hexdigest(), result["segment"]
assert result["segment"]["instance_url_sha256"] == hashlib.sha256(b"https://forge.example.org/gitea").hexdigest(), result["segment"]
assert result["segment"]["page_size"] == 2, result["segment"]
assert result["segment"]["consumed"] == {"issues":2,"proposals":None,"releases":2}, result["segment"]
assert [row["native_id"] for row in result["events"]] == ["gitea:3"], result["events"]
assert result["capabilities"]["proposals"]["status"] == "not_attempted", result["capabilities"]
assert result["pagination"]["issues"] == {"next":None,"complete":True}, result["pagination"]
assert result["pagination"]["proposals"] == {"next":None,"complete":True}, result["pagination"]
PY

before="$(wc -l < "$T/curl.args")"
if run_capture --instance "$T/different-base.json" --max-pages 1 --resume-from "$T/gitea-partial.out" "$T/wrong-instance.out"; then
  echo "continuation from another instance was unexpectedly accepted" >&2
  exit 1
fi
after="$(wc -l < "$T/curl.args")"
[[ "$before" == "$after" ]] || { echo "mismatched instance reached curl" >&2; exit 1; }
export RH_CURL_SELFHOSTED_SETTINGS="$T/settings-3.json"
if run_capture --instance "$T/gitea.json" --max-pages 1 --resume-from "$T/gitea-partial.out" "$T/changed-page-size.out"; then
  echo "continuation under a changed server page size was unexpectedly accepted" >&2
  exit 1
fi
if rg -q 'limit=3&page=' "$T/curl.args"; then
  echo "changed page size was used to advance an existing cursor" >&2
  exit 1
fi
export RH_CURL_SELFHOSTED_SETTINGS="$T/settings.json"

run_capture --instance "$T/forgejo.json" --max-pages 2 "$T/forgejo.out" || exit 1
python3 - "$T/forgejo.out" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["provider"] == "forgejo", result
assert result["events"][0]["native_id"] == "forgejo:1", result["events"]
PY
grep -q '^header = "Authorization: token forgejo_fixture_secret"$' "$T/curl.config"

echo "[forge-instance-events] page caps expose unfinished cursors"
run_capture --instance "$T/gitea.json" --max-pages 1 "$T/capped.out" || exit 1
python3 - "$T/capped.out" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["pagination"]["issues"] == {"next":"page=2","complete":False}, result["pagination"]
PY

echo "[forge-instance-events] approval and host policy reject before transport"
before="$(wc -l < "$T/curl.args")"
if run_capture --instance "$T/unapproved.json" --max-pages 2 "$T/unapproved.out"; then
  echo "unapproved instance unexpectedly collected" >&2
  exit 1
fi
if run_capture --instance "$T/loopback.json" --max-pages 2 "$T/loopback.out"; then
  echo "loopback instance unexpectedly collected" >&2
  exit 1
fi
after="$(wc -l < "$T/curl.args")"
[[ "$before" == "$after" ]] || { echo "rejected instance reached curl" >&2; exit 1; }

echo "[forge-instance-events] malformed settings and denied responses fail closed"
export RH_CURL_SELFHOSTED_SETTINGS="$T/bad-settings.json"
if run_capture --instance "$T/gitea.json" --max-pages 2 "$T/bad-settings.out"; then
  echo "missing page limit unexpectedly collected" >&2
  exit 1
fi
export RH_CURL_SELFHOSTED_SETTINGS="$T/settings.json"
export RH_CURL_HTTP_STATUS="403"
if run_capture --instance "$T/gitea.json" --max-pages 2 "$T/denied.out"; then
  echo "denied API response unexpectedly collected" >&2
  exit 1
fi
[[ "$(cat "$T/denied.out.gitea-events-settings-page-0.status")" == "403" ]]

echo "[forge-instance-events] PASS"
