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
cat > "$T/in.json" <<'JSON'
{"schema":"rh-proof-input/1","proposition_id":"bounds-safe","source_revision":"rev-123","checker_version":"elisa-proof/0.3","assumptions":["allocator-model","no-ffi"],"trusted_computing_base":["elisa-runtime","proof-kernel"],"proof_digest":"sha256:abcd","replay_result":"replayed","artifact_binding":{"source_revision":"rev-123","artifact_digest":"sha256:artifact"}}
JSON
"$ROOT/build/rh_cli" proof --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "proof run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-proof-result/1", d
assert d["replay_result"] == "replayed", d
assert d["assumptions"] == ["allocator-model", "no-ffi"], d
assert d["trusted_computing_base"] == ["elisa-runtime", "proof-kernel"], d
assert d["assumption_count"] == 2 and d["trusted_computing_base_count"] == 2, d
assert d["artifact_binding"]["status"] == "bound", d
assert "not a whole-application safety claim" in d["note"], d
print("[proof] typed replay/binding evidence OK")
PY

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
printf '{"schema":"rh-proof-input/1","proposition_id":"x","source_revision":"r","checker_version":"c","proof_digest":"d","replay_result":"maybe"}' > "$T/bad-replay.json"
"$ROOT/build/rh_cli" proof --input "$T/bad-replay.json" --out "$T/x" >/dev/null 2>&1; rc_replay=$?
printf '{"schema":"rh-proof-input/2"}' > "$T/bad-schema.json"
"$ROOT/build/rh_cli" proof --input "$T/bad-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf 'not json' > "$T/notjson"
"$ROOT/build/rh_cli" proof --input "$T/notjson" --out "$T/x" >/dev/null 2>&1; rc_json=$?
set -e
[[ "$rc_replay" -eq 4 && "$rc_schema" -eq 4 && "$rc_json" -eq 4 ]] || fail "malformed proof must exit 4 (got $rc_replay/$rc_schema/$rc_json)"

echo "test_proof_cli OK"
