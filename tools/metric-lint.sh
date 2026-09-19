#!/usr/bin/env bash
# tools/metric-lint.sh — M00-05 / M09 metric admission lint.
#
# Every definition must carry the base contract fields. Anything not yet
# `implemented` must ALSO carry the M09 admission-template fields (inputs,
# output numerator/denominator for ratios, params, missing_behavior,
# confounders) so a planned metric cannot be a bare name. Ratio outputs
# need an explicit numerator and denominator; no metric is publishable
# without a denominator rule.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import glob, json, os, re, sys
root = sys.argv[1]
STATUS = {"planned", "prototype", "implemented", "validated", "released", "retired"}
COST = {"low", "medium", "high"}
base = ["key", "version", "implementation_status", "owner", "subject_kind",
        "output", "denominator_rule", "source_requirements", "cost_class",
        "privacy_class", "fixture_references"]
admission = ["inputs", "params", "missing_behavior", "confounders"]
seen = {}
files = sorted(glob.glob(os.path.join(root, "metrics", "definitions", "*.json")))
assert files, "no metric definitions"
for p in files:
    d = json.load(open(p))
    for f in base:
        assert f in d and d[f] not in (None, "", [], {}), (p, "missing base field", f)
    assert re.fullmatch(r"\d+\.\d+\.\d+", d["version"]), (p, "bad version", d["version"])
    assert d["implementation_status"] in STATUS, (p, d["implementation_status"])
    assert d["cost_class"] in COST, (p, d["cost_class"])
    assert d.get("status_note"), (p, "missing status_note")
    out = d["output"]
    assert isinstance(out, dict) and out.get("unit"), (p, "output.unit")
    if out["unit"] == "ratio":
        assert out.get("numerator") and out.get("denominator"), (p, "ratio needs numerator+denominator")
    if d["implementation_status"] != "implemented":
        for f in admission:
            assert f in d and d[f] not in (None, "", [], {}), (p, "planned/prototype missing", f)
    # R024: an experimental metric must declare wave, limits, cost, opt-in.
    if d.get("group") == "experimental":
        assert d.get("wave") == "G", (p, "experimental metric must be wave G")
        assert d.get("limits"), (p, "experimental metric needs explicit limits")
        assert d["cost_class"] in ("medium", "high"), (p, "experimental metric must be costed medium/high")
        assert d["implementation_status"] != "implemented", (p, "experimental cannot be published implemented")
        blob = json.dumps(d).lower()
        for bad in ("abandon", "unreliab", "unhealth"):
            assert bad not in blob, (p, "experimental metric must not label:", bad)
    pair = (d["key"], d["version"])
    assert pair not in seen, ("duplicate key/version", pair)
    seen[pair] = d["implementation_status"]

counts = {}
for st in seen.values():
    counts[st] = counts.get(st, 0) + 1
print("metric-lint OK: %d definitions (%s)"
      % (len(seen), ", ".join("%s=%d" % (k, counts[k]) for k in sorted(counts))))
PY

echo "metric-lint OK"
