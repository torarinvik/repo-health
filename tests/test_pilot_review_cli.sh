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
cat > "$T/in.json" <<'JSON'
{"schema":"rh-pilot-review-input/1","review_id":"pilot-20260919","reviewer":"qa-1","reviewed_at":1758240000,"scope":"offline-fixture","mapping_review":{"sampled":8,"accepted":6,"needs_review":2},"corrections":{"requested":4,"resolved":3,"median_turnaround_seconds":3600},"decision_usefulness":{"understood":true,"false_positive_count":1,"false_negative_count":0},"provider_outage":{"capability":"reviews","status":"stale_unknown","other_capabilities_usable":true},"costs":{"events":1200,"bytes":64000,"elapsed_ms":850}}
JSON

echo "[pilot-review] review evidence is retained"
"$ROOT/build/rh_cli" pilot-review --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "pilot review run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-pilot-review-result/1", d
assert d["review"] == {"id":"pilot-20260919","reviewer":"qa-1","reviewed_at":1758240000,"scope":"offline-fixture"}, d
assert d["mapping_review"] == {"sampled":8,"accepted":6,"needs_review":2}, d
assert d["corrections"]["resolved"] == 3 and d["corrections"]["median_turnaround_seconds"] == 3600, d
assert d["decision_usefulness"]["understood"] is True, d
assert d["provider_outage"] == {"capability":"reviews","status":"stale_unknown","other_capabilities_usable":True}, d
assert d["costs"] == {"events":1200,"bytes":64000,"elapsed_ms":850}, d
assert "not an independent audit" in d["note"], d
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

echo "test_pilot_review_cli OK"
