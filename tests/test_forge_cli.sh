#!/usr/bin/env bash
# tests/test_forge_cli.sh — M02 forge normalization execution path:
# `rh_cli forge normalize --connector github|gitlab` turns a captured forge
# payload into canonical-repo/1. Asserts byte-for-byte reproduction of the
# checked-in goldens at a pinned collection time, determinism, and that
# unknown connectors / malformed payloads fail closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-forge"

fail() { echo "[forge] FAIL: $1" >&2; exit 1; }

echo "[forge] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT"/fixtures/connectors/*.json "$T"/

echo "[forge] github + gitlab + gitea + forgejo reproduce their canonical goldens"
"$ROOT/build/rh_cli" forge normalize --connector github --input "$T/github-repo.json" --out "$T/gh.out" --fetched-at 1700000000 >/dev/null || fail "github normalize"
"$ROOT/build/rh_cli" forge normalize --connector gitlab --input "$T/gitlab-project.json" --out "$T/gl.out" --fetched-at 1700000000 >/dev/null || fail "gitlab normalize"
"$ROOT/build/rh_cli" forge normalize --connector gitea --input "$T/gitea-repo.json" --out "$T/gt.out" --fetched-at 1700000000 >/dev/null || fail "gitea normalize"
"$ROOT/build/rh_cli" forge normalize --connector forgejo --input "$T/forgejo-project.json" --out "$T/fj.out" --fetched-at 1700000000 >/dev/null || fail "forgejo normalize"
"$ROOT/build/rh_cli" forge normalize --connector bitbucket --input "$T/bitbucket-repo.json" --out "$T/bb.out" --fetched-at 1700000000 >/dev/null || fail "bitbucket normalize"
python3 - "$T" <<'PY'
import sys
import hashlib
import json
t = sys.argv[1]
def norm(p):
    b = open(p, "rb").read()
    return b[:-1] if b.endswith(b"\n") else b
assert norm(t + "/gh.out") == norm(t + "/github-repo.canonical.json"), "github golden mismatch"
assert norm(t + "/gl.out") == norm(t + "/gitlab-project.canonical.json"), "gitlab golden mismatch"
assert norm(t + "/gt.out") == norm(t + "/gitea-repo.canonical.json"), "gitea golden mismatch"
assert norm(t + "/fj.out") == norm(t + "/forgejo-project.canonical.json"), "forgejo golden mismatch"
assert norm(t + "/bb.out") == norm(t + "/bitbucket-repo.canonical.json"), "bitbucket golden mismatch"
assert b"rh-canonical-repo/1" in open(t + "/gh.out", "rb").read()
for provider, source, output in [("github", "github-repo.json", "gh.out"),
                                ("gitlab", "gitlab-project.json", "gl.out"),
                                ("gitea", "gitea-repo.json", "gt.out"),
                                ("forgejo", "forgejo-project.json", "fj.out"),
                                ("bitbucket", "bitbucket-repo.json", "bb.out")]:
    report = json.load(open(t + "/" + output + ".transformations.json"))
    assert report["schema"] == "rh-forge-transformation-report/1", report
    assert report["provider"] == provider, report
    assert report["normalized_schema"] == "rh-canonical-repo/1" and report["normalizer_version"] == "1.0.0", report
    assert report["configuration_sha256"] == hashlib.sha256(("repo-health/forge-repo-normalizer/1:" + provider).encode()).hexdigest(), report
    assert report["input_sha256"] == hashlib.sha256(open(t + "/" + source, "rb").read()).hexdigest(), report
    assert report["normalized_sha256"] == hashlib.sha256(open(t + "/" + output, "rb").read()).hexdigest(), report
    assert {f["state"] for f in report["fields"]} >= {"preserved", "transformed", "inferred", "discarded"}, report
assert any(f["source"] == "web_url" for f in json.load(open(t + "/gl.out.transformations.json"))["fields"])
assert any(f["source"] == "links.html.href" and f["state"] == "transformed" for f in json.load(open(t + "/bb.out.transformations.json"))["fields"])
assert any(f["source"] == "pushed_at" and f["state"] == "transformed" for f in json.load(open(t + "/gh.out.transformations.json"))["fields"])
assert any(f["source"] == "not provided by this provider" and f["target"] == "pushed_at" and f["state"] == "unknown" for f in json.load(open(t + "/gl.out.transformations.json"))["fields"])
print("[forge] goldens reproduced byte-for-byte")
print("[forge] per-provider field-loss reports bind exact input and normalized digests")
PY

echo "[forge] determinism at a pinned time"
"$ROOT/build/rh_cli" forge normalize --connector github --input "$T/github-repo.json" --out "$T/gh2.out" --fetched-at 1700000000 >/dev/null || fail "github rerun"
cmp -s "$T/gh.out" "$T/gh2.out" || fail "normalization is not deterministic at a pinned time"

echo "[forge] the connectors are genuinely different outputs"
if cmp -s "$T/gh.out" "$T/gl.out"; then fail "github and gitlab produced identical canonical output"; fi
if cmp -s "$T/gt.out" "$T/fj.out"; then fail "gitea and forgejo produced identical canonical output"; fi
if cmp -s "$T/bb.out" "$T/gh.out" || cmp -s "$T/bb.out" "$T/gl.out"; then fail "bitbucket produced github/gitlab output"; fi

echo "[forge] default collection time produces valid canonical JSON"
"$ROOT/build/rh_cli" forge normalize --connector github --input "$T/github-repo.json" --out "$T/gh.now" >/dev/null || fail "default fetched-at"
python3 - "$T/gh.now" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-canonical-repo/1", d.get("schema")
print("[forge] default fetched-at OK")
PY

echo "[forge] bounded --url capture retains source/status/error evidence"
source_url="file://$T/github-repo.json"
"$ROOT/build/rh_cli" forge normalize --connector github --url "$source_url" --out "$T/gh-url.out" --fetched-at 1700000000 >/dev/null || fail "url normalize"
cmp -s "$T/github-repo.json" "$T/gh-url.out.source" || fail "url source evidence differs"
[[ -f "$T/gh-url.out.source.status" && "$(cat "$T/gh-url.out.source.status")" == "000" ]] || fail "url status evidence"
[[ -f "$T/gh-url.out.source.err" && ! -s "$T/gh-url.out.source.err" ]] || fail "url error evidence"
cmp -s "$T/gh.out" "$T/gh-url.out" || fail "url normalization differs"
echo "[forge] url capture OK"

echo "[forge] GitHub capture sends the manifest-pinned API version header"
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$RH_CURL_LOG"
body_out=""
config_stdin=0
while (($#)); do
  if [[ "$1" == "-o" ]]; then
    body_out="$2"
    shift 2
  elif [[ "$1" == "--config" && "$2" == "-" ]]; then
    config_stdin=1
    shift 2
  else
    shift
  fi
done
[[ -n "$body_out" ]]
if [[ "$config_stdin" == "1" ]]; then cat > "$RH_CURL_CONFIG_LOG"; fi
cp "$RH_CURL_BODY" "$body_out"
printf '%s' "${RH_CURL_STATUS:-000}"
SH
chmod +x "$T/bin/curl"
PATH="$T/bin:$PATH" RH_CURL_BODY="$T/github-repo.json" RH_CURL_LOG="$T/github-curl.args" \
  "$ROOT/build/rh_cli" forge normalize --connector github --url "$source_url" --out "$T/gh-versioned.out" --fetched-at 1700000000 >/dev/null || fail "versioned GitHub fetch"
grep -Fxq 'X-GitHub-Api-Version: 2026-03-10' "$T/github-curl.args" || fail "GitHub API version header missing"
! grep -Fq 'Authorization:' "$T/github-curl.args" || fail "unexpected credential header"
PATH="$T/bin:$PATH" RH_CURL_BODY="$T/gitea-repo.json" RH_CURL_LOG="$T/gitea-curl.args" \
  "$ROOT/build/rh_cli" forge normalize --connector gitea --url "file://$T/gitea-repo.json" --out "$T/gitea-versioned.out" --fetched-at 1700000000 >/dev/null || fail "unversioned Gitea fetch"
! grep -Fq 'X-GitHub-Api-Version:' "$T/gitea-curl.args" || fail "GitHub version header leaked to Gitea"
echo "[forge] API version header is connector-scoped and credential-free"

echo "[forge] optional GitHub token stays out of arguments and evidence"
cat > "$T/bin/python3" <<'SH'
#!/usr/bin/env bash
printf '140.82.114.5\n'
SH
chmod +x "$T/bin/python3"
api_url="https://api.github.com/repos/example/project"
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="ghp_test-token_1" RH_CURL_BODY="$T/github-repo.json" RH_CURL_STATUS=200 \
  RH_CURL_LOG="$T/github-auth.args" RH_CURL_CONFIG_LOG="$T/github-auth.config" \
  "$ROOT/build/rh_cli" forge normalize --connector github --url "$api_url" --out "$T/github-auth.out" --fetched-at 1700000000 >/dev/null \
  || fail "authenticated GitHub API fetch"
grep -Fxq 'header = "Authorization: Bearer ghp_test-token_1"' "$T/github-auth.config" || fail "GitHub bearer header missing from curl stdin config"
! grep -Fq 'ghp_test-token_1' "$T/github-auth.args" || fail "GitHub token leaked into curl arguments"
for evidence in "$T/github-auth.out" "$T/github-auth.out.source" "$T/github-auth.out.source.status" "$T/github-auth.out.source.err"; do
  [[ ! -f "$evidence" ]] || ! grep -Fq 'ghp_test-token_1' "$evidence" || fail "GitHub token leaked into retained evidence"
done
cmp -s "$T/gh.out" "$T/github-auth.out" || fail "authenticated GitHub normalization changed canonical output"
set +e
PATH="$T/bin:$PATH" RH_GITHUB_TOKEN="bad token" RH_CURL_BODY="$T/github-repo.json" \
  RH_CURL_LOG="$T/github-invalid-token.args" RH_CURL_CONFIG_LOG="$T/github-invalid-token.config" \
  "$ROOT/build/rh_cli" forge normalize --connector github --url "$api_url" --out "$T/github-invalid-token.out" --fetched-at 1700000000 >/dev/null 2>&1
invalid_token_rc=$?
set -e
[[ "$invalid_token_rc" -eq 4 ]] || fail "invalid GitHub token must fail closed (got $invalid_token_rc)"
[[ ! -e "$T/github-invalid-token.args" && ! -e "$T/github-invalid-token.out" ]] || fail "invalid GitHub token launched curl or wrote a result"
echo "[forge] token authentication is host-scoped, input-validated, and absent from arguments and evidence"

echo "[forge] negatives fail closed"
set +e
for conn in generic-git mercurial bogus ""; do
  "$ROOT/build/rh_cli" forge normalize --connector "$conn" --input "$T/github-repo.json" --out "$T/x" --fetched-at 1 >/dev/null 2>&1
  rc=$?
  [[ "$rc" -eq 3 ]] || fail "unsupported connector '$conn' must exit 3 (got $rc)"
done
printf '{"not":"a repo"}' > "$T/bad.json"
"$ROOT/build/rh_cli" forge normalize --connector github --input "$T/bad.json" --out "$T/x" --fetched-at 1 >/dev/null 2>&1; rc_shape=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" forge normalize --connector github --input "$T/notjson.json" --out "$T/x" --fetched-at 1 >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" forge normalize --connector github --input "$T/nope.json" --out "$T/x" --fetched-at 1 >/dev/null 2>&1; rc_missing=$?
"$ROOT/build/rh_cli" forge normalize --connector github --out "$T/x" --fetched-at 1 >/dev/null 2>&1; rc_neither=$?
"$ROOT/build/rh_cli" forge normalize --connector github --input "$T/github-repo.json" --url "$source_url" --out "$T/x" --fetched-at 1 >/dev/null 2>&1; rc_both=$?
set -e
[[ "$rc_shape" -eq 4 ]] || fail "shape mismatch must exit 4 (got $rc_shape)"
[[ "$rc_json" -eq 4 ]] || fail "invalid JSON must exit 4 (got $rc_json)"
[[ "$rc_missing" -eq 4 ]] || fail "missing input must exit 4 (got $rc_missing)"
[[ "$rc_neither" -eq 2 ]] || fail "missing input/url must exit 2 (got $rc_neither)"
[[ "$rc_both" -eq 2 ]] || fail "input and url together must exit 2 (got $rc_both)"

echo "test_forge_cli OK"
