#!/usr/bin/env bash
# tools/publication-review.sh — S010/R030 publication review (mechanical).
#
# Scans a produced report directory for language that would assert a
# person-level moral/medical/sensitive inference, a universal health/trust
# score, a safety certification, or an unsupported "all metrics available"
# claim. It checks the ACTUAL generated artifacts, not a policy document.
#
# Usage: tools/publication-review.sh <report_dir>
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:-}"

if [[ -z "$DIR" || ! -d "$DIR" ]]; then
  echo "usage: publication-review.sh <report_dir>" >&2
  exit 2
fi

python3 - "$DIR" <<'PY'
import os, re, sys
d = sys.argv[1]
files = []
for base, _, names in os.walk(d):
    for n in names:
        files.append(os.path.join(base, n))
assert files, "no report artifacts to review"

# Prohibited patterns: a report may not contain these. Word-boundary where
# it matters so "unhealthy" in a caveat cannot be confused with a verdict.
prohibited = [
    (r"\bhealth[\s_-]?score\b", "universal health score"),
    (r"\btrust[\s_-]?score\b", "universal trust score"),
    (r"\btrustworthy\b", "trustworthiness verdict"),
    (r"\bis safe\b", "safety verdict"),
    (r"\bunsafe\b(?!\W)", "safety verdict"),
    (r"\bcertified\b", "certification claim"),
    (r"\bmedical\b", "medical inference"),
    (r"\bmoral\b", "moral inference"),
    (r"\bsensitive[\s_-]?attribute", "sensitive-attribute inference"),
    (r"\bmaintainer[\s_-]?(worth|quality|reputation|score)\b", "maintainer worth verdict"),
    (r"all metrics available", "unsupported completeness claim"),
    (r"\bgrade\b\s*:", "letter-grade verdict"),
    (r"\brating\b\s*:", "rating verdict"),
]
allowed_caveat = [
    r"not called maintainers",
    r"not zero",
    r"never a trust",
    r"not a safety",
    r"not a score",
    r"unavailable",
]
violations = []
for p in files:
    try:
        text = open(p, encoding="utf-8", errors="replace").read().lower()
    except OSError:
        continue
    for pat, why in prohibited:
        for m in re.finditer(pat, text):
            # a caveat line that merely names the forbidden thing is fine
            line = text[max(0, text.rfind("\n", 0, m.start())): text.find("\n", m.end())]
            if any(re.search(c, line) for c in allowed_caveat):
                continue
            violations.append((os.path.relpath(p, d), why, m.group(0)))
if violations:
    for v in violations:
        print("PUBLICATION-REVIEW violation:", v)
    raise SystemExit("prohibited inference language in report")
print("publication-review OK: %d files clean" % len(files))
PY

echo "publication-review OK"
