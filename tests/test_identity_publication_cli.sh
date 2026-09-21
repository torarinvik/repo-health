#!/usr/bin/env bash
# tests/test_identity_publication_cli.sh — M04-09 project-focused identity
# publication: raw source identities stay restricted, aggregates are useful,
# correction requests retain a review channel, and malformed/publication-scope
# inputs fail closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-identity-publication"

fail() { echo "[identity-publication] FAIL: $1" >&2; exit 1; }

echo "[identity-publication] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/input.json" <<'JSON'
{"schema":"rh-identity-publication-input/1","project_id":"example-parser","publication_scope":"public","actor_count":5,"links":[{"a":0,"b":1,"state":"accepted","revision_added":1},{"a":1,"b":2,"state":"accepted","revision_added":2},{"a":3,"b":0,"state":"rejected","revision_added":3}],"actor_kinds":["human","human","unresolved","bot_known","service_known"],"correction_requests":[{"id":"c1","state":"open"},{"id":"c2","state":"accepted"},{"id":"c3","state":"rejected"},{"id":"c4","state":"withdrawn"}],"restricted_actor_metadata":[{"source_instance":"forge.example","native_object_id":"account-1","display_name":"Alice","aliases":["alice@example"]}]}
JSON

"$ROOT/build/rh_cli" identity-publish --input "$T/input.json" --out "$T/out.json" >/dev/null || fail "publication run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-identity-publication-result/1", d
assert d["project_id"] == "example-parser", d
assert d["publication_scope"] == "project" and d["raw_identity"] == "restricted", d
assert d["actor_count"] == 5 and d["identity_revision"] == 2 and d["cluster_count"] == 3, d
assert d["cluster_size_histogram"] == [{"size": 3, "clusters": 1}, {"size": 1, "clusters": 2}], d
assert d["actor_kinds"] == {"human": 2, "bot_known": 1, "service_known": 1, "unresolved": 1}, d
assert d["corrections"] == {"open": 1, "accepted": 1, "rejected": 1, "withdrawn": 1}, d
assert d["correction_channel"] == "project-owner-review" and d["personal_leaderboard"] is False, d
text = open(sys.argv[1]).read()
for secret in ("Alice", "account-1", "alice@example", "source_instance", "native_object_id", "cluster_id_by_actor"):
    assert secret not in text, (secret, text)
assert "project-scoped aggregates only" in d["note"], d
print("[identity-publication] restricted raw identity + aggregate contract OK")
PY

echo "[identity-publication] determinism"
"$ROOT/build/rh_cli" identity-publish --input "$T/input.json" --out "$T/out-2.json" >/dev/null || fail "repeat publication"
cmp -s "$T/out.json" "$T/out-2.json" || fail "publication output not deterministic"

cat > "$T/no-kinds.json" <<'JSON'
{"schema":"rh-identity-publication-input/1","project_id":"no-kinds","publication_scope":"public","actor_count":2,"links":[]}
JSON
"$ROOT/build/rh_cli" identity-publish --input "$T/no-kinds.json" --out "$T/no-kinds.out" >/dev/null || fail "unknown-kind publication"
python3 - "$T/no-kinds.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["actor_kinds"] == {"human": 0, "bot_known": 0, "service_known": 0, "unresolved": 2}, d
assert d["cluster_size_histogram"] == [{"size": 1, "clusters": 2}], d
print("[identity-publication] unknown kinds stay unresolved")
PY

echo "[identity-publication] malformed inputs fail closed"
set +e
printf '%s' '{"schema":"rh-identity-publication-input/2","project_id":"x","publication_scope":"public","actor_count":0,"links":[]}' > "$T/bad-schema.json"
"$ROOT/build/rh_cli" identity-publish --input "$T/bad-schema.json" --out "$T/bad-schema.out" >/dev/null 2>&1; rc_schema=$?
printf '%s' '{"schema":"rh-identity-publication-input/1","project_id":"x","publication_scope":"tenant-private","actor_count":0,"links":[]}' > "$T/bad-scope.json"
"$ROOT/build/rh_cli" identity-publish --input "$T/bad-scope.json" --out "$T/bad-scope.out" >/dev/null 2>&1; rc_scope=$?
printf '%s' '{"schema":"rh-identity-publication-input/1","project_id":"x","publication_scope":"public","actor_count":2,"links":[{"a":0,"b":9,"state":"accepted"}]}' > "$T/bad-link.json"
"$ROOT/build/rh_cli" identity-publish --input "$T/bad-link.json" --out "$T/bad-link.out" >/dev/null 2>&1; rc_link=$?
printf '%s' '{"schema":"rh-identity-publication-input/1","project_id":"x","publication_scope":"public","actor_count":1,"links":[],"correction_requests":[{"id":"same","state":"open"},{"id":"same","state":"accepted"}]}' > "$T/bad-duplicate.json"
"$ROOT/build/rh_cli" identity-publish --input "$T/bad-duplicate.json" --out "$T/bad-duplicate.out" >/dev/null 2>&1; rc_duplicate=$?
set -e
for rc in "$rc_schema" "$rc_scope" "$rc_link" "$rc_duplicate"; do
    [[ "$rc" -eq 4 ]] || fail "malformed publication must exit 4 (got $rc)"
done
for path in "$T/bad-schema.out" "$T/bad-scope.out" "$T/bad-link.out" "$T/bad-duplicate.out"; do
    [[ ! -e "$path" ]] || fail "failed publication wrote partial output: $path"
done

echo "test_identity_publication_cli OK"
