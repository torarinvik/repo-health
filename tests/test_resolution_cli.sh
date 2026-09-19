#!/usr/bin/env bash
# tests/test_resolution_cli.sh — M03-11 package identity/resolution-instance
# contract. Graph-local provider IDs are scoped by the deterministic snapshot
# digest; unresolved requirements remain outside the resolved instances.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T="/tmp/rh-resolution"

fail() { echo "[resolution] FAIL: $1" >&2; exit 1; }

echo "[resolution] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/packages/cargo-graph.golden.json" "$T/in.json"
python3 - "$T/in.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["provider_graph_context"] = {
    "environment": "linux-x86_64",
    "node_count": 8,
    "unresolved_count": 1,
    "difference_reason": "provider graph resolves target features unavailable to the local lockfile"
}
json.dump(d, open(p, "w"), separators=(",", ":"))
PY

echo "[resolution] separate package identity from graph instance"
"$ROOT/build/rh_cli" resolution --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "resolution run"
python3 - "$T/in.json" "$T/out.json" <<'PY'
import json, sys
raw = open(sys.argv[1], "rb").read()
digest = 14695981039346656037
for b in raw:
    digest ^= b
    digest = (digest * 1099511628211) & ((1 << 64) - 1)
digest = f"{digest:016x}"
d = json.load(open(sys.argv[2]))
assert d["schema"] == "rh-resolution-instance/1", d
assert d["graph_snapshot"] == {"digest": digest, "schema": "rh-dep-graph/1", "ecosystem": "cargo"}, d["graph_snapshot"]
assert d["unresolved_count"] == 2, d
assert d["provider_graph_context"] == {"environment": "linux-x86_64", "node_count": 8, "unresolved_count": 1, "difference_reason": "provider graph resolves target features unavailable to the local lockfile"}, d
assert len(d["instances"]) == 7, d
first = d["instances"][0]
assert first["package_identity"] == {"ecosystem": "cargo", "name": "app", "version": "0.1.0"}, first
assert first["resolution_instance"] == {"graph_digest": digest, "provider_node_id": 0, "context": "lockfile", "status": "resolved"}, first
assert first["source"] == "unknown" and first["source_attestation"] == {"state": "observed", "value": "unknown"}, first
assert first["dev"] is False and first["optional"] is False, first
assert d["edges"][0] == {"from": 1, "to": 3, "relation": "normal"}, d["edges"]
print("[resolution] identity + snapshot scope OK")
PY

echo "[resolution] deterministic replay"
"$ROOT/build/rh_cli" resolution --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "resolution output not deterministic"

echo "[resolution] absent provider context still serializes a complete report"
python3 - "$T/in.json" "$T/no-provider.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d.pop("provider_graph_context", None)
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" resolution --input "$T/no-provider.json" --out "$T/no-provider.out" >/dev/null || fail "no-provider resolution"
python3 - "$T/no-provider.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert "provider_graph_context" not in d and d["edges"], d
print("[resolution] no-provider serialization OK")
PY

echo "[resolution] malformed graphs fail closed"
set +e
printf '{"schema":"rh-dep-graph/2","ecosystem":"cargo","nodes":[],"unresolved":[]}' > "$T/bad-schema.json"
"$ROOT/build/rh_cli" resolution --input "$T/bad-schema.json" --out "$T/bad.out" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-dep-graph/1","ecosystem":"cargo","nodes":[{"id":0,"name":"x","version":null,"source":"unknown","dev":1,"optional":false}],"unresolved":[]}' > "$T/bad-bool.json"
"$ROOT/build/rh_cli" resolution --input "$T/bad-bool.json" --out "$T/bool.out" >/dev/null 2>&1; rc_bool=$?
set -e
[[ "$rc_schema" -eq 4 && "$rc_bool" -eq 4 ]] || fail "malformed graph must exit 4 (got $rc_schema/$rc_bool)"
[[ ! -f "$T/bad.out" && ! -f "$T/bool.out" ]] || fail "partial resolution published"

echo "test_resolution_cli OK"
