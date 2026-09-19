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
{"schema":"rh-identity-input/1","actor_count":4,"links":[{"a":0,"b":1,"state":"accepted","revision_added":1},{"a":1,"b":2,"state":"accepted","revision_added":2},{"a":3,"b":0,"state":"rejected","revision_added":3}],"actor_kinds":["human","human","unresolved","bot_known"],"actors":[{"source":"github","source_instance":"github.com/acme","native_object_id":"repo-1","display_name":"shared","aliases":[{"value":"old-name","observed_at":100}]},{"source":"github","source_instance":"github.com/acme","native_object_id":"repo-2","display_name":"other","aliases":[]},{"source":"gitlab","source_instance":"gitlab.com/acme","native_object_id":"repo-1","display_name":"shared","aliases":[]},{"source":"github","source_instance":"github.com/acme","native_object_id":"bot-1","display_name":"bot","aliases":[]}]}
JSON
cat > "$T/b.json" <<'JSON'
{"schema":"rh-identity-input/1","actor_count":4,"links":[{"a":0,"b":1,"state":"accepted","revision_added":1},{"a":1,"b":2,"state":"revoked","revision_added":4},{"a":3,"b":0,"state":"rejected","revision_added":3}]}
JSON

"$ROOT/build/rh_cli" identity --input "$T/a.json" --out "$T/a.out" >/dev/null || fail "A run"
python3 - "$T/a.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-identity-result/1", d
assert d["actor_count"] == 4 and d["identity_revision"] == 2, d
assert d["cluster_count"] == 2, d
assert d["clusters"] == [[0, 1, 2], [3]], d["clusters"]
assert d["cluster_id_by_actor"] == [0, 0, 0, 3], d["cluster_id_by_actor"]
assert d["actor_kinds"] == {"human": 2, "bot_known": 1, "unresolved": 1}, d["actor_kinds"]
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
assert d["clusters"] == [[0], [1], [2]], d["clusters"]
print("[identity] no-op links OK")
PY

echo "[identity] determinism"
"$ROOT/build/rh_cli" identity --input "$T/a.json" --out "$T/a2.out" >/dev/null || fail "rerun"
cmp -s "$T/a.out" "$T/a2.out" || fail "identity output not deterministic"

echo "[identity] malformed input fails closed"
set +e
printf '{"schema":"rh-identity-input/2","actor_count":1,"links":[]}' > "$T/badschema.json"
"$ROOT/build/rh_cli" identity --input "$T/badschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":1,"state":"maybe"}]}' > "$T/badstate.json"
"$ROOT/build/rh_cli" identity --input "$T/badstate.json" --out "$T/x" >/dev/null 2>&1; rc_state=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":5,"state":"accepted"}]}' > "$T/badactor.json"
"$ROOT/build/rh_cli" identity --input "$T/badactor.json" --out "$T/x" >/dev/null 2>&1; rc_actor=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":1,"state":"accepted"}],"actor_kinds":["human","alien"]}' > "$T/badkind.json"
"$ROOT/build/rh_cli" identity --input "$T/badkind.json" --out "$T/x" >/dev/null 2>&1; rc_kind=$?
"$ROOT/build/rh_cli" identity --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_state" "$rc_actor" "$rc_kind" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed identity input must exit 4 (got $rc)"
done

echo "test_identity_cli OK"
