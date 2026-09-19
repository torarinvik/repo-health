#!/usr/bin/env bash
# tests/test_m05.sh — M05 gate: labeled graph projections, temporal edges,
# reverse traversal, SCC, mirrors/families, downstream joins, adoption,
# scenarios, anti-circularity. Deterministic, offline.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m05] FAIL: $1" >&2; exit 1; }

echo "[m05] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_m05" ]] || fail "test_m05 not built"

echo "[m05] graph-count suite + temporal + anti-circularity"
out="$("$ROOT/build/test_m05")" || fail "test_m05: $out"
[[ "$out" == *"M05 OK"* ]] || fail "test_m05: $out"
echo "$out"

echo "[m05] S009: no future-evidence leakage across valid/known time"
grep -q "known-2025-cannot-see-2026-discovery" "$ROOT/src/test_m05.elisa" || fail "S009 known-time leakage check missing"
grep -q "known-2026-sees-discovery" "$ROOT/src/test_m05.elisa" || fail "S009 retrospective-visibility check missing"
grep -q "valid-2024-after-introduction" "$ROOT/src/test_m05.elisa" || fail "S009 valid-time check missing"

echo "[m05] S007: private nodes absent from public counts and frontier"
grep -q "private-subtree-not-in-public-frontier" "$ROOT/src/test_m05.elisa" || fail "private-frontier check missing"
grep -q "private-5-absent-from-frontier" "$ROOT/src/test_m05.elisa" || fail "private-frontier node check missing"

echo "[m05] structural: no recursion in graph traversal (iterative stacks only)"
if grep -qE "def rh_(transitive_dependents|scc_count)" "$ROOT/src/rh_graph.elisa"; then
  # The functions must not call themselves.
  python3 - "$ROOT/src/rh_graph.elisa" <<'EOF'
import re, sys
src = open(sys.argv[1]).read()
for fn in ("rh_transitive_dependents", "rh_scc_count", "rh_direct_dependents"):
    m = re.search(r'^def ' + fn + r'\(.*?\)[^:]*:\n((?:    .*\n|\n)*)', src, re.M)
    assert m, fn
    body = m.group(0)
    assert fn not in body.split("\n", 1)[1], (fn, "recursive")
print("[m05] iterative traversal OK")
EOF
fi

echo "[m05] honesty: STATUS.md marks M05 in progress"
grep -q "M05 temporal/downstream.*in_progress" "$ROOT/STATUS.md" || fail "STATUS.md misstates M05"

echo "test_m05 OK"
