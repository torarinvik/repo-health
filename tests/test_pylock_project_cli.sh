#!/usr/bin/env bash
# PEP 621 declarations compare with PEP 751 package membership only.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-pylock-project"

fail() { echo "[pylock-project] FAIL: $1" >&2; exit 1; }

echo "[pylock-project] build"
grep -q 'rh-pylock-project-membership/1' "$ROOT/fixtures/packages/pylock-project-membership-result.json" || fail "membership schema token missing"
bash "$ROOT/tools/build.sh" >/dev/null
rm -rf "$T"
mkdir -p "$T"
"$ROOT/build/rh_cli" pylock-project \
  --project "$ROOT/fixtures/packages/pylock-project-membership-project.toml" \
  --audit "$ROOT/fixtures/packages/pylock-project-membership-audit.json" \
  --out "$T/result.json" >/dev/null
cmp "$ROOT/fixtures/packages/pylock-project-membership-result.json" "$T/result.json" || fail "membership output differs from reviewed golden"
if grep -q 'secret@example.invalid' "$T/result.json"; then
  fail "direct-reference credentials leaked into the report"
fi
python3 - "$ROOT" "$T/result.json" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
result_path = pathlib.Path(sys.argv[2])
result = json.loads(result_path.read_bytes())
sidecar = json.loads(pathlib.Path(str(result_path) + ".transformations.json").read_bytes())
assert sidecar["schema"] == "rh-adapter-transformation-report/1", sidecar
assert sidecar["output_schema"] == "rh-pylock-project-membership/1", sidecar
assert sidecar["source_input_sha256"] == hashlib.sha256((root / "fixtures/packages/pylock-project-membership-project.toml").read_bytes()).hexdigest(), sidecar
assert sidecar["source_audit_sha256"] == hashlib.sha256((root / "fixtures/packages/pylock-project-membership-audit.json").read_bytes()).hexdigest(), sidecar
assert sidecar["normalized_output_sha256"] == hashlib.sha256(result_path.read_bytes()).hexdigest(), sidecar
assert sidecar["source_context_sha256"] is None, sidecar
assert result["installation_graph"] is False and result["markers_evaluated"] is False, result
assert next(row for row in result["packages"] if row["name"] == "pytest")["optional_group"] == "test-suite", result
requests = next(row for row in result["packages"] if row["name"] == "requests")
assert requests["state"] == "represented" and requests["specifier_candidate_count"] == 1, requests
assert result["coverage"]["specifier_match_count"] == 1, result
assert any(row["state"] == "discarded" for row in sidecar["fields"]), sidecar
assert all(row["state"] in {"preserved", "transformed", "inferred", "discarded", "unsupported", "unknown"} for row in sidecar["fields"]), sidecar
PY

cp "$ROOT/fixtures/packages/pylock-project-membership-audit.json" "$T/wrong-audit.json"
sed 's/rh-pylock-audit\/1/not-a-pylock-audit\/1/' "$T/wrong-audit.json" > "$T/malformed-audit.json"
set +e
"$ROOT/build/rh_cli" pylock-project \
  --project "$ROOT/fixtures/packages/pylock-project-membership-project.toml" \
  --audit "$T/malformed-audit.json" --out "$T/invalid.json" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 4 ]] || fail "wrong audit schema must fail closed (got $rc)"

cat > "$T/invalid-project.toml" <<'EOF'
[project]
dependencies = []
[project.optional-dependencies]
test.suite = ["pytest==7.0"]
EOF
set +e
"$ROOT/build/rh_cli" pylock-project \
  --project "$T/invalid-project.toml" \
  --audit "$ROOT/fixtures/packages/pylock-project-membership-audit.json" \
  --out "$T/invalid-project-result.json" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 4 ]] || fail "unsupported bare dotted optional key must fail closed (got $rc)"

for malformed in \
  '{"schema":"rh-pylock-audit/1","schema":"rh-pylock-audit/1","dependency_semantics":"informational_only","packages":[]}' \
  '{"schema":"rh-pylock-audit/1","dependency_semantics":"informational_only","packages":[{"name":"attrs","name":"attrs","version":"1.0"}]}'; do
  printf '%s\n' "$malformed" > "$T/duplicate-audit.json"
  set +e
  "$ROOT/build/rh_cli" pylock-project \
    --project "$ROOT/fixtures/packages/pylock-project-membership-project.toml" \
    --audit "$T/duplicate-audit.json" --out "$T/duplicate-result.json" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || fail "duplicate audit keys must fail closed (got $rc)"
done

cat > "$T/specifier-project.toml" <<'SPECIFIER_PROJECT'
[project]
name = "specifier-fixture"
version = "1.0"
dependencies = ["alpha>=2,<3", "beta!=1.0", "gamma~=1.4", "delta<2", "eps==1.2.*", "zeta!=1.2.*", "prelib>=1.0", "localib>=1.0"]
SPECIFIER_PROJECT
cat > "$T/specifier-audit.json" <<'SPECIFIER_AUDIT'
{"schema":"rh-pylock-audit/1","dependency_semantics":"informational_only","packages":[{"id":0,"name":"alpha","version":"2.1"},{"id":1,"name":"beta","version":"1.0"},{"id":2,"name":"beta","version":"1.1"},{"id":3,"name":"gamma","version":"1.4"},{"id":4,"name":"gamma","version":"1.5"},{"id":5,"name":"gamma","version":"2.0"},{"id":6,"name":"delta","version":"2.0"},{"id":7,"name":"eps","version":"1.2.9"},{"id":8,"name":"eps","version":"1.3"},{"id":9,"name":"zeta","version":"1.2.3"},{"id":10,"name":"zeta","version":"2.0"},{"id":11,"name":"prelib","version":"1.1rc1"},{"id":12,"name":"localib","version":"1.0+abc"}]}
SPECIFIER_AUDIT
"$ROOT/build/rh_cli" pylock-project --project "$T/specifier-project.toml" --audit "$T/specifier-audit.json" --out "$T/specifier-result.json" >/dev/null || fail "bounded specifier evaluation"
python3 - "$T/specifier-result.json" <<'PY'
import json, sys
rows = {row["name"]: row for row in json.load(open(sys.argv[1]))["packages"]}
assert rows["alpha"]["state"] == "represented" and rows["alpha"]["specifier_candidate_count"] == 1, rows
assert rows["beta"]["state"] == "represented" and rows["beta"]["specifier_candidate_count"] == 1, rows
assert rows["gamma"]["state"] == "represented" and rows["gamma"]["specifier_candidate_count"] == 2, rows
assert rows["delta"]["state"] == "version_not_present", rows
assert rows["eps"]["state"] == "represented" and rows["eps"]["specifier_candidate_count"] == 1, rows
assert rows["zeta"]["state"] == "represented" and rows["zeta"]["specifier_candidate_count"] == 1, rows
assert rows["prelib"]["state"] == "not_evaluated", rows
assert rows["localib"]["state"] == "not_evaluated", rows
PY
cat > "$T/marker-project.toml" <<'MARKER_PROJECT'
[project]
name = "marker-fixture"
version = "1.0"
dependencies = [
  'alpha==1.0; sys_platform == "linux"',
  'beta==2.0; sys_platform == "win32"',
  'gamma==3.0; unavailable_marker == "yes"',
]
[project.optional-dependencies]
test = ['pytest==7.0; extra == "test"']
MARKER_PROJECT
cat > "$T/marker-audit.json" <<'MARKER_AUDIT'
{"schema":"rh-pylock-audit/1","dependency_semantics":"informational_only","environments":[],"extras":[],"dependency_groups":[],"default_groups":[],"packages":[{"id":0,"name":"alpha","version":"1.0"},{"id":1,"name":"beta","version":"2.0"},{"id":2,"name":"gamma","version":"3.0"},{"id":3,"name":"pytest","version":"7.0"}]}
MARKER_AUDIT
cat > "$T/marker-context.json" <<'MARKER_CONTEXT'
{"schema":"rh-pylock-evaluation-context/1","environment":{"sys_platform":"linux"},"extra":"test"}
MARKER_CONTEXT
"$ROOT/build/rh_cli" pylock-project --project "$T/marker-project.toml" --audit "$T/marker-audit.json" --context "$T/marker-context.json" --out "$T/marker-result.json" >/dev/null || fail "context-aware marker evaluation"
python3 - "$T/marker-result.json" "$T/marker-context.json" <<'PY'
import hashlib, json, pathlib, sys
result_path, context_path = map(pathlib.Path, sys.argv[1:])
result = json.loads(result_path.read_bytes())
rows = {row["name"]: row for row in result["packages"]}
sidecar = json.loads(pathlib.Path(str(result_path) + ".transformations.json").read_bytes())
context_sha = hashlib.sha256(context_path.read_bytes()).hexdigest()
assert result["markers_evaluated"] is True and result["context_sha256"] == context_sha, result
assert rows["alpha"]["marker_state"] == "true" and rows["alpha"]["state"] == "represented", rows
assert rows["beta"]["marker_state"] == "false" and rows["beta"]["state"] == "represented", rows
assert rows["gamma"]["marker_state"] == "unknown", rows
assert rows["pytest"]["marker_state"] == "true" and rows["pytest"]["scope"] == "optional", rows
assert sidecar["source_context_sha256"] == context_sha, sidecar
assert sidecar["normalized_output_sha256"] == hashlib.sha256(result_path.read_bytes()).hexdigest(), sidecar
PY
sed 's/rh-pylock-evaluation-context\/1/unsupported-context\/1/' "$T/marker-context.json" > "$T/invalid-marker-context.json"
set +e
"$ROOT/build/rh_cli" pylock-project --project "$T/marker-project.toml" --audit "$T/marker-audit.json" --context "$T/invalid-marker-context.json" --out "$T/invalid-marker-result.json" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 4 ]] || fail "unsupported marker context schema must fail closed (got $rc)"
"$ROOT/build/rh_cli" pylock-project --project "$T/marker-project.toml" --audit "$T/marker-audit.json" --out "$T/marker-no-context.json" >/dev/null || fail "context-free marker membership"
python3 - "$T/marker-no-context.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
rows = {row["name"]: row for row in result["packages"]}
assert result["markers_evaluated"] is False and result["context_sha256"] is None, result
assert rows["alpha"]["marker_state"] == "not_evaluated", rows
PY
echo "test_pylock_project_cli OK"
