#!/usr/bin/env bash
# tests/test_docs.sh — doc gate: the governance, migration, release and
# runbook documents exist, name the mechanisms they describe, and contain
# no safety/trust verdict language. Also checks that every command they
# cite actually exists.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[docs] FAIL: $1" >&2; exit 1; }

need() { [[ -f "$ROOT/$1" ]] || fail "missing $1"; }
need docs/GOVERNANCE.md
need docs/operations/MIGRATIONS.md
need docs/operations/RELEASE.md
need docs/operations/runbooks.md
need docs/adr/ADR-000.md
need docs/THREAT_MODEL.md
need TOOLCHAIN.md

echo "[docs] cited paths exist"
python3 - "$ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
files = ["docs/GOVERNANCE.md", "docs/operations/MIGRATIONS.md",
         "docs/operations/RELEASE.md", "docs/operations/runbooks.md"]
missing = []
for f in files:
    text = open(os.path.join(root, f), encoding="utf-8").read()
    for m in re.finditer(r"`([A-Za-z0-9_./-]+\.(?:sh|json|elisa|md)|tests/[A-Za-z0-9_./-]+)`", text):
        p = m.group(1)
        if p.startswith("http") or p.startswith("build/"):
            continue  # generated artifacts, created by tools at run time
        if not os.path.exists(os.path.join(root, p)):
            missing.append((f, p))
assert not missing, ("cited paths do not exist", missing)
print("[docs] cited paths OK")
PY

echo "[docs] governance names the enforced mechanisms"
grep -q "metric-lint.sh" "$ROOT/docs/GOVERNANCE.md" || fail "governance missing metric-lint"
grep -q "test_profile.sh" "$ROOT/docs/GOVERNANCE.md" || fail "governance missing profile test"
grep -q "new version" "$ROOT/docs/GOVERNANCE.md" || fail "governance missing version-not-rewrite rule"

echo "[docs] migrations state rollback and replayability"
grep -qi "rollback" "$ROOT/docs/operations/MIGRATIONS.md" || fail "migrations missing rollback"
grep -q "not_replayable" "$ROOT/docs/operations/MIGRATIONS.md" || fail "migrations missing replayability"

echo "[docs] release doc forbids roadmap-as-released and hidden scores"
grep -qi "roadmap" "$ROOT/docs/operations/RELEASE.md" || fail "release missing roadmap rule"
grep -qi "hidden incompleteness" "$ROOT/docs/operations/RELEASE.md" || fail "release missing hidden-score rule"

echo "[docs] no safety/trust verdicts in process docs"
if grep -riE "\bis safe\b|trustworthy|certified safe|health score" \
    "$ROOT/docs/GOVERNANCE.md" "$ROOT/docs/operations/MIGRATIONS.md" \
    "$ROOT/docs/operations/RELEASE.md" "$ROOT/docs/operations/runbooks.md"; then
  fail "safety/trust verdict language in docs"
fi
echo "[docs] language OK"

echo "test_docs OK"
