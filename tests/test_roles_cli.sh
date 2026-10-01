#!/usr/bin/env bash
# tests/test_roles_cli.sh — R013 declared-roles execution path:
# `rh_cli roles` turns rh-roles-input/1 declarations + queries into
# rh-roles-result/1. Declared roles are time-scoped and separate from
# observed actions; an unrecognized role is unknown, never guessed; a
# revoked or not-yet-effective declaration is inactive; permissions are
# exact; declaration sources are tallied. Malformed input fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-roles"

fail() { echo "[roles] FAIL: $1" >&2; exit 1; }

echo "[roles] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-roles-input/1","authorization":{"state":"authorized"},"permission_inventory_complete":true,"identity_snapshot":{"identity_revision":8,"cluster_id_by_actor":[0,0,2,3,4]},"review_actor_id":4,"declarations":[{"actor_id":1,"role":"owner","permission":1,"source":"provider","declared_at":100},{"actor_id":2,"role":"triager","permission":2,"source":"file","declared_at":100,"revoked_at":200},{"actor_id":3,"role":"member","permission":4,"source":"operator","declared_at":300},{"actor_id":4,"role":"wizard","permission":8,"source":"file","declared_at":100}],"observed_actions":[{"actor_id":1,"identity_actor_index":0,"actor_type":"bot","kind":"release","at":120},{"actor_id":2,"identity_actor_index":1,"actor_type":"human","kind":"release","at":130},{"kind":"release","at":135},{"actor_id":null,"kind":"release","at":136},{"actor_id":3,"kind":"merge","at":140},{"actor_id":4,"kind":"review","at":150},{"actor_id":4,"kind":"review","at":160}],"queries":[{"actor_id":1,"as_of":150},{"actor_id":2,"as_of":150},{"actor_id":2,"as_of":250},{"actor_id":3,"as_of":250},{"actor_id":3,"as_of":350},{"actor_id":4,"as_of":150}],"permission_queries":[{"actor_id":1,"perm_bit":1,"as_of":150},{"actor_id":1,"perm_bit":2,"as_of":150}]}
JSON
"$ROOT/build/rh_cli" roles --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" "$T/in.json" "$T/out.json.transformations.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-roles-result/1", d
assert d["identity_revision"] == 8, d
assert d["declaration_count"] == 4, d
assert d["authorization_state"] == "authorized", d
tr = json.load(open(sys.argv[3]))
assert tr["schema"] == "rh-adapter-transformation-report/1" and tr["adapter"] == "declared-role-ledger", tr
assert tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/declared-role-ledger/2").hexdigest(), tr
assert any("change_id" in row["source"] for row in tr["fields"]), tr
assert {f["state"] for f in tr["fields"]} == {"preserved", "transformed", "unknown", "unsupported", "discarded"}, tr
assert d["source_tally"] == {"provider": 1, "file": 2, "operator": 1}, d["source_tally"]
assert d["role_tally"] == {"owner": 1, "maintainer": 0, "triager": 1, "member": 1, "unknown": 1}, d["role_tally"]
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["roles.owner_declaration_count"]["value"] == 1, metrics
assert metrics["roles.maintainer_declaration_count"]["value"] == 0, metrics
assert metrics["roles.triager_declaration_count"]["value"] == 1, metrics
assert metrics["roles.member_declaration_count"]["value"] == 1, metrics
assert metrics["roles.unknown_declaration_count"]["value"] == 1, metrics
assert metrics["roles.provider_declaration_count"]["value"] == 1, metrics
assert metrics["roles.file_declaration_count"]["value"] == 2, metrics
assert metrics["roles.operator_declaration_count"]["value"] == 1, metrics
for key in (
    "roles.owner_declaration_count",
    "roles.maintainer_declaration_count",
    "roles.triager_declaration_count",
    "roles.member_declaration_count",
    "roles.unknown_declaration_count",
    "roles.provider_declaration_count",
    "roles.file_declaration_count",
    "roles.operator_declaration_count",
    "maintainer.role_assignments_with_end_dates",
    "maintainer.observed_release_actors",
    "maintainer.observed_merge_actors",
    "maintainer.observed_review_actors",
    "maintainer.unattributed_release_count",
    "concentration.release_actor_count_80",
    "concentration.review_actor_count_80",
    "maintainer.permission_observed_current",
    "maintainer.review_share",
    "maintainer.release_role_automation_share",
    "maintainer.permission_inventory_coverage",
):
    metric = metrics[key]
    assert metric["status"] == "observed", metric
    assert metric["evidence"] == ["roles-input"], metric
    assert metric["quality_dimensions"] == {
        "completeness": "complete",
        "freshness": "unknown",
        "validity": "valid",
        "provenance": "evidence_backed",
    }, metric
assert metrics["maintainer.role_assignments_with_end_dates"]["value"] == 1, metrics
assert metrics["maintainer.declared_current"]["value"] == 1 and metrics["maintainer.declared_current"]["as_of"] == 350, metrics
assert metrics["maintainer.declared_current"]["quality_dimensions"] == {
    "completeness": "complete",
    "freshness": "unknown",
    "validity": "valid",
    "provenance": "evidence_backed",
}, metrics
assert metrics["maintainer.active_declared_12m"]["status"] == "unsupported", metrics
assert metrics["maintainer.active_declared_12m"]["value"] is None, metrics
assert metrics["maintainer.active_declared_12m"]["as_of"] == 350, metrics
assert metrics["maintainer.active_declared_12m"]["quality_dimensions"] == {
    "completeness": "unknown",
    "freshness": "unknown",
    "validity": "unknown",
    "provenance": "evidence_backed",
}, metrics
assert metrics["maintainer.permission_observed_current"]["value"] == 1, metrics
assert metrics["maintainer.permission_inventory_coverage"]["value"] == {"num": 1, "den": 1}, metrics
assert metrics["maintainer.observed_release_actors"]["value"] == 1, metrics
assert metrics["maintainer.observed_merge_actors"]["value"] == 1, metrics
assert metrics["maintainer.observed_review_actors"]["value"] == 1, metrics
assert d["action_events_by_actor_type"] == {
    "status": "observed",
    "release": {"human": 1, "bot": 1, "service": 0, "unknown": 2},
    "merge": {"human": 0, "bot": 0, "service": 0, "unknown": 1},
    "review": {"human": 0, "bot": 0, "service": 0, "unknown": 2},
}, d["action_events_by_actor_type"]
assert metrics["maintainer.unattributed_release_count"]["value"] == 2, metrics
assert metrics["maintainer.release_role_automation_share"]["value"] == {"num": 1, "den": 2}, metrics
assert metrics["maintainer.review_share"]["value"] == {"num": 2, "den": 2}, metrics
assert metrics["concentration.release_actor_count_80"]["value"] == 1, metrics
assert metrics["concentration.review_actor_count_80"]["value"] == 1, metrics
roles = [(q["actor_id"], q["as_of"], q["declared_role"]) for q in d["queries"]]
assert roles == [(1, 150, "owner"), (2, 150, "triager"), (2, 250, "unknown"),
                 (3, 250, "unknown"), (3, 350, "member"), (4, 150, "unknown")], roles
perms = [(p["actor_id"], p["perm_bit"], p["declared"]) for p in d["permission_queries"]]
assert perms == [(1, 1, True), (1, 2, False)], perms
assert "separate from observed actions" in d["note"], d["note"]
assert "never guessed" in d["note"], d["note"]
print("[roles] declared queries + tally OK")
PY

echo "[roles] determinism"
"$ROOT/build/rh_cli" roles --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "roles output not deterministic"
cmp -s "$T/out.json.transformations.json" "$T/out2.json.transformations.json" || fail "roles transformation report not deterministic"

echo "[roles] twelve-month declared continuity uses the explicit as-of time"
cat > "$T/long.json" <<'JSON'
{"schema":"rh-roles-input/1","as_of":31536100,"persistent_actors":[9],"declarations":[{"actor_id":9,"role":"maintainer","permission":0,"source":"file","declared_at":100}]}
JSON
"$ROOT/build/rh_cli" roles --input "$T/long.json" --out "$T/long.out.json" >/dev/null || fail "long declaration run"
python3 - "$T/long.out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["maintainer.active_declared_12m"]["value"] == 1, m
assert m["maintainer.active_declared_12m"]["as_of"] == 31536100, m
assert m["maintainer.active_declared_12m"]["quality_dimensions"] == {
    "completeness": "complete",
    "freshness": "unknown",
    "validity": "valid",
    "provenance": "evidence_backed",
}, m
print("[roles] twelve-month declaration metric OK")
PY

echo "[roles] missing evidence stays unsupported"
printf '{"schema":"rh-roles-input/1","authorization":{"state":"authorized"},"as_of":31536100,"declarations":[{"actor_id":9,"role":"maintainer","permission":1,"source":"provider","declared_at":100}]}' > "$T/incomplete.json"
"$ROOT/build/rh_cli" roles --input "$T/incomplete.json" --out "$T/incomplete.out.json" >/dev/null || fail "incomplete evidence run"
python3 - "$T/incomplete.out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["maintainer.active_declared_12m"]["status"] == "unsupported", m
assert m["maintainer.active_declared_12m"]["reason"] == "persistent-activity-profile-not-supplied", m
assert m["maintainer.active_declared_12m"]["quality_dimensions"] == {
    "completeness": "unknown",
    "freshness": "unknown",
    "validity": "unknown",
    "provenance": "evidence_backed",
}, m
assert m["maintainer.permission_inventory_coverage"]["status"] == "unsupported", m
assert m["maintainer.permission_inventory_coverage"]["reason"] == "permission-inventory-completeness-not-supplied", m
assert m["maintainer.permission_inventory_coverage"]["quality_dimensions"] == {
    "completeness": "unknown",
    "freshness": "unknown",
    "validity": "unknown",
    "provenance": "evidence_backed",
}, m
print("[roles] missing activity and permission completeness evidence stays unsupported")
PY

echo "[roles] empty provider permission inventory is not applicable"
printf '{"schema":"rh-roles-input/1","authorization":{"state":"authorized"},"permission_inventory_complete":true,"as_of":10,"declarations":[]}' > "$T/no-provider-permissions.json"
"$ROOT/build/rh_cli" roles --input "$T/no-provider-permissions.json" --out "$T/no-provider-permissions.out.json" >/dev/null || fail "empty provider permission inventory run"
python3 - "$T/no-provider-permissions.out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
metric = m["maintainer.permission_inventory_coverage"]
assert metric["status"] == "not_applicable" and metric["value"] is None, metric
assert metric["reason"] == "no-active-provider-permission-actors", metric
assert metric["quality_dimensions"] == {
    "completeness": "unknown",
    "freshness": "unknown",
    "validity": "unknown",
    "provenance": "evidence_backed",
}, metric
print("[roles] empty provider permission inventory remains reasoned not-applicable")
PY

echo "[roles] empty action populations are not applicable"
printf '{"schema":"rh-roles-input/1","declarations":[],"review_actor_id":1,"observed_actions":[{"actor_id":1,"kind":"merge","at":10}]}' > "$T/no-release-review.json"
"$ROOT/build/rh_cli" roles --input "$T/no-release-review.json" --out "$T/no-release-review.out.json" >/dev/null || fail "empty release and review populations run"
python3 - "$T/no-release-review.out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
change_metrics = {row["key"]: row for row in d["change_review"]["metrics"]}
for key in ("maintainer.reviewed_merge_change_count", "maintainer.linked_merge_change_count"):
    assert change_metrics[key]["status"] == "observed" and change_metrics[key]["value"] == 0, change_metrics[key]
for key, reason in (
    ("concentration.release_actor_count_80", "no-release-actions"),
    ("concentration.review_actor_count_80", "no-review-actions"),
    ("maintainer.review_share", "no-attributed-review-actions"),
    ("maintainer.release_role_automation_share", "no-attributed-release-actions"),
):
    assert m[key]["status"] == "not_applicable" and m[key]["value"] is None, m[key]
    assert m[key]["reason"] == reason, m[key]
    assert m[key]["quality_dimensions"] == {
        "completeness": "unknown",
        "freshness": "unknown",
        "validity": "unknown",
        "provenance": "evidence_backed",
    }, m[key]
print("[roles] empty action populations remain reasoned not-applicable")
PY

echo "[roles] bounded file URL capture retains transport evidence"
file_url="file://$T/in.json"
"$ROOT/build/rh_cli" roles --url "$file_url" --out "$T/url-out.json" >/dev/null || fail "file URL run"
cmp -s "$T/out.json" "$T/url-out.json" || fail "URL roles output differs"
python3 - "$T/roles-fetch-status.txt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-roles-fetch/1", d
assert d["state"] == "collected", d
assert d["status"] == "000", d
assert d["body_file"] == "roles-fetch-body.json", d
print("[roles] URL transport evidence OK")
PY
cmp -s "$T/in.json" "$T/roles-fetch-body.json" || fail "URL body evidence differs"

echo "[roles] blocked URL fails closed"
set +e
"$ROOT/build/rh_cli" roles --url "http://example.com/roles.json" --out "$T/blocked.json" >/dev/null 2>&1
rc_blocked=$?
set -e
[[ "$rc_blocked" -eq 4 ]] || fail "blocked URL must exit 4 (got $rc_blocked)"

echo "[roles] absent authorization stays unknown"
printf '{"schema":"rh-roles-input/1","declarations":[]}' > "$T/noauth.json"
"$ROOT/build/rh_cli" roles --input "$T/noauth.json" --out "$T/noauth-out.json" >/dev/null || fail "missing authorization run"
python3 - "$T/noauth-out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["authorization_state"] == "unknown", d
assert d["action_events_by_actor_type"]["status"] == "unsupported", d
change_review = d["change_review"]
change_metrics = {row["key"]: row for row in change_review["metrics"]}
for key in ("maintainer.reviewed_merge_change_count", "maintainer.linked_merge_change_count"):
    metric = change_metrics[key]
    assert metric["status"] == "unsupported" and metric["value"] is None, metric
    assert metric["reason"] == "observed-actions-not-supplied", metric
    assert metric["evidence"] == ["roles-input"], metric
    assert metric["quality_dimensions"] == {
        "completeness": "unknown",
        "freshness": "unknown",
        "validity": "unknown",
        "provenance": "evidence_backed",
    }, metric
m = {x["key"]: x for x in d["metrics"]}
for key in (
    "maintainer.observed_release_actors",
    "maintainer.observed_merge_actors",
    "maintainer.observed_review_actors",
    "maintainer.unattributed_release_count",
    "concentration.release_actor_count_80",
    "concentration.review_actor_count_80",
    "maintainer.review_share",
    "maintainer.release_role_automation_share",
):
    assert m[key]["status"] == "unsupported" and m[key]["value"] is None, m[key]
    assert m[key]["reason"] == "observed-actions-not-supplied", m[key]
    assert m[key]["quality_dimensions"] == {
        "completeness": "unknown",
        "freshness": "unknown",
        "validity": "unknown",
        "provenance": "evidence_backed",
    }, m[key]
for key in ("maintainer.declared_current", "maintainer.active_declared_12m"):
    assert m[key]["status"] == "unsupported" and m[key]["value"] is None, m[key]
    assert m[key]["reason"] == "no-declaration-as-of-time", m[key]
    assert m[key]["as_of"] is None, m[key]
    assert m[key]["quality_dimensions"] == {
        "completeness": "unknown",
        "freshness": "unknown",
        "validity": "unknown",
        "provenance": "evidence_backed",
    }, m[key]
for key in (
    "maintainer.permission_observed_current",
    "maintainer.permission_inventory_coverage",
):
    assert m[key]["status"] == "unsupported" and m[key]["value"] is None, m[key]
    assert m[key]["reason"] == "authorized-provider-permission-enumeration-not-available", m[key]
print("[roles] absent authorization is explicit unknown")
PY

echo "[roles] unauthorized permission observations are typed"
printf '{"schema":"rh-roles-input/1","authorization":{"state":"unauthorized"},"permission_inventory_complete":true,"as_of":10,"declarations":[]}' > "$T/unauthorized.json"
"$ROOT/build/rh_cli" roles --input "$T/unauthorized.json" --out "$T/unauthorized.out.json" >/dev/null || fail "unauthorized permission run"
python3 - "$T/unauthorized.out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
for key in (
    "maintainer.permission_observed_current",
    "maintainer.permission_inventory_coverage",
):
    metric = m[key]
    assert metric["status"] == "unauthorized" and metric["value"] is None, metric
    assert metric["reason"] == "provider-permission-enumeration-unauthorized", metric
    assert metric["quality_dimensions"] == {
        "completeness": "unknown",
        "freshness": "unknown",
        "validity": "unknown",
        "provenance": "evidence_backed",
    }, metric
print("[roles] unauthorized permission states remain explicit")
PY

echo "[roles] malformed input fails closed"
set +e
printf '{"schema":"rh-roles-input/2","declarations":[]}' > "$T/bschema.json"
"$ROOT/build/rh_cli" roles --input "$T/bschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-roles-input/1","declarations":[{"actor_id":1,"role":"owner","source":"vibes"}]}' > "$T/bsrc.json"
"$ROOT/build/rh_cli" roles --input "$T/bsrc.json" --out "$T/x" >/dev/null 2>&1; rc_src=$?
printf '{"schema":"rh-roles-input/1","declarations":42}' > "$T/bdecls.json"
"$ROOT/build/rh_cli" roles --input "$T/bdecls.json" --out "$T/x" >/dev/null 2>&1; rc_decls=$?
printf '{"schema":"rh-roles-input/1","declarations":[{"role":"owner","source":"file"}]}' > "$T/noid.json"
"$ROOT/build/rh_cli" roles --input "$T/noid.json" --out "$T/x" >/dev/null 2>&1; rc_id=$?
printf '{"schema":"rh-roles-input/1","authorization":{"state":"maybe"},"declarations":[]}' > "$T/bauth.json"
"$ROOT/build/rh_cli" roles --input "$T/bauth.json" --out "$T/x" >/dev/null 2>&1; rc_auth=$?
printf '{"schema":"rh-roles-input/1","declarations":[],"observed_actions":[{"actor_id":1,"actor_type":"robot","kind":"release","at":1}]}' > "$T/bactor-type.json"
"$ROOT/build/rh_cli" roles --input "$T/bactor-type.json" --out "$T/x" >/dev/null 2>&1; rc_actor_type=$?
printf '{"schema":"rh-roles-input/1","declarations":[],"observed_actions":[{"actor_id":1,"identity_actor_id":0,"kind":"release","at":1}]}' > "$T/bidentity-revision.json"
"$ROOT/build/rh_cli" roles --input "$T/bidentity-revision.json" --out "$T/x" >/dev/null 2>&1; rc_identity_revision=$?
printf '{"schema":"rh-roles-input/1","declarations":[],"observed_actions":[{"actor_id":1,"identity_actor_index":1,"kind":"release","at":1}],"identity_snapshot":{"identity_revision":1,"cluster_id_by_actor":[0]}}' > "$T/bidentity-index.json"
"$ROOT/build/rh_cli" roles --input "$T/bidentity-index.json" --out "$T/x" >/dev/null 2>&1; rc_identity_index=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" roles --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" roles --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_src" "$rc_decls" "$rc_id" "$rc_auth" "$rc_actor_type" "$rc_identity_revision" "$rc_identity_index" "$rc_json" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed roles input must exit 4 (got $rc)"
done

# Action windows are half-open: start is included and end is excluded.
cat > "$T/window.json" <<'JSON'
{"schema":"rh-roles-input/1","observed_actions_window":{"start":100,"end":200},"declarations":[],"observed_actions":[{"actor_id":1,"kind":"release","at":99},{"actor_id":2,"kind":"release","at":100},{"actor_id":2,"kind":"review","at":199},{"actor_id":3,"kind":"review","at":200}]}
JSON
"$ROOT/build/rh_cli" roles --input "$T/window.json" --out "$T/window-out.json" >/dev/null || fail "windowed run"
python3 - "$T/window-out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["observed_actions_window"] == {"start": 100, "end": 200}, d
m = {row["key"]: row for row in d["metrics"]}
assert m["maintainer.observed_release_actors"]["value"] == 1, m
assert m["maintainer.observed_review_actors"]["value"] == 1, m
PY
cat > "$T/change-links.json" <<'JSON'
{"schema":"rh-roles-input/1","declarations":[],"observed_actions":[{"kind":"merge","at":10,"change_id":"pr-1"},{"kind":"merge","at":11,"change_id":"pr-1"},{"kind":"merge","at":12,"change_id":"pr-2"},{"kind":"merge","at":13},{"kind":"review","at":14,"change_id":"pr-1"},{"kind":"review","at":15,"change_id":"pr-1"},{"kind":"review","at":16,"change_id":"pr-3"}]}
JSON
"$ROOT/build/rh_cli" roles --input "$T/change-links.json" --out "$T/change-links-out.json" >/dev/null || fail "linked change review share"
python3 - "$T/change-links-out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
change_review = d["change_review"]
assert {key: value for key, value in change_review.items() if key != "metrics"} == {"status": "observed", "numerator": 1, "denominator": 2, "basis": "unique-linked-merge-change-identifiers", "excluded_unlinked_merge_actions": 1}, d
change_metrics = {row["key"]: row for row in change_review["metrics"]}
for key, count in (("maintainer.reviewed_merge_change_count", 1), ("maintainer.linked_merge_change_count", 2)):
    metric = change_metrics[key]
    assert metric["status"] == "observed" and metric["value"] == count, metric
    assert metric["evidence"] == ["roles-input"], metric
    assert metric["quality_dimensions"] == {
        "completeness": "complete",
        "freshness": "unknown",
        "validity": "valid",
        "provenance": "evidence_backed",
    }, metric
PY
printf '{"schema":"rh-roles-input/1","declarations":[],"observed_actions":[{"kind":"merge","at":1,"change_id":""}]}' > "$T/empty-change-id.json"
if "$ROOT/build/rh_cli" roles --input "$T/empty-change-id.json" --out "$T/empty-change-id-out.json" >/dev/null 2>&1; then fail "empty change identifier accepted"; fi
printf '{"schema":"rh-roles-input/1","declarations":[],"observed_actions":[{"kind":"release","at":1,"change_id":"release-1"}]}' > "$T/wrong-change-kind.json"
if "$ROOT/build/rh_cli" roles --input "$T/wrong-change-kind.json" --out "$T/wrong-change-kind-out.json" >/dev/null 2>&1; then fail "change identifier on an unrelated action accepted"; fi
printf '{"schema":"rh-roles-input/1","observed_actions_window":{"start":200,"end":100},"declarations":[]}' > "$T/bwindow.json"
if "$ROOT/build/rh_cli" roles --input "$T/bwindow.json" --out "$T/bwindow-out.json" >/dev/null 2>&1; then fail "invalid action window accepted"; fi

echo "test_roles_cli OK"
