#!/usr/bin/env bash
# tests/test_pilot_review_cli.sh — RP-08 bounded pilot/operations record.
# It records supplied evidence without claiming an independent audit.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T="/tmp/rh-pilot-review"

fail() { echo "[pilot-review] FAIL: $1" >&2; exit 1; }

echo "[pilot-review] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/pilot-review/input.json" "$T/in.json"

echo "[pilot-review] review evidence is retained"
"$ROOT/build/rh_cli" pilot-review --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "pilot review run"
cmp -s "$ROOT/fixtures/pilot-review/result.json" "$T/out.json" || fail "pilot-review golden changed"
python3 - "$T/in.json" "$T/out.json" "$T/out.json.transformations.json" <<'PY'
import json, sys
import hashlib
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
normalized = Path(sys.argv[2]).read_bytes()
d = json.loads(normalized)
assert d["schema"] == "rh-pilot-review-result/1", d
assert d["review"] == {"id":"pilot-20260919","reviewer":"qa-1","reviewed_at":1758240000,"scope":"offline-fixture"}, d
assert d["mapping_review"] == {"sampled":8,"accepted":6,"needs_review":2}, d
assert d["corrections"]["resolved"] == 3 and d["corrections"]["median_turnaround_seconds"] == 3600, d
assert d["corrections"]["maintainer_effort_seconds"] == 5400, d
assert d["decision_usefulness"] == {"understood":True,"false_positive_count":1,"false_negative_count":0,"reviewed_findings":6,"decision_changed_count":2,"correct_findings_count":5,"actionable_findings_count":4,"unknowns_resolved_by_evidence_count":1}, d
assert d["provider_outage"] == {"capability":"reviews","status":"stale_unknown","other_capabilities_usable":True}, d
assert d["costs"] == {"events":1200,"bytes":64000,"elapsed_ms":850}, d
assert "not an independent audit" in d["note"], d
sidecar = json.load(open(sys.argv[3]))
assert sidecar["schema"] == "rh-adapter-transformation-report/1", sidecar
assert sidecar["adapter"] == "pilot-review-record", sidecar
assert sidecar["output_schema"] == "rh-pilot-review-result/1", sidecar
assert sidecar["source_input_sha256"] == hashlib.sha256(raw).hexdigest(), sidecar
assert sidecar["normalized_output_sha256"] == hashlib.sha256(normalized).hexdigest(), sidecar
assert sidecar["configuration_sha256"] == hashlib.sha256(b"repo-health/pilot-review/2").hexdigest(), sidecar
assert [field["state"] for field in sidecar["fields"]] == ["preserved", "preserved", "transformed"], sidecar
print("[pilot-review] mapping/correction/outage/cost record OK")
PY

echo "[pilot-review] deterministic replay + malformed records fail closed"
"$ROOT/build/rh_cli" pilot-review --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "pilot review rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "pilot review output not deterministic"
set +e
sed 's/"accepted":6/"accepted":9/' "$T/in.json" > "$T/bad-count.json"
"$ROOT/build/rh_cli" pilot-review --input "$T/bad-count.json" --out "$T/x" >/dev/null 2>&1; rc_count=$?
sed 's/"status":"stale_unknown"/"status":"vibes"/' "$T/in.json" > "$T/bad-status.json"
"$ROOT/build/rh_cli" pilot-review --input "$T/bad-status.json" --out "$T/x" >/dev/null 2>&1; rc_status=$?
sed 's/"understood":true/"understood":1/' "$T/in.json" > "$T/bad-bool.json"
"$ROOT/build/rh_cli" pilot-review --input "$T/bad-bool.json" --out "$T/x" >/dev/null 2>&1; rc_bool=$?
set -e
[[ "$rc_count" -eq 4 && "$rc_status" -eq 4 && "$rc_bool" -eq 4 ]] || fail "invalid review must exit 4 (got $rc_count/$rc_status/$rc_bool)"
[[ ! -f "$T/x" ]] || fail "invalid review published"

echo "[pilot-review] legacy inputs preserve unknown new observations"
cp "$ROOT/fixtures/pilot-review/legacy-input.json" "$T/legacy.json"
"$ROOT/build/rh_cli" pilot-review --input "$T/legacy.json" --out "$T/legacy-result.json" >/dev/null || fail "legacy pilot review"
cmp -s "$ROOT/fixtures/pilot-review/legacy-result.json" "$T/legacy-result.json" || fail "legacy pilot review changed"
python3 - "$T/legacy-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["corrections"]["maintainer_effort_seconds"] is None, d
assert all(d["decision_usefulness"][key] is None for key in ("reviewed_findings", "decision_changed_count", "correct_findings_count", "actionable_findings_count", "unknowns_resolved_by_evidence_count")), d
PY
sed 's/"reviewed_findings":6/"reviewed_findings":1/' "$T/in.json" > "$T/bad-denominator.json"
sed 's/,"correct_findings_count":5//' "$T/in.json" > "$T/partial-details.json"
python3 - "$T/in.json" "$T/mapping-overflow.json" <<'PY'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_bytes())
d["mapping_review"] = {"sampled": 9223372036854775807, "accepted": 9223372036854775807, "needs_review": 9223372036854775807}
Path(sys.argv[2]).write_text(json.dumps(d, separators=(",", ":")) + "\n")
PY
set +e
"$ROOT/build/rh_cli" pilot-review --input "$T/bad-denominator.json" --out "$T/x" >/dev/null 2>&1; rc_denominator=$?
"$ROOT/build/rh_cli" pilot-review --input "$T/partial-details.json" --out "$T/x" >/dev/null 2>&1; rc_partial=$?
"$ROOT/build/rh_cli" pilot-review --input "$T/mapping-overflow.json" --out "$T/x" >/dev/null 2>&1; rc_mapping_overflow=$?
set -e
[[ "$rc_denominator" -eq 4 && "$rc_partial" -eq 4 && "$rc_mapping_overflow" -eq 4 ]] || fail "invalid denominators must fail closed (got $rc_denominator/$rc_partial/$rc_mapping_overflow)"

echo "test_pilot_review_cli OK"
