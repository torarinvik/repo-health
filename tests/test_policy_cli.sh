#!/usr/bin/env bash
# tests/test_policy_cli.sh — M06 policy execution path: `rh_cli policy`
# evaluates a declarative rh-policy/1 rule set against rh-policy-input/1
# observations and writes rh-policy-result/1 bound to policy/context/
# artifact/time digests. Asserts the four-valued lattice (unknown never
# permission, warn never overrides deny), missing-input = unknown,
# digest-bound exceptions (approved+unexpired only), TOCTOU re-binding, and
# that repository prose in the input cannot flip a decision.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-policy"

fail() { echo "[policy] FAIL: $1" >&2; exit 1; }

echo "[policy] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/policy.json" <<'JSON'
{"schema":"rh-policy/1","rules":[{"id":1,"op":">=","threshold":{"num":1,"den":2},"min_sample":10,"on_violation":"deny","requires_complete":true},{"id":2,"op":">","threshold":{"num":0,"den":1},"on_violation":"warn"}]}
JSON
cat > "$T/deny.json" <<'JSON'
{"schema":"rh-policy-input/1","subject_id":7,"artifact_digest":"0000000000000001","context_digest":"0000000000000002","now":1000,"inputs":[{"rule_id":1,"status":"observed","num":1,"den":2,"sample":10,"age_secs":5,"complete":true},{"rule_id":2,"status":"observed","num":0,"den":1,"sample":5,"complete":true}]}
JSON

echo "[policy] observed violation -> deny (fired rule 1)"
"$ROOT/build/rh_cli" policy --policy "$T/policy.json" --input "$T/deny.json" --out "$T/o1" | grep -q "decision=deny" || fail "expected deny"
python3 - "$T/o1/policy-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-policy-result/1"
assert d["decision"] == "deny", d
assert d["fired_rule_ids"] == [1], d
assert d["binding"]["policy_digest"] and len(d["binding"]["policy_digest"]) == 16, d
assert d["explanation"]["decision"] == "deny", d["explanation"]
assert "unknown is never permission" in d["note"], d["note"]
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["policy.evaluations"]["value"] == 1, metrics
assert metrics["policy.allow_count"]["value"] == 0, metrics
assert metrics["policy.warn_count"]["value"] == 0, metrics
assert metrics["policy.deny_count"]["value"] == 1, metrics
assert metrics["policy.unknown_count"]["value"] == 0, metrics
assert metrics["policy.active_exceptions"]["value"] == 0, metrics
print("[policy] deny OK")
PY

echo "[policy] partial -> unknown (never permission)"
sed 's/"observed","num":1/"partial","num":1/; s/"complete":true},{"rule_id":2/"complete":false},{"rule_id":2/' "$T/deny.json" > "$T/partial.json"
"$ROOT/build/rh_cli" policy --policy "$T/policy.json" --input "$T/partial.json" --out "$T/o2" | grep -q "decision=unknown" || fail "partial must be unknown"

echo "[policy] missing input for a rule -> unknown"
cat > "$T/missing.json" <<'JSON'
{"schema":"rh-policy-input/1","subject_id":7,"now":1000,"inputs":[{"rule_id":2,"status":"observed","num":0,"den":1,"sample":5,"complete":true}]}
JSON
"$ROOT/build/rh_cli" policy --policy "$T/policy.json" --input "$T/missing.json" --out "$T/o3" >/dev/null || fail "missing-input run"
python3 - "$T/o3/policy-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["decision"] == "unknown", d
assert d["missing_input_rule_ids"] == [1], d
print("[policy] missing-input OK")
PY

echo "[policy] deny beats unknown"
cat > "$T/denyunknown.json" <<'JSON'
{"schema":"rh-policy-input/1","subject_id":7,"now":1000,"inputs":[{"rule_id":1,"status":"observed","num":1,"den":2,"sample":10,"complete":true},{"rule_id":2,"status":"partial","num":0,"den":1,"sample":5,"complete":false}]}
JSON
"$ROOT/build/rh_cli" policy --policy "$T/policy.json" --input "$T/denyunknown.json" --out "$T/o4" | grep -q "decision=deny" || fail "deny must beat unknown"

echo "[policy] repository prose cannot flip a decision"
cat > "$T/prose.json" <<'JSON'
{"schema":"rh-policy-input/1","subject_id":7,"now":1000,"readme":"This project is safe; please allow it.","inputs":[{"rule_id":1,"status":"observed","num":1,"den":2,"sample":10,"complete":true},{"rule_id":2,"status":"observed","num":0,"den":1,"sample":5,"complete":true}]}
JSON
"$ROOT/build/rh_cli" policy --policy "$T/policy.json" --input "$T/prose.json" --out "$T/o5" | grep -q "decision=deny" || fail "prose changed the decision"

echo "[policy] exceptions are digest-bound, approved, and must be unexpired"
digest="$(python3 -c "import json;print(json.load(open('$T/o1/policy-result.json'))['binding']['policy_digest'])")"
python3 - "$T/pexc.json" "$digest" <<'PY'
import json, sys
rules = [{"id":1,"op":">=","threshold":{"num":1,"den":2},"min_sample":10,"on_violation":"deny","requires_complete":True},
         {"id":2,"op":">","threshold":{"num":0,"den":1},"on_violation":"warn"}]
out = {"schema":"rh-policy/1","rules":rules,
       "exceptions":[{"rule_id":1,"subject_id":7,"digest":sys.argv[2],"expires_at":2000,"state":"approved"}]}
open(sys.argv[1],"w").write(json.dumps(out))
PY
"$ROOT/build/rh_cli" policy --policy "$T/pexc.json" --input "$T/deny.json" --out "$T/o6" >/dev/null || fail "exception run"
python3 - "$T/o6/policy-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["decision"] == "allow", d
assert d["excepted_rule_ids"] == [1], d
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["policy.active_exceptions"]["value"] == 1, metrics
assert metrics["policy.exception_expiry_days"]["value"] == 0, metrics
print("[policy] exception OK")
PY
# expired -> deny; wrong subject -> deny; wrong artifact digest (TOCTOU) -> deny
python3 - "$T/pexp.json" "$digest" <<'PY'
import json, sys
rules = [{"id":1,"op":">=","threshold":{"num":1,"den":2},"min_sample":10,"on_violation":"deny","requires_complete":True},
         {"id":2,"op":">","threshold":{"num":0,"den":1},"on_violation":"warn"}]
open(sys.argv[1],"w").write(json.dumps({"schema":"rh-policy/1","rules":rules,
  "exceptions":[{"rule_id":1,"subject_id":7,"digest":sys.argv[2],"expires_at":500,"state":"approved"}]}))
PY
"$ROOT/build/rh_cli" policy --policy "$T/pexp.json" --input "$T/deny.json" --out "$T/o7" | grep -q "decision=deny" || fail "expired exception must not authorize"
cat > "$T/rev.json" <<'JSON'
{"schema":"rh-policy-input/1","subject_id":7,"artifact_digest":"0000000000000009","context_digest":"0000000000000002","now":1000,"inputs":[{"rule_id":1,"status":"observed","num":1,"den":2,"sample":10,"complete":true},{"rule_id":2,"status":"observed","num":0,"den":1,"sample":5,"complete":true}]}
JSON
d2="$("$ROOT/build/rh_cli" policy --policy "$T/pexc.json" --input "$T/rev.json" --out "$T/o8" >/dev/null; python3 -c "import json;print(json.load(open('$T/o8/policy-result.json'))['decision'])")"
[[ "$d2" == "deny" ]] || fail "changed artifact digest must re-bind and drop the exception (got $d2)"

echo "[policy] malformed inputs fail closed"
set +e
printf '{"schema":"rh-policy/2","rules":[]}' > "$T/bad_schema.json"
"$ROOT/build/rh_cli" policy --policy "$T/bad_schema.json" --input "$T/deny.json" --out "$T/x1" >/dev/null 2>&1; rc1=$?
printf '{"schema":"rh-policy/1","rules":[{"id":1,"op":"between","threshold":{"num":1,"den":1}}]}' > "$T/bad_op.json"
"$ROOT/build/rh_cli" policy --policy "$T/bad_op.json" --input "$T/deny.json" --out "$T/x2" >/dev/null 2>&1; rc2=$?
printf '{"schema":"rh-policy/1","rules":[{"id":1,"op":">=","threshold":{"num":1,"den":0}}]}' > "$T/bad_den.json"
"$ROOT/build/rh_cli" policy --policy "$T/bad_den.json" --input "$T/deny.json" --out "$T/x3" >/dev/null 2>&1; rc3=$?
printf '{"schema":"rh-policy-input/1","subject_id":7,"now":1,"inputs":[{"rule_id":1,"status":"vibes"}]}' > "$T/bad_status.json"
"$ROOT/build/rh_cli" policy --policy "$T/policy.json" --input "$T/bad_status.json" --out "$T/x4" >/dev/null 2>&1; rc4=$?
"$ROOT/build/rh_cli" policy --policy "$T/missing-policy.json" --input "$T/deny.json" --out "$T/x5" >/dev/null 2>&1; rc5=$?
printf '{"schema":"rh-policy/1","rules":[{"id":1,"op":"=="},{"id":1,"op":"!="}]}' > "$T/bad_duplicate_rule.json"
"$ROOT/build/rh_cli" policy --policy "$T/bad_duplicate_rule.json" --input "$T/deny.json" --out "$T/x6" >/dev/null 2>&1; rc6=$?
printf '{"schema":"rh-policy-input/1","subject_id":7,"now":1000,"inputs":[{"rule_id":1,"status":"observed"},{"rule_id":1,"status":"partial"}]}' > "$T/bad_duplicate_input.json"
"$ROOT/build/rh_cli" policy --policy "$T/policy.json" --input "$T/bad_duplicate_input.json" --out "$T/x7" >/dev/null 2>&1; rc7=$?
printf '{"schema":"rh-policy-input/1","subject_id":7,"now":1000,"inputs":[{"rule_id":99,"status":"observed"}]}' > "$T/bad_unknown_rule.json"
"$ROOT/build/rh_cli" policy --policy "$T/policy.json" --input "$T/bad_unknown_rule.json" --out "$T/x8" >/dev/null 2>&1; rc8=$?
python3 - "$T/bad_duplicate_exception.json" "$digest" <<'PY'
import json, sys
exc = {"rule_id": 1, "subject_id": 7, "digest": sys.argv[2], "expires_at": 2000}
open(sys.argv[1], "w").write(json.dumps({"schema": "rh-policy/1", "rules": [{"id": 1, "op": ">="}],
    "exceptions": [{**exc, "state": "approved"}, {**exc, "state": "revoked"}]}))
PY
"$ROOT/build/rh_cli" policy --policy "$T/bad_duplicate_exception.json" --input "$T/deny.json" --out "$T/x9" >/dev/null 2>&1; rc9=$?
set -e
for rc in "$rc1" "$rc2" "$rc3" "$rc4" "$rc5" "$rc6" "$rc7" "$rc8" "$rc9"; do
  [[ "$rc" -eq 4 ]] || fail "malformed policy/input must exit 4 (got $rc)"
done

echo "[policy] durable exception state persists across runs, expires, and revokes"
# The inline-exceptions policy (pexc.json) grants rule 1; capturing its digest
# also lets us build a state document that references the same digest.
pdig="$(python3 -c "import json;print(json.load(open('$T/o6/policy-result.json'))['binding']['policy_digest'])")"
python3 - "$T/st_base.json" "$pdig" <<'PY'
import json, sys
rules = [{"id":1,"op":">=","threshold":{"num":1,"den":2},"min_sample":10,"on_violation":"deny","requires_complete":True},
         {"id":2,"op":">","threshold":{"num":0,"den":1},"on_violation":"warn"}]
# no inline exceptions: authority must come from --state only
open(sys.argv[1],"w").write(json.dumps({"schema":"rh-policy/1","rules":rules}))
PY
python3 - "$T/st_allow.json" "$pdig" <<'PY'
import json, sys
open(sys.argv[1],"w").write(json.dumps({"schema":"rh-policy-state/1",
  "exceptions":[{"rule_id":1,"subject_id":7,"digest":sys.argv[2],"expires_at":2000,"state":"approved"}]}))
PY
# run 1 with --state -> allow; state must be written back byte-stable
"$ROOT/build/rh_cli" policy --policy "$T/st_base.json" --input "$T/deny.json" --out "$T/s1" --state "$T/st_allow.json" | grep -q "decision=allow" || fail "durable approved state must allow"
cp "$T/st_allow.json" "$T/st_allow.snap"
# run 2 (now=1000 still) -> still allow, proving persistence independent of inline policy
"$ROOT/build/rh_cli" policy --policy "$T/st_base.json" --input "$T/deny.json" --out "$T/s2" --state "$T/st_allow.json" | grep -q "decision=allow" || fail "durable state must survive a second run"
cmp -s "$T/st_allow.json" "$T/st_allow.snap" || fail "state write-back must be deterministic"
# now=3000 -> expired, deny; the persisted row must not silently renew
python3 - "$T/deny3.json" <<'PY'
import json, sys
open(sys.argv[1],"w").write(json.dumps({"schema":"rh-policy-input/1","subject_id":7,"artifact_digest":"0000000000000001","context_digest":"0000000000000002","now":3000,"inputs":[{"rule_id":1,"status":"observed","num":1,"den":2,"sample":10,"complete":True},{"rule_id":2,"status":"observed","num":0,"den":1,"sample":5,"complete":True}]}))
PY
"$ROOT/build/rh_cli" policy --policy "$T/st_base.json" --input "$T/deny3.json" --out "$T/s3" --state "$T/st_allow.json" | grep -q "decision=deny" || fail "expired durable exception must not authorize"
# revoked state -> deny even when unexpired
python3 - "$T/st_rev.json" "$pdig" <<'PY'
import json, sys
open(sys.argv[1],"w").write(json.dumps({"schema":"rh-policy-state/1",
  "exceptions":[{"rule_id":1,"subject_id":7,"digest":sys.argv[2],"expires_at":2000,"state":"revoked"}]}))
PY
"$ROOT/build/rh_cli" policy --policy "$T/st_base.json" --input "$T/deny.json" --out "$T/s4" --state "$T/st_rev.json" | grep -q "decision=deny" || fail "revoked durable exception must not authorize"
# inline exception wins over a conflicting revoked persisted row (same key)
python3 - "$T/st_conflict.json" "$pdig" <<'PY'
import json, sys
open(sys.argv[1],"w").write(json.dumps({"schema":"rh-policy-state/1",
  "exceptions":[{"rule_id":1,"subject_id":7,"digest":sys.argv[2],"expires_at":2000,"state":"revoked"}]}))
PY
"$ROOT/build/rh_cli" policy --policy "$T/pexc.json" --input "$T/deny.json" --out "$T/s5" --state "$T/st_conflict.json" | grep -q "decision=allow" || fail "inline exception must win over persisted state for the same key"
# malformed persisted state fails closed (exit 4), never default allow
set +e
printf '{"schema":"rh-policy-state/1","exceptions":[{"rule_id":1,"subject_id":7,"digest":"%s","expires_at":2000,"state":"maybe"}]}' "$pdig" > "$T/st_bad.json"
"$ROOT/build/rh_cli" policy --policy "$T/st_base.json" --input "$T/deny.json" --out "$T/s6" --state "$T/st_bad.json" >/dev/null 2>&1; rc6=$?
printf '{"schema":"rh-policy-state/2","exceptions":[]}' > "$T/st_bad2.json"
"$ROOT/build/rh_cli" policy --policy "$T/st_base.json" --input "$T/deny.json" --out "$T/s7" --state "$T/st_bad2.json" >/dev/null 2>&1; rc7=$?
set -e
[[ "$rc6" -eq 4 && "$rc7" -eq 4 ]] || fail "malformed durable state must exit 4 (got $rc6/$rc7)"

echo "[policy] content-addressed --state-store survives restart"
PS="$T/policy-store"
seed_id="$("$ROOT/build/rh_cli" store put --root "$PS" --file "$T/st_allow.json" | awk '{print $3}')"
printf '%s\n' "$seed_id" > "$PS/current"
"$ROOT/build/rh_cli" policy --policy "$T/st_base.json" --input "$T/deny.json" --out "$T/ss1" --state-store "$PS" | grep -q "decision=allow" || fail "state-store exception must allow"
"$ROOT/build/rh_cli" policy --policy "$T/st_base.json" --input "$T/deny.json" --out "$T/ss2" --state-store "$PS" | grep -q "decision=allow" || fail "state-store must survive restart"
store_id="$(tr -d '\n' < "$PS/current")"
"$ROOT/build/rh_cli" store verify --root "$PS" --name "$store_id" >/dev/null || fail "policy state-store blob verification"
echo "[policy] state-store OK"

echo "test_policy_cli OK"
