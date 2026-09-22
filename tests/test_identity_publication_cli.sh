#!/usr/bin/env bash
# tests/test_identity_publication_cli.sh — M04-04/09 project-focused identity
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
{"schema":"rh-identity-publication-input/1","project_id":"example-parser","publication_scope":"public","actor_count":5,"links":[{"a":0,"b":1,"state":"accepted","revision_added":1},{"a":1,"b":2,"state":"accepted","revision_added":2},{"a":3,"b":0,"state":"rejected","revision_added":3}],"actor_kinds":["human","human","unresolved","bot_known","service_known"],"actor_kind_sources":["provider","provider","unknown","provider","project"],"actor_kind_observed_at":[1700000000,null,1700000200,1700000300,1700000400],"actor_kind_evidence_refs":["private:evidence-path-01",null,"private:evidence-path-03","private:evidence-path-04","private:evidence-path-05"],"correction_requests":[{"id":"c1","state":"open"},{"id":"c2","state":"accepted"},{"id":"c3","state":"rejected"},{"id":"c4","state":"withdrawn"}],"restricted_actor_metadata":[{"source_instance":"forge.example","native_object_id":"account-1","display_name":"Alice","aliases":["alice@example"]}]}
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
assert d["actor_kind_source_counts"] == {"provider": 3, "project": 1, "operator": 0, "unknown": 1}, d
assert d["actor_kind_observation_times"] == {"observed": 4, "unknown": 1}, d
assert d["actor_kind_evidence_references"] == {"present": 4, "unknown": 1}, d
assert d["corrections"] == {"open": 1, "accepted": 1, "rejected": 1, "withdrawn": 1}, d
assert d["correction_channel"] == "project-owner-review" and d["personal_leaderboard"] is False, d
text = open(sys.argv[1]).read()
for secret in ("Alice", "account-1", "alice@example", "source_instance", "native_object_id", "cluster_id_by_actor"):
    assert secret not in text, (secret, text)
for secret in ("1700000000", "1700000400", "private:evidence-path-01", "private:evidence-path-05"):
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
assert d["actor_kind_source_counts"] == {"provider": 0, "project": 0, "operator": 0, "unknown": 2}, d
assert d["cluster_size_histogram"] == [{"size": 1, "clusters": 2}], d
print("[identity-publication] unknown kinds stay unresolved")
PY

echo "[identity-publication] effective-dated actor kinds resolve at the requested time"
python3 - "$T/input.json" "$T/history.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["as_of"] = 200
d["actor_kind_history"] = [
    {"actor_id": 0, "kind": "human", "valid_from": 100, "valid_until": 200, "source": "provider"},
    {"actor_id": 0, "kind": "bot_known", "valid_from": 200, "valid_until": None, "source": "provider"},
    {"actor_id": 1, "kind": "human", "valid_from": 100, "valid_until": None, "source": "provider"},
    {"actor_id": 1, "kind": "service_known", "valid_from": 150, "valid_until": 250, "source": "operator"},
    {"actor_id": 2, "kind": "bot_known", "valid_from": 100, "valid_until": 150, "source": "provider"},
    {"actor_id": 3, "kind": "service_known", "valid_from": 100, "valid_until": None, "source": "project"},
]
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" identity-publish --input "$T/history.json" --out "$T/history.out" >/dev/null || fail "effective-dated identity publication"
python3 - "$T/history.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["actor_kind_history"] == {"as_of": 200, "assertions": 6, "conflicted_actors": 1, "source_conflicts": 1}, d
assert d["actor_kinds"] == {"human": 0, "bot_known": 1, "service_known": 2, "unresolved": 2}, d
assert d["actor_kind_source_counts"] == {"provider": 1, "project": 2, "operator": 0, "unknown": 2}, d
assert "actor_id" not in open(sys.argv[1]).read(), open(sys.argv[1]).read()
print("[identity-publication] as-of history, half-open boundaries, and conflicts OK")
PY
python3 - "$T/history.json" "$T/history-earlier.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["as_of"] = 150
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" identity-publish --input "$T/history-earlier.json" --out "$T/history-earlier.out" >/dev/null || fail "earlier effective-date publication"
python3 - "$T/history-earlier.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["actor_kind_history"]["as_of"] == 150, d
assert d["actor_kinds"] == {"human": 1, "bot_known": 0, "service_known": 2, "unresolved": 2}, d
print("[identity-publication] historical as-of recomputes actor-kind aggregates")
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
printf '%s' '{"schema":"rh-identity-publication-input/1","project_id":"x","publication_scope":"public","actor_count":1,"links":[],"actor_kinds":["human"],"actor_kind_observed_at":[-1]}' > "$T/bad-kind-time.json"
"$ROOT/build/rh_cli" identity-publish --input "$T/bad-kind-time.json" --out "$T/bad-kind-time.out" >/dev/null 2>&1; rc_kind_time=$?
printf '%s' '{"schema":"rh-identity-publication-input/1","project_id":"x","publication_scope":"public","actor_count":2,"links":[],"actor_kinds":["human","unresolved"],"actor_kind_observed_at":[1]}' > "$T/bad-kind-time-count.json"
"$ROOT/build/rh_cli" identity-publish --input "$T/bad-kind-time-count.json" --out "$T/bad-kind-time-count.out" >/dev/null 2>&1; rc_kind_time_count=$?
printf '%s' '{"schema":"rh-identity-publication-input/1","project_id":"x","publication_scope":"public","actor_count":2,"links":[],"actor_kinds":["human","unresolved"],"actor_kind_evidence_refs":["evidence:one"]}' > "$T/bad-kind-ref-count.json"
"$ROOT/build/rh_cli" identity-publish --input "$T/bad-kind-ref-count.json" --out "$T/bad-kind-ref-count.out" >/dev/null 2>&1; rc_kind_ref_count=$?
printf '%s' '{"schema":"rh-identity-publication-input/1","project_id":"x","publication_scope":"public","actor_count":1,"links":[],"actor_kinds":["human"],"actor_kind_evidence_refs":[""]}' > "$T/bad-kind-ref.json"
"$ROOT/build/rh_cli" identity-publish --input "$T/bad-kind-ref.json" --out "$T/bad-kind-ref.out" >/dev/null 2>&1; rc_kind_ref=$?
printf '%s' '{"schema":"rh-identity-publication-input/1","project_id":"x","publication_scope":"public","actor_count":1,"links":[],"actor_kind_evidence_refs":["evidence:one"]}' > "$T/kind-ref-without-kind.json"
"$ROOT/build/rh_cli" identity-publish --input "$T/kind-ref-without-kind.json" --out "$T/kind-ref-without-kind.out" >/dev/null 2>&1; rc_kind_ref_without_kind=$?
python3 - "$T/history.json" "$T/history-no-as-of.json" "$T/history-unsorted.json" "$T/history-empty-interval.json" "$T/history-missing-until.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
no_as_of = dict(d); no_as_of.pop("as_of")
unsorted = dict(d); unsorted["actor_kind_history"] = list(reversed(d["actor_kind_history"]))
empty_interval = dict(d); empty_interval["actor_kind_history"] = list(d["actor_kind_history"])
empty_interval["actor_kind_history"][0]["valid_until"] = 100
missing_until = dict(d); missing_until["actor_kind_history"] = list(d["actor_kind_history"])
missing_until["actor_kind_history"][0].pop("valid_until")
for value, path in zip((no_as_of, unsorted, empty_interval, missing_until), sys.argv[2:]):
    json.dump(value, open(path, "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" identity-publish --input "$T/history-no-as-of.json" --out "$T/history-no-as-of.out" >/dev/null 2>&1; rc_history_no_as_of=$?
"$ROOT/build/rh_cli" identity-publish --input "$T/history-unsorted.json" --out "$T/history-unsorted.out" >/dev/null 2>&1; rc_history_unsorted=$?
"$ROOT/build/rh_cli" identity-publish --input "$T/history-empty-interval.json" --out "$T/history-empty-interval.out" >/dev/null 2>&1; rc_history_empty_interval=$?
"$ROOT/build/rh_cli" identity-publish --input "$T/history-missing-until.json" --out "$T/history-missing-until.out" >/dev/null 2>&1; rc_history_missing_until=$?
set -e
for rc in "$rc_schema" "$rc_scope" "$rc_link" "$rc_duplicate" "$rc_kind_time" "$rc_kind_time_count" "$rc_kind_ref_count" "$rc_kind_ref" "$rc_kind_ref_without_kind" "$rc_history_no_as_of" "$rc_history_unsorted" "$rc_history_empty_interval" "$rc_history_missing_until"; do
    [[ "$rc" -eq 4 ]] || fail "malformed publication must exit 4 (got $rc)"
done
for path in "$T/bad-schema.out" "$T/bad-scope.out" "$T/bad-link.out" "$T/bad-duplicate.out" "$T/bad-kind-time.out" "$T/bad-kind-time-count.out" "$T/bad-kind-ref-count.out" "$T/bad-kind-ref.out" "$T/kind-ref-without-kind.out" "$T/history-no-as-of.out" "$T/history-unsorted.out" "$T/history-empty-interval.out" "$T/history-missing-until.out"; do
    [[ ! -e "$path" ]] || fail "failed publication wrote partial output: $path"
done

echo "test_identity_publication_cli OK"
