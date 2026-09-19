#!/usr/bin/env bash
# tests/test_requirements.sh — requirements/safety index gate.
# Every R001-R030 and S001-S012 maps to real evidence; partial/deferred
# entries carry a gap; a broken mapping fails (negative control).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[requirements] FAIL: $1" >&2; exit 1; }

echo "[requirements] audit index"
out="$(bash "$ROOT/tools/requirements-audit.sh")" || fail "$out"
echo "$out"

echo "[requirements] negative control: a bogus token fails the audit"
tmp="$ROOT/ops/_bad_index.json"
cp "$ROOT/ops/requirements-index.json" "$tmp"
python3 - "$tmp" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["requirements"][0]["evidence"][0]["token"] = "TOKEN_THAT_DOES_NOT_EXIST_ANYWHERE"
json.dump(d, open(p, "w"), indent=2)
PY
# point the auditor at the bad copy by swapping it in briefly
mv "$ROOT/ops/requirements-index.json" "$ROOT/ops/_good_index.json"
mv "$tmp" "$ROOT/ops/requirements-index.json"
if bash "$ROOT/tools/requirements-audit.sh" >/dev/null 2>&1; then
  mv "$ROOT/ops/requirements-index.json" "$tmp"
  mv "$ROOT/ops/_good_index.json" "$ROOT/ops/requirements-index.json"
  rm -f "$tmp"
  fail "audit accepted a non-existent evidence token"
fi
mv "$ROOT/ops/requirements-index.json" "$tmp"
mv "$ROOT/ops/_good_index.json" "$ROOT/ops/requirements-index.json"
rm -f "$tmp"
echo "[requirements] negative control OK"

echo "[requirements] partial requirements state their gap"
python3 - "$ROOT/ops/requirements-index.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for r in d["requirements"]:
    if r["status"] != "implemented":
        assert r.get("gap"), (r["id"], "missing gap")
print("[requirements] gaps OK")
PY

echo "test_requirements OK"
