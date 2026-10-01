#!/usr/bin/env bash
# M06-09: bind local policy decisions to the exact imported finding evidence.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-findings-policy"

fail() { echo "[findings-policy] FAIL: $1" >&2; exit 1; }

echo "[findings-policy] build"
bash "$ROOT/tools/build.sh" >/dev/null
rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/packages/scorecard-findings-v2.json" "$T/source.json"
cp "$ROOT/fixtures/findings-policy/bindings.json" "$T/bindings.json"
cp "$ROOT/fixtures/findings-policy/policy-warn.json" "$T/policy-warn.json"
cp "$ROOT/fixtures/findings-policy/policy-deny.json" "$T/policy-deny.json"

"$ROOT/build/rh_cli" findings --input "$T/source.json" --out "$T/findings.json" >/dev/null || fail "normalize findings"
"$ROOT/build/rh_cli" findings-policy --findings "$T/findings.json" --transformations "$T/findings.json.transformations.json" --policy "$T/policy-warn.json" --bindings "$T/bindings.json" --subject-id 42 --now 1700000060 --out "$T/warn.json" >/dev/null || fail "warn policy evaluation"
"$ROOT/build/rh_cli" findings-policy --findings "$T/findings.json" --transformations "$T/findings.json.transformations.json" --policy "$T/policy-deny.json" --bindings "$T/bindings.json" --subject-id 42 --now 1700000060 --out "$T/deny.json" >/dev/null || fail "deny policy evaluation"
cmp -s "$T/warn.json" "$ROOT/fixtures/findings-policy/result-warn.json" || fail "warn result differs from the public contract fixture"
cmp -s "$T/deny.json" "$ROOT/fixtures/findings-policy/result-deny.json" || fail "deny result differs from the public contract fixture"
python3 - "$T" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
findings_bytes = (root / "findings.json").read_bytes()
transform_bytes = (root / "findings.json.transformations.json").read_bytes()
bindings_bytes = (root / "bindings.json").read_bytes()
bindings = json.loads(bindings_bytes)
warn_policy_bytes = (root / "policy-warn.json").read_bytes()
deny_policy_bytes = (root / "policy-deny.json").read_bytes()
warn = json.loads((root / "warn.json").read_bytes())
deny = json.loads((root / "deny.json").read_bytes())
assert warn["schema"] == deny["schema"] == "rh-findings-policy-result/1"
assert bindings["schema"] == "rh-findings-policy-bindings/1"
assert warn["decision"] == "warn" and deny["decision"] == "deny", (warn, deny)
assert warn["assessment"] == deny["assessment"] == {
    "id": "scorecard:repo@abc123:1700000000",
    "tool": "OpenSSF Scorecard",
    "tool_version": "5.0.0",
    "subject_revision": "abc123",
    "assessed_at": 1700000000,
}
assert warn["evaluation"] == deny["evaluation"] == {"evaluated_at": 1700000060, "assessment_age_secs": 60}
assert warn["binding"]["findings_sha256"] == deny["binding"]["findings_sha256"] == hashlib.sha256(findings_bytes).hexdigest()
assert warn["binding"]["source_input_sha256"] == deny["binding"]["source_input_sha256"] == json.loads(transform_bytes)["source_input_sha256"]
assert warn["binding"]["transformations_sha256"] == deny["binding"]["transformations_sha256"] == hashlib.sha256(transform_bytes).hexdigest()
assert warn["binding"]["normalizer_configuration_sha256"] == json.loads(transform_bytes)["configuration_sha256"]
assert warn["binding"]["policy_sha256"] == hashlib.sha256(warn_policy_bytes).hexdigest()
assert deny["binding"]["policy_sha256"] == hashlib.sha256(deny_policy_bytes).hexdigest()
assert warn["binding"]["policy_sha256"] != deny["binding"]["policy_sha256"]
assert warn["binding"]["bindings_sha256"] == deny["binding"]["bindings_sha256"] == hashlib.sha256(bindings_bytes).hexdigest()
for result, decision in ((warn, "warn"), (deny, "deny")):
    row = result["rule_results"][0]
    assert row["rule_id"] == 7 and row["decision"] == decision and row["fired"] is True, row
    assert row["status"] == "observed" and row["sample"] == 1 and row["complete"] is True, row
    assert row["finding_index"] == 5 and row["match_count"] == 1, row
    assert row["value"] == {"num": 0, "den": 1}, row
    assert row["finding"] == {
        "check": "Branch-Protection",
        "probe": "default-branch-review",
        "probe_version": "1",
        "outcome": "fail",
        "polarity": "negative",
    }, row
print("[findings-policy] two local policies produce distinct decisions over the same unchanged assessment")
PY

echo "[findings-policy] assessment age comes from source time and stale evidence is unknown"
"$ROOT/build/rh_cli" findings-policy --findings "$T/findings.json" --transformations "$T/findings.json.transformations.json" --policy "$T/policy-deny.json" --bindings "$T/bindings.json" --subject-id 42 --now 1700000200 --out "$T/stale.json" >/dev/null || fail "stale policy evaluation"
python3 - "$T/stale.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["decision"] == "unknown", result
assert result["evaluation"] == {"evaluated_at": 1700000200, "assessment_age_secs": 200}, result
assert result["rule_results"][0]["status"] == "observed", result
assert result["rule_results"][0]["decision"] == "unknown", result
print("[findings-policy] original assessment time controls freshness")
PY

echo "[findings-policy] ambiguous and polarity-conflicted findings remain unknown"
python3 - "$T/findings.json" "$T/duplicate.json" "$T/duplicate.json.transformations.json" "$T/findings.json.transformations.json" <<'PY'
import hashlib, json, pathlib, sys
result = json.loads(pathlib.Path(sys.argv[1]).read_bytes())
result["findings"].append(dict(result["findings"][5]))
raw = (json.dumps(result, separators=(",", ":")) + "\n").encode()
pathlib.Path(sys.argv[2]).write_bytes(raw)
transform = json.loads(pathlib.Path(sys.argv[4]).read_bytes())
transform["normalized_output_sha256"] = hashlib.sha256(raw).hexdigest()
pathlib.Path(sys.argv[3]).write_text(json.dumps(transform, separators=(",", ":")) + "\n")
PY
"$ROOT/build/rh_cli" findings-policy --findings "$T/duplicate.json" --transformations "$T/duplicate.json.transformations.json" --policy "$T/policy-deny.json" --bindings "$T/bindings.json" --subject-id 42 --now 1700000060 --out "$T/ambiguous.json" >/dev/null || fail "ambiguous policy evaluation"
python3 - "$T/ambiguous.json" "$T/bindings.json" "$T/policy-deny.json" <<'PY'
import json, pathlib, sys
result = json.load(open(sys.argv[1]))
assert result["decision"] == "unknown", result
assert result["rule_results"][0]["status"] == "conflicted", result
assert result["rule_results"][0]["match_count"] == 2, result
print("[findings-policy] multiple matching findings fail closed")
PY
python3 - "$T/bindings.json" "$T/bad-polarity.json" <<'PY'
import json, pathlib, sys
doc = json.loads(pathlib.Path(sys.argv[1]).read_bytes())
doc["bindings"][0]["polarity"] = "positive"
pathlib.Path(sys.argv[2]).write_text(json.dumps(doc, separators=(",", ":")) + "\n")
PY
"$ROOT/build/rh_cli" findings-policy --findings "$T/findings.json" --transformations "$T/findings.json.transformations.json" --policy "$T/policy-deny.json" --bindings "$T/bad-polarity.json" --subject-id 42 --now 1700000060 --out "$T/polarity-conflict.json" >/dev/null || fail "polarity conflict evaluation"
python3 - "$T/polarity-conflict.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["decision"] == "unknown", result
assert result["rule_results"][0]["status"] == "conflicted", result
assert result["rule_results"][0]["finding"]["polarity"] == "negative", result
print("[findings-policy] polarity is checked against the exact local binding")
PY

echo "[findings-policy] every active rule needs one unique exact binding"
python3 - "$T/bindings.json" "$T/missing-binding.json" "$T/wrong-tool-version.json" <<'PY'
import json, pathlib, sys
doc = json.loads(pathlib.Path(sys.argv[1]).read_bytes())
missing = dict(doc)
missing["bindings"] = []
pathlib.Path(sys.argv[2]).write_text(json.dumps(missing, separators=(",", ":")) + "\n")
wrong_version = dict(doc)
wrong_version["tool_version"] = "5.0.1"
pathlib.Path(sys.argv[3]).write_text(json.dumps(wrong_version, separators=(",", ":")) + "\n")
PY
set +e
"$ROOT/build/rh_cli" findings-policy --findings "$T/findings.json" --transformations "$T/findings.json.transformations.json" --policy "$T/policy-deny.json" --bindings "$T/missing-binding.json" --subject-id 42 --now 1700000060 --out "$T/missing-binding.out" >/dev/null 2>&1; rc_missing=$?
"$ROOT/build/rh_cli" findings-policy --findings "$T/findings.json" --transformations "$T/findings.json.transformations.json" --policy "$T/policy-deny.json" --bindings "$T/wrong-tool-version.json" --subject-id 42 --now 1700000060 --out "$T/wrong-tool-version.out" >/dev/null 2>&1; rc_tool=$?
set -e
[[ "$rc_missing" -eq 4 && "$rc_tool" -eq 4 ]] || fail "missing or mismatched binding was accepted ($rc_missing/$rc_tool)"
[[ ! -f "$T/missing-binding.out" && ! -f "$T/wrong-tool-version.out" ]] || fail "invalid binding published output"

echo "[findings-policy] transformation mismatch and future evaluation fail closed"
python3 - "$T/findings.json.transformations.json" "$T/bad-transform.json" <<'PY'
import json, pathlib, sys
doc = json.loads(pathlib.Path(sys.argv[1]).read_bytes())
doc["normalized_output_sha256"] = "0" * 64
pathlib.Path(sys.argv[2]).write_text(json.dumps(doc, separators=(",", ":")) + "\n")
PY
set +e
"$ROOT/build/rh_cli" findings-policy --findings "$T/findings.json" --transformations "$T/bad-transform.json" --policy "$T/policy-deny.json" --bindings "$T/bindings.json" --subject-id 42 --now 1700000060 --out "$T/bad-transform.json.out" >/dev/null 2>&1; rc_transform=$?
"$ROOT/build/rh_cli" findings-policy --findings "$T/findings.json" --transformations "$T/findings.json.transformations.json" --policy "$T/policy-deny.json" --bindings "$T/bindings.json" --subject-id 42 --now 1699999999 --out "$T/future.json" >/dev/null 2>&1; rc_future=$?
set -e
[[ "$rc_transform" -eq 4 && "$rc_future" -eq 4 ]] || fail "invalid transformation or future evaluation was accepted ($rc_transform/$rc_future)"
[[ ! -f "$T/bad-transform.json.out" && ! -f "$T/future.json" ]] || fail "failed evaluation published output"

echo "test_findings_policy_cli OK"
