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
{"schema":"rh-roles-input/1","authorization":{"state":"authorized"},"declarations":[{"actor_id":1,"role":"owner","permission":1,"source":"provider","declared_at":100},{"actor_id":2,"role":"triager","permission":2,"source":"file","declared_at":100,"revoked_at":200},{"actor_id":3,"role":"member","permission":4,"source":"operator","declared_at":300},{"actor_id":4,"role":"wizard","permission":8,"source":"file","declared_at":100}],"observed_actions":[{"actor_id":1,"kind":"release","at":120},{"actor_id":2,"kind":"release","at":130},{"actor_id":3,"kind":"merge","at":140},{"actor_id":4,"kind":"review","at":150},{"actor_id":4,"kind":"review","at":160}],"queries":[{"actor_id":1,"as_of":150},{"actor_id":2,"as_of":150},{"actor_id":2,"as_of":250},{"actor_id":3,"as_of":250},{"actor_id":3,"as_of":350},{"actor_id":4,"as_of":150}],"permission_queries":[{"actor_id":1,"perm_bit":1,"as_of":150},{"actor_id":1,"perm_bit":2,"as_of":150}]}
JSON
"$ROOT/build/rh_cli" roles --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-roles-result/1", d
assert d["declaration_count"] == 4, d
assert d["authorization_state"] == "authorized", d
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
assert metrics["maintainer.role_assignments_with_end_dates"]["value"] == 1, metrics
assert metrics["maintainer.declared_current"]["value"] == 1 and metrics["maintainer.declared_current"]["as_of"] == 350, metrics
assert metrics["maintainer.permission_observed_current"]["value"] == 1, metrics
assert metrics["maintainer.observed_release_actors"]["value"] == 2, metrics
assert metrics["maintainer.observed_merge_actors"]["value"] == 1, metrics
assert metrics["maintainer.observed_review_actors"]["value"] == 1, metrics
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

echo "[roles] twelve-month declared continuity uses the explicit as-of time"
cat > "$T/long.json" <<'JSON'
{"schema":"rh-roles-input/1","as_of":31536100,"declarations":[{"actor_id":9,"role":"maintainer","permission":0,"source":"file","declared_at":100}]}
JSON
"$ROOT/build/rh_cli" roles --input "$T/long.json" --out "$T/long.out.json" >/dev/null || fail "long declaration run"
python3 - "$T/long.out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["maintainer.active_declared_12m"]["value"] == 1, m
assert m["maintainer.active_declared_12m"]["as_of"] == 31536100, m
print("[roles] twelve-month declaration metric OK")
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
print("[roles] absent authorization is explicit unknown")
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
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" roles --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" roles --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_src" "$rc_decls" "$rc_id" "$rc_auth" "$rc_json" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed roles input must exit 4 (got $rc)"
done

echo "test_roles_cli OK"
