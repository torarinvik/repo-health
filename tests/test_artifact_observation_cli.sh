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

echo "[artifact-observe] npm multi-token SRI selects SHA-512 across blocks"
python3 - "$T" <<'PY'
import base64, hashlib, json, pathlib, sys
t = pathlib.Path(sys.argv[1])
archive = bytes((i * 37 + 11) % 256 for i in range(4097))
(t / "npm.tarball").write_bytes(archive)
graph = {
    "schema": "rh-dep-graph/1",
    "ecosystem": "npm",
    "nodes": [{"id": 0, "name": "demo", "version": "1.0.0", "source": "registry"}],
    "artifacts": [{
        "id": 0,
        "package_node": 0,
        "kind": "archive",
        "expected_digest": " ".join([
            "sha256-" + base64.b64encode(hashlib.sha256(archive).digest()).decode(),
            "sha512-" + base64.b64encode(bytes([0xaa]) * 64).decode(),
            "SHA512-" + base64.b64encode(hashlib.sha512(archive).digest()).decode(),
        ]),
        "observed_digest": None,
        "identity_state": "unknown",
    }],
    "edges": [],
    "unresolved": [],
    "advisories": [],
}
with open(t / "npm-graph.json", "w") as out:
    json.dump(graph, out, separators=(",", ":"))
PY
"$ROOT/build/rh_cli" artifact-observe \
  --graph "$T/npm-graph.json" \
  --artifact 0 \
  --file "$T/npm.tarball" \
  --out "$T/npm-observation.json" >/dev/null
python3 - "$T/npm-observation.json" "$T/npm.tarball" <<'PY'
import base64, hashlib, json, pathlib, sys
result = json.load(open(sys.argv[1]))
archive = pathlib.Path(sys.argv[2]).read_bytes()
integrity = " ".join([
    "sha256-" + base64.b64encode(hashlib.sha256(archive).digest()).decode(),
    "sha512-" + base64.b64encode(bytes([0xaa]) * 64).decode(),
    "SHA512-" + base64.b64encode(hashlib.sha512(archive).digest()).decode(),
])
sha512_integrity = "sha512-" + base64.b64encode(hashlib.sha512(archive).digest()).decode()
assert result["expected_digest"] == integrity, result
assert result["observed_digest"] == sha512_integrity, result
assert result["identity_state"] == "match", result
assert result["digest_algorithm"] == "sha512", result
assert result["verification_basis"] == "raw_npm_tarball_bytes", result
PY
python3 - "$T/npm.tarball" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_bytes(path.read_bytes() + b"changed")
PY
"$ROOT/build/rh_cli" artifact-observe \
  --graph "$T/npm-graph.json" \
  --artifact 0 \
  --file "$T/npm.tarball" \
  --out "$T/npm-changed-observation.json" >/dev/null
python3 - "$T/npm-changed-observation.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["identity_state"] == "changed", result
assert result["observed_digest"] != result["expected_digest"], result
PY

echo "[artifact-observe] unsupported and out-of-range evidence fails closed"
python3 - "$T" "$ROOT/fixtures/packages/artifact-observation-graph.json" <<'PY'
import json, pathlib, sys
t = pathlib.Path(sys.argv[1])
graph = json.load(open(sys.argv[2]))
graph["ecosystem"] = "npm"
graph["artifacts"][0]["expected_digest"] = "sha1-deadbeef"
with open(t / "unsupported.json", "w") as out:
    json.dump(graph, out, separators=(",", ":"))
graph["artifacts"][0]["expected_digest"] = "sha512-" + "A" * 85 + "B=="
with open(t / "malformed-sri.json", "w") as out:
    json.dump(graph, out, separators=(",", ":"))
PY
for graph in unsupported malformed-sri; do
  if "$ROOT/build/rh_cli" artifact-observe --graph "$T/$graph.json" --artifact 0 --file "$ROOT/fixtures/packages/artifact-observation.archive" --out "$T/$graph-out.json" >/dev/null 2>&1; then
    echo "unsupported or malformed SRI unexpectedly accepted: $graph" >&2
    exit 1
  fi
done
if "$ROOT/build/rh_cli" artifact-observe --graph "$ROOT/fixtures/packages/artifact-observation-graph.json" --artifact 1 --file "$ROOT/fixtures/packages/artifact-observation.archive" --out "$T/out-of-range.json" >/dev/null 2>&1; then
  echo "out-of-range artifact unexpectedly accepted" >&2
  exit 1
fi
echo "test_artifact_observation_cli OK"
