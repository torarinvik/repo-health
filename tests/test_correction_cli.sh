#!/usr/bin/env bash
# tests/test_correction_cli.sh — M06 correction execution path:
# `rh_cli correct` applies an rh-corrections/1 document and writes
# rh-corrections-result/1. Asserts accepted corrections advance the
# revision and supersede only the target's older derived results (newly,
# once), rejected/open corrections change nothing, replay recomputes from
# unchanged raw inputs, and malformed kind/state/combine fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-correct"

fail() { echo "[correct] FAIL: $1" >&2; exit 1; }

echo "[correct] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
mkdir -p "$T/evidence-store"
printf 'review evidence payload\n' > "$T/evidence.bin"
evidence_digest="$("$ROOT/build/rh_cli" store put --root "$T/evidence-store" --file "$T/evidence.bin" | awk '{print $3}')"
[[ "${#evidence_digest}" -eq 16 ]] || fail "stored evidence digest was not returned"
printf '{"schema":"rh-corrections/1","current_revision":0,"corrections":[{"kind":"identity","target_id":1,"state":"accepted","evidence_ref":"%s","reviewed_by":"reviewer-a","reviewed_at":1700000000}]}' "$evidence_digest" > "$T/verified.json"
"$ROOT/build/rh_cli" correct --corrections "$T/verified.json" --out "$T/verified-out" --evidence-store "$T/evidence-store" >/dev/null || fail "registered correction evidence should verify"
python3 - "$T/verified.json" "$T/unverified.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["corrections"][0]["evidence_ref"] = "0000000000000000"
json.dump(d, open(sys.argv[2], "w"))
PY
set +e
"$ROOT/build/rh_cli" correct --corrections "$T/unverified.json" --out "$T/unverified-out" --evidence-store "$T/evidence-store" >/dev/null 2>&1; verify_rc=$?
set -e
[[ "$verify_rc" -eq 4 ]] || fail "missing correction evidence must fail closed (got $verify_rc)"

cat > "$T/corr.json" <<'JSON'
{"schema":"rh-corrections/1","current_revision":0,"corrections":[{"kind":"measurement","target_id":7,"state":"accepted","reviewed_by":"reviewer-a","reviewed_at":1700000000,"evidence_ref":"evidence-accepted"},{"kind":"identity","target_id":7,"state":"rejected","reviewed_by":"reviewer-b","reviewed_at":1700000100,"evidence_ref":"evidence-rejected"},{"kind":"mapping","target_id":9,"state":"open","evidence_ref":"evidence-open"},{"kind":"mapping","target_id":7,"state":"accepted","reviewed_by":"reviewer-a","reviewed_at":1700000000,"evidence_ref":"evidence-accepted"}],"derived":[{"subject_id":7,"revision_used":0,"superseded":false},{"subject_id":8,"revision_used":0,"superseded":false},{"subject_id":7,"revision_used":1,"superseded":false}],"replay":[{"subject_id":7,"raw_a":2,"raw_b":3,"combine":"add"},{"subject_id":7,"raw_a":9,"raw_b":4,"combine":"subtract"},{"subject_id":7,"raw_a":11,"raw_b":0,"combine":"identity"}]}
JSON
"$ROOT/build/rh_cli" correct --corrections "$T/corr.json" --out "$T/o" >/dev/null || fail "correct run"

python3 - "$T/o/corrections-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-corrections-result/1"
assert d["final_revision"] == 2, d
ap = d["applied"]
assert [a["state"] for a in ap] == ["accepted", "rejected", "open", "accepted"], ap
assert [a["evidence_ref"] for a in ap] == ["evidence-accepted", "evidence-rejected", "evidence-open", "evidence-accepted"], ap
assert [a["reviewed_by"] for a in ap] == ["reviewer-a", "reviewer-b", None, "reviewer-a"], ap
assert [a["reviewed_at"] for a in ap] == [1700000000, 1700000100, None, 1700000000], ap
assert len(d["notices"]) == 2, d["notices"]
assert [(n["subject_id"], n["correction_revision"], n["kind"]) for n in d["notices"]] == [(7, 1, "measurement"), (7, 2, "mapping")], d["notices"]
assert all(n["evidence_ref"] and n["reviewed_by"] and n["reviewed_at"] >= 0 for n in d["notices"]), d["notices"]
assert ap[0]["revision_before"] == 0 and ap[0]["revision_after"] == 1, ap[0]
assert ap[1]["revision_before"] == 1 and ap[1]["revision_after"] == 1, ap[1]  # rejected: no change
assert ap[2]["revision_before"] == 1 and ap[2]["revision_after"] == 1, ap[2]  # open: no change
assert ap[3]["revision_before"] == 1 and ap[3]["revision_after"] == 2, ap[3]
# newly superseded once each; the already-superseded rev0 result is not re-counted
assert ap[0]["superseded_count"] == 1, ap[0]
assert ap[1]["superseded_count"] == 0 and ap[2]["superseded_count"] == 0, ap
assert ap[3]["superseded_count"] == 1, ap[3]
der = {(x["subject_id"], x["revision_used"]): x["superseded"] for x in d["derived"]}
assert der == {(7, 0): True, (8, 0): False, (7, 1): True}, der
# subject 8 is untouched by a correction targeting 7
assert d["replay"] == [{"subject_id": 7, "value": 5},
                       {"subject_id": 7, "value": 5},
                       {"subject_id": 7, "value": 11}], d["replay"]
assert "raw inputs are never rewritten" in d["note"], d["note"]
print("[correct] applied/superseded/replay OK")
PY

echo "[correct] a rejected-only document changes nothing"
cat > "$T/reject.json" <<'JSON'
{"schema":"rh-corrections/1","current_revision":5,"corrections":[{"kind":"identity","target_id":1,"state":"rejected","reviewed_by":"reviewer-b","reviewed_at":1700000100,"evidence_ref":"evidence-rejected"}],"derived":[{"subject_id":1,"revision_used":5,"superseded":false}]}
JSON
"$ROOT/build/rh_cli" correct --corrections "$T/reject.json" --out "$T/r" >/dev/null || fail "reject run"
python3 - "$T/r/corrections-result.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["final_revision"] == 5, d
assert d["applied"][0]["superseded_count"] == 0, d["applied"]
assert d["derived"][0]["superseded"] is False, d["derived"]
print("[correct] rejected no-op OK")
PY

echo "[correct] negative controls fail closed"
set +e
check_rc() { # payload
  printf '%s' "$1" > "$T/bad.json"
  "$ROOT/build/rh_cli" correct --corrections "$T/bad.json" --out "$T/bad" >/dev/null 2>&1
  echo $?
}
rc1=$(check_rc '{"schema":"rh-corrections/1","current_revision":0,"corrections":[{"kind":"vibes","target_id":1,"state":"accepted","reviewed_by":"reviewer-a","reviewed_at":1700000000,"evidence_ref":"evidence-accepted"}]}')
rc2=$(check_rc '{"schema":"rh-corrections/1","current_revision":0,"corrections":[{"kind":"identity","target_id":1,"state":"maybe"}]}')
rc3=$(check_rc '{"schema":"rh-corrections/2","current_revision":0,"corrections":[]}')
rc4=$(check_rc '{"schema":"rh-corrections/1","current_revision":0,"corrections":[],"replay":[{"subject_id":1,"raw_a":1,"raw_b":2,"combine":"modulo"}]}')
rc5=$(check_rc 'not json')
rc7=$(check_rc '{"schema":"rh-corrections/1","current_revision":0,"corrections":[{"kind":"identity","target_id":1,"state":"accepted","evidence_ref":"x"}]}')
rc8=$(check_rc '{"schema":"rh-corrections/1","current_revision":0,"corrections":[{"kind":"identity","target_id":1,"state":"rejected","evidence_ref":"x","reviewed_at":12}]}')
"$ROOT/build/rh_cli" correct --corrections "$T/nope.json" --out "$T/nope" >/dev/null 2>&1
rc6=$?
set -e
for rc in "$rc1" "$rc2" "$rc3" "$rc4" "$rc5" "$rc6" "$rc7" "$rc8"; do
  [[ "$rc" -eq 4 ]] || fail "malformed correction input must exit 4 (got $rc)"
done

echo "[correct] durable ledger makes replay idempotent across runs"
cat > "$T/dur.json" <<'JSON'
{"schema":"rh-corrections/1","current_revision":0,"corrections":[{"kind":"measurement","target_id":7,"state":"accepted","reviewed_by":"reviewer-a","reviewed_at":1700000000,"evidence_ref":"evidence-accepted"},{"kind":"mapping","target_id":7,"state":"accepted","reviewed_by":"reviewer-a","reviewed_at":1700000000,"evidence_ref":"evidence-accepted"}],"derived":[{"subject_id":7,"revision_used":0,"superseded":false}]}
JSON
"$ROOT/build/rh_cli" correct --corrections "$T/dur.json" --out "$T/d1" --state "$T/state.json" >/dev/null || fail "first durable run"
rev1="$(python3 -c "import json;print(json.load(open('$T/d1/corrections-result.json'))['final_revision'])")"
[[ "$rev1" == "2" ]] || fail "first durable run must reach rev 2 (got $rev1)"
python3 - "$T/state.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-corrections-state/1", d
assert d["revision"] == 2 and d["watermark"] == 2, d
assert d["superseded_subjects"] == [7], d
print("[correct] state after run 1 OK")
PY
cp "$T/state.json" "$T/state.snap"
# Replaying the *same* document must not advance or re-supersede (idempotent).
"$ROOT/build/rh_cli" correct --corrections "$T/dur.json" --out "$T/d2" --state "$T/state.json" >/dev/null || fail "second durable run"
rev2="$(python3 -c "import json;print(json.load(open('$T/d2/corrections-result.json'))['final_revision'])")"
[[ "$rev2" == "2" ]] || fail "replayed ledger must stay at rev 2 (got $rev2)"
python3 - "$T/d2/corrections-result.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))["notices"] == []
print("[correct] replay emits no duplicate notices")
PY
cmp -s "$T/state.json" "$T/state.snap" || fail "state write-back must be deterministic"
# A persisted revision floor with a watermark covering the document lifts the
# result even with no new corrections folded in.
printf '{"schema":"rh-corrections-state/1","revision":9,"watermark":2,"superseded_subjects":[7]}' > "$T/floor.json"
"$ROOT/build/rh_cli" correct --corrections "$T/dur.json" --out "$T/d3" --state "$T/floor.json" >/dev/null || fail "floor run"
rev3="$(python3 -c "import json;print(json.load(open('$T/d3/corrections-result.json'))['final_revision'])")"
[[ "$rev3" == "9" ]] || fail "persisted revision floor must be honoured (got $rev3)"
# Malformed persisted state fails closed (exit 4), never defaults to allow.
set +e
printf '{"schema":"rh-corrections-state/1","revision":1,"watermark":1,"superseded_subjects":"x"}' > "$T/badstate.json"
"$ROOT/build/rh_cli" correct --corrections "$T/dur.json" --out "$T/d4" --state "$T/badstate.json" >/dev/null 2>&1; rc7=$?
printf '{"schema":"rh-corrections-state/2","revision":1,"watermark":1,"superseded_subjects":[]}' > "$T/badstate2.json"
"$ROOT/build/rh_cli" correct --corrections "$T/dur.json" --out "$T/d5" --state "$T/badstate2.json" >/dev/null 2>&1; rc8=$?
set -e
[[ "$rc7" -eq 4 && "$rc8" -eq 4 ]] || fail "malformed correction state must exit 4 (got $rc7/$rc8)"

echo "[correct] content-addressed --state-store survives restart"
CS="$T/correction-store"
"$ROOT/build/rh_cli" correct --corrections "$T/dur.json" --out "$T/cs1" --state-store "$CS" >/dev/null || fail "state-store run1"
"$ROOT/build/rh_cli" correct --corrections "$T/dur.json" --out "$T/cs2" --state-store "$CS" >/dev/null || fail "state-store run2"
rev_store="$(python3 -c "import json;print(json.load(open('$T/cs2/corrections-result.json'))['final_revision'])")"
[[ "$rev_store" == "2" ]] || fail "state-store replay must stay at rev 2 (got $rev_store)"
cs_id="$(tr -d '\n' < "$CS/current")"
"$ROOT/build/rh_cli" store verify --root "$CS" --name "$cs_id" >/dev/null || fail "correction state-store blob verification"
echo "[correct] state-store OK"

echo "test_correction_cli OK"
