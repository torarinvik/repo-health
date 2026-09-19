#!/usr/bin/env bash
# tests/test_role_grain_cli.sh — RP-05 event grain and correction fan-out.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-role-grain"

fail() { echo "[role-grain] FAIL: $1" >&2; exit 1; }

echo "[role-grain] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-role-grain-input/1","identity_revision":3,"as_known_revision":2,"events":[{"id":"e1","actor":"alice","role":"author","at":1},{"id":"e2","actor":"bob","role":"reviewer","at":2},{"id":"e3","actor":"alice","role":"releaser","at":3},{"id":"e4","actor":"carol","role":"reviewer","at":4}],"corrections":[{"event_id":"e2","action":"replace","actor":"alice","revision":3},{"event_id":"e3","action":"retract","revision":3}]}
JSON
"$ROOT/build/rh_cli" role-grain --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "role-grain run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-role-grain-result/1", d
assert d["event_grain"] == "one_event_one_role", d
known = {r["role"]: r for r in d["as_known"]["roles"]}
current = {r["role"]: r for r in d["current_corrected"]["roles"]}
assert d["as_known"]["event_count"] == 4, d
assert known["reviewer"]["events"] == 2 and known["reviewer"]["distinct_actors"] == 2, d
assert d["current_corrected"]["event_count"] == 3, d
assert current["releaser"]["events"] == 0, d
assert d["corrections"] == {"applied": 1, "retracted": 1, "invalidated_event_ids": ["e2", "e3"]}, d
print("[role-grain] one-event grain + as-known/current correction fan-out OK")
PY

echo "[role-grain] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" role-grain --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "role-grain output not deterministic"
set +e
sed 's/"role":"reviewer"/"role":"maintainer"/' "$T/in.json" > "$T/bad-role.json"
"$ROOT/build/rh_cli" role-grain --input "$T/bad-role.json" --out "$T/x" >/dev/null 2>&1; rc_role=$?
sed 's/"event_id":"e3"/"event_id":"missing"/' "$T/in.json" > "$T/bad-event.json"
"$ROOT/build/rh_cli" role-grain --input "$T/bad-event.json" --out "$T/x" >/dev/null 2>&1; rc_event=$?
sed 's/"action":"retract"/"action":"delete"/' "$T/in.json" > "$T/bad-action.json"
"$ROOT/build/rh_cli" role-grain --input "$T/bad-action.json" --out "$T/x" >/dev/null 2>&1; rc_action=$?
set -e
[[ "$rc_role" -eq 4 && "$rc_event" -eq 4 && "$rc_action" -eq 4 ]] || fail "invalid role-grain must exit 4 (got $rc_role/$rc_event/$rc_action)"

echo "test_role_grain_cli OK"
