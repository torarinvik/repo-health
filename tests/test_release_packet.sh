#!/usr/bin/env bash
# tests/test_release_packet.sh — M07 beta-checklist / M12 release packet:
# the packet must be generated from real tree state, be deterministic, and
# must not overclaim (no safety/trust verdicts, no result assertions).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[packet] FAIL: $1" >&2; exit 1; }

tmp="$ROOT/build/tmp_packet"
rm -rf "$tmp"
mkdir -p "$tmp"

echo "[packet] generate"
bash "$ROOT/tools/release-packet.sh" "$tmp" test-label >/dev/null
[[ -f "$tmp/release-packet.json" ]] || fail "json not written"
[[ -f "$tmp/release-packet.md" ]] || fail "markdown not written"

echo "[packet] determinism"
bash "$ROOT/tools/release-packet.sh" "$tmp" test-label >/dev/null
cp "$tmp/release-packet.json" "$tmp/once.json"
bash "$ROOT/tools/release-packet.sh" "$tmp" test-label >/dev/null
diff -q "$tmp/once.json" "$tmp/release-packet.json" >/dev/null || fail "packet not deterministic"

echo "[packet] schema + honesty"
python3 - "$tmp/release-packet.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["packet_version"] == "rh-release-packet/1"
assert d["release_label"] == "test-label"
cat = d["catalog"]
assert cat["implemented"] == len(d["metrics"]), "catalog count mismatch"
assert cat["candidate_target"] == 360
assert d["metrics"], "no implemented metrics"
for m in d["metrics"]:
    assert m["denominator_rule"], ("metric without denominator", m["key"])
    assert m["fixture_references"], ("metric without fixtures", m["key"])
    assert m["source_requirements"], ("metric without source reqs", m["key"])
fx = d["fixtures"]
assert fx["total"] == 40, fx
assert fx["covered"] + fx["partial"] + fx["planned"] == 40, fx
assert len(fx["planned_ids"]) == fx["planned"], fx
assert d["fixtures"]["note"].startswith("F001-F040")
assert len(d["supported_sources"]) >= 5
for s in d["supported_sources"]:
    assert s["capabilities"], ("source without capabilities", s["id"])
    assert "unauthorized" in s and "unsupported" in s
assert d["limitations"], "limitations must be stated"
perf = d["performance"]
assert perf["manifest"] == "build/bench-manifest.json", perf
assert "machine-specific" in perf["note"], perf
assert d["verification"]["harnesses"], "harness list must be present"
assert "does not assert a pass" in json.dumps(d["verification"]) or \
       "does not assert" in d["verification"]["run_required"]
# Scan the claim-bearing fields; milestone titles come from the plan and are
# not verdicts.
claims = json.dumps([d["metrics"], d["security_scope"], d["limitations"],
                     d["supported_sources"]]).lower()
for bad in (" safe ", "trustworthy", "guaranteed", "certified"):
    assert bad not in claims, ("overclaim language", bad)
print("[packet] schema OK:", cat["implemented"], "metrics,", len(d["supported_sources"]), "sources")
PY

echo "[packet] markdown carries limitations and no safe verdict"
md="$tmp/release-packet.md"
grep -q "Known limitations" "$md" || fail "markdown missing limitations"
grep -q "not a signature" "$md" || fail "markdown missing signing caveat"
if grep -qiE "\bis safe\b|trustworthy|certified safe" "$md"; then
  fail "markdown contains a safety verdict"
fi
echo "[packet] markdown OK"

echo "[packet] signing round-trip (M07-04)"
[[ -x "$ROOT/build/rh_cli" ]] || bash "$ROOT/tools/build.sh" >/dev/null
key="$tmp/key"
printf 'test-key-material\n' > "$key"
RH_SIGNING_KEY_FILE="$key" bash "$ROOT/tools/release-packet.sh" "$tmp" test-label >/dev/null 2>&1
[[ -f "$tmp/release-packet.sig" ]] || fail "signed packet missing signature file"
vsig="$("$ROOT/build/rh_cli" verify --key "$key" --subject "$tmp/release-packet.json" --sig "$tmp/release-packet.sig")" \
  || fail "packet signature did not verify"
case "$vsig" in
  *"not a code-safety claim"*) : ;;
  *) fail "verification must not claim code safety" ;;
esac
grep -q '"algorithm":"hmac-sha256"' "$tmp/release-packet.sig" || fail "signature missing algorithm"
rm -f "$tmp/release-packet.sig"
bash "$ROOT/tools/release-packet.sh" "$tmp" test-label >/dev/null 2>&1
[[ ! -f "$tmp/release-packet.sig" ]] || fail "unsigned run wrote a signature"
echo "[packet] signing OK"

echo "test_release_packet OK"
