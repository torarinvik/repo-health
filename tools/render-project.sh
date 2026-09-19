#!/usr/bin/env bash
# tools/render-project.sh — M06-03 accessible server-rendered page.
#
# Turns a scan report directory into a single static HTML page whose every
# value is a semantic table row: there is no chart, no color-only encoding,
# and no image. The text/table IS the primary representation, so a keyboard
# or screen-reader user gets the full content. Values that are unknown are
# rendered as the status word, never as 0.
#
# This is a renderer over a produced report, not a live server: the plan
# calls fixture-only UI a "demo", so the page carries the report digest and
# says it is a render of that pinned report.
#
# Usage: tools/render-project.sh <report_dir> [out.html]
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:-}"
OUT="${2:-}"

if [[ -z "$DIR" || ! -d "$DIR" ]]; then
  echo "usage: render-project.sh <report_dir> [out.html]" >&2
  exit 2
fi
[[ -f "$DIR/report.json" ]] || { echo "missing report.json in $DIR" >&2; exit 2; }
[[ -n "$OUT" ]] || OUT="$DIR/index.html"

python3 - "$DIR" "$OUT" <<'PY'
import html, json, os, sys
d, out = sys.argv[1], sys.argv[2]
r = json.load(open(os.path.join(d, "report.json")))

def esc(v):
    return html.escape(str(v))

parts = []
parts.append("<!DOCTYPE html>")
parts.append('<html lang="en"><head><meta charset="utf-8">')
parts.append('<meta name="viewport" content="width=device-width, initial-scale=1">')
parts.append("<title>repo-health report: %s</title>" % esc(r.get("source", "")))
parts.append("</head><body>")
parts.append("<main>")
parts.append("<h1>repo-health report</h1>")
parts.append("<h2>Source</h2>")
parts.append("<dl>")
parts.append("<dt>source</dt><dd><code>%s</code></dd>" % esc(r.get("source", "")))
parts.append("<dt>source kind</dt><dd>%s</dd>" % esc(r.get("source_kind", "")))
parts.append("<dt>evidence cutoff (unix)</dt><dd>%s</dd>" % esc(r.get("evidence_cutoff", "")))
parts.append("<dt>window (days)</dt><dd>%s</dd>" % esc(r.get("window_days", "")))
parts.append("<dt>full history</dt><dd>%s</dd>" % esc(r.get("full_history", "")))
parts.append("<dt>input digest</dt><dd><code>%s</code></dd>" % esc(r.get("input_digest_fnv1a64", "")))
parts.append("</dl>")

# Metrics as a table: the primary, keyboard-navigable representation.
parts.append("<h2>Metrics</h2>")
parts.append("<table>")
parts.append("<caption>Every metric with its status and value. "
             "Metrics with no value show their status word, never zero.</caption>")
parts.append("<thead><tr><th scope=\"col\">metric</th>"
             "<th scope=\"col\">version</th>"
             "<th scope=\"col\">status</th>"
             "<th scope=\"col\">value</th>"
             "<th scope=\"col\">evidence</th></tr></thead>")
parts.append("<tbody>")
for m in r.get("metrics", []):
    key = m.get("key", "")
    if "value" not in m:
        value = "(%s; no value)" % m.get("reason", m.get("status", "unknown"))
    else:
        v = m["value"]
        if isinstance(v, dict) and "num" in v and "den" in v:
            value = "%s/%s" % (v["num"], v["den"])
        elif isinstance(v, dict) and "label" in v:
            value = v["label"]
        else:
            value = v
    ev = ", ".join(m.get("evidence", []))
    parts.append("<tr><th scope=\"row\">%s</th><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>"
                 % (esc(key), esc(m.get("version", "")), esc(m.get("status", "")),
                    esc(value), esc(ev)))
parts.append("</tbody></table>")

parts.append("<h2>Capabilities and limitations</h2>")
parts.append("<table>")
parts.append("<caption>What was collected, and what is explicitly unavailable.</caption>")
parts.append("<thead><tr><th scope=\"col\">capability</th><th scope=\"col\">state</th></tr></thead>")
parts.append("<tbody>")
for k in sorted(r.get("capabilities", {}).keys()):
    parts.append("<tr><th scope=\"row\">%s</th><td>%s</td></tr>" % (esc(k), esc(r["capabilities"][k])))
parts.append("</tbody></table>")

parts.append("<h2>Limitations</h2>")
parts.append("<p>Raw commit authors are not maintainers. Unknown values are not zero. "
             "Review events, permissions, traffic, and downstream projects are not "
             "available from generic Git history.</p>")
parts.append("<p>This page is a render of a pinned report; it is not a live service and "
             "makes no health or trust judgement about any project or person.</p>")
parts.append("</main></body></html>")
page = "\n".join(parts) + "\n"
with open(out, "w", encoding="utf-8") as fh:
    fh.write(page)
print("render-project OK: %s" % out)
PY
