#!/usr/bin/env bash
# tests/test_adapter_manifest_cli.sh — RP-04 reviewed adapter binding.
# The result pins provider/interface/rights identity, cache inputs, and graph
# context before an optional adapter can enrich the canonical local graph.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T="/tmp/rh-adapter-manifest"

fail() { echo "[adapter-manifest] FAIL: $1" >&2; exit 1; }

echo "[adapter-manifest] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/input.json" <<'JSON'
{"schema":"rh-adapter-manifest-input/1","connector_id":"deps.dev","connector_version":"v3","adapter_kind":"lookup","interface_revision":"GetVersion/3","source_review_id":"deps.dev","rights_class":"metadata_only","owner":"packages","review_state":"reviewed","capabilities":["version","dependencies","advisories"],"cache_identity":{"input_digest":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","parser_version":"depsdev-adapter/1","configuration_digest":"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd","visibility":"public"},"graph_context":{"ecosystem":"cargo","snapshot_schema":"rh-dep-graph/1"}}
JSON

echo "[adapter-manifest] reviewed binding is retained"
"$ROOT/build/rh_cli" adapter-manifest --input "$T/input.json" --out "$T/out.json" >/dev/null || fail "adapter manifest run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-adapter-manifest-result/1", d
assert d["adapter"]["connector_id"] == "deps.dev", d
assert d["adapter"]["review_state"] == "reviewed", d
assert d["adapter"]["capabilities"] == ["version", "dependencies", "advisories"], d
assert d["cache_identity"]["visibility"] == "public", d
assert d["graph_context"] == {"ecosystem": "cargo", "snapshot_schema": "rh-dep-graph/1"}, d
assert "complete identity" in d["note"], d
print("[adapter-manifest] reviewed identity + rights + graph binding OK")
PY

echo "[adapter-manifest] deterministic replay"
"$ROOT/build/rh_cli" adapter-manifest --input "$T/input.json" --out "$T/out2.json" >/dev/null || fail "adapter manifest rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "adapter manifest output not deterministic"

echo "[adapter-manifest] unreviewed, bad digest, and wrong graph fail closed"
python3 - "$T/input.json" "$T/unreviewed.json" "$T/bad-digest.json" "$T/bad-graph.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
u = dict(d); u["review_state"] = "pending"; json.dump(u, open(sys.argv[2], "w"), separators=(",", ":"))
b = dict(d); b["cache_identity"] = dict(d["cache_identity"]); b["cache_identity"]["input_digest"] = "short"; json.dump(b, open(sys.argv[3], "w"), separators=(",", ":"))
g = dict(d); g["graph_context"] = {"ecosystem": "cargo", "snapshot_schema": "rh-dep-graph/2"}; json.dump(g, open(sys.argv[4], "w"), separators=(",", ":"))
PY
set +e
"$ROOT/build/rh_cli" adapter-manifest --input "$T/unreviewed.json" --out "$T/unreviewed.out" >/dev/null 2>&1; rc_review=$?
"$ROOT/build/rh_cli" adapter-manifest --input "$T/bad-digest.json" --out "$T/bad-digest.out" >/dev/null 2>&1; rc_digest=$?
"$ROOT/build/rh_cli" adapter-manifest --input "$T/bad-graph.json" --out "$T/bad-graph.out" >/dev/null 2>&1; rc_graph=$?
set -e
[[ "$rc_review" -eq 4 && "$rc_digest" -eq 4 && "$rc_graph" -eq 4 ]] || fail "invalid adapter manifest must exit 4 (got $rc_review/$rc_digest/$rc_graph)"
[[ ! -f "$T/unreviewed.out" && ! -f "$T/bad-digest.out" && ! -f "$T/bad-graph.out" ]] || fail "invalid binding published"

echo "test_adapter_manifest_cli OK"
