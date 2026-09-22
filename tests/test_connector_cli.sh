#!/usr/bin/env bash
# tests/test_connector_cli.sh — M02 connector-instance execution path:
# `rh_cli connector check --instance <file> --out <file>` reads an
# rh-connector-instance/1 document and writes rh-connector-instance-result/1
# with the connector capability table (unsupported stated, never omitted),
# the operator-declared capabilities, and a usability verdict. Approval and
# transport are separate gates: an arbitrary approved self-hosted base URL is
# usable (R007), but a URL in loopback/private space is transport-rejected
# even when approved (S002). Unknown connectors, unknown capability keys, and
# capabilities the connector does not declare fail closed (exit 4).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-connector"

fail() { echo "[connector] FAIL: $1" >&2; exit 1; }

echo "[connector] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

echo "[connector] runtime capability tables match the checked-in manifests"
python3 - "$ROOT" <<'PY'
import glob, json, os, subprocess, sys, tempfile
root = sys.argv[1]
binary = os.path.join(root, "build", "rh_cli")
manifests = {}
for path in glob.glob(os.path.join(root, "connectors", "manifests", "*.json")):
    manifest = json.load(open(path))
    manifests[manifest["connector_id"]] = manifest

implemented = {"github", "gitlab", "gitea", "forgejo", "bitbucket"}
assert implemented <= manifests.keys(), (implemented, manifests.keys())

def runtime_label(capability, declaration):
    if declaration in {"unsupported", "unsupported-no-traffic-api"}:
        return "unsupported"
    if capability == "history" and declaration == "generic-git":
        return "read"
    if declaration == "read":
        return "read"
    if declaration == "authorized-only":
        return "authorized-only"
    if declaration == "authorized-14-day-window":
        return "windowed"
    if declaration == "unauthorized-in-m02-slice":
        return "unauthorized"
    raise AssertionError((capability, declaration))

with tempfile.TemporaryDirectory(prefix="rh-connector-manifest-") as tmp:
    for connector in sorted(implemented):
        manifest = manifests[connector]
        instance = os.path.join(tmp, connector + ".json")
        output = os.path.join(tmp, connector + ".out")
        with open(instance, "w") as f:
            json.dump({"schema": "rh-connector-instance/1", "connector_id": connector,
                       "base_url": "https://manifest-check.example.org", "approved": True}, f)
        subprocess.run([binary, "connector", "check", "--instance", instance, "--out", output],
                       check=True, stdout=subprocess.DEVNULL)
        result = json.load(open(output))
        assert result["connector_id"] == connector, result
        expected = {cap: runtime_label(cap, declaration)
                    for cap, declaration in manifest["capabilities"].items()}
        assert result["capabilities"] == expected, (connector, result["capabilities"], expected)
print("[connector] manifest/runtime parity OK:", ", ".join(sorted(implemented)))
PY

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT"/fixtures/connectors/instance-*.json "$T"/

echo "[connector] arbitrary approved self-hosted base URL is usable"
"$ROOT/build/rh_cli" connector check \
  --instance "$T/instance-gitea-selfhosted.json" --out "$T/gt.out" | grep -q "verdict=usable" \
  || fail "approved self-hosted gitea instance must be usable"
python3 - "$T/gt.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-connector-instance-result/1", d
assert d["connector_id"] == "gitea", d
assert d["base_url"] == "https://codeberg.example.org", d
assert d["approved"] is True and d["verdict"] == "usable", d
# The connector's full capability table is stated; unsupported is explicit.
assert d["capabilities"]["history"] == "read", d
assert d["capabilities"]["issues"] == "read", d
assert d["capabilities"]["reviews"] == "read", d
assert d["capabilities"]["permissions"] == "unsupported", d
assert d["capabilities"]["traffic"] == "unsupported", d
assert set(d["declared_capabilities"]) == {"history", "issues", "reviews", "releases"}, d
assert "approval never overrides transport" in d["note"], d
print("[connector] self-hosted usable OK")
PY

echo "[connector] approval and transport are separate gates"
# Approved, but loopback: transport policy wins.
"$ROOT/build/rh_cli" connector check \
  --instance "$T/instance-forgejo-loopback.json" --out "$T/lb.out" | grep -q "verdict=transport-rejected" \
  || fail "approved loopback instance must be transport-rejected"
# Unapproved public instance: reported unapproved, not usable.
cat > "$T/unapproved.json" <<'JSON'
{"schema":"rh-connector-instance/1","connector_id":"forgejo","base_url":"https://code.example.net","approved":false}
JSON
"$ROOT/build/rh_cli" connector check --instance "$T/unapproved.json" --out "$T/un.out" | grep -q "verdict=unapproved" \
  || fail "unapproved instance must be unapproved"
# Various hostile-but-approved URLs all fail the transport gate.
for u in "https://10.0.0.5" "https://192.168.1.1" "https://169.254.169.254" \
         "http://git.example.org" "https://user@git.example.org" "https://intranet"; do
  python3 - "$T/url.json" "$u" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({
  "schema": "rh-connector-instance/1", "connector_id": "gitea",
  "base_url": sys.argv[2], "approved": True}))
PY
  "$ROOT/build/rh_cli" connector check --instance "$T/url.json" --out "$T/url.out" \
    | grep -q "verdict=transport-rejected" || fail "approved URL $u must be transport-rejected"
done
python3 - "$T/lb.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["verdict"] == "transport-rejected", d
assert d["approved"] is True, d
print("[connector] transport gate OK")
PY

echo "[connector] determinism and connector-specific capability tables"
a="$("$ROOT/build/rh_cli" connector check --instance "$T/instance-gitea-selfhosted.json" --out "$T/d1.out" >/dev/null; cat "$T/d1.out")"
b="$("$ROOT/build/rh_cli" connector check --instance "$T/instance-gitea-selfhosted.json" --out "$T/d2.out" >/dev/null; cat "$T/d2.out")"
[[ "$a" == "$b" ]] || fail "connector check must be deterministic"
# GitHub declares a windowed traffic capability; Gitea does not (no traffic API).
cat > "$T/gh.json" <<'JSON'
{"schema":"rh-connector-instance/1","connector_id":"github","base_url":"https://github.example.com","approved":true,"capabilities":["history","traffic"]}
JSON
"$ROOT/build/rh_cli" connector check --instance "$T/gh.json" --out "$T/gh.out" >/dev/null
python3 - "$T/gh.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["traffic"] == "windowed", d
assert d["capabilities"]["permissions"] == "authorized-only", d
assert "traffic" in d["declared_capabilities"], d
print("[connector] capability tables OK")
PY

echo "[connector] unsupported capability declarations and malformed input fail closed"
check_rc() { # payload
  printf '%s' "$1" > "$T/bad.json"
  "$ROOT/build/rh_cli" connector check --instance "$T/bad.json" --out "$T/bad.out" >/dev/null 2>&1
  echo $?
}
set +e
rc1=$(check_rc '{"schema":"rh-connector-instance/1","connector_id":"sourceforge","base_url":"https://x.example.com","approved":true}')
rc2=$(check_rc '{"schema":"rh-connector-instance/1","connector_id":"gitea","base_url":"https://x.example.com","approved":true,"capabilities":["traffic"]}')
rc3=$(check_rc '{"schema":"rh-connector-instance/1","connector_id":"gitea","base_url":"https://x.example.com","approved":true,"capabilities":["telepathy"]}')
rc4=$(check_rc '{"schema":"rh-connector-instance/2","connector_id":"gitea","base_url":"https://x.example.com"}')
rc5=$(check_rc '{"schema":"rh-connector-instance/1","connector_id":"gitea"}')
rc6=$(check_rc '{"schema":"rh-connector-instance/1","connector_id":"gitea","base_url":"https://x.example.com","approved":true,"capabilities":[5]}')
rc7=$(check_rc 'not json')
"$ROOT/build/rh_cli" connector check --instance "$T/nope.json" --out "$T/x.out" >/dev/null 2>&1
rc8=$?
set -e
for rc in "$rc1" "$rc2" "$rc3" "$rc4" "$rc5" "$rc6" "$rc7" "$rc8"; do
  [[ "$rc" -eq 4 ]] || fail "malformed connector instance must exit 4 (got $rc)"
done

echo "[connector] GitHub traffic probe retains bounded evidence and honest access states"
mkdir -p "$T/probe-bin"
cat > "$T/probe-bin/python3" <<'SH'
#!/usr/bin/env bash
printf '140.82.114.5\n'
SH
cat > "$T/probe-bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >> "$RH_PROBE_CURL_ARGS"
body_out=""
url=""
response_body="$RH_PROBE_BODY"
response_http="${RH_PROBE_HTTP:-200}"
while (($#)); do
  case "$1" in
    -o) body_out="$2"; shift 2 ;;
    --config) [[ "$2" == "-" ]] || exit 20; cat > "$RH_PROBE_CURL_CONFIG"; shift 2 ;;
    -w) shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  "https://api.github.com/repos/example/project/issues?per_page=1")
    response_body="${RH_PROBE_ISSUES_BODY:-$RH_PROBE_ARRAY_BODY}"
    response_http="${RH_PROBE_ISSUES_HTTP:-200}"
    ;;
  "https://api.github.com/repos/example/project/pulls?per_page=1")
    response_body="${RH_PROBE_PULLS_BODY:-$RH_PROBE_ARRAY_BODY}"
    response_http="${RH_PROBE_PULLS_HTTP:-200}"
    ;;
  "https://api.github.com/repos/example/project/releases?per_page=1")
    response_body="${RH_PROBE_RELEASES_BODY:-$RH_PROBE_ARRAY_BODY}"
    response_http="${RH_PROBE_RELEASES_HTTP:-200}"
    ;;
  "https://api.github.com/repos/example/project/pulls/23/reviews?per_page=1")
    response_body="${RH_PROBE_REVIEW_BODY:-$RH_PROBE_ARRAY_BODY}"
    response_http="${RH_PROBE_REVIEW_HTTP:-200}"
    ;;
  "https://api.github.com/repos/example/project/collaborators?per_page=1")
    response_body="${RH_PROBE_COLLABORATORS_BODY:-$RH_PROBE_ARRAY_BODY}"
    response_http="${RH_PROBE_COLLABORATORS_HTTP:-200}"
    ;;
  "https://api.github.com/repos/example/project/traffic/views")
    response_http="${RH_PROBE_TRAFFIC_HTTP:-${RH_PROBE_HTTP:-200}}"
    ;;
  "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/issues?per_page=1")
    response_body="${RH_GLP_ISSUES_BODY:-$RH_PROBE_ARRAY_BODY}"
    response_http="${RH_GLP_ISSUES_HTTP:-200}"
    ;;
  "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests?per_page=1")
    response_body="${RH_GLP_MERGE_REQUESTS_BODY:-$RH_PROBE_ARRAY_BODY}"
    response_http="${RH_GLP_MERGE_REQUESTS_HTTP:-200}"
    ;;
  "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/releases?per_page=1")
    response_body="${RH_GLP_RELEASES_BODY:-$RH_PROBE_ARRAY_BODY}"
    response_http="${RH_GLP_RELEASES_HTTP:-200}"
    ;;
  "https://codeberg.example.org/api/v1/repos/owner/project/issues?limit=1&type=issues"|"https://codeberg.example.org/api/v1/repos/owner/project/pulls?limit=1"|"https://codeberg.example.org/api/v1/repos/owner/project/releases?limit=1")
    response_body="$RH_PROBE_ARRAY_BODY"
    response_http="${RH_FORGE_HTTP:-200}"
    ;;
  *) exit 21 ;;
esac
cp "$response_body" "$body_out"
printf '%s' "$response_http"
SH
chmod +x "$T/probe-bin/python3" "$T/probe-bin/curl"
printf '%s\n' '{"count":12,"uniques":8,"views":[]}' > "$T/traffic-views.json"
printf '%s\n' '{"message":"Resource not accessible"}' > "$T/probe-error.json"
printf '%s\n' 'not json' > "$T/probe-malformed.json"
rm -f "$T/traffic-probe.out" "$T/traffic-probe.out.github-traffic-views."* "$T/probe.args" "$T/probe.config"
PATH="$T/probe-bin:$PATH" RH_GITHUB_TOKEN="ghp_probe_fixture" RH_PROBE_HTTP=200 RH_PROBE_BODY="$T/traffic-views.json" \
  RH_PROBE_CURL_ARGS="$T/probe.args" RH_PROBE_CURL_CONFIG="$T/probe.config" \
  "$ROOT/build/rh_cli" connector probe --github-repo example/project --out "$T/traffic-probe.out" >/dev/null || fail "GitHub traffic probe"
python3 - "$T/traffic-probe.out" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["schema"] == "rh-github-capability-probe-result/1", d
assert d["scope"] == {"repository":"example/project"}, d
assert d["authorization"]["credential"] == "configured", d
assert d["capabilities"]["traffic"] == {"declaration":"authorized-14-day-window","status":"observed","http_status":200,"coverage_state":"observed","window_days":14}, d
published = open(sys.argv[1]).read()
assert "count" not in d and '"count":12' not in published and '"uniques":8' not in published and '"views":[]' not in published, d
for ext in ("json", "status", "err", "url"):
    assert (t / f"traffic-probe.out.github-traffic-views.{ext}").exists(), ext
assert (t / "traffic-probe.out.github-traffic-views.url").read_text().strip() == "https://api.github.com/repos/example/project/traffic/views"
print("[connector] traffic probe reports access without publishing the traffic payload")
PY
grep -Fxq 'header = "Authorization: Bearer ghp_probe_fixture"' "$T/probe.config" || fail "probe token header absent from curl stdin config"
! grep -Fq 'ghp_probe_fixture' "$T/probe.args" || fail "probe token leaked into curl arguments"
for evidence in "$T"/traffic-probe.out.github-traffic-views.*; do
  [[ ! -f "$evidence" ]] || ! grep -Fq 'ghp_probe_fixture' "$evidence" || fail "probe token leaked into evidence"
done

for case_spec in "401:unauthorized:$T/probe-error.json" "403:forbidden_or_rate_limited:$T/probe-error.json" "404:not_found_or_private:$T/probe-error.json" "429:rate_limited:$T/probe-error.json" "200:malformed:$T/probe-malformed.json" "000:unavailable:$T/probe-error.json"; do
  IFS=: read -r http want body <<< "$case_spec"
  out="$T/probe-$http-$want.out"
  PATH="$T/probe-bin:$PATH" RH_PROBE_HTTP="$http" RH_PROBE_BODY="$body" \
    RH_PROBE_CURL_ARGS="$T/probe-$http.args" RH_PROBE_CURL_CONFIG="$T/probe-$http.config" \
    "$ROOT/build/rh_cli" connector probe --github-repo example/project --out "$out" >/dev/null || fail "probe response $http"
  python3 - "$out" "$want" "$http" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["traffic"]["status"] == sys.argv[2], d
coverage = {"observed":"observed", "malformed":"partial", "unauthorized":"unauthorized", "forbidden_or_rate_limited":"unavailable", "not_found_or_private":"unavailable", "rate_limited":"unavailable", "unavailable":"unavailable"}
assert d["capabilities"]["traffic"]["coverage_state"] == coverage[sys.argv[2]], d
if sys.argv[3] == "000":
    assert d["capabilities"]["traffic"]["http_status"] is None, d
else:
    assert d["capabilities"]["traffic"]["http_status"] == int(sys.argv[3]), d
print("[connector] mapped HTTP", sys.argv[3], "to", sys.argv[2])
PY
done

echo "[connector] pull-request-scoped review probe keeps evidence and explicit scope"
printf '%s\n' '[]' > "$T/probe-array.json"
PATH="$T/probe-bin:$PATH" RH_GITHUB_TOKEN="ghp_review_probe_fixture" \
  RH_PROBE_BODY="$T/probe-error.json" RH_PROBE_ARRAY_BODY="$T/probe-array.json" RH_PROBE_REVIEW_HTTP=403 \
  RH_PROBE_CURL_ARGS="$T/review-probe.args" RH_PROBE_CURL_CONFIG="$T/review-probe.config" \
  "$ROOT/build/rh_cli" connector probe --github-repo example/project --review-pull 23 \
    --out "$T/review-probe.out" >/dev/null || fail "GitHub pull-request review probe"
python3 - "$T/review-probe.out" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["schema"] == "rh-github-review-capability-probe-result/1", d
assert d["scope"] == {"repository":"example/project", "pull_request_number":23}, d
assert d["authorization"]["credential"] == "configured", d
assert d["capabilities"]["reviews"] == {"declaration":"read-one-item", "status":"forbidden_or_rate_limited", "http_status":403,"coverage_state":"unavailable"}, d
assert (t / "review-probe.out.github-pull-reviews.url").read_text().strip() == "https://api.github.com/repos/example/project/pulls/23/reviews?per_page=1"
for ext in ("json", "status", "err", "url"):
    assert (t / f"review-probe.out.github-pull-reviews.{ext}").exists(), ext
print("[connector] one-item review probe preserves scope and ambiguous access state")
PY
grep -Fxq 'header = "Authorization: Bearer ghp_review_probe_fixture"' "$T/review-probe.config" || fail "review probe token header absent"
! grep -Fq 'ghp_review_probe_fixture' "$T/review-probe.args" || fail "review probe token leaked into curl arguments"
[[ "$(grep -c 'api.github.com/repos/example/project/pulls/23/reviews?per_page=1' "$T/review-probe.args")" -eq 1 ]] || fail "review probe must issue exactly one fixed request"
set +e
PATH="$T/probe-bin:$PATH" RH_PROBE_CURL_ARGS="$T/review-invalid.args" \
  "$ROOT/build/rh_cli" connector probe --github-repo example/project --review-pull 0 \
    --out "$T/review-invalid.out" >/dev/null 2>&1
review_invalid_rc=$?
set -e
[[ "$review_invalid_rc" -eq 2 && ! -e "$T/review-invalid.args" && ! -e "$T/review-invalid.out" ]] || fail "invalid review scope reached transport"

echo "[connector] collaborator probe requires authentication and keeps account data out of its result"
printf '%s\n' '[{"login":"private-account","permissions":{"pull":true}}]' > "$T/collaborator-response.json"
PATH="$T/probe-bin:$PATH" RH_GITHUB_TOKEN="ghp_collaborator_probe_fixture" \
  RH_PROBE_BODY="$T/probe-error.json" RH_PROBE_ARRAY_BODY="$T/probe-array.json" \
  RH_PROBE_COLLABORATORS_BODY="$T/collaborator-response.json" RH_PROBE_CURL_ARGS="$T/collaborator-probe.args" \
  RH_PROBE_CURL_CONFIG="$T/collaborator-probe.config" \
  "$ROOT/build/rh_cli" connector probe --github-repo example/project --collaborators \
    --out "$T/collaborator-probe.out" >/dev/null || fail "authenticated collaborator capability probe"
python3 - "$T/collaborator-probe.out" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["schema"] == "rh-github-collaborator-probe-result/1", d
assert d["scope"] == {"repository":"example/project"}, d
assert d["authorization"]["credential"] == "configured", d
assert d["capabilities"]["collaborators"] == {"declaration":"read-one-item-authenticated", "status":"observed", "http_status":200,"coverage_state":"observed"}, d
assert "private-account" not in open(sys.argv[1]).read(), d
assert (t / "collaborator-probe.out.github-collaborators.json").read_text().find("private-account") >= 0
assert (t / "collaborator-probe.out.github-collaborators.url").read_text().strip() == "https://api.github.com/repos/example/project/collaborators?per_page=1"
print("[connector] collaborator probe publishes only access and scope, with raw item retained locally")
PY
grep -Fxq 'header = "Authorization: Bearer ghp_collaborator_probe_fixture"' "$T/collaborator-probe.config" || fail "collaborator probe token header absent"
! grep -Fq 'ghp_collaborator_probe_fixture' "$T/collaborator-probe.args" || fail "collaborator probe token leaked into curl arguments"
set +e
PATH="$T/probe-bin:$PATH" RH_PROBE_CURL_ARGS="$T/collaborator-missing-token.args" \
  "$ROOT/build/rh_cli" connector probe --github-repo example/project --collaborators \
    --out "$T/collaborator-missing-token.out" >/dev/null 2>&1
collaborator_missing_token_rc=$?
set -e
[[ "$collaborator_missing_token_rc" -eq 4 && ! -e "$T/collaborator-missing-token.args" && ! -e "$T/collaborator-missing-token.out" ]] || fail "collaborator probe ran without explicit credentials"

echo "[connector] GitLab capability matrix uses encoded project paths and host-scoped token auth"
PATH="$T/probe-bin:$PATH" RH_GITLAB_TOKEN="glpat_fixture_token" \
  RH_PROBE_ARRAY_BODY="$T/probe-array.json" RH_PROBE_BODY="$T/probe-error.json" \
  RH_GLP_ISSUES_HTTP=200 RH_GLP_MERGE_REQUESTS_HTTP=403 RH_GLP_RELEASES_HTTP=404 \
  RH_PROBE_CURL_ARGS="$T/gitlab-probe.args" RH_PROBE_CURL_CONFIG="$T/gitlab-probe.config" \
  "$ROOT/build/rh_cli" connector probe --gitlab-project group/subgroup/project --all \
    --out "$T/gitlab-probe.out" >/dev/null || fail "GitLab capability matrix probe"
python3 - "$T/gitlab-probe.out" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["schema"] == "rh-gitlab-capability-matrix/1", d
assert d["provider"] == "gitlab" and d["scope"] == {"project_path":"group/subgroup/project"}, d
assert d["authorization"]["credential"] == "configured", d
caps = d["capabilities"]
assert caps["issues"]["status"] == "observed" and caps["issues"]["coverage_state"] == "observed", caps
assert caps["merge_requests"]["status"] == "forbidden_or_rate_limited" and caps["merge_requests"]["coverage_state"] == "unavailable", caps
assert caps["releases"]["status"] == "not_found_or_private" and caps["releases"]["coverage_state"] == "unavailable", caps
assert "login" not in json.dumps(d) and "permissions" not in json.dumps(d), d
for route in ("issues", "merge_requests", "releases"):
    assert (t / f"gitlab-probe.out.gitlab-{route.replace('_','-')}.url").read_text().strip() == f"https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/{route}?per_page=1"
    for ext in ("json", "status", "err", "url"):
        assert (t / f"gitlab-probe.out.gitlab-{route.replace('_','-')}.{ext}").exists()
print("[connector] GitLab preserves endpoint status and maps to shared coverage without publishing response records")
PY
grep -Fxq 'header = "PRIVATE-TOKEN: glpat_fixture_token"' "$T/gitlab-probe.config" || fail "GitLab token header absent from curl stdin config"
! grep -Fq 'glpat_fixture_token' "$T/gitlab-probe.args" || fail "GitLab token leaked into curl arguments"
[[ "$(grep -c 'https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/' "$T/gitlab-probe.args")" -eq 3 ]] || fail "GitLab matrix must issue exactly three fixed requests"
for evidence in "$T"/gitlab-probe.out.gitlab-*; do
  ! grep -Fq 'glpat_fixture_token' "$evidence" || fail "GitLab token leaked into evidence"
done
env -u RH_GITLAB_TOKEN PATH="$T/probe-bin:$PATH" RH_PROBE_ARRAY_BODY="$T/probe-array.json" \
  RH_PROBE_BODY="$T/probe-error.json" RH_PROBE_CURL_ARGS="$T/gitlab-public.args" \
  "$ROOT/build/rh_cli" connector probe --gitlab-project group/subgroup/project --all \
    --out "$T/gitlab-public.out" >/dev/null || fail "unauthenticated public GitLab capability matrix"
python3 - "$T/gitlab-public.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["authorization"]["credential"] == "not_requested", d
assert all(cap["status"] == "observed" for cap in d["capabilities"].values()), d
print("[connector] public GitLab probing works without configuring credentials")
PY
[[ ! -e "$T/gitlab-public.config" ]] || fail "unauthenticated GitLab probe unexpectedly supplied curl credentials"
set +e
PATH="$T/probe-bin:$PATH" RH_PROBE_CURL_ARGS="$T/gitlab-invalid.args" \
  "$ROOT/build/rh_cli" connector probe --gitlab-project 'group/../project' --all \
    --out "$T/gitlab-invalid.out" >/dev/null 2>&1
gitlab_invalid_rc=$?
set -e
[[ "$gitlab_invalid_rc" -eq 4 && ! -e "$T/gitlab-invalid.args" && ! -e "$T/gitlab-invalid.out" ]] || fail "invalid GitLab project path reached transport"

echo "[connector] approved Gitea/Forgejo instance probes use only fixed routes"
cat > "$T/forge-instance.json" <<'JSON'
{"schema":"rh-connector-instance/1","connector_id":"gitea","base_url":"https://codeberg.example.org","approved":true}
JSON
: > "$T/forge.args"
PATH="$T/probe-bin:$PATH" RH_PROBE_CURL_ARGS="$T/forge.args" RH_PROBE_CURL_CONFIG="$T/forge.config" \
  RH_PROBE_BODY="$T/probe-error.json" RH_PROBE_ARRAY_BODY="$T/probe-array.json" \
  "$ROOT/build/rh_cli" connector probe --instance "$T/forge-instance.json" --repository owner/project --all \
    --out "$T/forge-probe.out" >/dev/null || fail "approved Gitea capability probe"
python3 - "$T/forge-probe.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-forge-capability-matrix/1", d
assert d["provider"] == "gitea" and d["repository"] == "owner/project", d
assert all(d["capabilities"][name]["status"] == "observed" for name in ("issues", "pulls", "releases")), d
assert "private" not in open(sys.argv[1]).read()
PY
[[ "$(grep -c 'https://codeberg.example.org/api/v1/repos/owner/project/' "$T/forge.args")" -eq 3 ]] || fail "forge matrix must issue three fixed requests"
for route in issues pulls releases; do
  [[ -f "$T/forge-probe.out.forge-$route.json" && -f "$T/forge-probe.out.forge-$route.url" ]] || fail "forge $route evidence missing"
done
cat > "$T/forge-unapproved.json" <<'JSON'
{"schema":"rh-connector-instance/1","connector_id":"forgejo","base_url":"https://codeberg.example.org","approved":false}
JSON
: > "$T/forge-unapproved.args"
set +e
PATH="$T/probe-bin:$PATH" RH_PROBE_CURL_ARGS="$T/forge-unapproved.args" \
  "$ROOT/build/rh_cli" connector probe --instance "$T/forge-unapproved.json" --repository owner/project --all \
    --out "$T/forge-unapproved.out" >/dev/null 2>&1
forge_unapproved_rc=$?
set -e
[[ "$forge_unapproved_rc" -eq 4 && ! -s "$T/forge-unapproved.args" && ! -e "$T/forge-unapproved.out" ]] || fail "unapproved forge reached transport"

echo "[connector] --all probes bounded GitHub routes with separate evidence"
printf '%s\n' '[]' > "$T/probe-array.json"
PATH="$T/probe-bin:$PATH" RH_GITHUB_TOKEN="ghp_probe_fixture" \
  RH_PROBE_ARRAY_BODY="$T/probe-array.json" RH_PROBE_BODY="$T/probe-error.json" \
  RH_PROBE_ISSUES_HTTP=200 RH_PROBE_PULLS_HTTP=200 RH_PROBE_RELEASES_HTTP=403 RH_PROBE_TRAFFIC_HTTP=404 \
  RH_PROBE_CURL_ARGS="$T/matrix.args" RH_PROBE_CURL_CONFIG="$T/matrix.config" \
  "$ROOT/build/rh_cli" connector probe --github-repo example/project --out "$T/capability-matrix.out" --all >/dev/null || fail "GitHub capability matrix probe"
python3 - "$T/capability-matrix.out" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1]))
t = pathlib.Path(sys.argv[2])
assert d["schema"] == "rh-github-capability-matrix/1", d
assert d["authorization"]["credential"] == "configured", d
caps = d["capabilities"]
assert caps["issues"]["status"] == "observed" and caps["issues"]["http_status"] == 200, caps
assert caps["pull_requests"]["status"] == "observed" and caps["pull_requests"]["http_status"] == 200, caps
assert caps["releases"]["status"] == "forbidden_or_rate_limited" and caps["releases"]["http_status"] == 403, caps
assert caps["traffic"]["status"] == "not_found_or_private" and caps["traffic"]["http_status"] == 404, caps
assert caps["releases"]["coverage_state"] == "unavailable" and caps["traffic"]["coverage_state"] == "unavailable", caps
assert "count" not in json.dumps(caps) and "uniques" not in json.dumps(caps), caps
for key in ("issues", "pull_requests", "releases", "traffic"):
    for evidence in d["evidence"][key].values():
        assert (t / pathlib.Path(evidence).name).exists(), evidence
assert (t / "capability-matrix.out.github-issues.url").read_text().strip().endswith("/issues?per_page=1")
assert (t / "capability-matrix.out.github-pulls.url").read_text().strip().endswith("/pulls?per_page=1")
assert (t / "capability-matrix.out.github-releases.url").read_text().strip().endswith("/releases?per_page=1")
print("[connector] matrix distinguishes route availability, authorization, and hidden-repository states")
PY
grep -Fxq 'header = "Authorization: Bearer ghp_probe_fixture"' "$T/matrix.config" || fail "matrix token header absent from curl stdin config"
! grep -Fq 'ghp_probe_fixture' "$T/matrix.args" || fail "matrix token leaked into curl arguments"
[[ "$(grep -c 'api.github.com/repos/example/project/' "$T/matrix.args")" -eq 4 ]] || fail "matrix must issue exactly four fixed requests"
for evidence in "$T"/capability-matrix.out.github-*; do
  ! grep -Fq 'ghp_probe_fixture' "$evidence" || fail "matrix token leaked into evidence"
done

PATH="$T/probe-bin:$PATH" RH_GITHUB_TOKEN="ghp_probe_fixture" \
  RH_PROBE_ARRAY_BODY="$T/probe-array.json" RH_PROBE_ISSUES_BODY="$T/probe-malformed.json" \
  RH_PROBE_BODY="$T/traffic-views.json" RH_PROBE_ISSUES_HTTP=200 RH_PROBE_PULLS_HTTP=200 \
  RH_PROBE_RELEASES_HTTP=200 RH_PROBE_TRAFFIC_HTTP=200 \
  RH_PROBE_CURL_ARGS="$T/malformed-matrix.args" RH_PROBE_CURL_CONFIG="$T/malformed-matrix.config" \
  "$ROOT/build/rh_cli" connector probe --github-repo example/project --out "$T/malformed-matrix.out" --all >/dev/null || fail "malformed GitHub matrix probe"
python3 - "$T/malformed-matrix.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["issues"] == {"declaration":"read", "status":"malformed", "http_status":200,"coverage_state":"partial"}, d
print("[connector] matrix marks a 200 non-array response malformed")
PY

set +e
PATH="$T/probe-bin:$PATH" RH_PROBE_CURL_ARGS="$T/probe-invalid.args" RH_PROBE_CURL_CONFIG="$T/probe-invalid.config" \
  "$ROOT/build/rh_cli" connector probe --github-repo 'example/../project' --out "$T/probe-invalid.out" >/dev/null 2>&1
rc_probe_route=$?
set -e
[[ "$rc_probe_route" -eq 4 && ! -e "$T/probe-invalid.args" && ! -e "$T/probe-invalid.out" ]] || fail "invalid probe repository reached transport or wrote output"

echo "[connector] GitHub traffic observations preserve daily buckets as non-additive snapshots"
cp "$ROOT/fixtures/connectors/github-traffic-views.json" "$T/traffic-response.json"
"$ROOT/build/rh_cli" connector traffic-observe --github-repo example/project \
  --captured-at 1789992000 --input "$T/traffic-response.json" \
  --out "$T/traffic-observation.json" >/dev/null || fail "traffic observation normalization"
cmp "$ROOT/fixtures/connectors/github-traffic-observation.json" "$T/traffic-observation.json" \
  || fail "traffic observation golden mismatch"
python3 - "$T/traffic-observation.json" "$T/traffic-response.json" <<'PY'
import hashlib, json, pathlib, sys
d = json.load(open(sys.argv[1]))
raw = pathlib.Path(sys.argv[2]).read_bytes()
assert d["schema"] == "rh-github-traffic-observation/1", d
assert d["origin"] == "caller_supplied_response", d
assert d["window"] == {"days":14,"views":14,"uniques":10}, d
assert [x["timestamp"] for x in d["daily_observations"]] == [
    "2026-09-19T00:00:00Z", "2026-09-20T00:00:00Z"], d
assert d["aggregation"] == {"kind":"rolling_window_snapshot","additive_across_captures":False}, d
assert d["response_sha256"] == hashlib.sha256(raw).hexdigest(), d
assert "github-traffic-views.json" not in open(sys.argv[1]).read(), d
print("[connector] traffic window snapshot and exact response digest OK")
PY

python3 - "$T" <<'PY'
import json, pathlib, sys
t = pathlib.Path(sys.argv[1])
base = {"count": 2, "uniques": 2, "views": [
    {"timestamp":"2026-09-19T00:00:00Z","count":1,"uniques":1},
    {"timestamp":"2026-09-20T00:00:00Z","count":1,"uniques":1}]}
cases = {
    "duplicate": lambda d: d["views"].__setitem__(1, dict(d["views"][0])),
    "out-of-order": lambda d: d["views"].reverse(),
    "future": lambda d: d["views"][1].update(timestamp="2026-09-22T00:00:00Z"),
    "not-daily": lambda d: d["views"][1].update(timestamp="2026-09-20T12:00:00Z"),
    "bad-date": lambda d: d["views"][1].update(timestamp="2026-02-30T00:00:00Z"),
    "unique-exceeds-count": lambda d: d["views"][1].update(uniques=2),
}
for name, change in cases.items():
    d = json.loads(json.dumps(base))
    change(d)
    (t / (name + ".json")).write_text(json.dumps(d))
too_many = json.loads(json.dumps(base))
too_many["views"] = [{"timestamp":f"2026-09-{day:02d}T00:00:00Z","count":1,"uniques":1}
                     for day in range(1, 16)]
(t / "too-many-days.json").write_text(json.dumps(too_many))
(t / "oversized-response.json").write_bytes(b" " * (3 * 1024 * 1024 + 1))
PY
for malformed in duplicate out-of-order future not-daily bad-date unique-exceeds-count too-many-days; do
  set +e
  "$ROOT/build/rh_cli" connector traffic-observe --github-repo example/project \
    --captured-at 1789992000 --input "$T/$malformed.json" --out "$T/$malformed.out" >/dev/null 2>&1
  rc_traffic=$?
  set -e
  [[ "$rc_traffic" -eq 4 && ! -e "$T/$malformed.out" ]] || fail "malformed traffic response $malformed was accepted or published"
done
set +e
"$ROOT/build/rh_cli" connector traffic-observe --github-repo example/project \
  --captured-at 1789992000 --input "$T/oversized-response.json" --out "$T/oversized-response.out" >/dev/null 2>&1
rc_traffic_size=$?
set -e
[[ "$rc_traffic_size" -eq 4 && ! -e "$T/oversized-response.out" ]] || fail "oversized traffic response was accepted or published"
echo "[connector] malformed and oversized-window traffic samples fail closed"

echo "test_connector_cli OK"
