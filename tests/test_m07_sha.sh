#!/usr/bin/env bash
# tests/test_m07_sha.sh — M07-04 publication integrity primitive.
# 1) SHA-256/SHA-384/SHA-512, SRI Base64, and HMAC-SHA256 checked against published vectors.
# 2) CLI sign/verify round-trip on a real file.
# 3) Negative controls: tampered subject, wrong key, empty key, malformed sig.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-m07-sha"

fail() { echo "[m07-sha] FAIL: $1" >&2; exit 1; }

echo "[m07-sha] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_m07_sha" ]] || fail "test_m07_sha not built"
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

echo "[m07-sha] published vectors"
out="$("$ROOT/build/test_m07_sha")" || fail "vector suite failed: $out"
echo "$out"
[[ "$out" == "M07 SHA OK" ]] || fail "unexpected vector output"

rm -rf "$T"; mkdir -p "$T"
printf 'release-key-v1-0123456789abcdef0123456789abcdef' > "$T/key"
printf '{"release":"1.0.0","packet":true}\n' > "$T/packet.json"

echo "[m07-sha] CLI sign/verify round-trip"
"$ROOT/build/rh_cli" sign --key "$T/key" --subject "$T/packet.json" --sig "$T/packet.sig" >/dev/null \
  || fail "sign failed"
python3 - "$T/key" <<'PY'
import os, stat, sys
assert stat.S_IMODE(os.stat(sys.argv[1]).st_mode) == 0o600, oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))
PY
echo "[m07-sha] signing key is restricted to its owner"
grep -q '"algorithm":"hmac-sha256"' "$T/packet.sig" || fail "signature missing algorithm"
cp "$T/packet.json" "$T/packet.before-collision"
set +e
"$ROOT/build/rh_cli" sign --key "$T/key" --subject "$T/packet.json" --sig "$T/packet.json" >/dev/null 2>&1; rc_sign_subject=$?
"$ROOT/build/rh_cli" sign --key "$T/key" --subject "$T/packet.json" --sig "$T/key" >/dev/null 2>&1; rc_sign_key=$?
"$ROOT/build/rh_cli" verify --key "$T/key" --subject "$T/packet.json" --sig "$T/packet.json" >/dev/null 2>&1; rc_verify_subject=$?
set -e
[[ "$rc_sign_subject" -eq 3 && "$rc_sign_key" -eq 3 && "$rc_verify_subject" -eq 3 ]] || fail "colliding signing paths must be rejected"
cmp -s "$T/packet.json" "$T/packet.before-collision" || fail "colliding signing path modified the subject"
vout="$("$ROOT/build/rh_cli" verify --key "$T/key" --subject "$T/packet.json" --sig "$T/packet.sig")" \
  || fail "verify failed: $vout"
echo "$vout"
case "$vout" in
  *"not a code-safety claim"*) : ;;
  *) fail "verify must not claim code safety" ;;
esac

echo "[m07-sha] negative controls"
set +e
printf '{"release":"1.0.0","packet":false}\n' > "$T/packet.json"
"$ROOT/build/rh_cli" verify --key "$T/key" --subject "$T/packet.json" --sig "$T/packet.sig" >/dev/null 2>&1
rc_tamper=$?
printf 'other-key--0123456789abcdef0123456789abcdef' > "$T/key2"
printf '{"release":"1.0.0","packet":true}\n' > "$T/packet.json"
"$ROOT/build/rh_cli" verify --key "$T/key2" --subject "$T/packet.json" --sig "$T/packet.sig" >/dev/null 2>&1
rc_wrongkey=$?
: > "$T/emptykey"
"$ROOT/build/rh_cli" sign --key "$T/emptykey" --subject "$T/packet.json" --sig "$T/empty.sig" >/dev/null 2>&1
rc_empty=$?
printf 'short' > "$T/shortkey"
"$ROOT/build/rh_cli" sign --key "$T/shortkey" --subject "$T/packet.json" --sig "$T/short.sig" >/dev/null 2>&1
rc_short=$?
printf 'not json\n' > "$T/bad.sig"
"$ROOT/build/rh_cli" verify --key "$T/key" --subject "$T/packet.json" --sig "$T/bad.sig" >/dev/null 2>&1
rc_badsig=$?
set -e
[[ "$rc_tamper" -eq 5 ]] || fail "tampered subject must exit 5 (got $rc_tamper)"
[[ "$rc_wrongkey" -eq 5 ]] || fail "wrong key must exit 5 (got $rc_wrongkey)"
[[ "$rc_empty" -eq 3 && "$rc_short" -eq 3 ]] || fail "empty/short key must exit 3 (got $rc_empty/$rc_short)"
[[ "$rc_badsig" -eq 3 ]] || fail "malformed signature must exit 3 (got $rc_badsig)"
echo "[m07-sha] negative controls OK"

echo "test_m07_sha OK"
