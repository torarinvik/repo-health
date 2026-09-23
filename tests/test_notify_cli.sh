#!/usr/bin/env bash
# tests/test_notify_cli.sh — M06-08 notification execution path:
# `rh_cli notify` applies authorization, dedup/cooldown, outage suppression,
# and ack/resolve to an rh-notify-input/2 event stream, writing
# rh-notify-result/2. The non-negotiable rule: an upstream maintainer is
# refused unless explicitly subscribed, and a refusal records nothing (so it
# cannot start a phantom cooldown).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-notify"

fail() { echo "[notify] FAIL: $1" >&2; exit 1; }

echo "[notify] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-notify-input/2","cooldown_secs":3600,"events":[
{"op":"notify","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa","target":"subscriber","authorized":true,"now":1000},
{"op":"notify","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa","target":"upstream_maintainer","subscribed":false,"now":1000},
{"op":"notify","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa","target":"subscriber","authorized":true,"now":2000},
{"op":"notify","rule_id":1,"subject_id":7,"artifact_digest":"bbbbbbbbbbbbbbbb","target":"subscriber","authorized":true,"now":2000},
{"op":"notify","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa","target":"subscriber","authorized":true,"now":9000},
{"op":"notify","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa","target":"subscriber","authorized":true,"now":9500,"outage":true},
{"op":"ack","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa"},
{"op":"notify","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa","target":"subscriber","authorized":true,"now":99999},
{"op":"resolve","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa"},
{"op":"notify","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa","target":"subscriber","authorized":true,"now":999999}
]}
JSON
"$ROOT/build/rh_cli" notify --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "notify run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-notify-result/2", d
seq = [(x["op"], x.get("decision") or x.get("applied")) for x in d["decisions"]]
assert seq[0] == ("notify", "new")
assert seq[1] == ("notify", "suppressed_unauthorized")
assert seq[2] == ("notify", "suppressed_cooldown")
assert seq[3] == ("notify", "new")          # changed digest -> new key
assert seq[4] == ("notify", "new")          # after cooldown for aaaa
assert seq[5] == ("notify", "suppressed_outage")
assert seq[6] == ("ack", True)
assert seq[7] == ("notify", "suppressed_acknowledged")
assert seq[8] == ("resolve", True)
assert seq[9] == ("notify", "suppressed_resolved")
c = d["counts"]
assert c == {"new": 3, "suppressed_unauthorized": 1, "suppressed_outage": 1,
             "suppressed_resolved": 1, "suppressed_acknowledged": 1,
             "suppressed_cooldown": 1}, c
assert d["decisions"][0]["delivered"] is True and d["decisions"][1]["delivered"] is False, d
assert "refused unless explicitly subscribed" in d["note"], d["note"]
print("[notify] policy scenario OK")
PY

echo "[notify] a refused upstream send records nothing (no phantom cooldown)"
cat > "$T/phantom.json" <<'JSON'
{"schema":"rh-notify-input/2","cooldown_secs":3600,"events":[
{"op":"notify","rule_id":2,"subject_id":9,"artifact_digest":"cccccccccccccccc","target":"upstream_maintainer","subscribed":false,"now":1000},
{"op":"notify","rule_id":2,"subject_id":9,"artifact_digest":"cccccccccccccccc","target":"subscriber","authorized":true,"now":1001}
]}
JSON
"$ROOT/build/rh_cli" notify --input "$T/phantom.json" --out "$T/phantom.out" >/dev/null || fail "phantom run"
python3 - "$T/phantom.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert [x["decision"] for x in d["decisions"]] == ["suppressed_unauthorized", "new"], d["decisions"]
print("[notify] no-phantom-cooldown OK")
PY

echo "[notify] subscriber authorization is required explicitly"
cat > "$T/missing-authorization.json" <<'JSON'
{"schema":"rh-notify-input/2","events":[{"op":"notify","rule_id":11,"subject_id":9,"artifact_digest":"cccccccccccccccc","target":"subscriber","now":1000}]}
JSON
"$ROOT/build/rh_cli" notify --input "$T/missing-authorization.json" --out "$T/missing-authorization.out" --state "$T/missing-authorization.state" >/dev/null || fail "missing authorization run"
python3 - "$T/missing-authorization.out" "$T/missing-authorization.state" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["decisions"][0]["decision"] == "suppressed_unauthorized", d
assert d["decisions"][0]["delivered"] is False, d
assert json.load(open(sys.argv[2]))["rows"] == [], "unauthorized subscriber must not start a phantom cooldown"
print("[notify] missing subscriber authorization denied without recording state")
PY

echo "[notify] an explicitly subscribed upstream destination is allowed"
cat > "$T/sub.json" <<'JSON'
{"schema":"rh-notify-input/2","cooldown_secs":0,"events":[
{"op":"notify","rule_id":3,"subject_id":1,"artifact_digest":"1111111111111111","target":"upstream_maintainer","subscribed":true,"now":10}
]}
JSON
"$ROOT/build/rh_cli" notify --input "$T/sub.json" --out "$T/sub.out" >/dev/null || fail "subscribed run"
python3 - "$T/sub.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["decisions"][0]["decision"] == "new" and d["decisions"][0]["delivered"] is True, d
print("[notify] subscribed-upstream OK")
PY

echo "[notify] ack on an unknown key is not applied"
cat > "$T/ack.json" <<'JSON'
{"schema":"rh-notify-input/2","events":[{"op":"ack","rule_id":9,"subject_id":9,"artifact_digest":"9999999999999999"}]}
JSON
"$ROOT/build/rh_cli" notify --input "$T/ack.json" --out "$T/ack.out" >/dev/null || fail "ack run"
python3 - "$T/ack.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["decisions"][0]["applied"] is False, d
print("[notify] ack-unknown OK")
PY

echo "[notify] durable state across runs (--state)"
cat > "$T/pn.json" <<'JSON'
{"schema":"rh-notify-input/2","cooldown_secs":3600,"events":[{"op":"notify","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa","target":"subscriber","authorized":true,"now":1000}]}
JSON
cat > "$T/pn2.json" <<'JSON'
{"schema":"rh-notify-input/2","cooldown_secs":3600,"events":[{"op":"notify","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa","target":"subscriber","authorized":true,"now":2000}]}
JSON
printf '{"schema":"rh-notify-input/2","events":[{"op":"ack","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa"}]}' > "$T/pack.json"
printf '{"schema":"rh-notify-input/2","events":[{"op":"resolve","rule_id":1,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa"}]}' > "$T/pres.json"
S="$T/state.json"
"$ROOT/build/rh_cli" notify --input "$T/pn.json" --out "$T/pn1.out" --state "$S" >/dev/null || fail "persist run1"
[[ -f "$S" ]] || fail "state file not written"
grep -q '"schema":"rh-notify-state/1"' "$S" || fail "state schema missing"
"$ROOT/build/rh_cli" notify --input "$T/pn2.json" --out "$T/pn2.out" --state "$S" >/dev/null || fail "persist run2"
"$ROOT/build/rh_cli" notify --input "$T/pack.json" --out "$T/pack.out" --state "$S" >/dev/null || fail "persist ack"
"$ROOT/build/rh_cli" notify --input "$T/pn2.json" --out "$T/pn3.out" --state "$S" >/dev/null || fail "persist run3"
"$ROOT/build/rh_cli" notify --input "$T/pres.json" --out "$T/pres.out" --state "$S" >/dev/null || fail "persist resolve"
"$ROOT/build/rh_cli" notify --input "$T/pn2.json" --out "$T/pn4.out" --state "$S" >/dev/null || fail "persist run4"
python3 - "$T/pn1.out" "$T/pn2.out" "$T/pn3.out" "$T/pn4.out" "$S" <<'PY'
import json, sys
r1, r2, r3, r4 = (json.load(open(p))["decisions"][0] for p in sys.argv[1:5])
assert r1["decision"] == "new", r1
assert r2["decision"] == "suppressed_cooldown", r2
assert r3["decision"] == "suppressed_acknowledged", r3
assert r4["decision"] == "suppressed_resolved", r4
state = json.load(open(sys.argv[5]))
assert state["schema"] == "rh-notify-state/1", state
assert len(state["rows"]) == 1 and state["rows"][0]["subject_id"] == 7, state
print("[notify] durable state OK")
PY

echo "[notify] content-addressed --state-store survives restart"
NS="$T/notify-store"
"$ROOT/build/rh_cli" notify --input "$T/pn.json" --out "$T/ns1.out" --state-store "$NS" >/dev/null || fail "state-store run1"
"$ROOT/build/rh_cli" notify --input "$T/pn2.json" --out "$T/ns2.out" --state-store "$NS" >/dev/null || fail "state-store run2"
python3 - "$T/ns1.out" "$T/ns2.out" <<'PY'
import json, sys
r1 = json.load(open(sys.argv[1]))["decisions"][0]
r2 = json.load(open(sys.argv[2]))["decisions"][0]
assert r1["decision"] == "new", r1
assert r2["decision"] == "suppressed_cooldown", r2
print("[notify] state-store OK")
PY
ns_id="$(tr -d '\n' < "$NS/current")"
"$ROOT/build/rh_cli" store verify --root "$NS" --name "$ns_id" >/dev/null || fail "notify state-store blob verification"
printf 'not-a-digest\n' > "$NS/current"
set +e
"$ROOT/build/rh_cli" notify --input "$T/pn.json" --out "$T/ns-bad.out" --state-store "$NS" >/dev/null 2>&1
rc_store=$?
set -e
[[ "$rc_store" -eq 4 ]] || fail "corrupt state-store pointer must exit 4 (got $rc_store)"

echo "[notify] determinism"
"$ROOT/build/rh_cli" notify --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "notify output not deterministic"

echo "[notify] malformed inputs fail closed"
set +e
"$ROOT/build/rh_cli" notify --input "$T/sub.json" --out "$T/x" >/dev/null 2>&1; rc_ok=$?
printf '{"schema":"rh-notify-input/3","events":[]}' > "$T/badschema.json"
"$ROOT/build/rh_cli" notify --input "$T/badschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-notify-input/1","events":[]}' > "$T/legacy-schema.json"
"$ROOT/build/rh_cli" notify --input "$T/legacy-schema.json" --out "$T/x" >/dev/null 2>&1; rc_legacy=$?
printf '{"schema":"rh-notify-input/2","events":[{"op":"notify","rule_id":1,"subject_id":1,"artifact_digest":"1111111111111111","target":"stranger","now":1}]}' > "$T/badtarget.json"
"$ROOT/build/rh_cli" notify --input "$T/badtarget.json" --out "$T/x" >/dev/null 2>&1; rc_target=$?
printf '{"schema":"rh-notify-input/2","events":[{"op":"notify","rule_id":1,"subject_id":1,"artifact_digest":"zz","target":"subscriber","now":1}]}' > "$T/baddigest.json"
"$ROOT/build/rh_cli" notify --input "$T/baddigest.json" --out "$T/x" >/dev/null 2>&1; rc_digest=$?
printf '{"schema":"rh-notify-input/2","events":[{"op":"shout","rule_id":1,"subject_id":1,"artifact_digest":"1111111111111111"}]}' > "$T/badop.json"
"$ROOT/build/rh_cli" notify --input "$T/badop.json" --out "$T/x" >/dev/null 2>&1; rc_op=$?
"$ROOT/build/rh_cli" notify --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
printf 'not a state' > "$T/badstate.json"
"$ROOT/build/rh_cli" notify --input "$T/pn.json" --out "$T/x" --state "$T/badstate.json" >/dev/null 2>&1; rc_state=$?
set -e
[[ "$rc_ok" -eq 0 ]] || fail "valid input must exit 0 (got $rc_ok)"
[[ "$rc_state" -eq 4 ]] || fail "corrupt state file must exit 4 (got $rc_state)"
for rc in "$rc_schema" "$rc_legacy" "$rc_target" "$rc_digest" "$rc_op" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed notify input must exit 4 (got $rc)"
done

echo "test_notify_cli OK"
