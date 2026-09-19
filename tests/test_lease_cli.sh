#!/usr/bin/env bash
# tests/test_lease_cli.sh — M02-03 job-lease execution path:
# `rh_cli store lease` applies a claim/heartbeat/release/status sequence to a
# real filesystem lease and enforces fencing: a live lease is held, an
# expired one is reclaimable, a terminal phase refuses further claims, and a
# stale worker (wrong token) cannot heartbeat or release. Malformed input
# fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-lease"

fail() { echo "[lease] FAIL: $1" >&2; exit 1; }

echo "[lease] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/a.json" <<'JSON'
{"schema":"rh-store-lease-input/1","owner":"worker-1","ops":[{"op":"claim","now":1000,"ttl":100},{"op":"claim","now":1050,"ttl":100},{"op":"heartbeat","now":1050},{"op":"release","now":1100,"phase":"succeeded"},{"op":"claim","now":1200,"ttl":100},{"op":"heartbeat","now":1300}]}
JSON
"$ROOT/build/rh_cli" store lease --root "$T" --job jobA --input "$T/a.json" --out "$T/a.out" >/dev/null || fail "A run"
[[ -f "$T/leases/jobA.lease" && -f "$T/leases/jobA.log" ]] || fail "lease/log not written"
python3 - "$T/a.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
o = d["ops"]
assert d["schema"] == "rh-store-lease-result/1", d
assert o[0] == {"op": "claim", "outcome": "claimed", "token": 1, "phase": "leased"}, o[0]
assert o[1] == {"op": "claim", "outcome": "held"}, o[1]           # live lease held
assert o[2]["applied"] is True and o[2]["token"] == 1, o[2]
assert o[3]["applied"] is True and o[3]["phase"] == "succeeded", o[3]
assert o[4] == {"op": "claim", "outcome": "terminal"}, o[4]        # terminal refuses
assert o[5]["applied"] is False, o[5]                              # terminal heartbeat refused
assert d["final"]["phase"] == "succeeded", d["final"]
print("[lease] claim/held/release/terminal OK")
PY

echo "[lease] an expired lease is reclaimable"
cat > "$T/b.json" <<'JSON'
{"schema":"rh-store-lease-input/1","owner":"worker-1","ops":[{"op":"claim","now":1000,"ttl":100},{"op":"claim","now":1200,"ttl":100},{"op":"status","now":1200}]}
JSON
"$ROOT/build/rh_cli" store lease --root "$T" --job jobB --input "$T/b.json" --out "$T/b.out" >/dev/null || fail "B run"
python3 - "$T/b.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
o = d["ops"]
assert o[0]["token"] == 1 and o[1]["token"] == 2, o            # reclaimed with a new token
assert o[2]["op"] == "status" and o[2]["token"] == 2 and o[2]["phase"] == "leased", o[2]
print("[lease] expiry reclaim OK")
PY

echo "[lease] a stale worker (no current token) cannot heartbeat or release"
cat > "$T/c.json" <<'JSON'
{"schema":"rh-store-lease-input/1","owner":"worker-2","ops":[{"op":"heartbeat","now":1300},{"op":"release","now":1300,"phase":"succeeded"}]}
JSON
"$ROOT/build/rh_cli" store lease --root "$T" --job jobB --input "$T/c.json" --out "$T/c.out" >/dev/null || fail "C run"
python3 - "$T/c.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["ops"][0]["applied"] is False, d["ops"][0]
assert d["ops"][1]["applied"] is False, d["ops"][1]
print("[lease] stale-worker fencing OK")
PY

echo "[lease] determinism + fail-closed negatives"
"$ROOT/build/rh_cli" store lease --root "$T/det1" --job jobA --input "$T/a.json" --out "$T/det1.out" >/dev/null || fail "det1"
"$ROOT/build/rh_cli" store lease --root "$T/det2" --job jobA --input "$T/a.json" --out "$T/det2.out" >/dev/null || fail "det2"
cmp -s "$T/det1.out" "$T/det2.out" || fail "lease output not deterministic on a fresh store"
set +e
printf '{"schema":"rh-store-lease-input/2","owner":"x","ops":[]}' > "$T/bs.json"
"$ROOT/build/rh_cli" store lease --root "$T" --job j --input "$T/bs.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-store-lease-input/1","owner":"x","ops":[{"op":"release","now":1,"phase":"goodbye"}]}' > "$T/bp.json"
"$ROOT/build/rh_cli" store lease --root "$T" --job j --input "$T/bp.json" --out "$T/x" >/dev/null 2>&1; rc_phase=$?
printf '{"schema":"rh-store-lease-input/1","owner":"x","ops":42}' > "$T/bo.json"
"$ROOT/build/rh_cli" store lease --root "$T" --job j --input "$T/bo.json" --out "$T/x" >/dev/null 2>&1; rc_ops=$?
"$ROOT/build/rh_cli" store lease --root "$T" --job j --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_phase" "$rc_ops" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed lease input must exit 4 (got $rc)"
done

echo "test_lease_cli OK"
