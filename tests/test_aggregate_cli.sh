#!/usr/bin/env bash
# tests/test_aggregate_cli.sh — M10-02 validated daily/weekly aggregates.
# Distinct actors and role counts are exact; corrections identify only the
# affected UTC epoch partitions and raw event rows remain authoritative.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-aggregate"

fail() { echo "[aggregate] FAIL: $1" >&2; exit 1; }

echo "[aggregate] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-aggregate-input/1","events":[{"id":"e1","actor":"a","kind":"commit","role":"author","at":1700000000},{"id":"e2","actor":"b","kind":"review","role":"reviewer","at":1700000100},{"id":"e3","actor":"a","kind":"release","role":"author","at":1700600000}],"corrections":[{"id":"e1","action":"replace","reason":"actor correction"},{"id":"e3","action":"retract","reason":"duplicate release"}]}
JSON
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "aggregate run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-aggregate-result/1", d
assert d["windowing"] == {"daily_seconds": 86400, "weekly_seconds": 604800, "timezone": "utc_epoch"}, d
assert d["daily"] == [
    {"bucket": 19675, "event_count": 2, "distinct_actor_count": 2, "role_counts": {"author": 1, "reviewer": 1}},
    {"bucket": 19682, "event_count": 1, "distinct_actor_count": 1, "role_counts": {"author": 1}},
], d["daily"]
assert d["weekly"] == [
    {"bucket": 2810, "event_count": 2, "distinct_actor_count": 2, "role_counts": {"author": 1, "reviewer": 1}},
    {"bucket": 2811, "event_count": 1, "distinct_actor_count": 1, "role_counts": {"author": 1}},
], d["weekly"]
assert d["corrections"] == {"count": 2, "invalidated_daily": [19675, 19682], "invalidated_weekly": [2810, 2811]}, d["corrections"]
assert d["validation"]["full_recompute_equivalent"] is True, d
assert "never rewrite raw events" in d["note"], d
print("[aggregate] daily/weekly counts + correction invalidation OK")
PY

echo "[aggregate] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "aggregate output not deterministic"
set +e
sed 's/"action":"replace"/"action":"unknown"/' "$T/in.json" > "$T/bad-action.json"
"$ROOT/build/rh_cli" aggregate --input "$T/bad-action.json" --out "$T/x" >/dev/null 2>&1; rc_action=$?
sed 's/"id":"e1"/"id":"missing"/' "$T/in.json" > "$T/bad-id.json"
"$ROOT/build/rh_cli" aggregate --input "$T/bad-id.json" --out "$T/x" >/dev/null 2>&1; rc_id=$?
printf '{"schema":"rh-aggregate-input/1","events":[{"id":"e1","actor":"a","kind":"commit","role":"author","at":-1}]}' > "$T/bad-time.json"
"$ROOT/build/rh_cli" aggregate --input "$T/bad-time.json" --out "$T/x" >/dev/null 2>&1; rc_time=$?
set -e
[[ "$rc_action" -eq 4 && "$rc_id" -eq 4 && "$rc_time" -eq 4 ]] || fail "invalid aggregate must exit 4 (got $rc_action/$rc_id/$rc_time)"

echo "test_aggregate_cli OK"
