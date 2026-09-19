#!/usr/bin/env bash
# tests/test_explain_cli.sh — M06 report explanation projection:
# `rh_cli explain` turns a pinned repo-health-m01 report into deterministic
# Markdown that repeats typed status/reason/value/evidence and capabilities.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-explain"

fail() { echo "[explain] FAIL: $1" >&2; exit 1; }

echo "[explain] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T/src"
git init -q -b main "$T/src"
(
  cd "$T/src"
  git config user.name "Explain Dev"; git config user.email "explain@example.com"
  echo x > f; git add f
  GIT_AUTHOR_DATE="2024-03-01T00:00:00Z" GIT_COMMITTER_DATE="2024-03-01T00:00:00Z" git commit -qm one
)
"$ROOT/build/rh_cli" scan --repo "$T/src" --out "$T/report" --window-days 36500 >/dev/null || fail "scan"
"$ROOT/build/rh_cli" explain --input "$T/report/report.json" --out "$T/explain.md" >/dev/null || fail "explain"
python3 - "$T/explain.md" <<'PY'
import sys
h = open(sys.argv[1], encoding="utf-8").read()
for token in ("repo-health-explain/1", "history.commit_count", "coverage.window_completeness",
              "evidence/git-log.bin", "review_events", "Unknown is not zero"):
    assert token in h, token
assert "health, trust, or safety verdict" in h, h
assert "| metric | status | reason | value | evidence |" in h, h
print("[explain] typed metric/capability tables OK")
PY

echo "[explain] determinism"
"$ROOT/build/rh_cli" explain --input "$T/report/report.json" --out "$T/explain2.md" >/dev/null || fail "rerun"
cmp -s "$T/explain.md" "$T/explain2.md" || fail "explanation not deterministic"

echo "[explain] unsupported reports fail closed"
set +e
printf '{"report":"other","metrics":[]}' > "$T/other.json"
"$ROOT/build/rh_cli" explain --input "$T/other.json" --out "$T/x" >/dev/null 2>&1; rc_other=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" explain --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
set -e
[[ "$rc_other" -eq 4 ]] || fail "unsupported report must exit 4 (got $rc_other)"
[[ "$rc_json" -eq 4 ]] || fail "invalid report must exit 4 (got $rc_json)"

echo "test_explain_cli OK"
