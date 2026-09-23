#!/usr/bin/env bash
# tests/test_findings_cli.sh — M06-09 structured external findings adapter.
# Assessment time, origin identity, typed outcomes and delivery paths remain
# explicit; malformed or untyped findings never become a policy verdict.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-findings"

fail() { echo "[findings] FAIL: $1" >&2; exit 1; }

echo "[findings] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/packages/scorecard-findings.json" "$T/in.json"

echo "[findings] preserve assessment and typed findings"
"$ROOT/build/rh_cli" findings --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "findings run"
python3 - "$T/out.json" "$T/in.json" "$T/out.json.transformations.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
source = open(sys.argv[2], "rb").read()
transformation = json.load(open(sys.argv[3]))
assert d["schema"] == "rh-findings-result/1", d
assert d["assessment"] == {"id": "scorecard:repo@abc123:1700000000", "tool": "OpenSSF Scorecard", "tool_version": "5.0.0", "subject_revision": "abc123", "assessed_at": 1700000000}, d["assessment"]
assert d["delivery_paths"] == ["api", "artifact"], d
assert d["summary"] == {"total": 2, "pass": 1, "fail": 0, "unknown": 1, "omitted": 0, "inconclusive": 0, "error": 0}, d["summary"]
assert d["findings"][0] == {"check": "Pinned-Dependencies", "probe": "manifest-lock-match", "probe_version": "2", "outcome": "pass", "polarity": "positive", "locations": ["package-lock.json:1"], "remediation": "keep lockfile synchronized"}, d["findings"][0]
assert d["findings"][1]["outcome"] == "unknown" and d["findings"][1]["remediation"] is None, d["findings"][1]
assert "delivery paths do not refresh age" in d["note"], d["note"]
assert transformation["schema"] == "rh-adapter-transformation-report/1", transformation
assert transformation["adapter"] == "scorecard-findings", transformation
assert transformation["source_input_sha256"] == hashlib.sha256(source).hexdigest(), transformation
assert transformation["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), transformation
assert transformation["configuration_sha256"] == hashlib.sha256(b"repo-health/scorecard-findings/1").hexdigest(), transformation
assert {field["state"] for field in transformation["fields"]} == {"preserved", "transformed", "discarded", "unsupported"}, transformation
print("[findings] origin + typed outcomes OK")
PY

echo "[findings] determinism"
"$ROOT/build/rh_cli" findings --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "findings output not deterministic"

echo "[findings] malformed and untyped outcomes fail closed"
set +e
printf '{"schema":"rh-scorecard-findings-input/1","assessment_id":"a","tool":"t","tool_version":"1","subject_revision":"r","assessed_at":1,"findings":[]}' > "$T/empty-delivery.json"
"$ROOT/build/rh_cli" findings --input "$T/empty-delivery.json" --out "$T/empty.out" >/dev/null 2>&1; rc_empty=$?
printf '{"schema":"rh-scorecard-findings-input/1","assessment_id":"a","tool":"t","tool_version":"1","subject_revision":"r","assessed_at":1,"findings":[{"check":"x","probe":"p","outcome":"maybe","polarity":"positive","locations":[]}]}' > "$T/bad-outcome.json"
"$ROOT/build/rh_cli" findings --input "$T/bad-outcome.json" --out "$T/bad.out" >/dev/null 2>&1; rc_outcome=$?
printf '{"schema":"rh-scorecard-findings-input/2"}' > "$T/bad-schema.json"
"$ROOT/build/rh_cli" findings --input "$T/bad-schema.json" --out "$T/schema.out" >/dev/null 2>&1; rc_schema=$?
set -e
[[ "$rc_empty" -eq 0 ]] || fail "empty findings assessment should be valid (got $rc_empty)"
[[ "$rc_outcome" -eq 4 && "$rc_schema" -eq 4 ]] || fail "invalid findings input must exit 4 (got $rc_outcome/$rc_schema)"
[[ ! -f "$T/bad.out" && ! -f "$T/schema.out" ]] || fail "partial findings published"

echo "test_findings_cli OK"
