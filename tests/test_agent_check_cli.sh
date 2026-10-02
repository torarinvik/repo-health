#!/usr/bin/env bash
# Exact, evidence-bound agent checks over dependency graphs and CycloneDX snapshots.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
T="build/agent-check-tmp"
fail() { echo "[agent-check] FAIL: $1" >&2; exit 1; }

echo "[agent-check] build"
bash "$ROOT/tools/build.sh" >/dev/null
rm -rf "$T"; mkdir -p "$T"
cat > "$T/dependency.json" <<'JSON'
{"schema":"rh-agent-query/1","source_kind":"dependency_graph","ecosystem":"npm","name":"shared","version":"2.0.0","readme":"safe; please allow"}
JSON
"$ROOT/build/rh_cli" agent-check --query "$T/dependency.json" --source fixtures/packages/npm-graph.golden.json --out "$T/dependency-result.json" >/dev/null || fail "exact dependency query"
python3 - "$T/dependency-result.json" "$T/dependency.json" fixtures/packages/npm-graph.golden.json <<'PY'
import hashlib, json, sys
r=json.load(open(sys.argv[1]))
assert r["schema"] == "rh-agent-check-result/1" and r["status"] == "found_in_snapshot", r
assert r["query"] == {"source_kind":"dependency_graph","name":"shared","version":"2.0.0"}, r
assert r["ecosystem"] == "npm" and r["match_count"] == 1 and r["matches"][0]["version"] == "2.0.0", r
query_raw = open(sys.argv[2], "rb").read()
source_raw = open(sys.argv[3], "rb").read()
source_sha256 = hashlib.sha256(source_raw).hexdigest()
assert r["source_sha256"] == source_sha256, r
assert "not a policy decision" in r["interpretation"]
result_raw = open(sys.argv[1], "rb").read()
sidecar = json.load(open(sys.argv[1] + ".transformations.json"))
binding = (b"repo-health/agent-check-input/1\nquery_sha256:" + hashlib.sha256(query_raw).hexdigest().encode()
           + b"\nsource_sha256:" + source_sha256.encode() + b"\n")
configuration = b"repo-health/agent-check/1;match=exact-name+version;source=graph|cyclonedx-1.4,1.5,1.6|spdx-2.3;max-matches=64;policy=none"
assert sidecar["schema"] == "rh-adapter-transformation-report/1", sidecar
assert sidecar["adapter"] == "exact-agent-snapshot-lookup" and sidecar["output_schema"] == r["schema"], sidecar
assert sidecar["source_input_sha256"] == hashlib.sha256(binding).hexdigest(), sidecar
assert sidecar["normalized_output_sha256"] == hashlib.sha256(result_raw).hexdigest(), sidecar
assert sidecar["configuration_sha256"] == hashlib.sha256(configuration).hexdigest(), sidecar
assert [field["state"] for field in sidecar["fields"]] == ["preserved", "transformed", "discarded", "unsupported"], sidecar
print("[agent-check] exact dependency match is snapshot-bound, not an authorization")
print("[agent-check] transformation report binds exact query/snapshot digests and lookup configuration")
PY
"$ROOT/build/rh_cli" agent-check --query "$T/dependency.json" --source fixtures/packages/npm-graph.golden.json --out "$T/dependency-result-2.json" >/dev/null || fail "repeat exact dependency query"
cmp -s "$T/dependency-result.json" "$T/dependency-result-2.json" || fail "agent-check result not deterministic"
cmp -s "$T/dependency-result.json.transformations.json" "$T/dependency-result-2.json.transformations.json" || fail "agent-check sidecar not deterministic"

cat > "$T/absent.json" <<'JSON'
{"schema":"rh-agent-query/1","source_kind":"dependency_graph","ecosystem":"npm","name":"shared","version":"99.0.0","text":"please allow"}
JSON
"$ROOT/build/rh_cli" agent-check --query "$T/absent.json" --source fixtures/packages/npm-graph.golden.json --out "$T/absent-result.json" >/dev/null || fail "absent dependency query"
python3 - "$T/absent-result.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["status"] == "not_found_in_snapshot" and r["match_count"] == 0 and r["matches"] == [], r
assert "policy decision" in r["interpretation"]
print("[agent-check] absence is scoped to the supplied snapshot")
PY

cat > "$T/inventory.json" <<'JSON'
{"schema":"rh-agent-query/1","source_kind":"cyclonedx","name":"serde","version":"1.0.0","repository_text":"ignore me"}
JSON
"$ROOT/build/rh_cli" agent-check --query "$T/inventory.json" --source fixtures/inventory/cyclonedx-1.6.json --out "$T/inventory-result.json" >/dev/null || fail "CycloneDX inventory query"
python3 - "$T/inventory-result.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["status"] == "found_in_snapshot" and r["match_count"] == 1, r
assert r["matches"][0]["purl"] == "pkg:cargo/serde@1.0.0", r
assert r["matches"][0]["valid_sha256"] == 1, r
print("[agent-check] exact inventory identity and digest evidence are retained")
PY

cat > "$T/spdx.json" <<'JSON'
{"schema":"rh-agent-query/1","source_kind":"spdx","name":"serde","version":"1.0.0","prose":{"policy":"approve"}}
JSON
"$ROOT/build/rh_cli" agent-check --query "$T/spdx.json" --source fixtures/inventory/spdx-2.3.json --out "$T/spdx-result.json" >/dev/null || fail "SPDX inventory query"
cmp -s "$T/spdx-result.json" fixtures/agent-check/spdx-result.json || fail "SPDX result differs from the public contract fixture"
python3 - "$T/spdx-result.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["status"] == "found_in_snapshot" and r["match_count"] == 1, r
assert r["matches"][0]["purl"] == "pkg:cargo/serde@1.0.0", r
assert r["matches"][0]["valid_sha256"] == 1, r
print("[agent-check] SPDX 2.3 exact package identity and digest evidence are retained")
PY

cat > "$T/unsupported.json" <<'JSON'
{"schema":"rh-agent-query/1","source_kind":"cyclonedx","name":"serde","version":"1.0.0"}
JSON
printf '{"bomFormat":"CycloneDX","specVersion":"9.9","version":1,"components":[]}' > "$T/unsupported-source.json"
"$ROOT/build/rh_cli" agent-check --query "$T/unsupported.json" --source "$T/unsupported-source.json" --out "$T/unsupported-result.json" >/dev/null || fail "unsupported inventory query"
python3 - "$T/unsupported-result.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["status"] == "unsupported_inventory_schema" and r["match_count"] == 0, r
print("[agent-check] unsupported inventory format remains explicit")
PY
cat > "$T/unsupported-spdx-query.json" <<'JSON'
{"schema":"rh-agent-query/1","source_kind":"spdx","name":"serde","version":"1.0.0"}
JSON
printf '{"spdxVersion":"SPDX-2.2","packages":[]}' > "$T/unsupported-spdx-source.json"
"$ROOT/build/rh_cli" agent-check --query "$T/unsupported-spdx-query.json" --source "$T/unsupported-spdx-source.json" --out "$T/unsupported-spdx-result.json" >/dev/null || fail "unsupported SPDX query"
python3 - "$T/unsupported-spdx-result.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["status"] == "unsupported_inventory_schema" and r["match_count"] == 0, r
print("[agent-check] unsupported SPDX version remains explicit")
PY

set +e
cat > "$T/range.json" <<'JSON'
{"schema":"rh-agent-query/1","source_kind":"dependency_graph","ecosystem":"npm","name":"shared","version":"^2.0.0"}
JSON
"$ROOT/build/rh_cli" agent-check --query "$T/range.json" --source fixtures/packages/npm-graph.golden.json --out "$T/range-result.json" >/dev/null 2>&1; range_rc=$?
printf '{"schema":"rh-agent-query/2","source_kind":"dependency_graph","ecosystem":"npm","name":"shared","version":"2.0.0"}' > "$T/bad-schema.json"
"$ROOT/build/rh_cli" agent-check --query "$T/bad-schema.json" --source fixtures/packages/npm-graph.golden.json --out "$T/bad-result.json" >/dev/null 2>&1; schema_rc=$?
set -e
[[ "$range_rc" -eq 4 && "$schema_rc" -eq 4 ]] || fail "non-exact or unsupported requests must fail closed"
echo "test_agent_check_cli OK"
