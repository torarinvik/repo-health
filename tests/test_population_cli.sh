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
{"schema":"rh-population-input/1","focal_package":"acme-core","version_policy":"latest-published","discovery_source":"local-reverse-index","discovery_mode":"historical","discovery_as_of":1700000000,"page_limit":100,"truncated":true,"provider_status":"rate_limit","replay_attempts":2,"mapping_revision":4,"deduplication_unit":"accepted-project-family","metric_definitions":[{"key":"history.months_active","version":"1"},{"key":"review.coverage","version":"2"}],"dependents":[{"id":"repo-a","family":"family-a","package":"acme-core","version":"1.2.0","relation":"direct","published_packages":["acme-core","acme-cli"],"path_witness":["app","acme-core"],"metrics":[{"key":"history.months_active","version":"1","status":"observed","value":12,"policy":"pass"},{"key":"review.coverage","version":"2","status":"unknown","value":null,"policy":"unknown"}]},{"id":"repo-b","family":"family-a","package":"acme-core","version":"1.1.0","relation":"transitive","path_witness":["tool","dep","acme-core"],"metrics":[{"key":"history.months_active","version":"1","status":"partial","value":null,"policy":"unknown"},{"key":"review.coverage","version":"2","status":"observed","value":3,"policy":"fail"}]},{"id":"repo-c","family":"family-c","package":"acme-core","version":"1.0.0","relation":"direct","path_witness":["service","acme-core"],"metrics":[{"key":"history.months_active","version":"1","status":"unavailable","value":null,"policy":"unknown"},{"key":"review.coverage","version":"2","status":"observed","value":5,"policy":"pass"}]}],"unresolved":[{"package":"unknown-pkg","reason":"mapping review required"}]}
JSON
"$ROOT/build/rh_cli" population --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "population run"
python3 - "$T/out.json" "$T/in.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-population-result/1", d
assert d["discovery"]["truncated"] is True and d["discovery"]["page_limit"] == 100, d
assert d["discovery"]["provider_status"] == "rate_limit" and d["discovery"]["replay_attempts"] == 2, d
assert d["population"] == {"selected_dependents": 3, "distinct_families": 2, "unresolved": 1}, d
summary = {m["key"]: m for m in d["summary_metrics"]}
assert summary["population.selected_dependent_count"]["value"] == 3, summary
assert summary["population.distinct_family_count"]["value"] == 2, summary
assert summary["population.unresolved_mapping_count"]["value"] == 1, summary
assert d["dependents"][1]["path_witness"] == ["tool", "dep", "acme-core"], d
assert d["dependents"][0]["published_package_count"] == 2, d
assert d["population"]["selected_dependents"] == len(d["dependents"]), d
by = {(m["key"], m["version"]): m for m in d["metrics"]}
assert by[("history.months_active", "1")]["observed"] == 1, by
assert by[("history.months_active", "1")]["partial"] == 1, by
assert by[("history.months_active", "1")]["unavailable"] == 1, by
assert by[("review.coverage", "2")]["distribution"] == {"count": 2, "sum": 8, "min": 3, "max": 5}, by
assert by[("review.coverage", "2")]["policy_counts"] == {"pass": 1, "fail": 1, "unknown": 1}, by
assert "counts projects once" in d["note"], d
report = json.load(open(sys.argv[1] + ".transformations.json"))
assert report["schema"] == "rh-adapter-transformation-report/1", report
assert report["adapter"] == "focal-library-population", report
assert report["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), report
assert report["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), report
assert report["configuration_sha256"] == hashlib.sha256(b"repo-health/focal-library-population/1").hexdigest(), report
assert all(field["state"] in {"preserved", "transformed", "inferred", "discarded", "unsupported", "unknown"} for field in report["fields"]), report
print("[population] bounded selection + per-metric coverage + witnesses OK")
PY

echo "[population] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" population --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "population output not deterministic"
cmp -s "$T/out.json.transformations.json" "$T/out2.json.transformations.json" || fail "population transformation report not deterministic"
set +e
sed 's/"truncated":true/"truncated":"yes"/' "$T/in.json" > "$T/bad-bool.json"
"$ROOT/build/rh_cli" population --input "$T/bad-bool.json" --out "$T/x" >/dev/null 2>&1; rc_bool=$?
sed 's/"mapping_revision":4/"mapping_revision":-1/' "$T/in.json" > "$T/bad-revision.json"
"$ROOT/build/rh_cli" population --input "$T/bad-revision.json" --out "$T/x" >/dev/null 2>&1; rc_revision=$?
sed 's/"path_witness":\["service","acme-core"\]/"path_witness":[]/' "$T/in.json" > "$T/bad-path.json"
"$ROOT/build/rh_cli" population --input "$T/bad-path.json" --out "$T/x" >/dev/null 2>&1; rc_path=$?
sed 's/"path_witness":\["service","acme-core"\]/"path_witness":["service","other-package"]/' "$T/in.json" > "$T/bad-path-target.json"
"$ROOT/build/rh_cli" population --input "$T/bad-path-target.json" --out "$T/x" >/dev/null 2>&1; rc_path_target=$?
sed 's/"id":"repo-c"/"id":"repo-a"/' "$T/in.json" > "$T/bad-duplicate.json"
"$ROOT/build/rh_cli" population --input "$T/bad-duplicate.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate=$?
sed 's/"status":"unknown","value":null/"status":"unknown","value":1/' "$T/in.json" > "$T/bad-value.json"
"$ROOT/build/rh_cli" population --input "$T/bad-value.json" --out "$T/x" >/dev/null 2>&1; rc_value=$?
sed 's/"status":"unknown","value":null,"policy":"unknown"/"status":"unknown","value":null,"policy":"pass"/' "$T/in.json" > "$T/bad-policy-state.json"
"$ROOT/build/rh_cli" population --input "$T/bad-policy-state.json" --out "$T/x" >/dev/null 2>&1; rc_policy_state=$?
python3 - "$T/in.json" "$T/bad-duplicate-root-key.json" "$T/bad-duplicate-cell-key.json" <<'PY'
import sys
source = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(source.replace('"truncated":true', '"truncated":true,"truncated":false', 1))
open(sys.argv[3], "w").write(source.replace('"status":"unknown","value":null', '"status":"unknown","status":"observed","value":null', 1))
PY
"$ROOT/build/rh_cli" population --input "$T/bad-duplicate-root-key.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate_root=$?
"$ROOT/build/rh_cli" population --input "$T/bad-duplicate-cell-key.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate_cell=$?
sed 's/"provider_status":"rate_limit"/"provider_status":"mystery"/' "$T/in.json" > "$T/bad-provider.json"
"$ROOT/build/rh_cli" population --input "$T/bad-provider.json" --out "$T/x" >/dev/null 2>&1; rc_provider=$?
sed 's/"relation":"direct"/"relation":"indirect"/' "$T/in.json" > "$T/bad-relation.json"
"$ROOT/build/rh_cli" population --input "$T/bad-relation.json" --out "$T/x" >/dev/null 2>&1; rc_relation=$?
sed 's/"path_witness":\["tool","dep","acme-core"\]/"path_witness":["tool","acme-core"]/' "$T/in.json" > "$T/bad-path-relation.json"
"$ROOT/build/rh_cli" population --input "$T/bad-path-relation.json" --out "$T/x" >/dev/null 2>&1; rc_path_relation=$?
sed 's/"value":5/"value":-1/' "$T/in.json" > "$T/bad-negative-value.json"
"$ROOT/build/rh_cli" population --input "$T/bad-negative-value.json" --out "$T/x" >/dev/null 2>&1; rc_negative=$?
python3 - "$T/in.json" "$T/bad-overflow.json" "$T/bad-dependent-cap.json" "$T/bad-metric-cap.json" <<'PY'
import copy, json, sys
base = json.load(open(sys.argv[1]))
overflow = copy.deepcopy(base)
overflow["dependents"][1]["metrics"][1]["value"] = 9223372036854775807
overflow["dependents"][2]["metrics"][1]["value"] = 1
json.dump(overflow, open(sys.argv[2], "w"), separators=(",", ":"))
too_many = copy.deepcopy(base)
template = too_many["dependents"][0]
too_many["dependents"] = [dict(template, id=f"repo-{i}", family=f"family-{i}") for i in range(1001)]
json.dump(too_many, open(sys.argv[3], "w"), separators=(",", ":"))
too_many_metrics = copy.deepcopy(base)
too_many_metrics["metric_definitions"] = [{"key":f"metric.{i}", "version":"1"} for i in range(64)]
json.dump(too_many_metrics, open(sys.argv[4], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" population --input "$T/bad-overflow.json" --out "$T/x" >/dev/null 2>&1; rc_overflow=$?
"$ROOT/build/rh_cli" population --input "$T/bad-dependent-cap.json" --out "$T/x" >/dev/null 2>&1; rc_dependent_cap=$?
"$ROOT/build/rh_cli" population --input "$T/bad-metric-cap.json" --out "$T/x" >/dev/null 2>&1; rc_metric_cap=$?
set -e
[[ "$rc_bool" -eq 4 && "$rc_revision" -eq 4 && "$rc_path" -eq 4 && "$rc_path_target" -eq 4 && "$rc_duplicate" -eq 4 && "$rc_value" -eq 4 && "$rc_policy_state" -eq 4 && "$rc_duplicate_root" -eq 4 && "$rc_duplicate_cell" -eq 4 && "$rc_provider" -eq 4 && "$rc_relation" -eq 4 && "$rc_path_relation" -eq 4 && "$rc_negative" -eq 4 && "$rc_overflow" -eq 4 && "$rc_dependent_cap" -eq 4 && "$rc_metric_cap" -eq 4 ]] || fail "invalid population must exit 4 (got $rc_bool/$rc_revision/$rc_path/$rc_path_target/$rc_duplicate/$rc_value/$rc_policy_state/$rc_duplicate_root/$rc_duplicate_cell/$rc_provider/$rc_relation/$rc_path_relation/$rc_negative/$rc_overflow/$rc_dependent_cap/$rc_metric_cap)"

echo "test_population_cli OK"
