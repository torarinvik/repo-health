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
python3 - "$T/in.json" "$T/out.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[2]))
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
raw = open(sys.argv[1], "rb").read()
normalized = open(sys.argv[2], "rb").read()
sidecar = json.load(open(sys.argv[2] + ".transformations.json"))
configuration = b"repo-health/event-aggregate/2;daily=86400;weekly=604800;timezone=utc_epoch;corrections=invalidation-only;roles=distinct-actors"
assert sidecar["schema"] == "rh-adapter-transformation-report/1", sidecar
assert sidecar["adapter"] == "validated-event-aggregate" and sidecar["output_schema"] == d["schema"], sidecar
assert sidecar["source_input_sha256"] == hashlib.sha256(raw).hexdigest(), sidecar
assert sidecar["normalized_output_sha256"] == hashlib.sha256(normalized).hexdigest(), sidecar
assert sidecar["configuration_sha256"] == hashlib.sha256(configuration).hexdigest(), sidecar
assert [field["state"] for field in sidecar["fields"]] == ["transformed", "transformed", "discarded", "unsupported"], sidecar
print("[aggregate] daily/weekly counts + correction invalidation OK")
print("[aggregate] transformation report binds exact event input, output, and bucket rules")
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
            for _, row in sorted(rows.items())]
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
python3 - "$T/oracle-in.json" "$T/oracle-permuted.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["events"].reverse()
json.dump(data, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" aggregate --input "$T/oracle-permuted.json" --out "$T/oracle-permuted-out.json" >/dev/null || fail "permuted aggregate oracle run"
cmp -s "$T/oracle-out.json" "$T/oracle-permuted-out.json" || fail "event order changed canonical aggregate output"
echo "[aggregate] event permutation preserves canonical bucket and role order"

echo "[aggregate] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "aggregate output not deterministic"
set +e
sed 's/"action":"replace"/"action":"unknown"/' "$T/in.json" > "$T/bad-action.json"
"$ROOT/build/rh_cli" aggregate --input "$T/bad-action.json" --out "$T/x" >/dev/null 2>&1; rc_action=$?
sed 's/"id":"e1"/"id":"missing"/' "$T/in.json" > "$T/bad-id.json"
"$ROOT/build/rh_cli" aggregate --input "$T/bad-id.json" --out "$T/x" >/dev/null 2>&1; rc_id=$?
python3 - "$T/in.json" "$T/duplicate-id.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["events"].append(dict(data["events"][0]))
json.dump(data, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" aggregate --input "$T/duplicate-id.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate_id=$?
printf '{"schema":"rh-aggregate-input/1","events":[{"id":"e1","actor":"a","kind":"commit","role":"author","at":-1}]}' > "$T/bad-time.json"
"$ROOT/build/rh_cli" aggregate --input "$T/bad-time.json" --out "$T/x" >/dev/null 2>&1; rc_time=$?
set -e
[[ "$rc_action" -eq 4 && "$rc_id" -eq 4 && "$rc_duplicate_id" -eq 4 && "$rc_time" -eq 4 ]] || fail "invalid aggregate must exit 4 (got $rc_action/$rc_id/$rc_duplicate_id/$rc_time)"

echo "[aggregate] durable exact-snapshot cache reuses a verified projection"
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/state-first.json" --state-store "$T/state-store" > "$T/state-first.out" || fail "cache first projection"
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/state-second.json" --state-store "$T/state-store" > "$T/state-second.out" || fail "cache replay projection"
cmp -s "$T/state-first.json" "$T/state-second.json" || fail "cached projection differs"
cmp -s "$T/state-first.json.transformations.json" "$T/state-second.json.transformations.json" || fail "cached transformation report differs"
grep -q 'cache=miss' "$T/state-first.out" || fail "first state-store run should compute"
grep -q 'cache=hit' "$T/state-second.out" || fail "identical state-store run should reuse"
python3 - "$T/in.json" "$T/in-permuted.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["events"].reverse()
json.dump(data, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" aggregate --input "$T/in-permuted.json" --out "$T/state-permuted.json" --state-store "$T/state-store" > "$T/state-permuted.out" || fail "permuted partition cache projection"
grep -q 'partition-reuse=4' "$T/state-permuted.out" || fail "event-ID ordered fingerprints should reuse all four partitions after input reordering"
cmp -s "$T/state-first.json" "$T/state-permuted.json" || fail "permuted partition cache result differs"
python3 - "$T/in.json" "$T/changed.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["events"][0]["actor"] = "corrected-actor"
d["events"][0]["at"] += 86400
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" aggregate --input "$T/changed.json" --out "$T/state-changed.json" --state-store "$T/state-store" > "$T/state-changed.out" || fail "changed state-store projection"
grep -q 'cache=miss' "$T/state-changed.out" || fail "changed snapshot must invalidate cached projection"
grep -q 'partition-reuse=2' "$T/state-changed.out" || fail "changed snapshot should reuse its two unaffected partitions"
"$ROOT/build/rh_cli" aggregate --input "$T/changed.json" --out "$T/changed-fresh.json" >/dev/null || fail "changed full recomputation"
cmp -s "$T/changed-fresh.json" "$T/state-changed.json" || fail "cache miss differs from a fresh recomputation"
cmp -s "$T/state-first.json" "$T/state-changed.json" && fail "changed input reused stale projection"
python3 - "$T/changed.json" "$T/corrections-only.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["corrections"] = data["corrections"][:1]
json.dump(data, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" aggregate --input "$T/corrections-only.json" --out "$T/corrections-partial.json" --state-store "$T/state-store" > "$T/corrections-partial.out" || fail "correction-only partial projection"
grep -q 'partition-reuse=5' "$T/corrections-partial.out" || fail "correction-only change should reuse every daily and weekly partition"
"$ROOT/build/rh_cli" aggregate --input "$T/corrections-only.json" --out "$T/corrections-fresh.json" >/dev/null || fail "correction-only full recomputation"
cmp -s "$T/corrections-fresh.json" "$T/corrections-partial.json" || fail "correction-only partial result differs from full recomputation"
python3 - "$T/corrections-partial.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["corrections"]["count"] == 1, result["corrections"]
assert result["corrections"]["invalidated_daily"] == [19676], result["corrections"]
print("[aggregate] correction-only changes reuse all five partitions and refresh invalidation metadata")
PY
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/state-restored.json" --state-store "$T/state-store" > "$T/state-restored.out" || fail "historical snapshot partition restore"
grep -q 'partition-reuse=4' "$T/state-restored.out" || fail "historical snapshot should reuse its retained partitions"
cmp -s "$T/state-first.json" "$T/state-restored.json" || fail "historical partition reuse differs from its original projection"
echo "[aggregate] retained bounded history reuses a prior snapshot after pointer advancement"
printf '%s\n' '{"schema":"rh-aggregate-input/1","events":[{"id":"pipe-event","actor":"a","kind":"commit","role":"role R| marker","at":1700000000}]}' > "$T/pipe-role.json"
"$ROOT/build/rh_cli" aggregate --input "$T/pipe-role.json" --out "$T/pipe-first.json" --state-store "$T/pipe-store" >/dev/null || fail "pipe role cache seed"
"$ROOT/build/rh_cli" aggregate --input "$T/pipe-role.json" --out "$T/pipe-replay.json" --state-store "$T/pipe-store" > "$T/pipe-replay.out" || fail "pipe role cache replay"
cmp -s "$T/pipe-first.json" "$T/pipe-replay.json" || fail "pipe in role key confused cache report record"
grep -q 'cache=hit' "$T/pipe-replay.out" || fail "pipe role exact replay should hit"
python3 - "$T/pipe-role.json" "$T/pipe-role-corrected.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["corrections"] = [{"id":"pipe-event", "action":"retract", "reason":"metadata-only change"}]
json.dump(data, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" aggregate --input "$T/pipe-role-corrected.json" --out "$T/pipe-partial.json" --state-store "$T/pipe-store" > "$T/pipe-partial.out" || fail "pipe role partial reuse"
grep -q 'partition-reuse=2' "$T/pipe-partial.out" || fail "pipe in cached row must not break partition reuse"
"$ROOT/build/rh_cli" aggregate --input "$T/pipe-role-corrected.json" --out "$T/pipe-fresh.json" >/dev/null || fail "pipe role recomputation"
cmp -s "$T/pipe-fresh.json" "$T/pipe-partial.json" || fail "pipe role partial cache differs from full recomputation"
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
mkdir -p "$T/failing-state-store"
ln -s missing-lock-target "$T/failing-state-store/.rh-evidence.lock"
set +e
"$ROOT/build/rh_cli" aggregate --input "$T/in.json" --out "$T/publish-failure-out.json" --state-store "$T/failing-state-store" >/dev/null 2>&1
rc_publish_failure=$?
set -e
[[ "$rc_publish_failure" -eq 4 && ! -e "$T/publish-failure-out.json" ]] || fail "cache publication failure must not replace report output"

echo "test_aggregate_cli OK"
