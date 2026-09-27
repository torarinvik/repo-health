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

python3 - "$T/oracle-in.json" "$T/oracle-expected.json" <<'PY'
import json, random, sys
rng = random.Random(731)
events = [
    {"id": f"event-{i:04}", "actor": f"actor-{rng.randrange(37):02}",
     "kind": ("commit", "review", "release")[rng.randrange(3)],
     "role": ("author", "reviewer", "maintainer", "releaser")[rng.randrange(4)],
     "at": 1_700_000_000 + rng.randrange(0, 2_000_000)}
    for i in range(240)
]
corrections = [
    {"id": event["id"], "action": "replace" if i % 2 == 0 else "retract",
     "reason": "partition oracle correction"}
    for i, event in enumerate(events[::7])
]
def aggregate(seconds):
    rows = {}
    for event in events:
        bucket = event["at"] // seconds
        row = rows.setdefault(bucket, {"bucket": bucket, "event_count": 0,
                                       "actors": set(), "role_counts": {}})
        row["event_count"] += 1
        row["actors"].add(event["actor"])
        row["role_counts"][event["role"]] = row["role_counts"].get(event["role"], 0) + 1
    return [{"bucket": row["bucket"], "event_count": row["event_count"],
             "distinct_actor_count": len(row["actors"]), "role_counts": row["role_counts"]}
            for row in rows.values()]
def invalidated(seconds):
    result = []
    by_id = {event["id"]: event for event in events}
    for correction in corrections:
        bucket = by_id[correction["id"]]["at"] // seconds
        if bucket not in result:
            result.append(bucket)
    return result
with open(sys.argv[1], "w") as stream:
    json.dump({"schema": "rh-aggregate-input/1", "events": events,
               "corrections": corrections}, stream, separators=(",", ":"))
with open(sys.argv[2], "w") as stream:
    json.dump({"daily": aggregate(86400), "weekly": aggregate(604800),
               "corrections": {"count": len(corrections),
                               "invalidated_daily": invalidated(86400),
                               "invalidated_weekly": invalidated(604800)}},
              stream, separators=(",", ":"))
PY
"$ROOT/build/rh_cli" aggregate --input "$T/oracle-in.json" --out "$T/oracle-out.json" >/dev/null || fail "aggregate oracle run"
python3 - "$T/oracle-out.json" "$T/oracle-expected.json" <<'PY'
import json, sys
actual, expected = [json.load(open(path)) for path in sys.argv[1:]]
for key in ("daily", "weekly", "corrections"):
    assert actual[key] == expected[key], (key, actual[key], expected[key])
assert actual["validation"]["full_recompute_equivalent"] is True, actual
print("[aggregate] seeded 240-event daily/weekly/role oracle matches full recomputation")
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

echo "[aggregate] durable exact-snapshot cache reuses a verified projection"
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/state-first.json" --state-store "$T/state-store" > "$T/state-first.out" || fail "cache first projection"
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/state-second.json" --state-store "$T/state-store" > "$T/state-second.out" || fail "cache replay projection"
cmp -s "$T/state-first.json" "$T/state-second.json" || fail "cached projection differs"
grep -q 'cache=miss' "$T/state-first.out" || fail "first state-store run should compute"
grep -q 'cache=hit' "$T/state-second.out" || fail "identical state-store run should reuse"
python3 - "$T/in.json" "$T/changed.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["events"][0]["actor"] = "corrected-actor"
d["events"][0]["at"] += 86400
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" aggregate --input "$T/changed.json" --out "$T/state-changed.json" --state-store "$T/state-store" > "$T/state-changed.out" || fail "changed state-store projection"
grep -q 'cache=miss' "$T/state-changed.out" || fail "changed snapshot must invalidate cached projection"
"$ROOT/build/rh_cli" aggregate --input "$T/changed.json" --out "$T/changed-fresh.json" >/dev/null || fail "changed full recomputation"
cmp -s "$T/changed-fresh.json" "$T/state-changed.json" || fail "cache miss differs from a fresh recomputation"
cmp -s "$T/state-first.json" "$T/state-changed.json" && fail "changed input reused stale projection"
set +e
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/state-store/current" --state-store "$T/state-store" >/dev/null 2>&1
rc_output_collision=$?
set -e
[[ "$rc_output_collision" -eq 3 ]] || fail "output must not replace state-store pointer"
printf 'not-a-digest\n' > "$T/state-store/current"
set +e
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/corrupt-state-out.json" --state-store "$T/state-store" >/dev/null 2>&1
rc_corrupt_state=$?
set -e
[[ "$rc_corrupt_state" -eq 4 && ! -e "$T/corrupt-state-out.json" ]] || fail "corrupt cache pointer must fail closed before output"

echo "test_aggregate_cli OK"
