#!/usr/bin/env bash
# tests/test_registry_meta_cli.sh — M03-05 registry enrichment execution
# path: `rh_cli registry-meta` turns an rh-registry-meta/1 document into
# rh-registry-meta-result/1. Asserts yanked versions are retained, an absent
# yank field is null (unknown, not false), numeric and ISO published times
# are preserved, deprecation notices stay tri-state and bounded, a declared
# repository link is an assertion (not identity),
# declared dependency counts are exact, and malformed input fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-registry-meta"

fail() { echo "[registry-meta] FAIL: $1" >&2; exit 1; }

echo "[registry-meta] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/packages/registry-meta.json" "$T/in.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
cmp -s "$T/out.json" "$ROOT/fixtures/packages/registry-meta-result.json" || fail "output differs from the checked-in contract fixture"
python3 - "$T/out.json" "$T/in.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
raw = open(sys.argv[2], "rb").read()
assert d["schema"] == "rh-registry-meta-result/1", d
assert d["provenance"] == {"input_sha256": hashlib.sha256(raw).hexdigest(),
                            "origin": "local_input", "locator_sha256": None}, d["provenance"]
assert sys.argv[2] not in json.dumps(d), "local path leaked into report"
assert d["counts"] == {"versions": 3, "yanked": 1, "unknown_yank": 1,
                       "deprecated": 1, "not_deprecated": 1, "unknown_deprecation": 1, "with_repo": 1, "with_source_link": 1,
                       "declared_deps": 3, "optional_deps": 1, "dev_deps": 1}, d["counts"]
v = d["versions"]
assert v[0] == {"version": "1.0.0", "yanked": False, "deprecated": False, "deprecation_notice": None,
                "published_at": 1609459200,
                "repository": "https://example.invalid/serde",
                "source_link": "https://example.invalid/serde", "source_link_kind": "repository",
                "dep_count": 3, "optional_dep_count": 1, "dev_dep_count": 1}, v[0]
assert v[1]["yanked"] is True and v[1]["published_at"] == "2024-03-10T12:00:00Z", v[1]
assert v[1]["deprecated"] is True and v[1]["deprecation_notice"] == "Use 1.0.2 instead", v[1]
# retained, not deleted: the yanked version is still present
assert len(v) == 3 and v[1]["version"] == "1.0.1", v
# absent yank -> null (unknown), never false
assert v[2]["yanked"] is None and v[2]["published_at"] is None, v[2]
assert v[2]["deprecated"] is None and v[2]["deprecation_notice"] is None, v[2]
assert v[2]["source_link"] is None and v[2]["source_link_kind"] is None, v[2]
assert "assertion, not identity" in d["note"], d["note"]
assert "retained, not deleted" in d["note"], d["note"]
print("[registry-meta] counts + honest states OK")
PY

echo "[registry-meta] legacy repository inputs get an explicit source-link kind"
cat > "$T/legacy-link.json" <<'JSON'
{"versions":[{"num":"1.0.0","repository":"https://example.invalid/source"}]}
JSON
"$ROOT/build/rh_cli" registry-meta --input "$T/legacy-link.json" --out "$T/legacy-link.out" >/dev/null || fail "legacy link alias"
python3 - "$T/legacy-link.out" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))["versions"][0]
assert v["repository"] == "https://example.invalid/source", v
assert v["source_link"] == v["repository"] and v["source_link_kind"] == "repository", v
print("[registry-meta] legacy link assertion retained and typed OK")
PY

echo "[registry-meta] yank false/true/absent map to false/true/null"
cat > "$T/yanks.json" <<'JSON'
{"versions":[{"num":"1","yanked":false},{"num":"2","yanked":true},{"num":"3"}]}
JSON
"$ROOT/build/rh_cli" registry-meta --input "$T/yanks.json" --out "$T/yanks.out" >/dev/null || fail "yanks"
python3 - "$T/yanks.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert [x["yanked"] for x in d["versions"]] == [False, True, None], d["versions"]
assert d["counts"]["yanked"] == 1 and d["counts"]["unknown_yank"] == 1, d["counts"]
print("[registry-meta] yank tri-state OK")
PY

echo "[registry-meta] determinism"
"$ROOT/build/rh_cli" registry-meta --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "registry-meta output not deterministic"

echo "[registry-meta] PyPI provider shape normalizes to the canonical contract"
cat > "$T/pypi.json" <<'JSON'
{
  "info": {
    "version": "2.0.0",
    "home_page": "https://example.invalid/project",
    "requires_dist": ["httpx>=1", "sphinx; extra == 'docs'"]
  },
  "releases": {
    "1.0.0": [
      {"upload_time_iso_8601": "2023-01-02T03:04:05Z", "yanked": false}
    ],
    "1.1.0": [
      {"upload_time_iso_8601": "2023-02-02T03:04:05Z", "yanked": true},
      {"upload_time_iso_8601": "2023-02-02T03:05:05Z", "yanked": true}
    ],
    "2.0.0": [
      {"upload_time_iso_8601": "2024-01-02T03:04:05Z"}
    ]
  }
}
JSON
"$ROOT/build/rh_cli" registry-meta --input "$T/pypi.json" --out "$T/pypi.out" >/dev/null || fail "pypi adapter"
python3 - "$T/pypi.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-registry-meta-result/1", d
assert d["counts"] == {"versions": 3, "yanked": 1, "unknown_yank": 1,
                       "deprecated": 0, "not_deprecated": 0, "unknown_deprecation": 3, "with_repo": 3, "with_source_link": 3,
                       "declared_deps": 2, "optional_deps": 1, "dev_deps": 0}, d["counts"]
v = d["versions"]
assert v[0]["version"] == "1.0.0" and v[0]["yanked"] is False, v[0]
assert v[1]["version"] == "1.1.0" and v[1]["yanked"] is True, v[1]
assert v[2]["version"] == "2.0.0" and v[2]["yanked"] is None, v[2]
assert v[2]["repository"] == "https://example.invalid/project", v[2]
assert v[2]["source_link_kind"] == "homepage" and v[2]["source_link"] == v[2]["repository"], v[2]
assert v[2]["dep_count"] == 2 and v[2]["optional_dep_count"] == 1, v[2]
print("[registry-meta] PyPI release/yank/dependency normalization OK")
PY

echo "[registry-meta] npm provider shape normalizes to the canonical contract"
cat > "$T/npm.json" <<'JSON'
{
  "name": "demo",
  "time": {
    "created": "2024-01-01T00:00:00Z",
    "1.0.0": "2024-01-02T00:00:00Z",
    "1.1.0": "2024-02-02T00:00:00Z"
  },
  "versions": {
      "1.0.0": {
        "version": "1.0.0",
        "deprecated": "Use 1.1.0 instead",
      "repository": {"type": "git", "url": "https://example.invalid/demo.git"},
      "dependencies": {"a": "^1"},
      "optionalDependencies": {"b": "^2"},
      "devDependencies": {"c": "^3"}
    },
    "1.1.0": {
      "version": "1.1.0",
      "homepage": "https://example.invalid/home",
      "dependencies": {}
    }
  }
}
JSON
"$ROOT/build/rh_cli" registry-meta --input "$T/npm.json" --out "$T/npm.out" >/dev/null || fail "npm adapter"
python3 - "$T/npm.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["counts"] == {"versions": 2, "yanked": 0, "unknown_yank": 2,
                       "deprecated": 1, "not_deprecated": 1, "unknown_deprecation": 0, "with_repo": 2, "with_source_link": 2,
                       "declared_deps": 3, "optional_deps": 1, "dev_deps": 1}, d["counts"]
v = d["versions"]
assert v[0]["published_at"] == "2024-01-02T00:00:00Z", v[0]
assert v[0]["repository"] == "https://example.invalid/demo.git", v[0]
assert v[0]["source_link_kind"] == "repository", v[0]
assert v[0]["deprecated"] is True and v[0]["deprecation_notice"] == "Use 1.1.0 instead", v[0]
assert v[0]["dep_count"] == 3 and v[0]["optional_dep_count"] == 1 and v[0]["dev_dep_count"] == 1, v[0]
assert v[1]["repository"] == "https://example.invalid/home" and v[1]["yanked"] is None, v[1]
assert v[1]["source_link_kind"] == "homepage", v[1]
assert v[1]["deprecated"] is False and v[1]["deprecation_notice"] is None, v[1]
print("[registry-meta] npm release/time/repository/dependency normalization OK")
PY

echo "[registry-meta] crates.io provider envelope normalizes to the canonical contract"
cat > "$T/crates.json" <<'JSON'
{
  "crate": {"name": "demo", "repository": "https://example.invalid/demo"},
  "versions": [
    {"num": "1.0.0", "yanked": false, "created_at": "2024-01-02T00:00:00Z"},
    {"num": "1.1.0", "yanked": true},
    {"num": "1.2.0"}
  ]
}
JSON
"$ROOT/build/rh_cli" registry-meta --input "$T/crates.json" --out "$T/crates.out" >/dev/null || fail "crates adapter"
python3 - "$T/crates.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["counts"] == {"versions": 3, "yanked": 1, "unknown_yank": 1,
                       "deprecated": 0, "not_deprecated": 0, "unknown_deprecation": 3, "with_repo": 3, "with_source_link": 3,
                       "declared_deps": 0, "optional_deps": 0, "dev_deps": 0}, d["counts"]
v = d["versions"]
assert v[0]["published_at"] == "2024-01-02T00:00:00Z" and v[0]["repository"] == "https://example.invalid/demo", v[0]
assert v[0]["source_link_kind"] == "repository", v[0]
assert v[1]["yanked"] is True and v[2]["yanked"] is None, v
print("[registry-meta] crates version/yank/time/repository normalization OK")
PY

echo "[registry-meta] RubyGems versions endpoint normalizes to the canonical contract"
cp "$ROOT/fixtures/packages/rubygems-project.json" "$T/rubygems.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/rubygems.json" --out "$T/rubygems.out" >/dev/null || fail "RubyGems adapter"
python3 - "$T/rubygems.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["counts"] == {"versions": 3, "yanked": 1, "unknown_yank": 1,
                       "deprecated": 0, "not_deprecated": 0, "unknown_deprecation": 3, "with_repo": 3, "with_source_link": 3,
                       "declared_deps": 2, "optional_deps": 0, "dev_deps": 1}, d["counts"]
v = d["versions"]
assert v[0]["version"] == "1.0.0" and v[0]["repository"] == "https://example.invalid/gems/demo", v[0]
assert v[0]["source_link_kind"] == "source_code", v[0]
assert v[0]["dep_count"] == 2 and v[0]["dev_dep_count"] == 1, v[0]
assert v[1]["yanked"] is True and v[1]["published_at"] == "2024-02-02T00:00:00Z", v[1]
assert v[1]["repository"] == "https://example.invalid/home", v[1]
assert v[1]["source_link_kind"] == "homepage", v[1]
assert v[2]["yanked"] is None and v[2]["published_at"] is None, v[2]
print("[registry-meta] RubyGems release/yank/dependency normalization OK")
PY
cat > "$T/rubygems-array.json" <<'JSON'
[
  {"number":"2.0.0","created_at":"2025-01-01T00:00:00Z","yanked":false}
]
JSON
"$ROOT/build/rh_cli" registry-meta --input "$T/rubygems-array.json" --out "$T/rubygems-array.out" >/dev/null || fail "RubyGems versions array"
python3 - "$T/rubygems-array.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["counts"]["versions"] == 1 and d["versions"][0]["version"] == "2.0.0", d
assert d["versions"][0]["repository"] is None, d
print("[registry-meta] RubyGems versions array OK")
PY

echo "[registry-meta] NuGet registration pages normalize listed/yanked metadata"
cp "$ROOT/fixtures/packages/nuget-registration.json" "$T/nuget.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/nuget.json" --out "$T/nuget.out" >/dev/null || fail "NuGet adapter"
python3 - "$T/nuget.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["counts"] == {"versions": 2, "yanked": 1, "unknown_yank": 0,
                       "deprecated": 1, "not_deprecated": 1, "unknown_deprecation": 0, "with_repo": 1, "with_source_link": 1,
                       "declared_deps": 2, "optional_deps": 0, "dev_deps": 0}, d["counts"]
v = d["versions"]
assert v[0]["version"] == "1.0.0" and v[0]["yanked"] is False, v[0]
assert v[0]["repository"] == "https://example.invalid/nuget/demo" and v[0]["dep_count"] == 2, v[0]
assert v[0]["source_link_kind"] == "project_url", v[0]
assert v[1]["version"] == "1.1.0" and v[1]["yanked"] is True, v[1]
assert v[1]["deprecated"] is True and v[1]["deprecation_notice"] == "Use 2.0.0 or later", v[1]
print("[registry-meta] NuGet registration normalization OK")
PY

echo "[registry-meta] NuGet nested pages preserve unknown listed state"
cat > "$T/nuget-nested.json" <<'JSON'
{"items":[{"items":[{"catalogEntry":{"version":"2.0.0","published":null,"listed":null,"dependencyGroups":[]}}]}]}
JSON
"$ROOT/build/rh_cli" registry-meta --input "$T/nuget-nested.json" --out "$T/nuget-nested.out" >/dev/null || fail "NuGet nested page adapter"
python3 - "$T/nuget-nested.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["counts"] == {"versions": 1, "yanked": 0, "unknown_yank": 1,
                       "deprecated": 0, "not_deprecated": 1, "unknown_deprecation": 0, "with_repo": 0, "with_source_link": 0,
                       "declared_deps": 0, "optional_deps": 0, "dev_deps": 0}, d["counts"]
assert d["versions"] == [{"version": "2.0.0", "yanked": None, "deprecated": False,
                          "deprecation_notice": None, "published_at": None,
                          "repository": None, "source_link": None, "source_link_kind": None,
                          "dep_count": 0, "optional_dep_count": 0,
                          "dev_dep_count": 0}], d["versions"]
print("[registry-meta] NuGet nested page + unknown listed state OK")
PY

echo "[registry-meta] bounded file transport capture"
URL="file://$T/in.json"
"$ROOT/build/rh_cli" registry-meta --url "$URL" --out "$T/fetched.json" >/dev/null || fail "file fetch"
python3 - "$T/out.json" "$T/fetched.json" "$T/in.json" "$URL" <<'PY'
import hashlib, json, sys
local, fetched = (json.load(open(path)) for path in sys.argv[1:3])
raw = open(sys.argv[3], "rb").read()
url = sys.argv[4]
assert local["counts"] == fetched["counts"] and local["versions"] == fetched["versions"], fetched
assert fetched["provenance"] == {"input_sha256": hashlib.sha256(raw).hexdigest(),
                                 "origin": "captured_url",
                                 "locator_sha256": hashlib.sha256(url.encode()).hexdigest()}, fetched["provenance"]
assert url not in json.dumps(fetched), "raw URL leaked into report"
print("[registry-meta] exact-byte digest + captured origin/locator OK")
PY
python3 - "$T/registry-meta-fetch-status.txt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d == {
    "schema": "rh-registry-meta-fetch/1",
    "source_url": "file://" + sys.argv[1].rsplit("/registry-meta-fetch-status.txt", 1)[0] + "/in.json",
    "status": "000",
    "body_file": "registry-meta-fetch-body.json",
    "state": "collected",
    "note": "bounded transport capture retained before registry metadata parsing",
}, d
print("[registry-meta] fetch evidence retained")
PY
cmp -s "$T/in.json" "$T/registry-meta-fetch-body.json" || fail "fetched body not retained"

echo "[registry-meta] malformed input fails closed"
set +e
python3 - "$T/oversized.json" <<'PY'
import sys
with open(sys.argv[1], "wb") as f:
    f.seek(4 * 1024 * 1024)
    f.write(b"x")
PY
"$ROOT/build/rh_cli" registry-meta --input "$T/oversized.json" --out "$T/oversized.out" >/dev/null 2>&1; rc_oversized=$?
printf '{"versions":42}' > "$T/shape.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/shape.json" --out "$T/x" >/dev/null 2>&1; rc_shape=$?
printf '[{"versions":[]}]' > "$T/arr.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/arr.json" --out "$T/x" >/dev/null 2>&1; rc_arr=$?
printf '{"noversions":[]}' > "$T/novers.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/novers.json" --out "$T/x" >/dev/null 2>&1; rc_novers=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" registry-meta --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
"$ROOT/build/rh_cli" registry-meta --url "https://127.0.0.1/nope" --out "$T/x" >/dev/null 2>&1; rc_blocked=$?
printf '{"versions":{"1.0.0":42}}' > "$T/npm-bad.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/npm-bad.json" --out "$T/x" >/dev/null 2>&1; rc_npm=$?
printf '{"crate":{},"versions":[42]}' > "$T/crates-bad.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/crates-bad.json" --out "$T/x" >/dev/null 2>&1; rc_crates=$?
printf '[{"number":42}]' > "$T/rubygems-bad.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/rubygems-bad.json" --out "$T/x" >/dev/null 2>&1; rc_rubygems=$?
printf '{"items":[{"catalogEntry":{"version":42}}]}' > "$T/nuget-bad.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/nuget-bad.json" --out "$T/x" >/dev/null 2>&1; rc_nuget=$?
printf '{"versions":[{"num":"1","deprecated":"yes"}]}' > "$T/deprecated-bad.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/deprecated-bad.json" --out "$T/x" >/dev/null 2>&1; rc_deprecated=$?
printf '{"versions":[{"num":"1","source_link_kind":"homepage"}]}' > "$T/link-kind-without-link.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/link-kind-without-link.json" --out "$T/x" >/dev/null 2>&1; rc_link_kind=$?
printf '{"versions":[{"num":"1","repository":"https://example.invalid/x","source_link_kind":"hosted_at"}]}' > "$T/link-kind-unsupported.json"
"$ROOT/build/rh_cli" registry-meta --input "$T/link-kind-unsupported.json" --out "$T/x" >/dev/null 2>&1; rc_link_kind_unsupported=$?
python3 - "$T/deprecated-large.json" <<'PY'
import json, sys
json.dump({"versions": [{"num": "1", "deprecated": True, "deprecation_notice": "x" * 4097}]}, open(sys.argv[1], "w"))
PY
"$ROOT/build/rh_cli" registry-meta --input "$T/deprecated-large.json" --out "$T/x" >/dev/null 2>&1; rc_deprecated_large=$?
set -e
for rc in "$rc_oversized" "$rc_shape" "$rc_arr" "$rc_novers" "$rc_json" "$rc_missing" "$rc_blocked" "$rc_npm" "$rc_crates" "$rc_rubygems" "$rc_nuget" "$rc_deprecated" "$rc_link_kind" "$rc_link_kind_unsupported" "$rc_deprecated_large"; do
  [[ "$rc" -eq 4 ]] || fail "malformed registry-meta input must exit 4 (got $rc)"
done
[[ ! -e "$T/oversized.out" ]] || fail "oversized input produced a partial report"

echo "test_registry_meta_cli OK"
