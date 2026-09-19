#!/usr/bin/env bash
# tests/test_render_cli.sh — M06-03 accessible server-rendered report page:
# `rh_cli render` turns an M01 report.json into a self-contained HTML page
# with a metric table (the text alternative), a capabilities table, and the
# mandatory caveats. Every dynamic string is HTML-escaped, so a hostile
# repository name cannot inject markup. Malformed input fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-render"

fail() { echo "[render] FAIL: $1" >&2; exit 1; }

echo "[render] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T/src"
git init -q -b main "$T/src"
(
  cd "$T/src"
  git config user.name "Dev"; git config user.email "dev@example.com"
  echo x > f && git add f
  GIT_AUTHOR_DATE="2024-03-01T00:00:00Z" GIT_COMMITTER_DATE="2024-03-01T00:00:00Z" git commit -qm one
)
"$ROOT/build/rh_cli" scan --repo "$T/src" --out "$T/rep" --window-days 36500 >/dev/null || fail "scan"
"$ROOT/build/rh_cli" render --report "$T/rep/report.json" --out "$T/rep/page.html" >/dev/null || fail "render"

echo "[render] page has a table, caveats, and no verdict"
python3 - "$T/rep/page.html" <<'PY'
import sys
h = open(sys.argv[1], encoding="utf-8").read()
assert "<!DOCTYPE html>" in h and "<table>" in h, "missing html/table"
assert 'content="repo-health-report-html/1"' in h, "missing generator version token"
assert 'scope="col"' in h and 'scope="row"' in h, "table headers must be scoped"
for key in ("history.commit_count", "history.reachable_revisions", "coverage.window_completeness"):
    assert key in h, ("missing metric key", key)
for caveat in ("not maintainers", "Unknown is not zero", "no universal health",
               "not collected from generic Git"):
    assert caveat in h, ("missing caveat", caveat)
assert "adds no verdict" in h, h[-500:]
assert "<h2>Capabilities</h2>" in h and "git_log" in h, "missing capabilities table"
# metrics table rows: one <tr> per metric plus the header
assert h.count("<tr>") >= 12, h.count("<tr>")
print("[render] structure + caveats OK")
PY

echo "[render] hostile source name is escaped, not injected"
cat > "$T/evil.json" <<'JSON'
{"report":"repo-health-m01","source":"<script>alert(1)</script>&\"","source_kind":"local","metrics":[{"key":"history.commit_count","version":"1.0.0","status":"observed","value":3,"evidence":["evidence/git-log.bin"]}],"capabilities":{"git_log":"observed"},"timeline":[{"at":1700000000,"label":"release <one>","status":"observed"}],"neighborhood":[{"id":"pkg<&","kind":"project","depth":1,"scope":"public"}]}
JSON
"$ROOT/build/rh_cli" render --report "$T/evil.json" --out "$T/evil.html" >/dev/null || fail "evil render"
python3 - "$T/evil.html" <<'PY'
import sys
h = open(sys.argv[1], encoding="utf-8").read()
assert "<script>alert" not in h, "raw script tag leaked"
assert "&lt;script&gt;alert(1)&lt;/script&gt;" in h, "script not escaped"
assert "&amp;" in h and "&quot;" in h, "amp/quote not escaped"
assert "history.commit_count" in h, h
assert "<h2>Timeline</h2>" in h and "release &lt;one&gt;" in h, "timeline table missing or unescaped"
assert "<h2>Graph neighborhood</h2>" in h and "pkg&lt;&amp;" in h, "neighborhood table missing or unescaped"
print("[render] escaping OK")
PY

echo "[render] continuity artifacts appear as accessible tables"
cat > "$T/rep/continuity.json" <<'JSON'
{"schema":"rh-continuity/1","window":{"first_month_index":651,"months":12},"coverage":{"basis":"full","activity_change_claims_supported":true},"first_observation_basis":"first-ever","actors_total":4,"persistent":2,"event_totals":{"commits":12,"releases":3,"reviews":1},"identity_revision":7}
JSON
cat > "$T/rep/continuity-metrics.json" <<'JSON'
{"schema":"rh-continuity-metrics/1","metrics":[{"key":"persistence.retained_90d","version":"1.0.0","status":"observed","value":{"num":1,"den":3}},{"key":"concentration.change_hhi","version":"1.0.0","status":"unknown","reason":"windowed"}]}
JSON
"$ROOT/tools/render-project.sh" "$T/rep" "$T/rep/project.html" >/dev/null || fail "continuity render"
python3 - "$T/rep/project.html" <<'PY'
import sys
h = open(sys.argv[1], encoding="utf-8").read()
assert "<h2>Continuity</h2>" in h and "coverage basis" in h, h
assert "first-ever" in h and "651" in h and "4" in h, h
assert "<h3>Continuity metrics</h3>" in h and "persistence.retained_90d" in h and "1/3" in h, h
assert "unknown" in h and 'scope="row"' in h, h
print("[render] continuity tables OK")
PY

echo "[render] determinism + fail-closed negatives"
"$ROOT/build/rh_cli" render --report "$T/rep/report.json" --out "$T/rep/page2.html" >/dev/null || fail "rerun"
cmp -s "$T/rep/page.html" "$T/rep/page2.html" || fail "render not deterministic"
set +e
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" render --report "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
printf '{"source":"x"}' > "$T/nometrics.json"
"$ROOT/build/rh_cli" render --report "$T/nometrics.json" --out "$T/x" >/dev/null 2>&1; rc_nom=$?
"$ROOT/build/rh_cli" render --report "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
[[ "$rc_json" -eq 4 ]] || fail "invalid JSON must exit 4 (got $rc_json)"
[[ "$rc_nom" -eq 4 ]] || fail "report without metrics must exit 4 (got $rc_nom)"
[[ "$rc_missing" -eq 4 ]] || fail "missing report must exit 4 (got $rc_missing)"

echo "test_render_cli OK"
