#!/usr/bin/env bash
# Replay committed PostgreSQL forge stage rows through rh-forge-events/1.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-staged-forge"
fail() { echo "[staged-forge] FAIL: $1" >&2; exit 1; }

echo "[staged-forge] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/postgres/staged-github-issues-input.json" "$T/input.json"
cp "$ROOT/fixtures/postgres/staged-github-issues-output.json" "$T/expected.json"
cp "$ROOT/fixtures/postgres/staged-github-proposals-input.json" "$T/proposals-input.json"
cp "$ROOT/fixtures/postgres/staged-github-reviews-input.json" "$T/reviews-input.json"
cp "$ROOT/fixtures/postgres/staged-github-releases-input.json" "$T/releases-input.json"
cp "$ROOT/fixtures/postgres/staged-gitlab-issues-input.json" "$T/gitlab-issues-input.json"
cp "$ROOT/fixtures/postgres/staged-gitlab-proposals-input.json" "$T/gitlab-proposals-input.json"
cp "$ROOT/fixtures/postgres/staged-gitlab-releases-input.json" "$T/gitlab-releases-input.json"
cp "$ROOT/fixtures/postgres/staged-forge-events-gitea-issues-input.json" "$T/gitea-issues-input.json"
cp "$ROOT/fixtures/postgres/staged-forge-events-forgejo-proposals-input.json" "$T/forgejo-proposals-input.json"
cp "$ROOT/fixtures/postgres/staged-forge-events-bitbucket-issues-input.json" "$T/bitbucket-issues-input.json"

echo "[staged-forge] replay binds the exact stage input and preserves provenance"
"$ROOT/build/rh_cli" staged-normalize --input "$T/input.json" --out "$T/output.json" >/dev/null || fail "valid staged rows"
python3 - "$T/output.json" "$T/expected.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == json.load(open(sys.argv[2])), "result differs from checked-in replay"
PY

echo "[staged-forge] generic input keeps Gitea, Forgejo, and Bitbucket identities distinct"
for provider_capability in gitea-issues forgejo-proposals bitbucket-issues; do
  input="$T/$provider_capability-input.json"
  output="$T/$provider_capability-output.json"
  expected="$ROOT/fixtures/postgres/staged-forge-events-$provider_capability-output.json"
  "$ROOT/build/rh_cli" staged-normalize --input "$input" --out "$output" >/dev/null || fail "valid $provider_capability stage"
  python3 - "$input" "$output" "$expected" "$provider_capability" <<'PY'
import hashlib, json, sys
got = json.load(open(sys.argv[2]))
assert got == json.load(open(sys.argv[3])), (got, sys.argv[3])
assert got["input_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), got
provider, capability = sys.argv[4].split("-")
assert got["provider"] == provider and got["canonical_capability"] == capability, got
assert got["normalized"]["events"][0]["native_id"].startswith(provider + ":"), got["normalized"]["events"]
PY
done

echo "[staged-forge] GitLab merge-request identity and merged state stay native"
"$ROOT/build/rh_cli" staged-normalize --input "$T/gitlab-proposals-input.json" --out "$T/gitlab-proposals-output.json" >/dev/null || fail "valid staged GitLab merge requests"
python3 - "$T/gitlab-proposals-input.json" "$T/gitlab-proposals-output.json" "$ROOT/fixtures/postgres/staged-gitlab-proposals-output.json" <<'PY'
import hashlib, json, sys
got = json.load(open(sys.argv[2]))
expected = json.load(open(sys.argv[3]))
assert got == expected, (got, expected)
assert got["input_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), got
n = got["normalized"]
assert got["provider"] == "gitlab" and got["canonical_capability"] == "proposals", got
assert n["capabilities"]["proposals"]["count"] == 1, n["capabilities"]
assert n["events"][0]["native_id"] == "gitlab:8" and n["events"][0]["status"] == "merged", n["events"]
PY

echo "[staged-forge] GitLab release tags use the existing provider mapping"
"$ROOT/build/rh_cli" staged-normalize --input "$T/gitlab-releases-input.json" --out "$T/gitlab-releases-output.json" >/dev/null || fail "valid staged GitLab releases"
python3 - "$T/gitlab-releases-input.json" "$T/gitlab-releases-output.json" "$ROOT/fixtures/postgres/staged-gitlab-releases-output.json" <<'PY'
import hashlib, json, sys
got = json.load(open(sys.argv[2]))
expected = json.load(open(sys.argv[3]))
assert got == expected, (got, expected)
assert got["input_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), got
n = got["normalized"]
assert got["provider"] == "gitlab" and got["canonical_capability"] == "releases", got
assert n["capabilities"]["releases"]["count"] == 1, n["capabilities"]
assert n["events"][0]["native_id"] == "gitlab:10" and n["events"][0]["tag"] == "v2.0.0", n["events"]
PY

echo "[staged-forge] GitLab issue identity and status pass through the provider adapter"
"$ROOT/build/rh_cli" staged-normalize --input "$T/gitlab-issues-input.json" --out "$T/gitlab-issues-output.json" >/dev/null || fail "valid staged GitLab issues"
python3 - "$T/gitlab-issues-input.json" "$T/gitlab-issues-output.json" "$ROOT/fixtures/postgres/staged-gitlab-issues-output.json" <<'PY'
import hashlib, json, sys
got = json.load(open(sys.argv[2]))
expected = json.load(open(sys.argv[3]))
assert got == expected, (got, expected)
assert got["input_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), got
assert got["provider"] == "gitlab" and got["canonical_capability"] == "issues", got
n = got["normalized"]
assert n["provider"] == "gitlab" and "scope" not in n, n
assert n["capabilities"]["issues"]["count"] == 1, n["capabilities"]
assert n["events"][0]["native_id"] == "gitlab:12" and n["events"][0]["status"] == "opened", n["events"]
PY

echo "[staged-forge] explicit release binding normalizes published releases"
"$ROOT/build/rh_cli" staged-normalize --input "$T/releases-input.json" --out "$T/releases-output.json" >/dev/null || fail "valid staged releases"
python3 - "$T/releases-input.json" "$T/releases-output.json" "$ROOT/fixtures/postgres/staged-github-releases-output.json" <<'PY'
import hashlib, json, sys
got = json.load(open(sys.argv[2]))
expected = json.load(open(sys.argv[3]))
assert got == expected, (got, expected)
assert got["input_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), got
assert got["canonical_capability"] == "releases" and got["record_count"] == 1, got
n = got["normalized"]
assert n["capabilities"]["releases"]["status"] == "observed" and n["capabilities"]["releases"]["count"] == 1, n
assert n["events"][0]["kind"] == "releases" and n["events"][0]["native_id"] == "github:501", n["events"]
assert n["events"][0]["tag"] == "v1.0.0", n["events"]
assert n["capabilities"]["issues"]["status"] == "not_attempted" and n["capabilities"]["proposals"]["status"] == "not_attempted", n["capabilities"]
PY
python3 - "$T/input.json" "$T/output.json" <<'PY'
import hashlib, json, sys
raw = open(sys.argv[1], "rb").read()
d = json.load(open(sys.argv[2]))
assert d["schema"] == "rh-postgres-staged-normalize-result/1", d
assert d["input_sha256"] == hashlib.sha256(raw).hexdigest(), d["input_sha256"]
assert (d["source_id"], d["collection_run_id"]) == ("source-github-example", "run-github-example-001"), d
assert d["canonical_capability"] == "issues" and d["collector_label"] == "issues-page-v1", d
assert d["record_count"] == 2 and d["staged_records"] == [
    {"page_number": 0, "record_ordinal": 0}, {"page_number": 1, "record_ordinal": 0}
], d["staged_records"]
n = d["normalized"]
assert n["schema"] == "rh-forge-events-result/1" and n["capabilities"]["issues"]["duplicate_replacements"] == 1, n
assert n["capabilities"]["issues"]["count"] == 1 and n["events"][0]["native_id"] == "github:101", n
assert n["events"][0]["status"] == "closed", n["events"]
assert all(n["capabilities"][k]["status"] == "not_attempted" for k in ("proposals", "reviews", "releases")), n
PY
"$ROOT/build/rh_cli" staged-normalize --input "$T/input.json" --out "$T/replay.json" >/dev/null || fail "deterministic replay"
cmp -s "$T/output.json" "$T/replay.json" || fail "replay changed output bytes"

echo "[staged-forge] explicit pull-request binding normalizes proposals"
"$ROOT/build/rh_cli" staged-normalize --input "$T/proposals-input.json" --out "$T/proposals-output.json" >/dev/null || fail "valid staged pull requests"
python3 - "$T/proposals-input.json" "$T/proposals-output.json" "$ROOT/fixtures/postgres/staged-github-proposals-output.json" <<'PY'
import hashlib, json, sys
got = json.load(open(sys.argv[2]))
expected = json.load(open(sys.argv[3]))
assert got == expected, (got, expected)
assert got["input_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), got
assert got["canonical_capability"] == "proposals" and got["record_count"] == 1, got
n = got["normalized"]
assert n["capabilities"]["proposals"]["status"] == "observed" and n["capabilities"]["proposals"]["count"] == 1, n
assert n["events"][0]["kind"] == "proposals" and n["events"][0]["native_id"] == "github:17", n["events"]
assert n["capabilities"]["issues"]["status"] == "not_attempted", n["capabilities"]
PY

echo "[staged-forge] review inputs require and preserve pull-request scope"
"$ROOT/build/rh_cli" staged-normalize --input "$T/reviews-input.json" --out "$T/reviews-output.json" >/dev/null || fail "valid scoped reviews"
python3 - "$T/reviews-input.json" "$T/reviews-output.json" "$ROOT/fixtures/postgres/staged-github-reviews-output.json" <<'PY'
import hashlib, json, sys
got = json.load(open(sys.argv[2]))
expected = json.load(open(sys.argv[3]))
assert got == expected, (got, expected)
assert got["input_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), got
assert got["canonical_capability"] == "reviews", got
n = got["normalized"]
assert n["scope"] == {"repository": "example/project", "pull_request": 17}, n["scope"]
assert n["capabilities"]["reviews"]["status"] == "observed" and n["capabilities"]["reviews"]["count"] == 1, n
assert n["events"][0]["kind"] == "reviews" and n["events"][0]["native_id"] == "github:91" and n["events"][0]["pull_request"] == 17, n["events"]
PY

echo "[staged-forge] committed empty pages remain observed empty"
python3 - "$T/input.json" "$T/empty.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["pages"] = [{"page_number": 3, "committed": True, "completeness": "empty", "records": []}]
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" staged-normalize --input "$T/empty.json" --out "$T/empty.out" >/dev/null || fail "valid empty page"
python3 - "$T/empty.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["record_count"] == 0 and d["pages"] == [{"page_number": 3, "completeness": "empty", "record_count": 0}], d
issues = d["normalized"]["capabilities"]["issues"]
assert issues["status"] == "observed" and issues["count"] == 0 and issues["rejected"] == 0, issues
PY

echo "[staged-forge] uncommitted, partial, misbound, and malformed rows fail closed"
python3 - "$T/input.json" "$T" <<'PY'
import copy, json, os, sys
base = json.load(open(sys.argv[1]))
out = sys.argv[2]
cases = {}
d = copy.deepcopy(base); d["pages"][0]["committed"] = False; cases["uncommitted"] = d
d = copy.deepcopy(base); d["pages"][0]["completeness"] = "partial"; cases["partial"] = d
d = copy.deepcopy(base); d["pages"][0]["records"][0]["collector_label"] = "other-capability"; cases["misbound"] = d
d = copy.deepcopy(base); d["pages"][0]["records"][0]["record_ordinal"] = 1; cases["ordinal"] = d
d = copy.deepcopy(base); d["pages"][0]["records"][0]["raw_payload"] = "[]"; cases["non-object-payload"] = d
d = copy.deepcopy(base); d["canonical_capability"] = "proposals"; cases["schema-capability-mismatch"] = d
d = json.load(open(os.path.join(out, "reviews-input.json"))); d["scope"].pop("pull_request"); cases["review-scope-missing"] = d
d = json.load(open(os.path.join(out, "gitlab-issues-input.json"))); d["scope"] = {"repository": "group/project"}; cases["gitlab-github-scope-confusion"] = d
d = json.load(open(os.path.join(out, "bitbucket-issues-input.json"))); d["canonical_capability"] = "releases"; cases["unsupported-bitbucket-releases"] = d
d = json.load(open(os.path.join(out, "gitea-issues-input.json"))); d["canonical_capability"] = "reviews"; cases["unsupported-gitea-reviews"] = d
for name, value in cases.items():
    with open(os.path.join(out, name + ".json"), "w", encoding="utf-8") as f:
        json.dump(value, f, separators=(",", ":"))
PY
for name in uncommitted partial misbound ordinal non-object-payload schema-capability-mismatch review-scope-missing gitlab-github-scope-confusion unsupported-bitbucket-releases unsupported-gitea-reviews; do
  if "$ROOT/build/rh_cli" staged-normalize --input "$T/$name.json" --out "$T/$name.out" >/dev/null 2>&1; then
    fail "$name stage input was accepted"
  fi
  [[ ! -e "$T/$name.out" ]] || fail "$name wrote an output despite rejection"
done

grep -q "rh-postgres-staged-github-issues-input/1" "$ROOT/src/rh_staged_forge.elisa" || fail "issue input contract token missing"
grep -q "rh-postgres-staged-github-proposals-input/1" "$ROOT/src/rh_staged_forge.elisa" || fail "proposal input contract token missing"
grep -q "rh-postgres-staged-github-reviews-input/1" "$ROOT/src/rh_staged_forge.elisa" || fail "review input contract token missing"
grep -q "rh-postgres-staged-github-releases-input/1" "$ROOT/src/rh_staged_forge.elisa" || fail "release input contract token missing"
grep -q "rh-postgres-staged-gitlab-issues-input/1" "$ROOT/src/rh_staged_forge.elisa" || fail "GitLab input contract token missing"
grep -q "rh-postgres-staged-gitlab-proposals-input/1" "$ROOT/src/rh_staged_forge.elisa" || fail "GitLab proposal contract token missing"
grep -q "rh-postgres-staged-gitlab-releases-input/1" "$ROOT/src/rh_staged_forge.elisa" || fail "GitLab release contract token missing"
grep -q "rh-postgres-staged-forge-events-input/1" "$ROOT/src/rh_staged_forge.elisa" || fail "generic forge events contract token missing"
grep -q "rh-postgres-staged-normalize-result/1" "$ROOT/src/rh_staged_forge.elisa" || fail "result contract token missing"
echo "test_staged_forge_cli OK"
