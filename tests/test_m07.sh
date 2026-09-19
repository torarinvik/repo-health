#!/usr/bin/env bash
# tests/test_m07.sh — M07 gate: adversarial transport (S002), parser
# hardening (M07-03), monitoring service/project separation (M07-11),
# source-respect quotas (M07-12), and backup/restore drills (M07-10).
# Deterministic, offline.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m07] FAIL: $1" >&2; exit 1; }

echo "[m07] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_m07" ]] || fail "test_m07 not built"

echo "[m07] transport + parser hardening + monitoring + quota + backup/restore"
rm -rf "$ROOT/build/tmp_m07"
mkdir -p "$ROOT/build/tmp_m07/store/evidence" "$ROOT/build/tmp_m07/restore/evidence"
out="$(cd "$ROOT" && "$ROOT/build/test_m07")" || fail "test_m07: $out"
[[ "$out" == *"M07 OK"* ]] || fail "test_m07: $out"
echo "$out"

echo "[m07] anti-rebinding: address guard applied after resolution"
grep -q "before any bytes leave" "$ROOT/src/rh_git.elisa" || fail "post-resolution guard note missing"
grep -q "def rh_addr_guard" "$ROOT/src/rh_git.elisa" || fail "rh_addr_guard missing"

echo "[m07] no-unknown-to-zero: monitor rate is -1 with no denominator"
grep -q "MUST surface unknown rather than 0" "$ROOT/src/rh_ops.elisa" || fail "unknown-rate contract missing"

echo "[m07] integrity-not-safety: digest verification is not a signature claim"
grep -q "NOT a cryptographic" "$ROOT/src/rh_ops.elisa" || fail "integrity-vs-safety caveat missing"

echo "[m07] corrupt backup must not restore"
grep -q "never restored" "$ROOT/src/rh_ops.elisa" || fail "restore refusal contract missing"

echo "[m07] deletion drill: replayability label changes when inputs are gone"
grep -q "NOT replayable" "$ROOT/src/rh_ops.elisa" || fail "replayability contract missing"
grep -q "Idempotent" "$ROOT/src/rh_store.elisa" || fail "idempotent-delete note missing"

echo "[m07] source review register schema (M07-06)"
python3 - "$ROOT/ops/source-review-register.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("register_version") == "rh-source-review/1", "register version"
assert len(d.get("sources", [])) >= 5, "need at least five reviewed source families"
required = ["id", "kind", "terms_reviewed_at", "redistribution", "attribution",
            "personal_data_fields", "retention_days", "contact",
            "capabilities", "unauthorized", "unsupported"]
ids = set()
for s in d["sources"]:
    for k in required:
        assert k in s, ("missing field", s.get("id"), k)
    assert s["id"] not in ids, "duplicate source id"
    ids.add(s["id"])
    assert s["capabilities"], ("no declared capabilities", s["id"])
    assert isinstance(s["retention_days"], int) and s["retention_days"] > 0
    assert s["redistribution"] in ("none", "metadata_only", "full"), s["id"]
    assert s["terms_reviewed_at"], s["id"]
# GitHub traffic must be explicitly unauthorized, not silently scraped (P01).
gh = [s for s in d["sources"] if s["id"] == "github"][0]
assert "traffic" in gh["unauthorized"], "github traffic must be unauthorized"
blob = json.dumps(d).lower()
for bad in ("token", "password", "secret", "api_key", "bearer"):
    assert bad not in blob, ("possible credential field", bad)
print("[m07] register validated:", len(d["sources"]), "sources")
PY

echo "[m07] honesty: STATUS.md marks M07 in progress"
grep -q 'M07 beta gate | `in_progress`' "$ROOT/STATUS.md" || fail "STATUS.md misstates M07"

echo "test_m07 OK"
