#!/usr/bin/env bash
# tests/test_adoption_cli.sh — M05 staged adoption and censoring evidence.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-adoption"

fail() { echo "[adoption] FAIL: $1" >&2; exit 1; }

echo "[adoption] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-adoption-input/1","cutoff":1000,"adoptions":[{"first_seen":0,"confirmed_introduction":null,"confirmed_removal":null,"last_seen":900,"first_version_ord":1001001,"latest_version_ord":2000001,"supported_major":2},{"first_seen":100,"confirmed_introduction":200,"confirmed_removal":null,"last_seen":850,"first_version_ord":1001001,"latest_version_ord":1001000,"supported_major":2},{"first_seen":100,"confirmed_introduction":200,"confirmed_removal":500,"last_seen":500,"first_version_ord":1001001,"latest_version_ord":1001001,"supported_major":1},{"first_seen":null,"confirmed_introduction":null,"confirmed_removal":null},{"first_seen":null,"confirmed_introduction":null,"confirmed_removal":500},{"first_seen":null,"confirmed_introduction":0,"confirmed_removal":null,"last_seen":900}]}
JSON
"$ROOT/build/rh_cli" adoption --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "adoption run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-adoption-result/1", d
assert d["cutoff"] == 1000, d
assert [a["status"] for a in d["adoptions"]] == ["first_seen_only", "confirmed_introduced", "confirmed_removal", "unknown", "confirmed_removal", "confirmed_introduced"], d
assert d["adoptions"][0]["duration_censored"] is True, d
assert d["adoptions"][2]["duration_censored"] == 300, d
assert d["adoptions"][0]["last_seen"] == 900, d
assert d["adoptions"][0]["first_seen"] == 0, d
assert d["adoptions"][0]["observed_upgrade"] is True and d["adoptions"][0]["supported_line"] is True, d
assert d["adoptions"][1]["observed_upgrade"] is False and d["adoptions"][1]["supported_line"] is False, d
assert d["adoptions"][1]["duration_seconds"] == 650 and d["adoptions"][1]["duration_status"] == "right_censored", d
assert d["adoptions"][2]["duration_seconds"] == 300 and d["adoptions"][2]["duration_status"] == "confirmed_removal", d
assert d["adoptions"][3]["observed_upgrade"] is None and d["adoptions"][3]["supported_line"] is None, d
assert d["adoptions"][4]["duration_seconds"] is None and d["adoptions"][4]["duration_status"] == "unknown", d
assert d["adoptions"][5]["confirmed_introduction"] == 0 and d["adoptions"][5]["duration_seconds"] == 900, d
assert d["status_counts"] == {"unknown": 1, "first_seen_only": 1, "confirmed_introduced": 2, "confirmed_removal": 2}, d
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["adoption.unknown_count"]["value"] == 1, metrics
assert metrics["adoption.first_seen_only_count"]["value"] == 1, metrics
assert metrics["adoption.confirmed_introduction_count"]["value"] == 2, metrics
assert metrics["adoption.confirmed_removal_count"]["value"] == 2, metrics
for key, value in {
    "adoption.observed_upgrade_count": 1,
    "adoption.version_comparison_count": 3,
    "adoption.supported_line_adoption_count": 2,
    "adoption.supported_line_assessed_count": 3,
    "adoption.duration_confirmed_count": 1,
    "adoption.duration_right_censored_count": 2,
    "adoption.duration_unknown_count": 3,
}.items():
    assert metrics[key]["status"] == "observed" and metrics[key]["value"] == value, (key, metrics[key])
assert metrics["downstream_condition.supported_version_adoption_share"] == {
    "key": "downstream_condition.supported_version_adoption_share",
    "version": "1.0.0", "status": "observed", "value": {"num": 2, "den": 3},
    "evidence": ["adoption-input"]
}, metrics["downstream_condition.supported_version_adoption_share"]
assert d["evidence_counts"] == {"version_comparison": 3, "version_comparison_unknown": 3, "supported_line_assessed": 3, "supported_line_unknown": 3}, d
assert d["duration_counts"] == {"confirmed": 1, "right_censored": 2, "unknown": 3}, d
assert metrics["adoption.confirmed_duration_distribution"]["value"] == {
    "bucket_upper_seconds": [604799, 2591999, 7775999, 31535999, None], "counts": [1, 0, 0, 0, 0]
}, metrics["adoption.confirmed_duration_distribution"]
assert metrics["adoption.right_censored_duration_distribution"]["value"] == {
    "bucket_upper_seconds": [604799, 2591999, 7775999, 31535999, None], "counts": [2, 0, 0, 0, 0]
}, metrics["adoption.right_censored_duration_distribution"]
assert "not proof of migration" in d["note"], d
print("[adoption] staged states + right censoring OK")
PY

printf '{"schema":"rh-adoption-input/1","cutoff":1000,"adoptions":[]}' > "$T/empty.json"
"$ROOT/build/rh_cli" adoption --input "$T/empty.json" --out "$T/empty.out" >/dev/null || fail "empty adoption population"
python3 - "$T/empty.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["adoptions"] == [], d
for metric in d["metrics"]:
    if metric["key"].startswith("adoption.observed_upgrade") or metric["key"].startswith("adoption.version_comparison") or metric["key"].startswith("adoption.supported_line") or metric["key"].startswith("adoption.duration_") or metric["key"].endswith("duration_distribution") or metric["key"] == "downstream_condition.supported_version_adoption_share":
        assert metric["status"] == "not_applicable" and metric["value"] is None, metric
print("[adoption] empty evidence populations remain not_applicable")
PY

python3 - "$T/buckets.json" <<'PY'
import json, sys
edges = [0, 604799, 604800, 2592000, 7776000, 31536000]
doc = {"schema": "rh-adoption-input/1", "cutoff": 31536000,
       "adoptions": [{"first_seen": None, "confirmed_introduction": 0, "confirmed_removal": end} for end in edges]}
json.dump(doc, open(sys.argv[1], "w"))
PY
"$ROOT/build/rh_cli" adoption --input "$T/buckets.json" --out "$T/buckets.out" >/dev/null || fail "duration bucket boundaries"
python3 - "$T/buckets.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["adoption.confirmed_duration_distribution"]["value"] == {
    "bucket_upper_seconds": [604799, 2591999, 7775999, 31535999, None], "counts": [2, 1, 1, 1, 1]
}, m
print("[adoption] duration histogram boundaries include exact cutoffs")
PY

echo "[adoption] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" adoption --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "adoption output not deterministic"
set +e
sed 's/"confirmed_removal":500/"confirmed_removal":50/' "$T/in.json" > "$T/bad-order.json"
"$ROOT/build/rh_cli" adoption --input "$T/bad-order.json" --out "$T/x" >/dev/null 2>&1; rc_order=$?
sed 's/"cutoff":1000/"cutoff":150/' "$T/in.json" > "$T/bad-cutoff.json"
"$ROOT/build/rh_cli" adoption --input "$T/bad-cutoff.json" --out "$T/x" >/dev/null 2>&1; rc_cutoff=$?
sed 's/"last_seen":850/"last_seen":150/' "$T/in.json" > "$T/bad-last-seen.json"
"$ROOT/build/rh_cli" adoption --input "$T/bad-last-seen.json" --out "$T/x" >/dev/null 2>&1; rc_last=$?
sed 's/"latest_version_ord":2000001/"latest_version_ord":0/' "$T/in.json" > "$T/bad-version.json"
"$ROOT/build/rh_cli" adoption --input "$T/bad-version.json" --out "$T/x" >/dev/null 2>&1; rc_version=$?
printf '{"schema":"rh-adoption-input/1","cutoff":1,"adoptions":[{"first_seen":null,"confirmed_introduction":null}]}' > "$T/missing.json"
"$ROOT/build/rh_cli" adoption --input "$T/missing.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
[[ "$rc_order" -eq 4 && "$rc_cutoff" -eq 4 && "$rc_last" -eq 4 && "$rc_version" -eq 4 && "$rc_missing" -eq 4 ]] || fail "invalid adoption must exit 4 (got $rc_order/$rc_cutoff/$rc_last/$rc_version/$rc_missing)"

echo "test_adoption_cli OK"
