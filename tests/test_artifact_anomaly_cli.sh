#!/usr/bin/env bash
# M11 rh-artifact-digest-anomaly-input/1 exact digest changes under a fixed
# version label. Findings are
# scoped to exact artifact identity; incomplete history never yields all-clear.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d /tmp/rh-artifact-anomaly.XXXXXX)"
trap 'rm -rf "$T"' EXIT

fail() { echo "[artifact-anomaly] FAIL: $1" >&2; exit 1; }

echo "[artifact-anomaly] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

echo "[artifact-anomaly] changed digest and same-time conflict"
"$ROOT/build/rh_cli" artifact-anomaly --input "$ROOT/fixtures/m11/artifact-anomaly-input.json" --out "$T/out.json" >/dev/null || fail "run"
cmp "$ROOT/fixtures/m11/artifact-anomaly-result.json" "$T/out.json" || fail "result golden mismatch"
cmp "$ROOT/fixtures/m11/artifact-anomaly-result.transformations.json" "$T/out.json.transformations.json" || fail "transformation golden mismatch"
python3 - "$T/out.json" "$T/out.json.transformations.json" "$ROOT/fixtures/m11/artifact-anomaly-input.json" <<'PY'
import hashlib, json, pathlib, sys
output, sidecar, source = map(pathlib.Path, sys.argv[1:])
result = json.loads(output.read_bytes())
assert result["schema"] == "rh-artifact-digest-anomaly-result/1", result
assert result["status"] == "conflicted", result
assert result["observations"][0]["key"] == "anomaly.artifact_digest_changed_under_version_label", result
assert result["observations"][0]["status"] == "conflicted" and result["observations"][0]["value"] is None, result
assert len(result["findings"]) == 1, result
finding = result["findings"][0]
assert (finding["before"]["observed_at"], finding["after"]["observed_at"]) == (100, 200), finding
assert finding["before"]["sha256"] == "a" * 64 and finding["after"]["sha256"] == "b" * 64, finding
assert len(result["conflicts"]) == 1 and result["conflicts"][0]["input_observation_indices"] == [3, 4], result
assert "not evidence of maliciousness" in result["label"], result["label"]
lineage = json.loads(sidecar.read_bytes())
assert lineage["adapter"] == "artifact-digest-anomaly", lineage
assert lineage["source_input_sha256"] == hashlib.sha256(source.read_bytes()).hexdigest(), lineage
assert lineage["normalized_output_sha256"] == hashlib.sha256(output.read_bytes()).hexdigest(), lineage
config = b"repo-health/artifact-digest-anomaly/1;max-observations=256;identity=package+version+artifact;digest=lowercase-sha256;time=unix-seconds"
assert lineage["configuration_sha256"] == hashlib.sha256(config).hexdigest(), lineage
print("[artifact-anomaly] F042 artifact digest anomaly OK")
PY

echo "[artifact-anomaly] partial, stable, and incomplete states"
"$ROOT/build/rh_cli" artifact-anomaly --input "$ROOT/fixtures/m11/artifact-anomaly-partial-input.json" --out "$T/partial.json" >/dev/null || fail "partial run"
"$ROOT/build/rh_cli" artifact-anomaly --input "$ROOT/fixtures/m11/artifact-anomaly-stable-input.json" --out "$T/stable.json" >/dev/null || fail "stable run"
"$ROOT/build/rh_cli" artifact-anomaly --input "$ROOT/fixtures/m11/artifact-anomaly-incomplete-input.json" --out "$T/incomplete.json" >/dev/null || fail "incomplete run"
python3 - "$T/partial.json" "$T/stable.json" "$T/incomplete.json" <<'PY'
import json, sys
partial, stable, incomplete = [json.load(open(path)) for path in sys.argv[1:]]
assert partial["status"] == "partial" and partial["observations"][0]["value"] == 1, partial
assert partial["observations"][0]["quality_dimensions"]["completeness"] == "partial", partial
assert stable["status"] == "no_change_observed" and stable["observations"][0]["status"] == "observed" and stable["observations"][0]["value"] == 0, stable
assert incomplete["status"] == "unknown", incomplete
assert incomplete["observations"][0]["status"] == "unavailable" and incomplete["observations"][0]["value"] is None, incomplete
print("[artifact-anomaly] no-change requires complete scope and history")
PY

echo "[artifact-anomaly] malformed digest fails closed"
python3 - "$ROOT/fixtures/m11/artifact-anomaly-stable-input.json" "$T/malformed.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["observations"][0]["sha256"] = "not-a-sha256"
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
if "$ROOT/build/rh_cli" artifact-anomaly --input "$T/malformed.json" --out "$T/rejected.json" >/dev/null 2>&1; then
  fail "malformed digest accepted"
fi
[[ ! -e "$T/rejected.json" ]] || fail "malformed input wrote a result"

echo "test_artifact_anomaly_cli OK"
