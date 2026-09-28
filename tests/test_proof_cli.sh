#!/usr/bin/env bash
# tests/test_proof_cli.sh — M11 formal-proof evidence adapter. Proof replay,
# source revision, artifact binding, assumptions, and trusted computing base
# stay separate typed fields; malformed or unknown replay states fail closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-proof"

fail() { echo "[proof] FAIL: $1" >&2; exit 1; }

echo "[proof] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/m11/proof-input.json" "$T/in.json"
"$ROOT/build/rh_cli" proof --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "proof run"
cmp "$ROOT/fixtures/m11/proof-result.json" "$T/out.json" || fail "proof golden output mismatch"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-proof-result/1", d
assert d["replay_result"] == "replayed", d
assert d["proof_digest"] == "sha256:" + "a" * 64, d
assert d["assumptions"] == ["allocator-model", "no-ffi"], d
assert d["trusted_computing_base"] == ["elisa-runtime", "proof-kernel"], d
assert d["assumption_count"] == 2 and d["trusted_computing_base_count"] == 2, d
assert d["artifact_binding"]["status"] == "bound", d
assert "not a whole-application safety claim" in d["note"], d
print("[proof] typed replay/binding evidence OK")
PY

python3 - "$T/in.json" "$T/unbound.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["artifact_binding"] = None
json.dump(d, open(sys.argv[2], "w"))
PY
"$ROOT/build/rh_cli" proof --input "$T/unbound.json" --out "$T/unbound-out.json" >/dev/null || fail "explicit null artifact binding"
python3 - "$T/unbound-out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["artifact_binding"] is None, d
PY
echo "[proof] explicit null artifact binding is accepted as unbound"

echo "[proof] conflicted binding stays conflicted"
sed 's/"source_revision":"rev-123","artifact_digest"/"source_revision":"other-rev","artifact_digest"/' "$T/in.json" > "$T/conflict.json"
"$ROOT/build/rh_cli" proof --input "$T/conflict.json" --out "$T/conflict.out" >/dev/null || fail "conflict run"
python3 - "$T/conflict.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["artifact_binding"]["status"] == "conflicted", d
assert d["replay_result"] == "replayed", d
print("[proof] binding conflict does not alter replay result")
PY

echo "[proof] determinism + malformed inputs fail closed"
"$ROOT/build/rh_cli" proof --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "proof output not deterministic"
set +e
printf '{"schema":"rh-proof-input/1","proposition_id":"x","source_revision":"r","checker_version":"c","assumptions":[],"trusted_computing_base":[],"proof_digest":"sha256:%064d","replay_result":"maybe"}' 0 > "$T/bad-replay.json"
"$ROOT/build/rh_cli" proof --input "$T/bad-replay.json" --out "$T/x" >/dev/null 2>&1; rc_replay=$?
printf '{"schema":"rh-proof-input/2"}' > "$T/bad-schema.json"
"$ROOT/build/rh_cli" proof --input "$T/bad-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
python3 - "$T/in.json" "$T/bad-proof-digest.json" "$T/bad-artifact-digest.json" "$T/missing-tcb.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["proof_digest"] = "sha256:abcd"
json.dump(d, open(sys.argv[2], "w"))
d = json.load(open(sys.argv[1])); d["artifact_binding"]["artifact_digest"] = "sha256:not-a-digest"
json.dump(d, open(sys.argv[3], "w"))
d = json.load(open(sys.argv[1])); del d["trusted_computing_base"]
json.dump(d, open(sys.argv[4], "w"))
PY
"$ROOT/build/rh_cli" proof --input "$T/bad-proof-digest.json" --out "$T/x" >/dev/null 2>&1; rc_proof_digest=$?
"$ROOT/build/rh_cli" proof --input "$T/bad-artifact-digest.json" --out "$T/x" >/dev/null 2>&1; rc_artifact_digest=$?
"$ROOT/build/rh_cli" proof --input "$T/missing-tcb.json" --out "$T/x" >/dev/null 2>&1; rc_tcb=$?
printf 'not json' > "$T/notjson"
"$ROOT/build/rh_cli" proof --input "$T/notjson" --out "$T/x" >/dev/null 2>&1; rc_json=$?
set -e
[[ "$rc_replay" -eq 4 && "$rc_schema" -eq 4 && "$rc_proof_digest" -eq 4 && "$rc_artifact_digest" -eq 4 && "$rc_tcb" -eq 4 && "$rc_json" -eq 4 ]] || fail "malformed proof must exit 4 (got $rc_replay/$rc_schema/$rc_proof_digest/$rc_artifact_digest/$rc_tcb/$rc_json)"

echo "test_proof_cli OK"
