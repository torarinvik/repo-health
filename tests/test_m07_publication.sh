#!/usr/bin/env bash
# tests/test_m07_publication.sh — S010/R030 publication review gate.
# Runs the scanner on a real repo, then verifies the produced artifacts
# contain no person-level moral/medical/sensitive, safety, or universal
# score language; and includes a negative control proving the reviewer
# rejects such language when injected.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-m07-publication"

fail() { echo "[publication] FAIL: $1" >&2; exit 1; }

echo "[publication] build + scan a real repo"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
rm -rf "$T"; mkdir -p "$T"
# Build a real repo with history (the allowlist rejects paths with spaces,
# so the fixture lives under /tmp).
mkdir -p "$T/src" && git init -q -b main "$T/src" && (
  cd "$T/src" && git config user.name "Dev" && git config user.email "dev@example.com"
  echo x > f && git add f
  GIT_AUTHOR_DATE="2024-03-01T00:00:00Z" GIT_COMMITTER_DATE="2024-03-01T00:00:00Z" git commit -qm "one"
)
"$ROOT/build/rh_cli" scan --repo "$T/src" --out "$T/rep" --window-days 36500 >/dev/null || fail "scan failed"

echo "[publication] generated report is clean"
out="$(bash "$ROOT/tools/publication-review.sh" "$T/rep")" || fail "$out"
echo "$out"

echo "[publication] negative control: injected verdict language is rejected"
cp -r "$T/rep" "$T/bad"
printf '\nThis project is trustworthy and has a health score of 9.\n' >> "$T/bad/report.md"
if bash "$ROOT/tools/publication-review.sh" "$T/bad" >/dev/null 2>&1; then
  fail "reviewer accepted prohibited verdict language"
fi
echo "[publication] negative control OK"

echo "[publication] report states prohibited inferences are not collected"
python3 - "$T/rep/report.md" <<'PY'
import sys
md = open(sys.argv[1]).read().lower()
assert "not called maintainers" in md, md
assert "not zero" in md, md
print("[publication] caveat language OK")
PY

echo "test_m07_publication OK"
