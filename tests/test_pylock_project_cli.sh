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
assert result["installation_graph"] is False and result["markers_evaluated"] is False, result
assert next(row for row in result["packages"] if row["name"] == "pytest")["optional_group"] == "test-suite", result
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

echo "test_pylock_project_cli OK"
