#!/usr/bin/env bash
# tests/test_experimental_cli.sh — M11 experimental isolation execution path
# (R024): `rh_cli experimental` turns rh-experimental-input/1 into
# rh-experimental-result/1. A spec is admissible only when opt-in, in wave G,
# costed, and explicitly limited; the sample discontinuity metric is an
# observable horizon outcome, labelled experimental, with censored subjects
# excluded from the denominator and zero-observable reported not_applicable.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-experimental"

fail() { echo "[experimental] FAIL: $1" >&2; exit 1; }

echo "[experimental] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/m11/experimental-input.json" "$T/in.json"
"$ROOT/build/rh_cli" experimental --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
cmp "$ROOT/fixtures/m11/experimental-result.json" "$T/out.json" || fail "experimental golden output mismatch"
cmp "$ROOT/fixtures/m11/experimental-result.transformations.json" "$T/out.json.transformations.json" || fail "experimental transformation golden mismatch"
python3 - "$T/in.json" "$T/out.json" "$T/out.json.transformations.json" <<'PY'
import json, sys
import hashlib
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
normalized = Path(sys.argv[2]).read_bytes()
d = json.loads(normalized)
assert d["schema"] == "rh-experimental-result/1", d
by = {s["key"]: s for s in d["specs"]}
assert by["discontinuity.no_qualifying_release_in_horizon"]["admissible"] is True, by
assert by["x.wrongwave"]["reason"] == "wrong-wave", by
assert by["x.nooptin"]["reason"] == "not-opt-in", by
assert by["x.nocost"]["reason"] == "no-cost", by
assert by["x.nolimits"]["reason"] == "no-limits", by
v = d["metric"]["value"]
assert d["metric"]["status"] == "observed", d["metric"]
assert v == {"with_release": 1, "without_release": 1, "censored": 1,
             "denominator": 2, "rate": {"num": 1, "den": 2}}, v
assert d["label"] == "experimental: observable horizon outcome, not a reliability or abandonment label", d["label"]
assert "excluded from the default policy path" in d["note"], d["note"]
assert "not a claim about the project" in d["note"], d["note"]
assert d["anomaly"]["key"] == "anomaly.cadence_deviation_windows", d["anomaly"]
assert d["anomaly"]["status"] == "observed", d["anomaly"]
assert d["anomaly"]["value"] == {"floor": 1, "baseline_mean": {"num": 18, "den": 2}, "finding_window_indices": [2, 4], "observed_window_count": 2, "censored_window_count": 1}, d["anomaly"]
assert "not a maliciousness" in d["anomaly"]["label"], d["anomaly"]
sidecar = json.load(open(sys.argv[3]))
assert sidecar["schema"] == "rh-adapter-transformation-report/1", sidecar
assert sidecar["adapter"] == "experimental-metric-evaluation", sidecar
assert sidecar["output_schema"] == "rh-experimental-result/1", sidecar
assert sidecar["source_input_sha256"] == hashlib.sha256(raw).hexdigest(), sidecar
assert sidecar["normalized_output_sha256"] == hashlib.sha256(normalized).hexdigest(), sidecar
assert sidecar["configuration_sha256"] == hashlib.sha256(b"repo-health/experimental-metric-evaluation/1").hexdigest(), sidecar
assert [field["state"] for field in sidecar["fields"]] == ["transformed", "transformed", "preserved", "transformed"], sidecar
print("[experimental] admissibility + outcome OK")
PY

echo "[experimental] all-censored -> not_applicable; no admissible spec -> unsupported"
printf '{"schema":"rh-experimental-input/1","specs":[{"key":"discontinuity.no_qualifying_release_in_horizon","wave":7,"cost":"low","limits":["a"],"opt_in":true}],"observations":[{"follow_up_complete":false,"qualifying_release_in_horizon":false}]}' > "$T/censored.json"
"$ROOT/build/rh_cli" experimental --input "$T/censored.json" --out "$T/censored.out" >/dev/null || fail "censored run"
printf '{"schema":"rh-experimental-input/1","specs":[{"key":"discontinuity.no_qualifying_release_in_horizon","wave":1,"cost":"low","limits":["a"],"opt_in":true}],"observations":[{"follow_up_complete":true,"qualifying_release_in_horizon":false}]}' > "$T/inadm.json"
"$ROOT/build/rh_cli" experimental --input "$T/inadm.json" --out "$T/inadm.out" >/dev/null || fail "inadm run"
python3 - "$T/censored.out" "$T/inadm.out" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
i = json.load(open(sys.argv[2]))
assert c["metric"]["status"] == "not_applicable" and c["metric"]["value"] is None, c["metric"]
assert i["metric"]["status"] == "unsupported" and i["metric"]["reason"] == "no-admissible-experimental-spec", i["metric"]
print("[experimental] not_applicable/unsupported OK")
PY

echo "[experimental] cadence anomaly distinguishes an unobservable baseline"
python3 - "$T/in.json" "$T/no-baseline.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for window in d["cadence"]["windows"][:2]:
    window["observable"] = False
json.dump(d, open(sys.argv[2], "w"))
PY
"$ROOT/build/rh_cli" experimental --input "$T/no-baseline.json" --out "$T/no-baseline.out" >/dev/null || fail "no cadence baseline"
python3 - "$T/no-baseline.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["anomaly"]["status"] == "not_applicable", d["anomaly"]
assert d["anomaly"]["reason"] == "no-observable-baseline-window", d["anomaly"]
PY

echo "[experimental] missing cadence evidence remains unsupported"
python3 - "$T/in.json" "$T/missing-cadence.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); del d["cadence"]
json.dump(d, open(sys.argv[2], "w"))
PY
"$ROOT/build/rh_cli" experimental --input "$T/missing-cadence.json" --out "$T/missing-cadence.out" >/dev/null || fail "missing cadence evidence"
python3 - "$T/missing-cadence.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["anomaly"]["status"] == "unsupported", d["anomaly"]
assert d["anomaly"]["reason"] == "missing-cadence-evidence", d["anomaly"]
PY

echo "[experimental] no observable evaluation windows remain not_applicable"
python3 - "$T/in.json" "$T/no-evaluation.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["cadence"]["windows"] = d["cadence"]["windows"][:2]
json.dump(d, open(sys.argv[2], "w"))
PY
"$ROOT/build/rh_cli" experimental --input "$T/no-evaluation.json" --out "$T/no-evaluation.out" >/dev/null || fail "no cadence evaluation windows"
python3 - "$T/no-evaluation.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["anomaly"]["status"] == "not_applicable", d["anomaly"]
assert d["anomaly"]["reason"] == "no-observable-evaluation-window", d["anomaly"]
PY

echo "[experimental] determinism + fail-closed negatives"
"$ROOT/build/rh_cli" experimental --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "experimental output not deterministic"
set +e
printf '{"schema":"rh-experimental-input/2","specs":[]}' > "$T/bschema.json"
"$ROOT/build/rh_cli" experimental --input "$T/bschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-experimental-input/1","specs":42}' > "$T/bsp.json"
"$ROOT/build/rh_cli" experimental --input "$T/bsp.json" --out "$T/x" >/dev/null 2>&1; rc_specs=$?
printf '{"schema":"rh-experimental-input/1","specs":[{"key":"k","wave":7,"cost":"free","limits":["a"],"opt_in":true}]}' > "$T/bcost.json"
"$ROOT/build/rh_cli" experimental --input "$T/bcost.json" --out "$T/x" >/dev/null 2>&1; rc_cost=$?
python3 - "$T/in.json" "$T" <<'PY'
import json, pathlib, sys
d = json.load(open(sys.argv[1])); d["cadence"]["windows"][0]["observable"] = "unknown"
pathlib.Path(sys.argv[2], "bad-cadence-bool.json").write_text(json.dumps(d))
d = json.load(open(sys.argv[1])); d["cadence"]["windows"][0]["count"] = -1
pathlib.Path(sys.argv[2], "bad-cadence-count.json").write_text(json.dumps(d))
d = json.load(open(sys.argv[1])); d["cadence"]["windows"][0]["count"] = 9223372036854775807; d["cadence"]["windows"][1]["count"] = 9223372036854775807
pathlib.Path(sys.argv[2], "overflow-cadence-baseline.json").write_text(json.dumps(d))
PY
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" experimental --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" experimental --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
"$ROOT/build/rh_cli" experimental --input "$T/bad-cadence-bool.json" --out "$T/x" >/dev/null 2>&1; rc_cadence_bool=$?
"$ROOT/build/rh_cli" experimental --input "$T/bad-cadence-count.json" --out "$T/x" >/dev/null 2>&1; rc_cadence_count=$?
"$ROOT/build/rh_cli" experimental --input "$T/overflow-cadence-baseline.json" --out "$T/x" >/dev/null 2>&1; rc_cadence_overflow=$?
set -e
for rc in "$rc_schema" "$rc_specs" "$rc_cost" "$rc_json" "$rc_missing" "$rc_cadence_bool" "$rc_cadence_count" "$rc_cadence_overflow"; do
  [[ "$rc" -eq 4 ]] || fail "malformed experimental input must exit 4 (got $rc)"
done

echo "test_experimental_cli OK"
