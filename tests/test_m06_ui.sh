#!/usr/bin/env bash
# tests/test_m06_ui.sh — M06-03 accessible renderer gate.
# Renders a real report to HTML and asserts: valid parse, semantic tables
# with captions and header cells (keyboard/screen-reader first), unknown
# values shown as status words not 0, and no health/trust verdict.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-m06-ui"

fail() { echo "[ui] FAIL: $1" >&2; exit 1; }

echo "[ui] build + scan"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
rm -rf "$T"; mkdir -p "$T/src"
(
  cd "$T/src" && git init -q -b main . && git config user.name "Dev" && git config user.email "dev@example.com"
  echo x > f && git add f
  GIT_AUTHOR_DATE="2024-03-01T00:00:00Z" GIT_COMMITTER_DATE="2024-03-01T00:00:00Z" git commit -qm one
)
"$ROOT/build/rh_cli" scan --repo "$T/src" --out "$T/rep" --window-days 36500 >/dev/null || fail "scan failed"

echo "[ui] render"
out="$(bash "$ROOT/tools/render-project.sh" "$T/rep")" || fail "$out"
echo "$out"
[[ -f "$T/rep/index.html" ]] || fail "no index.html"

echo "[ui] semantic structure + accessibility"
python3 - "$T/rep/index.html" <<'PY'
import html.parser, re, sys
page = open(sys.argv[1], encoding="utf-8").read()
class P(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(); self.tags = {}
    def handle_starttag(self, tag, attrs):
        self.tags[tag] = self.tags.get(tag, 0) + 1
p = P(); p.feed(page)
for tag, minimum in (("main", 1), ("table", 2), ("caption", 2), ("th", 4)):
    assert p.tags.get(tag, 0) >= minimum, (tag, p.tags.get(tag, 0))
assert 'scope="col"' in page, "col headers need scope"
assert 'scope="row"' in page, "row headers need scope"
assert 'lang="en"' in page, "document language must be declared"
print("[ui] structure OK: tables=%d th=%d" % (p.tags["table"], p.tags["th"]))
PY

echo "[ui] unknown renders as status word, never 0"
# An empty repository genuinely yields an absent (unavailable) metric.
git init -q -b main "$T/empty"
"$ROOT/build/rh_cli" scan --repo "$T/empty" --out "$T/rep-empty" --window-days 90 >/dev/null || fail "empty scan failed"
bash "$ROOT/tools/render-project.sh" "$T/rep-empty" >/dev/null || fail "render empty failed"
python3 - "$T/rep-empty/index.html" <<'PY'
import json, re, sys
page = open(sys.argv[1], encoding="utf-8").read()
report = json.load(open(sys.argv[1].rsplit("/", 1)[0] + "/report.json"))
unknown = [m for m in report["metrics"] if "value" not in m]
assert unknown, "empty repo produced no unknown metric"
for m in unknown:
    key = m["key"]
    row = re.search(r"<tr><th scope=\"row\">%s</th>(.*?)</tr>" % re.escape(key), page)
    assert row, key
    cells = re.findall(r"<td>(.*?)</td>", row.group(1))
    val = cells[1]
    assert val != "0", (key, "unknown rendered as zero")
    assert m.get("reason", m.get("status")) in val or m["status"] in val, (key, val)
print("[ui] unknown-not-zero OK (%d unknown metrics)" % len(unknown))
PY

echo "[ui] no health/trust verdict language"
if grep -qiE "\bis safe\b|trustworthy|health score|trust score" "$T/rep/index.html"; then
  fail "verdict language in rendered page"
fi
echo "[ui] language OK"

echo "test_m06_ui OK"
