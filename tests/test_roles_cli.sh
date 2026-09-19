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
{"schema":"rh-roles-input/1","declarations":[{"actor_id":1,"role":"owner","permission":1,"source":"provider","declared_at":100},{"actor_id":2,"role":"triager","permission":2,"source":"file","declared_at":100,"revoked_at":200},{"actor_id":3,"role":"member","permission":4,"source":"operator","declared_at":300},{"actor_id":4,"role":"wizard","permission":8,"source":"file","declared_at":100}],"queries":[{"actor_id":1,"as_of":150},{"actor_id":2,"as_of":150},{"actor_id":2,"as_of":250},{"actor_id":3,"as_of":250},{"actor_id":3,"as_of":350},{"actor_id":4,"as_of":150}],"permission_queries":[{"actor_id":1,"perm_bit":1,"as_of":150},{"actor_id":1,"perm_bit":2,"as_of":150}]}
JSON
"$ROOT/build/rh_cli" roles --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-roles-result/1", d
assert d["declaration_count"] == 4, d
assert d["source_tally"] == {"provider": 1, "file": 2, "operator": 1}, d["source_tally"]
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
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" roles --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" roles --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_src" "$rc_decls" "$rc_id" "$rc_json" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed roles input must exit 4 (got $rc)"
done

echo "test_roles_cli OK"
