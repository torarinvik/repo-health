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
print("[forge] goldens reproduced byte-for-byte")
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
