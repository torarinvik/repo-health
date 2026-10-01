#!/usr/bin/env bash
# tests/test_parser_diff_cli.sh — M03-10 retained parser-adoption comparison.
# It compares native/candidate graph snapshots without executing a resolver,
# classifies losses, and includes parser/configuration/visibility in the cache
# identity. Unsupported candidate output is retained as a distinct status.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T="/tmp/rh-parser-diff"

fail() { echo "[parser-diff] FAIL: $1" >&2; exit 1; }

echo "[parser-diff] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/packages/cargo-graph.golden.json" "$T/native.json"

echo "[parser-diff] equal snapshots match"
"$ROOT/build/rh_cli" parser-diff --native "$T/native.json" --candidate "$T/native.json" --out "$T/match.json" \
  --native-parser native-lock/1 --candidate-parser alt-lock/2 --config cargo-default --visibility public >/dev/null || fail "equal diff"
python3 - "$T/match.json" "$ROOT" <<'PY'
import glob, hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-parser-diff/1" and d["status"] == "match", d
assert d["summary"] == {"mismatches": 0, "mapping": 0, "context": 0, "parser_support": 0, "normalization": 0}, d["summary"]
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["coverage.parser_error_count"]["value"] == 0, metrics
assert metrics["coverage.mapping_conflict_count"]["value"] == 0, metrics
assert set(metrics) == {"coverage.parser_error_count", "coverage.mapping_conflict_count"}, metrics
definitions = {}
for path in glob.glob(sys.argv[2] + "/metrics/definitions/*.json"):
  definition = json.load(open(path))
  definitions[(definition["key"], definition["version"])] = definition
expected = {
  "coverage.parser_error_count": (
    ["native_dependency_graph", "candidate_dependency_graph"],
    "records",
    "none; parser-support mismatches retained by the selected differential run"),
  "coverage.mapping_conflict_count": (
    ["native_dependency_graph", "candidate_dependency_graph"],
    "assertions",
    "none; unmatched package, edge, or unresolved identities in the selected differential run"),
}
for metric in metrics.values():
  key = metric["key"]
  definition = definitions[(key, metric["version"])]
  inputs, unit, denominator = expected[key]
  assert definition["implementation_status"] == "implemented", (key, definition)
  assert definition["subject_kind"] == "project", (key, definition)
  assert definition["source_requirements"] == ["parser-diff"], (key, definition["source_requirements"])
  assert definition["inputs"] == inputs, (key, definition["inputs"])
  assert definition["output"] == {"type": "integer", "unit": unit}, (key, definition["output"])
  assert definition["denominator_rule"] == denominator, (key, definition["denominator_rule"])
  assert metric["status"] == "observed", metric
  assert type(metric["value"]) is int and metric["value"] >= 0, metric
  assert metric["evidence"] == ["parser-diff"], metric
  assert metric["quality_dimensions"] == {"completeness":"complete", "freshness":"unknown", "validity":"valid", "provenance":"evidence_backed"}, metric
print("[parser-diff] both emitted metric rows match catalog subjects, sources, inputs, types, units, and denominators")
assert d["parsers"] == {"native": "native-lock/1", "candidate": "alt-lock/2", "configuration": "cargo-default", "visibility": "public"}, d["parsers"]
assert len(d["cache_key"]) == 16, d
report = json.load(open(sys.argv[1] + ".transformations.json"))
native = open(sys.argv[1].rsplit("/", 1)[0] + "/native.json", "rb").read()
configuration = [b"native-lock/1", b"alt-lock/2", b"cargo-default", b"public"]
combined = str(len(native)).encode() + b":" + native + str(len(native)).encode() + b":" + native
config = b"".join(str(len(value)).encode() + b":" + value for value in configuration)
assert report["schema"] == "rh-adapter-transformation-report/1", report
assert report["adapter"] == "dependency-parser-differential", report
assert report["output_schema"] == "rh-parser-diff/1", report
assert report["source_input_sha256"] == hashlib.sha256(combined).hexdigest(), report
assert report["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), report
assert report["configuration_sha256"] == hashlib.sha256(config).hexdigest(), report
states = {field["state"] for field in report["fields"]}
assert {"preserved", "transformed", "unsupported", "discarded"} <= states, report
print("[parser-diff] equal snapshot + metadata OK")
PY

echo "[parser-diff] mapping/context/parser-support losses are classified"
python3 - "$T/native.json" "$T/candidate.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["nodes"][1]["name"] = "left-renamed"
d["nodes"][0]["dev"] = True
d["nodes"][3]["digest"] = False
d["unresolved"][0]["reason"] = "context"
d["nodes"].append({"id": 99, "name": "candidate-only", "version": "9.0.0", "source": "registry", "digest": False, "dev": False, "optional": False})
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" parser-diff --native "$T/native.json" --candidate "$T/candidate.json" --out "$T/different.json" \
  --native-parser native-lock/1 --candidate-parser alt-lock/2 --config cargo-default --visibility private >/dev/null || fail "different diff"
python3 - "$T/different.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "different", d
assert d["parsers"]["visibility"] == "private", d
assert d["summary"]["mapping"] >= 1, d["summary"]
assert d["summary"]["context"] >= 1, d["summary"]
assert d["summary"]["parser_support"] >= 1, d["summary"]
assert d["summary"]["normalization"] >= 2, d["summary"]
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["coverage.parser_error_count"]["value"] == d["summary"]["parser_support"], metrics
assert metrics["coverage.mapping_conflict_count"]["value"] == d["summary"]["mapping"], metrics
classes = {x["class"] for x in d["mismatches"]}
assert {"mapping", "context", "parser_support", "normalization"} <= classes, classes
print("[parser-diff] loss classes + visibility isolation OK")
PY

echo "[parser-diff] unsupported candidate is explicit and retained"
sed 's#rh-dep-graph/1#rh-dep-graph/2#' "$T/native.json" > "$T/unsupported.json"
set +e
"$ROOT/build/rh_cli" parser-diff --native "$T/native.json" --candidate "$T/unsupported.json" --out "$T/unsupported.out" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 3 ]] || fail "unsupported candidate must exit 3 (got $rc)"
python3 - "$T/unsupported.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "unsupported", d
assert "successful empty graph" in d["note"], d
assert d["summary"]["mismatches"] == 0, d
metrics = {row["key"]: row for row in d["metrics"]}
assert len(metrics) == 2, metrics
assert all(row["status"] == "unsupported" and row["value"] is None for row in metrics.values()), metrics
assert all(row["reason"] == d["reason"] and row["evidence"] == ["parser-diff"] for row in metrics.values()), metrics
assert all(row["quality_dimensions"]["validity"] == "unknown" for row in metrics.values()), metrics
report = json.load(open(sys.argv[1] + ".transformations.json"))
assert report["output_schema"] == "rh-parser-diff/1", report
assert any(field["state"] == "unsupported" for field in report["fields"]), report
print("[parser-diff] unsupported state OK")
PY

echo "[parser-diff] malformed native fails closed without output"
printf '{"schema":"rh-dep-graph/1","nodes":42}' > "$T/bad-native.json"
set +e
"$ROOT/build/rh_cli" parser-diff --native "$T/bad-native.json" --candidate "$T/native.json" --out "$T/bad.out" >/dev/null 2>&1
rc_bad=$?
set -e
[[ "$rc_bad" -eq 4 ]] || fail "malformed native must exit 4 (got $rc_bad)"
[[ ! -f "$T/bad.out" ]] || fail "malformed native published output"

echo "test_parser_diff_cli OK"
