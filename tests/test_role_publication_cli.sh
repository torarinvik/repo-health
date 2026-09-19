#!/usr/bin/env bash
# tests/test_role_publication_cli.sh — restricted public role aggregates.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-role-publication"

fail() { echo "[role-publication] FAIL: $1" >&2; exit 1; }

echo "[role-publication] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-roles-input/1","authorization":{"state":"authorized"},"declarations":[{"actor_id":1,"role":"owner","permission":1,"source":"provider","declared_at":100},{"actor_id":2,"role":"triager","permission":2,"source":"file","declared_at":100,"revoked_at":200},{"actor_id":3,"role":"member","permission":4,"source":"operator","declared_at":300},{"actor_id":4,"role":"wizard","permission":8,"source":"file","declared_at":100}],"queries":[{"actor_id":1,"as_of":150},{"actor_id":2,"as_of":150},{"actor_id":2,"as_of":250},{"actor_id":3,"as_of":250},{"actor_id":3,"as_of":350},{"actor_id":4,"as_of":150}],"permission_queries":[{"actor_id":1,"perm_bit":1,"as_of":150},{"actor_id":1,"perm_bit":2,"as_of":150}]}
JSON
"$ROOT/build/rh_cli" roles-publish --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
d = json.loads(raw)
assert d["schema"] == "rh-role-publication-result/1", d
assert d["authorization_state"] == "authorized" and d["raw_identity"] == "restricted", d
assert d["role_counts"] == {"owner": 1, "maintainer": 0, "triager": 1, "member": 1, "unknown": 1}, d
assert d["source_tally"] == {"provider": 1, "file": 2, "operator": 1}, d
assert d["query_coverage"] == {"role_queries": 6, "known_role": 3, "unknown_role": 3, "permission_queries": 2, "granted_permission": 1}, d
assert d["personal_leaderboard"] is False, d
assert "actor_id" not in raw and "permission_documents" not in raw, raw
assert "separate from observed actions" in d["note"], d
print("[role-publication] restricted role and permission aggregates OK")
PY

echo "[role-publication] deterministic output"
"$ROOT/build/rh_cli" roles-publish --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "role publication output not deterministic"

echo "[role-publication] malformed input fails closed"
set +e
printf '{"schema":"rh-roles-input/2","declarations":[]}' > "$T/badschema.json"
"$ROOT/build/rh_cli" roles-publish --input "$T/badschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-roles-input/1","declarations":[{"actor_id":1,"role":"owner","permission":1,"source":"vibes","declared_at":1}]}' > "$T/badsource.json"
"$ROOT/build/rh_cli" roles-publish --input "$T/badsource.json" --out "$T/x" >/dev/null 2>&1; rc_source=$?
printf 'not json' > "$T/notjson"
"$ROOT/build/rh_cli" roles-publish --input "$T/notjson" --out "$T/x" >/dev/null 2>&1; rc_json=$?
set -e
for rc in "$rc_schema" "$rc_source" "$rc_json"; do
  [[ "$rc" -eq 4 ]] || fail "malformed role publication must exit 4 (got $rc)"
done

echo "test_role_publication_cli OK"
