#!/usr/bin/env bash
# tests/test_m02.sh — M02 gate: forge adapters without live network.
# Default: sanitized fixtures + file:// transport only. Live GitHub fetch
# runs solely under RH_LIVE_TESTS=1 (opt-in, never in the default gate).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FORGE="$ROOT/build/test_forge"
W="/tmp/rh-m02-wd"

fail() { echo "[m02] FAIL: $1" >&2; exit 1; }
expect() {
  local want="$1"; shift
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  [[ "$got" == "$want" ]] || fail "expected exit $want, got $got: $*"
}

echo "[m02] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$FORGE" ]] || fail "test_forge not built"

rm -rf "$W"; mkdir -p "$W"
cp "$ROOT"/fixtures/connectors/*.json "$W"/
cp "$ROOT"/connectors/manifests/*.json "$W"/

echo "[m02] forge unit (goldens, escape, manifests, file transport, guard)"
out="$("$FORGE" "$W")" || fail "test_forge: $out"
[[ "$out" == *"FORGE OK"* ]] || fail "test_forge: $out"
echo "$out"

echo "[m02] manifests: distinct ids, honest capability strings"
python3 - "$ROOT/connectors/manifests" <<'EOF'
import json, glob, sys
seen = {}
for p in sorted(glob.glob(sys.argv[1] + "/*.json")):
    d = json.load(open(p))
    cid = d["connector_id"]
    assert cid not in seen, ("duplicate connector", cid)
    seen[cid] = p
    assert d["connector_version"] == "1.0.0", p
    assert isinstance(d["capabilities"], dict), p
assert set(seen) == {"generic-git", "github", "gitlab", "forgejo", "gitea", "bitbucket", "mercurial", "subversion", "fossil", "release-feed"}, seen
assert seen["mercurial"] != seen["subversion"] and seen["subversion"] != seen["fossil"], "native-vcs manifests must be separate"
assert seen["forgejo"] != seen["gitea"], "forgejo/gitea must be separate manifests"
print("[m02] manifests OK:", ", ".join(sorted(seen)))
EOF

echo "[m02] goldens are valid canonical observations"
python3 - "$ROOT/fixtures/connectors" <<'EOF'
import json, glob, sys
for p in sorted(glob.glob(sys.argv[1] + "/*.canonical.json")):
    d = json.load(open(p))
    assert d["schema"] == "rh-canonical-repo/1", p
    assert d["source"] in ("github", "gitlab", "gitea", "forgejo", "bitbucket"), p
    assert d["native_id"].startswith(d["source"] + ":"), p
    assert isinstance(d["created_at"], int), p
print("[m02] goldens OK")
EOF

echo "[m02] bounded workflow-event import"
"$ROOT/tests/test_forge_events_cli.sh" >/dev/null || fail "forge events CLI"
echo "[m02] workflow-event boundary OK"

if [[ "${RH_LIVE_TESTS:-0}" == "1" ]]; then
  echo "[m02] live GitHub fetch (opt-in)"
  out="$("$FORGE" "$W" live)" || fail "live test_forge failed (provider outage is not a code regression; re-run to distinguish)"
  [[ "$out" == *"FORGE OK"* ]] || fail "live: $out"
  echo "$out"
else
  echo "[m02] live tests skipped (RH_LIVE_TESTS!=1)"
fi

echo "[m02] usage gate"
expect 2 "$FORGE"

echo "[m02] store selftest (blobs, dedup, cursor, leases, coverage)"
STORE="$ROOT/build/test_store"
[[ -x "$STORE" ]] || fail "test_store not built"
SW="/tmp/rh-m02-store"
rm -rf "$SW"
out="$("$STORE" "$SW" selftest)" || fail "store selftest: $out"
[[ "$out" == *"STORE OK"* ]] || fail "store selftest: $out"
echo "$out"

echo "[m02] S005: 3x webhook + reordering yields exactly one copy"
grep -q "wh-exactly-one-each" "$ROOT/src/test_store.elisa" || fail "webhook dedup check missing"
grep -q "wh-x-dupe-3" "$ROOT/src/test_store.elisa" || fail "webhook triple-delivery check missing"

echo "[m02] crash injection: kill -9 holder, fencing must hold (S004/M02-03)"
"$STORE" "$SW" hold job3 2 > "$SW/hold.out" 2>&1 &
HOLDER=$!
sleep 1
old_tok="$(awk '/^TOKEN /{print $2}' "$SW/hold.out")"
[[ -n "$old_tok" ]] || { kill -9 "$HOLDER" 2>/dev/null; fail "holder never acquired"; }
sleep 4
now="$(date +%s)"
new_tok="$("$STORE" "$SW" acquire job3 w2 100 "$now" | awk '/^RESULT /{print $2}')"
[[ "$new_tok" == "$((old_tok + 1))" ]] || { kill -9 "$HOLDER" 2>/dev/null; fail "expired lease not reclaimable (old=$old_tok new=$new_tok)"; }
kill -9 "$HOLDER" 2>/dev/null
wait "$HOLDER" 2>/dev/null || true
stale="$("$STORE" "$SW" release job3 "$old_tok" 3 w1 "$now" | awk '/^RESULT /{print $2}')"
[[ "$stale" == "0" ]] || fail "stale worker published (token $old_tok)"
fresh="$("$STORE" "$SW" release job3 "$new_tok" 3 w2 "$now" | awk '/^RESULT /{print $2}')"
[[ "$fresh" == "1" ]] || fail "current worker release failed"
grep -q "stale-release-refused" "$SW/store/leases/job3.log" || fail "refusal not logged"
echo "[m02] crash injection OK (old=$old_tok refused, new=$new_tok released)"

echo "test_m02 OK"
