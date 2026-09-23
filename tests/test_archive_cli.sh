#!/usr/bin/env bash
# tests/test_archive_cli.sh — bounded source-archive metadata execution.
# Archive bytes are never expanded or executed; this path records only
# declared identifiers, links, digests, times, and sizes.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-archive"

fail() { echo "[archive] FAIL: $1" >&2; exit 1; }

echo "[archive] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-archive-input/1","archives":[{"identifier":"v1.2.3","kind":"source","format":"tar.gz","uri":"https://example.org/v1.2.3.tar.gz","digest":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","published_at":1700000000,"size":12345},{"identifier":"snapshot-2024","kind":"snapshot","format":"zip","uri":"file:///tmp/snapshot.zip","digest":null,"published_at":null,"size":null}]}
JSON

"$ROOT/build/rh_cli" archive --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" "$T/in.json" "$T/out.json.transformations.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-archive-result/1", d
tr = json.load(open(sys.argv[3]))
assert tr["adapter"] == "source-archive-metadata" and tr["output_schema"] == d["schema"], tr
assert tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/source-archive-metadata/1").hexdigest(), tr
assert {f["state"] for f in tr["fields"]} == {"preserved", "transformed", "unknown", "unsupported", "discarded"}, tr
assert d["counts"] == {"archives": 2, "digest_known": 1, "published_known": 1}, d
assert d["archives"][0]["identifier"] == "v1.2.3" and d["archives"][0]["digest"].startswith("sha256:"), d
assert d["archives"][1]["published_at"] is None and d["archives"][1]["size"] is None, d
assert d["source"] == {"history_supported": False, "identity_supported": False, "extraction_supported": False}, d
assert "never extracted or executed" in d["note"], d
print("[archive] metadata + explicit unsupported capabilities OK")
PY

echo "[archive] deterministic output"
"$ROOT/build/rh_cli" archive --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "archive output not deterministic"

echo "[archive] invalid digest, URI, duplicate identifier, and malformed JSON fail closed"
set +e
sed 's/sha256:[0-9a-f]*/sha256:bad/' "$T/in.json" > "$T/baddigest.json"
"$ROOT/build/rh_cli" archive --input "$T/baddigest.json" --out "$T/x" >/dev/null 2>&1; rc_digest=$?
sed 's#https://example.org#http://example.org#' "$T/in.json" > "$T/baduri.json"
"$ROOT/build/rh_cli" archive --input "$T/baduri.json" --out "$T/x" >/dev/null 2>&1; rc_uri=$?
sed 's/snapshot-2024/v1.2.3/' "$T/in.json" > "$T/duplicate.json"
"$ROOT/build/rh_cli" archive --input "$T/duplicate.json" --out "$T/x" >/dev/null 2>&1; rc_dup=$?
printf 'not json' > "$T/notjson"
"$ROOT/build/rh_cli" archive --input "$T/notjson" --out "$T/x" >/dev/null 2>&1; rc_json=$?
set -e
for rc in "$rc_digest" "$rc_uri" "$rc_dup" "$rc_json"; do
  [[ "$rc" -eq 4 ]] || fail "malformed archive metadata must exit 4 (got $rc)"
done

echo "test_archive_cli OK"
