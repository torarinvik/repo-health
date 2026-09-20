#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

echo "[artifact-observe] build"
bash "$ROOT/tools/build.sh" >/dev/null

echo "[artifact-observe] raw Cargo archive bytes match the lockfile checksum"
"$ROOT/build/rh_cli" artifact-observe \
  --graph "$ROOT/fixtures/packages/artifact-observation-graph.json" \
  --artifact 0 \
  --file "$ROOT/fixtures/packages/artifact-observation.archive" \
  --out "$T/match.json" >/dev/null
python3 - "$T/match.json" "$ROOT/fixtures/packages/artifact-observation-graph.json" <<'PY'
import hashlib, json, pathlib, sys
result = json.load(open(sys.argv[1]))
graph = pathlib.Path(sys.argv[2]).read_bytes()
archive = pathlib.Path(sys.argv[2]).with_name("artifact-observation.archive").read_bytes()
assert result == {
    "schema": "rh-artifact-observation-result/1",
    "graph_sha256": hashlib.sha256(graph).hexdigest(),
    "artifact_id": 0,
    "package_node": 0,
    "expected_digest": hashlib.sha256(archive).hexdigest(),
    "observed_digest": hashlib.sha256(archive).hexdigest(),
    "identity_state": "match",
    "digest_algorithm": "sha256",
    "verification_basis": "raw_cargo_archive_bytes",
    "archive_size_bytes": len(archive),
}, result
PY

echo "[artifact-observe] changed bytes remain distinct under the same package label"
cp "$ROOT/fixtures/packages/artifact-observation.archive" "$T/changed.archive"
printf 'changed' >> "$T/changed.archive"
"$ROOT/build/rh_cli" artifact-observe \
  --graph "$ROOT/fixtures/packages/artifact-observation-graph.json" \
  --artifact 0 \
  --file "$T/changed.archive" \
  --out "$T/changed.json" >/dev/null
python3 - "$T/changed.json" "$T/changed.archive" <<'PY'
import hashlib, json, pathlib, sys
result = json.load(open(sys.argv[1]))
archive = pathlib.Path(sys.argv[2]).read_bytes()
assert result["identity_state"] == "changed", result
assert result["observed_digest"] == hashlib.sha256(archive).hexdigest(), result
assert result["observed_digest"] != result["expected_digest"], result
PY

echo "[artifact-observe] unsupported and out-of-range evidence fails closed"
python3 - "$T" "$ROOT/fixtures/packages/artifact-observation-graph.json" <<'PY'
import json, pathlib, sys
t = pathlib.Path(sys.argv[1])
graph = json.load(open(sys.argv[2]))
graph["ecosystem"] = "npm"
with open(t / "unsupported.json", "w") as out:
    json.dump(graph, out, separators=(",", ":"))
PY
if "$ROOT/build/rh_cli" artifact-observe --graph "$T/unsupported.json" --artifact 0 --file "$ROOT/fixtures/packages/artifact-observation.archive" --out "$T/unsupported-out.json" >/dev/null 2>&1; then
  echo "unsupported ecosystem unexpectedly accepted" >&2
  exit 1
fi
if "$ROOT/build/rh_cli" artifact-observe --graph "$ROOT/fixtures/packages/artifact-observation-graph.json" --artifact 1 --file "$ROOT/fixtures/packages/artifact-observation.archive" --out "$T/out-of-range.json" >/dev/null 2>&1; then
  echo "out-of-range artifact unexpectedly accepted" >&2
  exit 1
fi
echo "test_artifact_observation_cli OK"
