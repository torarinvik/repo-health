#!/usr/bin/env bash
# tests/test_m01.sh — M01 exit gate: safe scan, replay, hostile fixtures.
# All fixture paths are allowlist-clean (no spaces/metachars) by construction.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/build/rh_cli"
T="/tmp/rh-m01-gate"

fail() { echo "[m01] FAIL: $1" >&2; exit 1; }
# expect <code> <command...>: asserts an expected nonzero exit under set -e.
expect() {
  local want="$1"; shift
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  [[ "$got" == "$want" ]] || fail "expected exit $want, got $got: $*"
}
need() { # need <file> <desc>
  [[ -f "$1" ]] || fail "missing $2 ($1)"
}

echo "[m01] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$CLI" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"

# --- usage / validation gates ---
expect 2 "$CLI" bogus
expect 3 "$CLI" scan --repo 'http://evil.example/x' --out "$T/r1"
expect 3 "$CLI" scan --repo 'ssh://example.com/a' --out "$T/r1"
expect 3 "$CLI" scan --repo '/tmp/ok;id' --out "$T/r1"
expect 3 "$CLI" scan --repo '/tmp/ok$(id)' --out "$T/r1"
expect 4 "$CLI" scan --repo "$T/does-not-exist" --out "$T/r1"
echo "[m01] validation gates OK"

# --- F001: empty repository -> observed empty, honest unknowns ---
git init -q -b main "$T/empty"
"$CLI" scan --repo "$T/empty" --out "$T/rep-empty" >/dev/null || fail "empty scan"
python3 - "$T/rep-empty/report.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.commit_count"]["value"] == 0, m
assert m["contributors.raw_identity_count"]["value"] == 0, m
assert m["freshness.evidence_max_age_hours"]["status"] == "unavailable", m
assert "value" not in m["freshness.evidence_max_age_hours"], "unknown must carry no value"
print("[m01] F001 empty OK")
EOF

# --- F002: multi-author history, exact numbers + replay ---
mkdir -p "$T/fix2" && git init -q -b main "$T/fix2" && (
  cd "$T/fix2" && git config user.name "Alice" && git config user.email "alice@example.com"
  echo one > a.txt && git add a.txt
  GIT_AUTHOR_DATE="2024-03-10T12:00:00Z" GIT_COMMITTER_DATE="2024-03-10T12:00:00Z" git commit -qm "first"
  git config user.name "Bob" && git config user.email "bob@example.com"
  echo two > b.txt && git add b.txt
  GIT_AUTHOR_DATE="2024-06-15T12:00:00Z" GIT_COMMITTER_DATE="2024-06-20T12:00:00Z" git commit -qm "second"
  echo three >> a.txt && git add a.txt
  GIT_AUTHOR_DATE="2025-01-05T12:00:00Z" GIT_COMMITTER_DATE="2025-01-05T12:00:00Z" git commit -qm "third"
)
"$CLI" scan --repo "$T/fix2" --out "$T/rep-fix2" --window-days 36500 >/dev/null || fail "fix2 scan"
python3 - "$T/rep-fix2/report.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.commit_count"]["value"] == 3, m
assert m["history.reachable_revisions"]["value"] == 3, m
assert m["history.rejected_record_count"]["value"] == 0, m
assert m["contributors.raw_identity_count"]["value"] == 2, m
assert m["activity.active_complete_months"]["value"] == 3, m
assert len(d["metrics"]) == 13, d
coverage = {(x["key"], x["version"]): x for x in d["metrics"] if x["key"] == "coverage.window_completeness"}
assert coverage[("coverage.window_completeness", "1.0.0")]["value"]["num"] == coverage[("coverage.window_completeness", "1.0.0")]["value"]["den"], coverage
assert coverage[("coverage.window_completeness", "2.0.0")]["value"]["num"] == coverage[("coverage.window_completeness", "2.0.0")]["value"]["den"], coverage
valid = {"observed","not_observed","unavailable","unauthorized","partial","stale","not_applicable","error","conflicted","suppressed","unsupported"}
for x in d["metrics"]:
    assert x["status"] in valid, x
    if x["status"] not in ("observed","partial","stale"):
        assert "value" not in x, ("unknown carries value", x)
print("[m01] F002 exact OK")
EOF
"$CLI" replay --bundle "$T/rep-fix2/bundle.manifest" --out "$T/replay-fix2" >/dev/null || fail "replay"
python3 -c "
import json; d = json.load(open('$T/replay-fix2/replay.json'))
assert d['verified'] is True, d; print('[m01] replay verified OK')"
# determinism: scan twice, same digest
"$CLI" scan --repo "$T/fix2" --out "$T/rep-fix2b" --window-days 36500 >/dev/null || fail "rescan"
a="$(grep digest-fnv1a64 "$T/rep-fix2/bundle.manifest")"; b="$(grep digest-fnv1a64 "$T/rep-fix2b/bundle.manifest")"
[[ "$a" == "$b" ]] || fail "non-deterministic digest: $a vs $b"
echo "[m01] determinism OK"

# --- hostile: unicode author, future timestamp, skew, merge ---
mkdir -p "$T/hostile" && git init -q -b main "$T/hostile" && (
  cd "$T/hostile" && git config user.name "Åsa Ö" && git config user.email "asa@example.com"
  echo x > f && git add f
  GIT_AUTHOR_DATE="2024-01-01T00:00:00Z" GIT_COMMITTER_DATE="2030-01-01T00:00:00Z" git commit -qm "skewed future"
  git checkout -qb side && echo y > g && git add g
  GIT_AUTHOR_DATE="2024-02-01T00:00:00Z" GIT_COMMITTER_DATE="2024-02-01T00:00:00Z" git commit -qm "side work"
  git checkout -q main && git merge -q --no-ff side -m "merge side"
  printf 'bad\xffsubject' > msg && git commit -q --allow-empty -F msg
)
out="$("$CLI" scan --repo "$T/hostile" --out "$T/rep-hostile" --window-days 36500)" || fail "hostile scan crashed"
echo "$out"
python3 - "$T/rep-hostile/report.md" <<'EOF'
import sys
md = open(sys.argv[1]).read()
assert "| future timestamps | flagged | " in md, md
print("[m01] hostile future-flagged OK")
EOF
python3 -c "
import json; d = json.load(open('$T/rep-hostile/report.json'))
m = {x['key']: x for x in d['metrics']}
assert m['history.commit_count']['value'] == 4, m"
echo "[m01] hostile counts OK"

# --- S001: the scanner never runs a source-controlled command ---
# A hostile repository can carry config/attribute traps that would run
# arbitrary code under a naive tool (e.g. `core.fsmonitor` as a command,
# `core.pager`, filter drivers). The scanner must ignore all of them.
# The canary file must NOT be created by the scan.
mkdir -p "$T/traps" && git init -q -b main "$T/traps" && (
  cd "$T/traps" && git config user.name "Eve" && git config user.email "eve@example.com"
  # config traps whose values are shell commands
  git config core.fsmonitor "$T/CANARY_FSMONITOR"
  git config core.pager "$T/CANARY_PAGER"
  git config core.hooksPath "$T/traps-hooks"
  git config filter.evil.clean "$T/CANARY_FILTER"
  git config diff.evil.textconv "$T/CANARY_TEXTconv"
  # attributes trap referencing the filter
  printf '*.evil filter=evil\n' > .gitattributes
  printf 'payload\n' > f.evil
  echo x > f && git add f .gitattributes f.evil
  GIT_AUTHOR_DATE="2024-04-01T00:00:00Z" GIT_COMMITTER_DATE="2024-04-01T00:00:00Z" git commit -qm "traps"
  # an executable .git/hooks/post-checkout that would fire on a checkout-based tool
  printf '#!/bin/sh\ntouch "%s"\n' "$T/CANARY_HOOK" > .git/hooks/post-checkout
  chmod +x .git/hooks/post-checkout
)
rm -f "$T"/CANARY_*
"$CLI" scan --repo "$T/traps" --out "$T/rep-traps" --window-days 36500 >/dev/null || fail "traps scan crashed"
if ls "$T"/CANARY_* >/dev/null 2>&1; then
  fail "S001: a source-controlled command executed during collection: $(ls "$T"/CANARY_*)"
fi
python3 -c "
import json; d = json.load(open('$T/rep-traps/report.json'))
m = {x['key']: x for x in d['metrics']}
assert m['history.commit_count']['value'] == 1, m
print('[m01] S001 no-source-command canaries intact OK')"

# --- S003: transport credentials never appear in report, evidence, or logs ---
# The canary is a CREDENTIAL (a git credential-store token), not committed
# history. It must never appear anywhere. (A token a project deliberately
# commits as author data is evidence, not a leaked credential — that case
# is covered by the transport guard rejecting userinfo in URLs.)
SECRET='ghp_CANARY0123456789CANARY0123456789'
mkdir -p "$T/secret" && git init -q -b main "$T/secret" && (
  cd "$T/secret" && git config user.name "Secret Holder" && git config user.email "secret@example.com"
  git config credential.helper "store --file=$T/credentials"
  printf 'https://user:%s@example.invalid\n' "$SECRET" > "$T/credentials"
  chmod 600 "$T/credentials"
  echo x > f && git add f
  GIT_AUTHOR_DATE="2024-07-01T00:00:00Z" GIT_COMMITTER_DATE="2024-07-01T00:00:00Z" git commit -qm "clean history"
  # a URL with embedded credentials in upstream config: the transport guard
  # must reject userinfo, and nothing should echo the secret.
  git remote add origin "https://user:${SECRET}@example.invalid/x.git"
)
"$CLI" scan --repo "$T/secret" --out "$T/rep-secret" --window-days 36500 >/dev/null || fail "secret scan crashed"
if grep -R -q -- "$SECRET" "$T/rep-secret" 2>/dev/null; then
  fail "S003: credential canary found in scan output: $(grep -Rl -- "$SECRET" "$T/rep-secret")"
fi
# The remote URL itself is not evidence the scan copies, and the credential
# store file must not be captured by the scanner.
if grep -R -q -- "$SECRET" "$T/rep-secret/evidence" 2>/dev/null; then
  fail "S003: credential canary found in evidence"
fi
out_secret="$("$CLI" scan --repo "$T/secret" --out "$T/rep-secret2" --window-days 36500 2>&1 || true)"
if printf '%s' "$out_secret" | grep -q -- "$SECRET"; then
  fail "S003: credential canary found on stdout/stderr"
fi
echo "[m01] S003 credential-canary absent OK"

# --- shallow clone: no complete-lifetime claim ---
git clone -q --depth 1 "file://$T/fix2" "$T/shallow" 2>/dev/null
"$CLI" scan --repo "$T/shallow" --out "$T/rep-shallow" --window-days 36500 >/dev/null || fail "shallow scan"
python3 - "$T/rep-shallow/report.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.coverage_state"]["value"]["label"] == "shallow", m
assert m["coverage.window_completeness"]["status"] == "partial", m
coverage = {(x["key"], x["version"]): x for x in d["metrics"] if x["key"] == "coverage.window_completeness"}
v1 = coverage[("coverage.window_completeness", "1.0.0")]
v2 = coverage[("coverage.window_completeness", "2.0.0")]
assert v1["value"]["num"] == v1["value"]["den"], (v1, v2)
assert v2["value"]["num"] == v1["value"]["num"] and v2["value"]["den"] > v1["value"]["den"], (v1, v2)
print("[m01] shallow OK")
EOF

# --- clone-path equivalence: same history, different provenance ---
git clone -q "$T/fix2" "$T/fix2copy" 2>/dev/null
"$CLI" scan --repo "$T/fix2copy" --out "$T/rep-copy" --window-days 36500 >/dev/null || fail "copy scan"
python3 - "$T/rep-fix2/report.json" "$T/rep-copy/report.json" <<'EOF'
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
assert a["metrics"] == b["metrics"], "same history must yield same metrics"
assert a["source"] != b["source"], "provenance must differ"
print("[m01] clone equivalence OK")
EOF

# --- F004: missing blobs -> history observed, blob metrics partial ---
# A partial clone is marked via extensions.partialClone; the scanner must
# report blob-derived metrics PARTIAL while history stays observed. Both
# directions are checked: no marker -> not partial.
mkdir -p "$T/partial" && git init -q -b main "$T/partial" && (
  cd "$T/partial" && git config user.name "Pat" && git config user.email "pat@example.com"
  echo x > f && git add f
  GIT_AUTHOR_DATE="2024-05-01T00:00:00Z" GIT_COMMITTER_DATE="2024-05-01T00:00:00Z" git commit -qm "one"
  git config extensions.partialClone origin
  git config remote.origin.promisor true
)
"$CLI" scan --repo "$T/partial" --out "$T/rep-partial" --window-days 36500 >/dev/null || fail "partial scan"
python3 - "$T/rep-partial/report.json" "$T/rep-partial/report.md" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.commit_count"]["status"] == "observed", m
caps = d["capabilities"]
assert caps["blob_metrics"] == "partial-missing-blobs", caps
md = open(sys.argv[2]).read()
assert "blob-derived metrics | partial" in md, md
print("[m01] F004 partial-clone blob-partial OK")
EOF
"$CLI" scan --repo "$T/fix2" --out "$T/rep-nopart" --window-days 36500 >/dev/null || fail "nopart scan"
python3 - "$T/rep-nopart/report.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["blob_metrics"] == "not-derived", d["capabilities"]
print("[m01] F004 no-marker-not-partial OK")
EOF

# --- F006: identical-patch commits (cherry-pick-like) stay distinct ---
mkdir -p "$T/fix6" && git init -q -b main "$T/fix6" && (
  cd "$T/fix6" && git config user.name "Dev" && git config user.email "dev@example.com"
  echo base > base.txt && git add base.txt
  GIT_AUTHOR_DATE="2024-01-01T00:00:00Z" GIT_COMMITTER_DATE="2024-01-01T00:00:00Z" git commit -qm "base"
  echo shared > shared.txt && git add shared.txt
  GIT_AUTHOR_DATE="2024-02-01T00:00:00Z" GIT_COMMITTER_DATE="2024-02-01T00:00:00Z" git commit -qm "add shared"
  git checkout -q -b alt HEAD~1
  echo shared > shared.txt && git add shared.txt
  GIT_AUTHOR_DATE="2024-03-01T00:00:00Z" GIT_COMMITTER_DATE="2024-03-01T00:00:00Z" git commit -qm "add shared (re-created)"
)
"$CLI" scan --repo "$T/fix6" --out "$T/rep-fix6" --window-days 36500 >/dev/null || fail "fix6 scan"
python3 - "$T/rep-fix6/report.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.commit_count"]["value"] == 3, m
assert m["history.reachable_revisions"]["value"] == 3, m
blob = json.dumps(d).lower()
assert "equivalent" not in blob, "must not claim revision equivalence without evidence"
print("[m01] F006 distinct-revisions OK")
EOF

# --- tamper evidence: appended byte -> exit 5, no fabricated success ---
cp -r "$T/rep-fix2" "$T/rep-tampered"
printf 'X' >> "$T/rep-tampered/evidence/git-log.bin"
expect 5 "$CLI" replay --bundle "$T/rep-tampered/bundle.manifest" --out "$T/replay-t"
echo "[m01] tamper exit-5 OK"
# corrupt manifest -> exit 4 (fails closed)
cp "$T/rep-fix2/bundle.manifest" "$T/bad.manifest"
python3 -c "
src = open('$T/bad.manifest').read()
import re; src = re.sub(r'digest-fnv1a64: [0-9a-f]+', 'digest-fnv1a64: zzzzzzzzzzzzzzzz', src)
open('$T/bad.manifest','w').write(src)"
expect 4 "$CLI" replay --bundle "$T/bad.manifest" --out "$T/replay-b"
echo "[m01] corrupt-manifest exit-4 OK"

# --- R030: no universal score language anywhere in outputs ---
if grep -ril "health_score\|trust_score\|trustworthy\|health-rating" "$T/rep-fix2" "$T/rep-empty" "$T/rep-hostile" 2>/dev/null; then
  fail "universal-score language in reports"
fi
echo "[m01] R030 language scan OK"

echo "test_m01 OK"
