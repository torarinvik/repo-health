#!/usr/bin/env bash
# tests/test_population_cli.sh — RP-06 bounded focal-library population.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-population"

fail() { echo "[population] FAIL: $1" >&2; exit 1; }

echo "[population] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-population-input/1","focal_package":"acme-core","version_policy":"latest-published","discovery_source":"local-reverse-index","discovery_mode":"historical","discovery_as_of":1700000000,"page_limit":100,"truncated":true,"mapping_revision":4,"deduplication_unit":"accepted-project-family","metric_definitions":[{"key":"history.months_active","version":"1"},{"key":"review.coverage","version":"2"}],"dependents":[{"id":"repo-a","family":"family-a","package":"acme-core","version":"1.2.0","relation":"direct","path_witness":["app","acme-core"],"metrics":[{"key":"history.months_active","version":"1","status":"observed","value":12,"policy":"pass"},{"key":"review.coverage","version":"2","status":"unknown","value":null,"policy":"unknown"}]},{"id":"repo-b","family":"family-a","package":"acme-core","version":"1.1.0","relation":"transitive","path_witness":["tool","dep","acme-core"],"metrics":[{"key":"history.months_active","version":"1","status":"partial","value":null,"policy":"unknown"},{"key":"review.coverage","version":"2","status":"observed","value":3,"policy":"fail"}]},{"id":"repo-c","family":"family-c","package":"acme-core","version":"1.0.0","relation":"direct","path_witness":["service","acme-core"],"metrics":[{"key":"history.months_active","version":"1","status":"unavailable","value":null,"policy":"unknown"},{"key":"review.coverage","version":"2","status":"observed","value":5,"policy":"pass"}]}],"unresolved":[{"package":"unknown-pkg","reason":"mapping review required"}]}
JSON
"$ROOT/build/rh_cli" population --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "population run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-population-result/1", d
assert d["discovery"]["truncated"] is True and d["discovery"]["page_limit"] == 100, d
assert d["population"] == {"selected_dependents": 3, "distinct_families": 2, "unresolved": 1}, d
assert d["dependents"][1]["path_witness"] == ["tool", "dep", "acme-core"], d
by = {(m["key"], m["version"]): m for m in d["metrics"]}
assert by[("history.months_active", "1")]["observed"] == 1, by
assert by[("history.months_active", "1")]["partial"] == 1, by
assert by[("history.months_active", "1")]["unavailable"] == 1, by
assert by[("review.coverage", "2")]["distribution"] == {"count": 2, "sum": 8, "min": 3, "max": 5}, by
assert by[("review.coverage", "2")]["policy_counts"] == {"pass": 1, "fail": 1, "unknown": 1}, by
assert "not imputed as zero" in d["note"], d
print("[population] bounded selection + per-metric coverage + witnesses OK")
PY

echo "[population] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" population --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "population output not deterministic"
set +e
sed 's/"truncated":true/"truncated":"yes"/' "$T/in.json" > "$T/bad-bool.json"
"$ROOT/build/rh_cli" population --input "$T/bad-bool.json" --out "$T/x" >/dev/null 2>&1; rc_bool=$?
sed 's/"mapping_revision":4/"mapping_revision":-1/' "$T/in.json" > "$T/bad-revision.json"
"$ROOT/build/rh_cli" population --input "$T/bad-revision.json" --out "$T/x" >/dev/null 2>&1; rc_revision=$?
sed 's/"path_witness":\["service","acme-core"\]/"path_witness":[]/' "$T/in.json" > "$T/bad-path.json"
"$ROOT/build/rh_cli" population --input "$T/bad-path.json" --out "$T/x" >/dev/null 2>&1; rc_path=$?
sed 's/"id":"repo-c"/"id":"repo-a"/' "$T/in.json" > "$T/bad-duplicate.json"
"$ROOT/build/rh_cli" population --input "$T/bad-duplicate.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate=$?
sed 's/"status":"unknown","value":null/"status":"unknown","value":1/' "$T/in.json" > "$T/bad-value.json"
"$ROOT/build/rh_cli" population --input "$T/bad-value.json" --out "$T/x" >/dev/null 2>&1; rc_value=$?
set -e
[[ "$rc_bool" -eq 4 && "$rc_revision" -eq 4 && "$rc_path" -eq 4 && "$rc_duplicate" -eq 4 && "$rc_value" -eq 4 ]] || fail "invalid population must exit 4 (got $rc_bool/$rc_revision/$rc_path/$rc_duplicate/$rc_value)"

echo "test_population_cli OK"
