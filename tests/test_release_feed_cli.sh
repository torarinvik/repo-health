#!/usr/bin/env bash
# tests/test_release_feed_cli.sh — M08 release-only source execution path:
# `rh_cli release-feed` turns an rh-release-feed-input/1 feed into
# rh-release-feed-result/1. Asserts published (valid time) and first-seen
# (known time) are kept separate, a missing published time stays unknown,
# asset/digest counts are exact, history/identity are unsupported, a
# re-observation keeps its own first-seen, and malformed input fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-release-feed"

fail() { echo "[release-feed] FAIL: $1" >&2; exit 1; }

echo "[release-feed] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-release-feed-input/1","first_seen":1700000123,"releases":[{"tag":"v1.0.0","published_at":1700000000,"assets":[{"name":"a.tgz","digest":"sha256:abc"},{"name":"b.tgz"}]},{"tag":"v1.1.0"}]}
JSON
"$ROOT/build/rh_cli" release-feed --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-release-feed-result/1", d
r = d["releases"]
assert len(r) == 2 and d["rejected"] == 0, d
assert r[0] == {"tag": "v1.0.0", "published_at": 1700000000, "first_seen": 1700000123,
                "asset_count": 2, "digest_known_count": 1}, r[0]
# missing published time stays unknown (null), never replaced by first-seen
assert r[1]["published_at"] is None and r[1]["first_seen"] == 1700000123, r[1]
assert d["source"] == {"history_supported": False, "identity_supported": False}, d["source"]
assert "no history or author identity is derived" in d["note"], d["note"]
print("[release-feed] fields + validity/known time OK")
PY

echo "[release-feed] a re-observation keeps its own first-seen (tag is not identity)"
cat > "$T/reobs.json" <<'JSON'
{"schema":"rh-release-feed-input/1","first_seen":1600000000,"releases":[{"tag":"v1.0.0","published_at":1700000000}]}
JSON
"$ROOT/build/rh_cli" release-feed --input "$T/reobs.json" --out "$T/reobs.out" >/dev/null || fail "reobs"
python3 - "$T/reobs.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["releases"][0]["first_seen"] == 1600000000, d
assert d["releases"][0]["published_at"] == 1700000000, d
print("[release-feed] re-observation OK")
PY

echo "[release-feed] an entry with no tag is rejected, not guessed"
printf '{"first_seen":5,"releases":[{"published_at":5},{"tag":"ok"}]}' > "$T/rej.json"
"$ROOT/build/rh_cli" release-feed --input "$T/rej.json" --out "$T/rej.out" >/dev/null || fail "rej"
python3 - "$T/rej.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["rejected"] == 1 and len(d["releases"]) == 1, d
assert d["releases"][0]["tag"] == "ok", d
print("[release-feed] rejected-not-guessed OK")
PY

echo "[release-feed] determinism"
"$ROOT/build/rh_cli" release-feed --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "release-feed output not deterministic"

echo "[release-feed] negatives fail closed"
set +e
printf '{"releases":[]}' > "$T/nofs.json"
"$ROOT/build/rh_cli" release-feed --input "$T/nofs.json" --out "$T/x" >/dev/null 2>&1; rc_nofs=$?
printf '[{"tag":"v1"}]' > "$T/arr.json"
"$ROOT/build/rh_cli" release-feed --input "$T/arr.json" --out "$T/x" >/dev/null 2>&1; rc_arr=$?
printf '{"first_seen":1,"releases":42}' > "$T/badshape.json"
"$ROOT/build/rh_cli" release-feed --input "$T/badshape.json" --out "$T/x" >/dev/null 2>&1; rc_shape=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" release-feed --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" release-feed --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_nofs" "$rc_arr" "$rc_shape" "$rc_json" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed release-feed input must exit 4 (got $rc)"
done

echo "test_release_feed_cli OK"
