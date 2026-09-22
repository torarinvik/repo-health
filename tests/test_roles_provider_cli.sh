#!/usr/bin/env bash
# Provider permission imports retain authorization evidence and normalize
# GitHub/GitLab role vocabularies into the generic role input contract.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-roles-provider"
cd "$ROOT"

fail() { echo "[roles-provider] FAIL: $1" >&2; exit 1; }

echo "[roles-provider] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
mkdir -p "$T"

echo "[roles-provider] GitHub mapping"
"$ROOT/build/rh_cli" roles-import --input fixtures/roles/github-provider-input.json --out "$T/github.json" >/dev/null || fail "GitHub import"
python3 - "$T/github.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d == {
  "schema": "rh-roles-input/1",
  "provider": "github",
  "authorization": {"state": "authorized"},
  "declarations": [
    {"actor_id": 7001, "role": "owner", "permission": 1, "source": "provider", "declared_at": 1700000000},
    {"actor_id": 7002, "role": "maintainer", "permission": 2, "source": "provider", "declared_at": 1700000000},
    {"actor_id": 7003, "role": "triager", "permission": 4, "source": "provider", "declared_at": 1700000000},
    {"actor_id": 7004, "role": "member", "permission": 8, "source": "provider", "declared_at": 1700000000},
    {"actor_id": 7005, "role": "unknown", "permission": 0, "source": "provider", "declared_at": 1700000000},
  ],
}, d
print("[roles-provider] GitHub mapping + unknown role OK")
PY

echo "[roles-provider] GitLab mapping"
"$ROOT/build/rh_cli" roles-import --input fixtures/roles/gitlab-provider-input.json --out "$T/gitlab.json" >/dev/null || fail "GitLab import"
python3 - "$T/gitlab.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert [x["role"] for x in d["declarations"]] == ["owner", "maintainer", "member", "member"], d
assert [x["permission"] for x in d["declarations"]] == [1, 2, 8, 8], d
assert all(x["source"] == "provider" for x in d["declarations"]), d
print("[roles-provider] GitLab access levels OK")
PY

echo "[roles-provider] restricted publication consumes normalized evidence"
"$ROOT/build/rh_cli" roles-publish --input "$T/github.json" --out "$T/public.json" >/dev/null || fail "restricted publication"
python3 - "$T/public.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
raw = open(sys.argv[1], encoding="utf-8").read()
assert d["schema"] == "rh-role-publication-result/1", d
assert d["authorization_state"] == "authorized", d
assert "7001" not in raw and "permission documents" in d["note"], d
print("[roles-provider] restricted publication boundary OK")
PY

echo "[roles-provider] unauthorized capture withholds declarations"
cat > "$T/unauthorized.json" <<'JSON'
{"schema":"rh-provider-roles-input/1","provider":"github","authorization":{"state":"unauthorized"},"captured_at":1700000000,"members":[{"id":9001,"permission":"admin"}]}
JSON
"$ROOT/build/rh_cli" roles-import --input "$T/unauthorized.json" --out "$T/unauthorized-out.json" >/dev/null || fail "unauthorized import"
python3 - "$T/unauthorized-out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["authorization"] == {"state": "unauthorized"}, d
assert d["declarations"] == [], d
print("[roles-provider] unauthorized state is fail-closed")
PY

echo "[roles-provider] deterministic replay"
"$ROOT/build/rh_cli" roles-import --input fixtures/roles/github-provider-input.json --out "$T/github-2.json" >/dev/null || fail "replay"
cmp -s "$T/github.json" "$T/github-2.json" || fail "output not deterministic"

echo "[roles-provider] duplicate page observations replace by actor identity"
python3 - "fixtures/roles/github-provider-input.json" "$T/duplicate-page.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["members"].append({"id": 7002, "permission": "admin"})
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" roles-import --input "$T/duplicate-page.json" --out "$T/duplicate-page.out" >/dev/null || fail "duplicate role page"
python3 - "$T/duplicate-page.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert len(d["declarations"]) == 5, d
actor = [x for x in d["declarations"] if x["actor_id"] == 7002]
assert actor == [{"actor_id": 7002, "role": "owner", "permission": 1, "source": "provider", "declared_at": 1700000000}], actor
print("[roles-provider] duplicate replacement + bounded declarations OK")
PY

echo "[roles-provider] opaque pagination state is retained"
python3 - "fixtures/roles/github-provider-input.json" "$T/paginated.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["pagination"] = {"next": "members-page-2", "complete": False}
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" roles-import --input "$T/paginated.json" --out "$T/paginated.out" >/dev/null || fail "pagination import"
python3 - "$T/paginated.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["pagination"] == {"next": "members-page-2", "complete": False}, d
assert d["permission_inventory_complete"] is False, d
print("[roles-provider] pagination cursor + completion state OK")
PY

echo "[roles-provider] authenticated GitHub collaborator snapshot preserves scope and completeness"
mkdir -p "$T/bin"
python3 - "$T/collaborators-short.json" "$T/collaborators-full.json" "$T/collaborators-page-2.json" "$T/collaborators-page-3.json" <<'PY'
import json, sys
short = [
    {"id": 7101, "login": "owner-login", "role_name": "admin", "permissions": {"admin": True}},
    {"id": 7102, "login": "maintainer-login", "role_name": "maintain", "permissions": {"maintain": True}},
    {"id": 7103, "login": "custom-login", "role_name": "custom-reviewer", "permissions": {"push": True}},
]
full = [{"id": 8000 + i, "login": f"collaborator-{i}", "role_name": "read", "permissions": {"pull": True}} for i in range(100)]
page2 = [{"id": 8100 + i, "login": f"later-collaborator-{i}", "role_name": "read", "permissions": {"pull": True}} for i in range(100)]
page3 = [
    {"id": 8100, "login": "later-collaborator-0", "role_name": "admin", "permissions": {"admin": True}},
    {"id": 9001, "login": "new-collaborator", "role_name": "triage", "permissions": {"triage": True}},
]
json.dump(short, open(sys.argv[1], "w"), separators=(",", ":"))
json.dump(full, open(sys.argv[2], "w"), separators=(",", ":"))
json.dump(page2, open(sys.argv[3], "w"), separators=(",", ":"))
json.dump(page3, open(sys.argv[4], "w"), separators=(",", ":"))
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
if [[ "$url" == https://gitlab.com/* ]]; then
  body="$RH_CURL_GITLAB_PAGE1"
  [[ "$url" != *'page=2' ]] || body="$RH_CURL_GITLAB_PAGE2"
else
  body="$RH_CURL_COLLABORATORS_PAGE1"
  [[ "$url" != *'page=2' ]] || body="$RH_CURL_COLLABORATORS_PAGE2"
  [[ "$url" != *'page=3' ]] || body="$RH_CURL_COLLABORATORS_PAGE3"
fi
cp "$body" "$body_out"
printf '%s' 200
SH
chmod +x "$T/bin/python3" "$T/bin/curl"
rm -f "$T/github-live.json" "$T/github-live.json.github-collaborators-page-"* "$T/roles-curl.args" "$T/roles-curl.config"
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="ghp_roles_fixture" RH_CURL_COLLABORATORS_PAGE1="$T/collaborators-short.json" RH_CURL_COLLABORATORS_PAGE2="$T/collaborators-page-2.json" RH_CURL_COLLABORATORS_PAGE3="$T/collaborators-page-3.json" \
  RH_CURL_LOG="$T/roles-curl.args" RH_CURL_CONFIG_LOG="$T/roles-curl.config" \
  "$ROOT/build/rh_cli" roles-import --github-repo example/project --max-pages 2 --out "$T/github-live.json" >/dev/null || fail "GitHub collaborator fetch"
python3 - "$T/github-live.json" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["schema"] == "rh-roles-input/1", d
assert d["authorization"] == {"state": "authorized"}, d
assert d["scope"] == {"repository": "example/project"}, d
assert d["pagination"] == {"next": None, "complete": True}, d
assert d["permission_inventory_complete"] is True, d
assert d["pages_fetched"] == 1, d
assert [x["role"] for x in d["declarations"]] == ["owner", "maintainer", "unknown"], d
assert [x["actor_id"] for x in d["declarations"]] == [7101, 7102, 7103], d
assert all(login not in open(sys.argv[1]).read() for login in ("owner-login", "maintainer-login", "custom-login"))
url = (t / "github-live.json.github-collaborators-page-1.url").read_text().strip()
assert url == "https://api.github.com/repos/example/project/collaborators?affiliation=all&per_page=100&page=1", url
assert (t / "github-live.json.github-collaborators-page-1.status").read_text() == "200"
print("[roles-provider] authenticated GitHub scope, roles, and complete inventory OK")
PY
grep -Fxq 'header = "Authorization: Bearer ghp_roles_fixture"' "$T/roles-curl.config" || fail "permission token header absent from curl stdin config"
! grep -Fq 'ghp_roles_fixture' "$T/roles-curl.args" || fail "permission token leaked into curl arguments"
! grep -Fq 'ghp_roles_fixture' "$T/github-live.json.github-collaborators-page-1.json" || fail "permission token leaked into raw evidence"

echo "[roles-provider] authenticated GitLab project-member inventory is bounded and resumable"
python3 - "$T/gitlab-page-full.json" "$T/gitlab-page-short.json" <<'PY'
import json, sys
full = [{"id": 10000 + i, "access_level": 20 if i == 0 else 30, "username": f"person-{i}"} for i in range(100)]
short = [{"id": 10000, "access_level": 40, "username": "person-0"}, {"id": 20001, "access_level": 50, "username": "person-final"}]
json.dump(full, open(sys.argv[1], "w"), separators=(",", ":"))
json.dump(short, open(sys.argv[2], "w"), separators=(",", ":"))
PY
rm -f "$T/gitlab-partial.json" "$T/gitlab-partial.json.gitlab-members-page-"* "$T/gitlab-roles-curl.args" "$T/gitlab-roles-curl.config"
PATH="$T/bin:$PATH" RH_GITLAB_TOKEN="glpat_roles_fixture" RH_CURL_GITLAB_PAGE1="$T/gitlab-page-full.json" RH_CURL_GITLAB_PAGE2="$T/gitlab-page-short.json" \
  RH_CURL_LOG="$T/gitlab-roles-curl.args" RH_CURL_CONFIG_LOG="$T/gitlab-roles-curl.config" \
  "$ROOT/build/rh_cli" roles-import --gitlab-project group/subgroup/project --max-pages 1 --out "$T/gitlab-partial.json" >/dev/null || fail "GitLab project-member fetch"
python3 - "$T/gitlab-partial.json" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["provider"] == "gitlab" and d["scope"] == {"project_path": "group/subgroup/project"}, d
assert d["pagination"] == {"next": "page=2", "complete": False} and d["permission_inventory_complete"] is False, d
assert len(d["declarations"]) == 100 and d["declarations"][0]["role"] == "member", d
url = (t / "gitlab-partial.json.gitlab-members-page-1.url").read_text().strip()
assert url == "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/members/all?per_page=100&page=1", url
assert "person-0" not in open(sys.argv[1]).read()
print("[roles-provider] GitLab partial inventory and nested project scope OK")
PY
grep -Fxq 'header = "PRIVATE-TOKEN: glpat_roles_fixture"' "$T/gitlab-roles-curl.config" || fail "GitLab token header absent from curl stdin config"
! grep -Fq 'glpat_roles_fixture' "$T/gitlab-roles-curl.args" || fail "GitLab token leaked into curl arguments"
python3 - "$T/gitlab-partial.json" "$T/gitlab-wrong-scope.json" "$T/gitlab-skipped-cursor.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
wrong_scope = dict(d)
wrong_scope["scope"] = {"project_path": "group/other/project"}
json.dump(wrong_scope, open(sys.argv[2], "w"), separators=(",", ":"))
bad_cursor = dict(d)
bad_cursor["pagination"] = {"next": "page=3", "complete": False}
json.dump(bad_cursor, open(sys.argv[3], "w"), separators=(",", ":"))
PY
for resume_case in wrong-scope skipped-cursor; do
  rm -f "$T/gitlab-$resume_case.out" "$T/gitlab-$resume_case-curl.args"
  set +e
  PATH="$T/bin:$PATH" RH_GITLAB_TOKEN="glpat_roles_fixture" RH_CURL_LOG="$T/gitlab-$resume_case-curl.args" RH_CURL_CONFIG_LOG="$T/gitlab-$resume_case.config" \
    "$ROOT/build/rh_cli" roles-import --gitlab-project group/subgroup/project --resume-from "$T/gitlab-$resume_case.json" --out "$T/gitlab-$resume_case.out" >/dev/null 2>&1
  resume_rc=$?
  set -e
  [[ "$resume_rc" -eq 4 && ! -e "$T/gitlab-$resume_case-curl.args" && ! -e "$T/gitlab-$resume_case.out" ]] || fail "GitLab resume accepted $resume_case or made a request before validation"
done
echo "[roles-provider] GitLab resume rejects wrong scope and skipped cursor before network access"
rm -f "$T/gitlab-complete.json" "$T/gitlab-complete.json.gitlab-members-page-"* "$T/gitlab-resume-curl.args" "$T/gitlab-resume-curl.config"
PATH="$T/bin:$PATH" RH_GITLAB_TOKEN="glpat_roles_fixture" RH_CURL_GITLAB_PAGE1="$T/gitlab-page-full.json" RH_CURL_GITLAB_PAGE2="$T/gitlab-page-short.json" \
  RH_CURL_LOG="$T/gitlab-resume-curl.args" RH_CURL_CONFIG_LOG="$T/gitlab-resume-curl.config" \
  "$ROOT/build/rh_cli" roles-import --gitlab-project group/subgroup/project --resume-from "$T/gitlab-partial.json" --max-pages 1 --out "$T/gitlab-complete.json" >/dev/null || fail "resume GitLab project-member inventory"
python3 - "$T/gitlab-complete.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["provider"] == "gitlab" and d["scope"] == {"project_path": "group/subgroup/project"}, d
assert d["pagination"] == {"next": None, "complete": True} and d["permission_inventory_complete"] is True, d
assert d["pages_fetched"] == 2 and len(d["declarations"]) == 101, d
assert next(x for x in d["declarations"] if x["actor_id"] == 10000)["role"] == "maintainer", d
assert next(x for x in d["declarations"] if x["actor_id"] == 20001)["role"] == "owner", d
print("[roles-provider] resumed GitLab inventory merges IDs and completes scope")
PY
grep -Fxq 'https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/members/all?per_page=100&page=2' "$T/gitlab-resume-curl.args" || fail "GitLab resume did not fetch cursor page 2"
! grep -Fxq 'https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/members/all?per_page=100&page=1' "$T/gitlab-resume-curl.args" || fail "GitLab resume restarted at page 1"
python3 - "$T/gitlab-complete.json" "$T/gitlab-complete-ready.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["as_of"] = max(x["declared_at"] for x in d["declarations"])
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" roles --input "$T/gitlab-complete-ready.json" --out "$T/gitlab-roles-result.json" >/dev/null || fail "GitLab permission coverage report"
python3 - "$T/gitlab-roles-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert d["scope"] == {"project_path": "group/subgroup/project"}, d
assert m["maintainer.permission_inventory_coverage"]["status"] == "observed", m
assert m["maintainer.permission_inventory_coverage"]["value"] == {"num": 101, "den": 101}, m
print("[roles-provider] GitLab inventory scope and coverage reach roles report")
PY
python3 - "$T/github-live.json" "$T/github-live-ready.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["as_of"] = d["declarations"][0]["declared_at"]
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" roles --input "$T/github-live-ready.json" --out "$T/github-live-result.json" >/dev/null || fail "scoped roles report"
python3 - "$T/github-live-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["scope"] == {"repository": "example/project"}, d
coverage = next(x for x in d["metrics"] if x["key"] == "maintainer.permission_inventory_coverage")
assert coverage["status"] == "observed" and coverage["value"] == {"num": 3, "den": 3}, coverage
print("[roles-provider] scoped permission coverage reaches the role report")
PY

echo "[roles-provider] page cap keeps incomplete permission coverage explicit"
rm -f "$T/github-partial.json" "$T/github-partial.json.github-collaborators-page-"* "$T/roles-partial-curl.args" "$T/roles-partial-curl.config"
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="ghp_roles_fixture" RH_CURL_COLLABORATORS_PAGE1="$T/collaborators-full.json" RH_CURL_COLLABORATORS_PAGE2="$T/collaborators-page-2.json" RH_CURL_COLLABORATORS_PAGE3="$T/collaborators-page-3.json" \
  RH_CURL_LOG="$T/roles-partial-curl.args" RH_CURL_CONFIG_LOG="$T/roles-partial-curl.config" \
  "$ROOT/build/rh_cli" roles-import --github-repo example/project --max-pages 1 --out "$T/github-partial.json" >/dev/null || fail "partial GitHub collaborator fetch"
python3 - "$T/github-partial.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["pagination"] == {"next": "page=2", "complete": False}, d
assert d["permission_inventory_complete"] is False, d
assert d["pages_fetched"] == 1, d
assert len(d["declarations"]) == 100, d
print("[roles-provider] page cap emits a continuation cursor without claiming coverage")
PY

echo "[roles-provider] continuation validates scope and merges pages by provider actor id"
python3 - "$T/github-partial.json" "$T/github-wrong-scope.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["scope"]["repository"] = "other/project"
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
rm -f "$T/github-wrong-scope.out" "$T/wrong-scope-curl.args"
set +e
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="ghp_roles_fixture" RH_CURL_LOG="$T/wrong-scope-curl.args" RH_CURL_CONFIG_LOG="$T/wrong-scope-curl.config" \
  "$ROOT/build/rh_cli" roles-import --github-repo example/project --resume-from "$T/github-wrong-scope.json" --out "$T/github-wrong-scope.out" >/dev/null 2>&1
rc_wrong_scope=$?
set -e
[[ "$rc_wrong_scope" -eq 4 && ! -e "$T/wrong-scope-curl.args" && ! -e "$T/github-wrong-scope.out" ]] || fail "resume crossed repository scope"
python3 - "$T/github-partial.json" "$T/github-bad-cursor.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["pagination"]["next"] = "page=2&state=all"
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
rm -f "$T/github-bad-cursor.out" "$T/bad-cursor-curl.args"
set +e
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="ghp_roles_fixture" RH_CURL_LOG="$T/bad-cursor-curl.args" RH_CURL_CONFIG_LOG="$T/bad-cursor-curl.config" \
  "$ROOT/build/rh_cli" roles-import --github-repo example/project --resume-from "$T/github-bad-cursor.json" --out "$T/github-bad-cursor.out" >/dev/null 2>&1
rc_bad_cursor=$?
set -e
[[ "$rc_bad_cursor" -eq 4 && ! -e "$T/bad-cursor-curl.args" && ! -e "$T/github-bad-cursor.out" ]] || fail "resume accepted a nonnumeric cursor"
python3 - "$T/github-partial.json" "$T/github-skipped-cursor.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["pagination"]["next"] = "page=3"
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
rm -f "$T/github-skipped-cursor.out" "$T/skipped-cursor-curl.args"
set +e
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="ghp_roles_fixture" RH_CURL_LOG="$T/skipped-cursor-curl.args" RH_CURL_CONFIG_LOG="$T/skipped-cursor-curl.config" \
  "$ROOT/build/rh_cli" roles-import --github-repo example/project --resume-from "$T/github-skipped-cursor.json" --out "$T/github-skipped-cursor.out" >/dev/null 2>&1
rc_skipped_cursor=$?
set -e
[[ "$rc_skipped_cursor" -eq 4 && ! -e "$T/skipped-cursor-curl.args" && ! -e "$T/github-skipped-cursor.out" ]] || fail "resume skipped an uncaptured page"
rm -f "$T/github-resume-page-2.json" "$T/github-resume-page-2.json.github-collaborators-page-"* "$T/roles-resume-page-2-curl.args" "$T/roles-resume-page-2-curl.config"
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="ghp_roles_fixture" RH_CURL_COLLABORATORS_PAGE1="$T/collaborators-short.json" RH_CURL_COLLABORATORS_PAGE2="$T/collaborators-page-2.json" RH_CURL_COLLABORATORS_PAGE3="$T/collaborators-page-3.json" \
  RH_CURL_LOG="$T/roles-resume-page-2-curl.args" RH_CURL_CONFIG_LOG="$T/roles-resume-page-2-curl.config" \
  "$ROOT/build/rh_cli" roles-import --github-repo example/project --resume-from "$T/github-partial.json" --max-pages 1 --out "$T/github-resume-page-2.json" >/dev/null || fail "resume GitHub collaborator page 2"
python3 - "$T/github-partial.json" "$T/github-resume-page-2.json" <<'PY'
import json, sys
previous = json.load(open(sys.argv[1]))
d = json.load(open(sys.argv[2]))
assert d["pagination"] == {"next": "page=3", "complete": False}, d
assert d["permission_inventory_complete"] is False, d
assert d["pages_fetched"] == 2, d
assert len(d["declarations"]) == 200, d
assert next(x for x in d["declarations"] if x["actor_id"] == 8100)["role"] == "member", d
assert next(x for x in d["declarations"] if x["actor_id"] == 8000)["declared_at"] == next(x for x in previous["declarations"] if x["actor_id"] == 8000)["declared_at"], d
print("[roles-provider] resumed page advances the cursor and retains earlier declarations")
PY
grep -Fxq 'https://api.github.com/repos/example/project/collaborators?affiliation=all&per_page=100&page=2' "$T/roles-resume-page-2-curl.args" || fail "resume did not fetch cursor page 2"
! grep -Fxq 'https://api.github.com/repos/example/project/collaborators?affiliation=all&per_page=100&page=1' "$T/roles-resume-page-2-curl.args" || fail "resume restarted from page 1"
rm -f "$T/github-resume-complete.json" "$T/github-resume-complete.json.github-collaborators-page-"* "$T/roles-resume-page-3-curl.args" "$T/roles-resume-page-3-curl.config"
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="ghp_roles_fixture" RH_CURL_COLLABORATORS_PAGE1="$T/collaborators-short.json" RH_CURL_COLLABORATORS_PAGE2="$T/collaborators-page-2.json" RH_CURL_COLLABORATORS_PAGE3="$T/collaborators-page-3.json" \
  RH_CURL_LOG="$T/roles-resume-page-3-curl.args" RH_CURL_CONFIG_LOG="$T/roles-resume-page-3-curl.config" \
  "$ROOT/build/rh_cli" roles-import --github-repo example/project --resume-from "$T/github-resume-page-2.json" --max-pages 1 --out "$T/github-resume-complete.json" >/dev/null || fail "resume GitHub collaborator page 3"
python3 - "$T/github-resume-complete.json" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["pagination"] == {"next": None, "complete": True}, d
assert d["permission_inventory_complete"] is True, d
assert d["pages_fetched"] == 3, d
assert len(d["declarations"]) == 201, d
assert next(x for x in d["declarations"] if x["actor_id"] == 8100)["role"] == "owner", d
assert next(x for x in d["declarations"] if x["actor_id"] == 9001)["role"] == "triager", d
assert (t / "github-resume-complete.json.github-collaborators-page-3.status").read_text() == "200"
print("[roles-provider] final short page completes the merged permission inventory")
PY
grep -Fxq 'https://api.github.com/repos/example/project/collaborators?affiliation=all&per_page=100&page=3' "$T/roles-resume-page-3-curl.args" || fail "resume did not fetch cursor page 3"
python3 - "$T/github-resume-complete.json" "$T/github-resume-ready.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["as_of"] = max(x["declared_at"] for x in d["declarations"])
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" roles --input "$T/github-resume-ready.json" --out "$T/github-resume-result.json" >/dev/null || fail "resumed scoped roles report"
python3 - "$T/github-resume-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert d["scope"] == {"repository": "example/project"}, d
assert m["maintainer.permission_inventory_coverage"]["status"] == "observed", m
assert m["maintainer.permission_inventory_coverage"]["value"] == {"num": 201, "den": 201}, m
print("[roles-provider] resumed coverage reaches the report with scope intact")
PY

python3 - "$T/github-partial.json" "$T/github-partial-ready.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["as_of"] = d["declarations"][0]["declared_at"]
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" roles --input "$T/github-partial-ready.json" --out "$T/github-partial-result.json" >/dev/null || fail "partial scoped roles report"
python3 - "$T/github-partial-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["maintainer.permission_inventory_coverage"]["status"] == "unsupported", m
assert m["maintainer.permission_inventory_coverage"]["reason"] == "permission-inventory-completeness-not-supplied", m
print("[roles-provider] partial collaborator page cannot claim permission coverage")
PY

echo "[roles-provider] live permission fetch requires an explicit token"
rm -f "$T/no-token.out" "$T/no-token-curl.args"
set +e
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="" RH_CURL_LOG="$T/no-token-curl.args" RH_CURL_CONFIG_LOG="$T/no-token-curl.config" \
  "$ROOT/build/rh_cli" roles-import --github-repo example/project --out "$T/no-token.out" >/dev/null 2>&1
rc_no_token=$?
set -e
[[ "$rc_no_token" -eq 4 && ! -e "$T/no-token-curl.args" && ! -e "$T/no-token.out" ]] || fail "permission fetch proceeded without an explicit token"
rm -f "$T/gitlab-no-token.out" "$T/gitlab-no-token-curl.args"
set +e
PATH="$T/bin:$PATH" RH_GITLAB_TOKEN="" RH_CURL_LOG="$T/gitlab-no-token-curl.args" RH_CURL_CONFIG_LOG="$T/gitlab-no-token.config" \
  "$ROOT/build/rh_cli" roles-import --gitlab-project group/project --out "$T/gitlab-no-token.out" >/dev/null 2>&1
rc_gitlab_no_token=$?
set -e
[[ "$rc_gitlab_no_token" -eq 4 && ! -e "$T/gitlab-no-token-curl.args" && ! -e "$T/gitlab-no-token.out" ]] || fail "GitLab permission fetch proceeded without an explicit token"

echo "[roles-provider] malformed input fails closed"
set +e
printf '{"schema":"rh-provider-roles-input/2","provider":"github","captured_at":1,"members":[]}' > "$T/bad-schema.json"
"$ROOT/build/rh_cli" roles-import --input "$T/bad-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-provider-roles-input/1","provider":"bitbucket","captured_at":1,"members":[]}' > "$T/bad-provider.json"
"$ROOT/build/rh_cli" roles-import --input "$T/bad-provider.json" --out "$T/x" >/dev/null 2>&1; rc_provider=$?
printf '{"schema":"rh-provider-roles-input/1","provider":"github","captured_at":1,"members":[{"id":-1}]}' > "$T/bad-id.json"
"$ROOT/build/rh_cli" roles-import --input "$T/bad-id.json" --out "$T/x" >/dev/null 2>&1; rc_id=$?
set -e
for rc in "$rc_schema" "$rc_provider" "$rc_id"; do
  [[ "$rc" -eq 4 ]] || fail "malformed provider input must exit 4 (got $rc)"
done

echo "test_roles_provider_cli OK"
