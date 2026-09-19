#!/usr/bin/env bash
# Provider permission imports retain authorization evidence and normalize
# GitHub/GitLab role vocabularies into the generic role input contract.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-roles-provider"
cd "$ROOT"

fail() { echo "[roles-provider] FAIL: $1" >&2; exit 1; }

echo "[roles-provider] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
mkdir -p "$T"

echo "[roles-provider] GitHub mapping"
"$ROOT/build/rh_cli" roles-import --input fixtures/roles/github-provider-input.json --out "$T/github.json" >/dev/null || fail "GitHub import"
python3 - "$T/github.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d == {
  "schema": "rh-roles-input/1",
  "authorization": {"state": "authorized"},
  "declarations": [
    {"actor_id": 7001, "role": "owner", "permission": 1, "source": "provider", "declared_at": 1700000000},
    {"actor_id": 7002, "role": "maintainer", "permission": 2, "source": "provider", "declared_at": 1700000000},
    {"actor_id": 7003, "role": "triager", "permission": 4, "source": "provider", "declared_at": 1700000000},
    {"actor_id": 7004, "role": "member", "permission": 8, "source": "provider", "declared_at": 1700000000},
    {"actor_id": 7005, "role": "unknown", "permission": 0, "source": "provider", "declared_at": 1700000000},
  ],
}, d
print("[roles-provider] GitHub mapping + unknown role OK")
PY

echo "[roles-provider] GitLab mapping"
"$ROOT/build/rh_cli" roles-import --input fixtures/roles/gitlab-provider-input.json --out "$T/gitlab.json" >/dev/null || fail "GitLab import"
python3 - "$T/gitlab.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert [x["role"] for x in d["declarations"]] == ["owner", "maintainer", "member", "unknown"], d
assert [x["permission"] for x in d["declarations"]] == [1, 2, 8, 0], d
assert all(x["source"] == "provider" for x in d["declarations"]), d
print("[roles-provider] GitLab access levels OK")
PY

echo "[roles-provider] unauthorized capture withholds declarations"
cat > "$T/unauthorized.json" <<'JSON'
{"schema":"rh-provider-roles-input/1","provider":"github","authorization":{"state":"unauthorized"},"captured_at":1700000000,"members":[{"id":9001,"permission":"admin"}]}
JSON
"$ROOT/build/rh_cli" roles-import --input "$T/unauthorized.json" --out "$T/unauthorized-out.json" >/dev/null || fail "unauthorized import"
python3 - "$T/unauthorized-out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["authorization"] == {"state": "unauthorized"}, d
assert d["declarations"] == [], d
print("[roles-provider] unauthorized state is fail-closed")
PY

echo "[roles-provider] deterministic replay"
"$ROOT/build/rh_cli" roles-import --input fixtures/roles/github-provider-input.json --out "$T/github-2.json" >/dev/null || fail "replay"
cmp -s "$T/github.json" "$T/github-2.json" || fail "output not deterministic"

echo "[roles-provider] malformed input fails closed"
set +e
printf '{"schema":"rh-provider-roles-input/2","provider":"github","captured_at":1,"members":[]}' > "$T/bad-schema.json"
"$ROOT/build/rh_cli" roles-import --input "$T/bad-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-provider-roles-input/1","provider":"bitbucket","captured_at":1,"members":[]}' > "$T/bad-provider.json"
"$ROOT/build/rh_cli" roles-import --input "$T/bad-provider.json" --out "$T/x" >/dev/null 2>&1; rc_provider=$?
printf '{"schema":"rh-provider-roles-input/1","provider":"github","captured_at":1,"members":[{"id":-1}]}' > "$T/bad-id.json"
"$ROOT/build/rh_cli" roles-import --input "$T/bad-id.json" --out "$T/x" >/dev/null 2>&1; rc_id=$?
set -e
for rc in "$rc_schema" "$rc_provider" "$rc_id"; do
  [[ "$rc" -eq 4 ]] || fail "malformed provider input must exit 4 (got $rc)"
done

echo "test_roles_provider_cli OK"
