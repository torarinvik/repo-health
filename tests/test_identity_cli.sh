#!/usr/bin/env bash
# tests/test_identity_cli.sh — M04-03 reversible identity-link execution
# path: `rh_cli identity` turns an rh-identity-input/1 ledger into
# rh-identity-result/1 with the identity revision, clusters over ACCEPTED
# links only, and a per-actor cluster map. Revoking recomputes clusters and
# changes the revision; rejected/proposed links change nothing; malformed
# input fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-identity"

fail() { echo "[identity] FAIL: $1" >&2; exit 1; }

echo "[identity] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/a.json" <<'JSON'
{"schema":"rh-identity-input/1","actor_count":5,"links":[{"a":0,"b":1,"state":"accepted","revision_added":1},{"a":1,"b":2,"state":"accepted","revision_added":2},{"a":3,"b":0,"state":"rejected","revision_added":3}],"actor_kinds":["human","human","unresolved","bot_known","service_known"],"actor_kind_sources":["provider","provider","unknown","provider","project"],"actor_kind_observed_at":[1700000000,null,1700000200,1700000300,1700000400],"actor_kind_evidence_refs":["evidence:provider-run-8",null,"evidence:project-declaration-2","evidence:provider-run-8","evidence:operator-review-3"],"actors":[{"source":"github","source_instance":"github.com/acme","native_object_id":"repo-1","display_name":"shared","aliases":[{"value":"old-name","observed_at":100}]},{"source":"github","source_instance":"github.com/acme","native_object_id":"repo-2","display_name":"other","aliases":[]},{"source":"gitlab","source_instance":"gitlab.com/acme","native_object_id":"repo-1","display_name":"shared","aliases":[]},{"source":"github","source_instance":"github.com/acme","native_object_id":"bot-1","display_name":"bot","aliases":[]},{"source":"github","source_instance":"github.com/acme","native_object_id":"service-1","display_name":"automation service","aliases":[]}]}
JSON
cat > "$T/b.json" <<'JSON'
{"schema":"rh-identity-input/1","actor_count":4,"links":[{"a":0,"b":1,"state":"accepted","revision_added":1},{"a":1,"b":2,"state":"revoked","revision_added":4},{"a":3,"b":0,"state":"rejected","revision_added":3}]}
JSON

"$ROOT/build/rh_cli" identity --input "$T/a.json" --out "$T/a.out" >/dev/null || fail "A run"
python3 - "$T/a.json" "$T/a.out" <<'PY'
import hashlib, json, sys
source, output = sys.argv[1:]
v = json.load(open(output + ".evidence-verification.json"))
n = json.load(open(output + ".identity-review-notices.json"))
assert v["state"] == "unverified" and v["verified_reference_count"] == 0, v
assert n["state"] == "unverified" and n["notice_count"] == 0 and n["notices"] == [], n
assert v["source_input_sha256"] == n["source_input_sha256"] == hashlib.sha256(open(source, "rb").read()).hexdigest()
assert v["identity_output_sha256"] == n["identity_output_sha256"] == hashlib.sha256(open(output, "rb").read()).hexdigest()
print("[identity] absent evidence-store state is explicit and bound")
PY
python3 - "$T/a.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-identity-result/1", d
assert d["actor_count"] == 5 and d["identity_revision"] == 2, d
assert d["cluster_count"] == 3, d
assert d["metrics"][0]["key"] == "contributor.accepted_actor_clusters" and d["metrics"][0]["value"] == 3, d
assert d["metrics"][1]["key"] == "contributor.known_human_accounts" and d["metrics"][1]["value"] == 2, d
assert d["clusters"] == [[0, 1, 2], [3], [4]], d["clusters"]
assert d["cluster_id_by_actor"] == [0, 0, 0, 3, 4], d["cluster_id_by_actor"]
assert d["actor_kinds"] == {"human": 2, "bot_known": 1, "service_known": 1, "unresolved": 1}, d["actor_kinds"]
assert d["actor_kind_sources"] == {"provider": 3, "project": 1, "operator": 0, "unknown": 1}, d["actor_kind_sources"]
assert d["actor_kind_observation_times"] == {"observed": 4, "unknown": 1}, d["actor_kind_observation_times"]
assert d["actor_kind_evidence_references"] == {"present": 4, "unknown": 1}, d["actor_kind_evidence_references"]
assert d["actor_classifications"][0] == {"actor_id": 0, "kind": "human", "source": "provider", "observed_at": 1700000000, "evidence_ref": "evidence:provider-run-8"}, d["actor_classifications"]
assert d["actor_classifications"][1] == {"actor_id": 1, "kind": "human", "source": "provider", "observed_at": None, "evidence_ref": None}, d["actor_classifications"]
assert d["actor_classifications"][4] == {"actor_id": 4, "kind": "service_known", "source": "project", "observed_at": 1700000400, "evidence_ref": "evidence:operator-review-3"}, d["actor_classifications"]
assert d["actors"][0]["source_instance"] == "github.com/acme", d
assert d["actors"][0]["aliases"] == [{"value": "old-name", "observed_at": 100}], d
assert d["actors"][0]["display_name"] == d["actors"][2]["display_name"] and d["actors"][0]["source_instance"] != d["actors"][2]["source_instance"], d
assert "unresolved never forced human" in d["note"], d["note"]
print("[identity] clusters + kinds OK")
PY

echo "[identity] rejecting a link changes nothing; revoking recomputes"
"$ROOT/build/rh_cli" identity --input "$T/b.json" --out "$T/b.out" >/dev/null || fail "B run"
python3 - "$T/a.out" "$T/b.out" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
# A has an extra accepted link (1-2); B has it revoked. Revision drops and
# the cluster splits.
assert a["identity_revision"] == 2 and b["identity_revision"] == 1, (a, b)
assert b["clusters"] == [[0, 1], [2], [3]], b["clusters"]
assert b["cluster_id_by_actor"] == [0, 0, 2, 3], b["cluster_id_by_actor"]
print("[identity] revoke recompute OK")
PY

echo "[identity] proposed/rejected-only ledgers never merge"
cat > "$T/none.json" <<'JSON'
{"schema":"rh-identity-input/1","actor_count":3,"links":[{"a":0,"b":1,"state":"proposed"},{"a":1,"b":2,"state":"rejected"}]}
JSON
"$ROOT/build/rh_cli" identity --input "$T/none.json" --out "$T/none.out" >/dev/null || fail "none run"
python3 - "$T/none.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["identity_revision"] == 0 and d["cluster_count"] == 3, d
assert d["metrics"][0]["value"] == 3, d
assert d["clusters"] == [[0], [1], [2]], d["clusters"]
print("[identity] no-op links OK")
PY

echo "[identity] determinism"
"$ROOT/build/rh_cli" identity --input "$T/a.json" --out "$T/a2.out" >/dev/null || fail "rerun"
cmp -s "$T/a.out" "$T/a2.out" || fail "identity output not deterministic"

echo "[identity] malformed input fails closed"
python3 - "$T/a.json" "$T/badnative.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["actor_count"] += 1
d["actor_kinds"].append("human")
d["actor_kind_sources"].append("provider")
d["actors"].append(dict(d["actors"][0]))
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
set +e
printf '{"schema":"rh-identity-input/2","actor_count":1,"links":[]}' > "$T/badschema.json"
"$ROOT/build/rh_cli" identity --input "$T/badschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":1,"state":"maybe"}]}' > "$T/badstate.json"
"$ROOT/build/rh_cli" identity --input "$T/badstate.json" --out "$T/x" >/dev/null 2>&1; rc_state=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":5,"state":"accepted"}]}' > "$T/badactor.json"
"$ROOT/build/rh_cli" identity --input "$T/badactor.json" --out "$T/x" >/dev/null 2>&1; rc_actor=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":1,"state":"accepted"}],"actor_kinds":["human","alien"]}' > "$T/badkind.json"
"$ROOT/build/rh_cli" identity --input "$T/badkind.json" --out "$T/x" >/dev/null 2>&1; rc_kind=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[],"actor_kinds":["human","unresolved"],"actor_kind_sources":["provider","made-up"]}' > "$T/badkindsource.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindsource.json" --out "$T/x" >/dev/null 2>&1; rc_kind_source=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[],"actor_kinds":["human","unresolved"],"actor_kind_sources":["project"]}' > "$T/badkindsourcecount.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindsourcecount.json" --out "$T/x" >/dev/null 2>&1; rc_kind_source_count=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[],"actor_kinds":["human","unresolved"],"actor_kind_observed_at":[1]}' > "$T/badkindtimecount.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindtimecount.json" --out "$T/x" >/dev/null 2>&1; rc_kind_time_count=$?
printf '{"schema":"rh-identity-input/1","actor_count":1,"links":[],"actor_kinds":["human"],"actor_kind_observed_at":[-1]}' > "$T/badkindtime.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindtime.json" --out "$T/x" >/dev/null 2>&1; rc_kind_time=$?
printf '{"schema":"rh-identity-input/1","actor_count":1,"links":[],"actor_kind_observed_at":[1]}' > "$T/kindtimewithoutkind.json"
"$ROOT/build/rh_cli" identity --input "$T/kindtimewithoutkind.json" --out "$T/x" >/dev/null 2>&1; rc_kind_time_without_kind=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[],"actor_kinds":["human","unresolved"],"actor_kind_evidence_refs":["evidence:one"]}' > "$T/badkindrefcount.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindrefcount.json" --out "$T/x" >/dev/null 2>&1; rc_kind_ref_count=$?
printf '{"schema":"rh-identity-input/1","actor_count":1,"links":[],"actor_kinds":["human"],"actor_kind_evidence_refs":[""]}' > "$T/badkindref.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindref.json" --out "$T/x" >/dev/null 2>&1; rc_kind_ref=$?
printf '{"schema":"rh-identity-input/1","actor_count":1,"links":[],"actor_kind_evidence_refs":["evidence:one"]}' > "$T/kindrefwithoutkind.json"
"$ROOT/build/rh_cli" identity --input "$T/kindrefwithoutkind.json" --out "$T/x" >/dev/null 2>&1; rc_kind_ref_without_kind=$?
"$ROOT/build/rh_cli" identity --input "$T/badnative.json" --out "$T/x" >/dev/null 2>&1; rc_native_duplicate=$?
"$ROOT/build/rh_cli" identity --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_state" "$rc_actor" "$rc_kind" "$rc_kind_source" "$rc_kind_source_count" "$rc_kind_time_count" "$rc_kind_time" "$rc_kind_time_without_kind" "$rc_kind_ref_count" "$rc_kind_ref" "$rc_kind_ref_without_kind" "$rc_native_duplicate" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed identity input must exit 4 (got $rc)"
done

echo "[identity] optional evidence-store verifies content-addressed actor evidence"
mkdir -p "$T/evidence"
printf 'actor-kind source evidence\n' > "$T/kind-evidence.txt"
evidence_name=$("$ROOT/build/rh_cli" store put --root "$T/evidence" --file "$T/kind-evidence.txt" | awk '{print $3}')
python3 - "$T/verified-input.json" "$evidence_name" <<'PY'
import json, sys
json.dump({"schema":"rh-identity-input/1","actor_count":1,"links":[],"actor_kinds":["human"],"actor_kind_evidence_refs":[sys.argv[2]]}, open(sys.argv[1], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" identity --input "$T/verified-input.json" --out "$T/verified.out" --evidence-store "$T/evidence" >/dev/null || fail "verified evidence reference"
python3 - "$T/verified-input.json" "$T/verified.out" <<'PY'
import hashlib, json, sys
r = json.load(open(sys.argv[2] + ".evidence-verification.json"))
assert r["schema"] == "rh-identity-evidence-verification/1" and r["state"] == "verified", r
assert r["verified_reference_count"] == 1, r
assert r["source_input_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), r
assert r["identity_output_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), r
print("[identity] evidence digest + output binding OK")
PY
python3 - "$T/reviewed-link-input.json" "$evidence_name" <<'PY'
import json, sys
json.dump({"schema":"rh-identity-input/1","actor_count":2,"actors":[{"source":"github","source_instance":"github.com/acme","native_object_id":"1","display_name":"a","aliases":[]},{"source":"gitlab","source_instance":"gitlab.com/acme","native_object_id":"1","display_name":"b","aliases":[]}],"links":[{"a":0,"b":1,"state":"accepted","revision_added":1,"reviewed_by":"maintainer","reviewed_at":1700000000,"review_reason":"Verified shared ownership evidence","evidence_ref":sys.argv[2]}]}, open(sys.argv[1], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" identity --input "$T/reviewed-link-input.json" --out "$T/reviewed-link.out" --evidence-store "$T/evidence" >/dev/null || fail "evidence-backed accepted identity link"
python3 - "$T/reviewed-link-input.json" "$T/reviewed-link.out" <<'PY'
import hashlib, json, sys
source, output = sys.argv[1:]
d = json.load(open(output + ".evidence-verification.json"))
assert d["verified_reference_count"] == 1 and d["reviewed_link_count"] == 1 and d["reviewed_cross_source_link_count"] == 1, d
n = json.load(open(output + ".identity-review-notices.json"))
assert n["schema"] == "rh-identity-review-notices/1" and n["scope"] == "restricted" and n["notice_count"] == 1, n
input_bytes = open(source, "rb").read()
output_bytes = open(output, "rb").read()
assert n["source_input_sha256"] == hashlib.sha256(input_bytes).hexdigest(), n
assert n["identity_output_sha256"] == hashlib.sha256(output_bytes).hexdigest(), n
notice = n["notices"][0]
assert notice == {"state":"accepted","actor_pair":[0,1],"reviewed_by":"maintainer","reviewed_at":1700000000,"evidence_ref":json.load(open(source))["links"][0]["evidence_ref"],"review_reason":"Verified shared ownership evidence"}, notice
print("[identity] cross-source review evidence + reviewer/time/reason OK")
PY
cp "$T/reviewed-link-input.json" "$T/reviewed-link-valid.json"
python3 - "$T/reviewed-link-valid.json" "$T/same-source-link.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["actors"][1]["source"] = d["actors"][0]["source"]
d["actors"][1]["source_instance"] = d["actors"][0]["source_instance"]
d["actors"][1]["native_object_id"] = "same-source-distinct-account"
d["links"][0].pop("review_reason")
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" identity --input "$T/same-source-link.json" --out "$T/same-source-link.out" --evidence-store "$T/evidence" >/dev/null || fail "same-source reviewed identity link"
python3 - "$T/same-source-link.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1] + ".evidence-verification.json"))
assert d["reviewed_link_count"] == 1 and d["reviewed_cross_source_link_count"] == 0, d
n = json.load(open(sys.argv[1] + ".identity-review-notices.json"))
assert n["notice_count"] == 0 and n["notices"] == [], n
print("[identity] same-source review does not require cross-source rationale")
PY
python3 - "$T/reviewed-link-valid.json" "$T" <<'PY'
import json, sys
source, root = sys.argv[1:]
for state in ("rejected", "revoked"):
    d = json.load(open(source)); d["links"][0]["state"] = state
    json.dump(d, open(f"{root}/{state}-cross-source.json", "w"), separators=(",", ":"))
PY
for review_state in rejected revoked; do
    "$ROOT/build/rh_cli" identity --input "$T/$review_state-cross-source.json" --out "$T/$review_state-cross-source.out" --evidence-store "$T/evidence" >/dev/null || fail "evidence-backed $review_state cross-source link"
    python3 - "$T/$review_state-cross-source.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1] + ".evidence-verification.json"))
assert d["reviewed_link_count"] == 1 and d["reviewed_cross_source_link_count"] == 1, d
PY
done
printf '[identity] reviewed rejected/revoked cross-source links\n'
python3 - "$T/reviewed-link-input.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["links"][0].pop("evidence_ref")
json.dump(d, open(p, "w"), separators=(",", ":"))
PY
set +e
"$ROOT/build/rh_cli" identity --input "$T/reviewed-link-input.json" --out "$T/unverified-link.out" --evidence-store "$T/evidence" >/dev/null 2>&1
rc_unverified_link=$?
set -e
[[ "$rc_unverified_link" -eq 4 && ! -f "$T/unverified-link.out" ]] || fail "reviewed identity link without evidence must fail closed"
python3 - "$T/reviewed-link-valid.json" "$T" <<'PY'
import json, sys
source, root = sys.argv[1:]
for name, field, value in (("missing-reviewer", "reviewed_by", None), ("negative-review-time", "reviewed_at", -1), ("missing-cross-source-reason", "review_reason", None)):
    d = json.load(open(source))
    if value is None:
        d["links"][0].pop(field)
    else:
        d["links"][0][field] = value
    json.dump(d, open(f"{root}/{name}.json", "w"), separators=(",", ":"))
PY
for invalid_review in missing-reviewer negative-review-time; do
    set +e
    "$ROOT/build/rh_cli" identity --input "$T/$invalid_review.json" --out "$T/$invalid_review.out" --evidence-store "$T/evidence" >/dev/null 2>&1
    rc_invalid_review=$?
    set -e
    [[ "$rc_invalid_review" -eq 4 && ! -f "$T/$invalid_review.out" ]] || fail "invalid reviewed identity metadata must fail closed: $invalid_review"
done
printf 'corrupt\n' > "$T/evidence/$evidence_name"
set +e
"$ROOT/build/rh_cli" identity --input "$T/verified-input.json" --out "$T/corrupt.out" --evidence-store "$T/evidence" >/dev/null 2>&1
rc_corrupt=$?
set -e
[[ "$rc_corrupt" -eq 4 && ! -f "$T/corrupt.out" ]] || fail "corrupt evidence must fail before identity publication"

echo "test_identity_cli OK"
