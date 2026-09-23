#!/usr/bin/env bash
# tests/test_coverage_cli.sh — M05 source-specific capability coverage.
# Validity intervals preserve unknown endpoints as null, while capability
# state remains separate from observed activity and project conclusions.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-coverage"

fail() { echo "[coverage] FAIL: $1" >&2; exit 1; }

echo "[coverage] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-coverage-input/1","source":"github","source_instance":"github.com/acme/project","collected_at":1700003700,"capabilities":[{"capability":"review_events","state":"partial","reason":"page cap","valid_start":null,"valid_end":1700000000,"known_as_of":1700000100},{"capability":"maintainer_permissions","state":"unauthorized","reason":"owner authorization required","valid_start":1690000000,"valid_end":null,"known_as_of":1700000100},{"capability":"git_log","state":"observed","reason":"complete public log","valid_start":1690000000,"valid_end":1700000000,"known_as_of":1700000100}]}
JSON
"$ROOT/build/rh_cli" coverage --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "coverage run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-coverage-result/1", d
assert d["source"] == "github" and d["source_instance"] == "github.com/acme/project", d
assert d["state_counts"] == {"observed": 1, "partial": 1, "stale": 0, "unavailable": 0, "unauthorized": 1, "not_applicable": 0, "unsupported": 0}, d
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["coverage.observed_capability_count"]["value"] == 1, metrics
assert metrics["coverage.partial_capability_count"]["value"] == 1, metrics
assert metrics["coverage.stale_capability_count"]["value"] == 0, metrics
assert metrics["coverage.unavailable_capability_count"]["value"] == 0, metrics
assert metrics["coverage.unauthorized_capability_count"]["value"] == 1, metrics
assert metrics["coverage.not_applicable_capability_count"]["value"] == 0, metrics
assert metrics["coverage.unsupported_capability_count"]["value"] == 0, metrics
assert metrics["coverage.requested_capabilities"]["value"] == 3, metrics
assert metrics["coverage.available_capability_share"]["value"] == {"num": 2, "den": 3}, metrics
assert metrics["coverage.unauthorized_capabilities"]["value"] == 1, metrics
assert metrics["coverage.partial_collection_count"]["value"] == 1, metrics
assert metrics["coverage.source_freshness_hours"]["value"] == 1, metrics
assert d["capabilities"][0]["valid_start"] is None, d
assert d["capabilities"][1]["valid_end"] is None, d
assert "source-specific" in d["note"], d
print("[coverage] intervals + source-specific state evidence OK")
PY

echo "[coverage] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" coverage --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "coverage output not deterministic"
set +e
sed 's/"state":"partial"/"state":"unknown"/' "$T/in.json" > "$T/bad-state.json"
"$ROOT/build/rh_cli" coverage --input "$T/bad-state.json" --out "$T/x" >/dev/null 2>&1; rc_state=$?
sed 's/"valid_start":null//' "$T/in.json" > "$T/missing-endpoint.json"
"$ROOT/build/rh_cli" coverage --input "$T/missing-endpoint.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
sed 's/"schema":"rh-coverage-input\/1"/"schema":"rh-coverage-input\/2"/' "$T/in.json" > "$T/bad-schema.json"
"$ROOT/build/rh_cli" coverage --input "$T/bad-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
sed 's/,"collected_at":1700003700//' "$T/in.json" > "$T/missing-collected-at.json"
"$ROOT/build/rh_cli" coverage --input "$T/missing-collected-at.json" --out "$T/x" >/dev/null 2>&1; rc_missing_collected=$?
sed 's/"known_as_of":1700000100/"known_as_of":1700003701/' "$T/in.json" > "$T/future-known-at.json"
"$ROOT/build/rh_cli" coverage --input "$T/future-known-at.json" --out "$T/x" >/dev/null 2>&1; rc_future_known=$?
set -e
[[ "$rc_state" -eq 4 && "$rc_missing" -eq 4 && "$rc_schema" -eq 4 && "$rc_missing_collected" -eq 4 && "$rc_future_known" -eq 4 ]] || fail "invalid coverage must exit 4 (got $rc_state/$rc_missing/$rc_schema/$rc_missing_collected/$rc_future_known)"

printf '%s\n' '{"schema":"rh-coverage-input/1","source":"test","source_instance":"test/zero","collected_at":0,"capabilities":[{"capability":"events","state":"observed","reason":"captured at epoch zero","valid_start":0,"valid_end":null,"known_as_of":0}]}' > "$T/epoch-zero.json"
"$ROOT/build/rh_cli" coverage --input "$T/epoch-zero.json" --out "$T/epoch-zero.out" >/dev/null || fail "epoch zero is a valid instant"
python3 - "$T/epoch-zero.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"][0]["valid_start"] == 0, d
assert d["capabilities"][0]["known_as_of"] == 0, d
print("[coverage] epoch zero remains a valid instant")
PY

echo "test_coverage_cli OK"
