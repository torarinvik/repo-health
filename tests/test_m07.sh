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

echo "[m07] DNS pinning: unsafe answers fail before curl; safe answers are pinned"
grep -q "def rh_addr_guard" "$ROOT/src/rh_git.elisa" || fail "rh_addr_guard missing"
grep -q "def rh_v6_parse" "$ROOT/src/rh_git.elisa" || fail "strict IPv6 parser missing"
RESOLVE_T="/tmp/rh-m07-resolve-$$"
rm -rf "$RESOLVE_T"
trap 'rm -rf "$RESOLVE_T"' EXIT
RESOLVE_BIN="$RESOLVE_T/bin"
mkdir -p "$RESOLVE_BIN"
REAL_PYTHON="$(command -v python3)"
cat > "$RESOLVE_BIN/python3" <<'SH'
#!/bin/sh
set -eu
[ "$1" = "-I" ] || exit 90
shift
[ "$1" = "-c" ] || exit 91
shift
resolver="$1"
shift
host="$1"
exec "$RH_TEST_SYSTEM_PYTHON" -I -c '
import ipaddress, socket, sys
_, resolver, host, raw = sys.argv
def getaddrinfo(name, port, family=0, type=0, proto=0, flags=0):
    if name != host:
        raise RuntimeError("unexpected resolver host")
    rows = []
    for address in filter(None, raw.split(",")):
        parsed = ipaddress.ip_address(address)
        family = socket.AF_INET6 if parsed.version == 6 else socket.AF_INET
        sockaddr = (address, port, 0, 0) if parsed.version == 6 else (address, port)
        rows.append((family, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", sockaddr))
    return rows
socket.getaddrinfo = getaddrinfo
sys.argv = ["resolver", host]
exec(compile(resolver, "<resolver>", "exec"), {})
' "$resolver" "$host" "$RH_TEST_DNS_ADDRESSES"
SH
cat > "$RESOLVE_BIN/curl" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$@" > "$RH_TEST_CURL_LOG"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) : > "$2"; shift 2 ;;
    -w) printf '200'; shift 2 ;;
    *) shift ;;
  esac
done
SH
chmod +x "$RESOLVE_BIN/python3" "$RESOLVE_BIN/curl"
SOURCE_URL="https://api.github.com/repos/octocat/Hello-World"
export RH_TEST_SYSTEM_PYTHON="$REAL_PYTHON"
export RH_TEST_CURL_LOG="$RESOLVE_T/curl.args"
set +e
PATH="$RESOLVE_BIN:$PATH" RH_TEST_DNS_ADDRESSES="93.184.216.34,127.0.0.1" \
  "$ROOT/build/rh_cli" forge normalize --connector github --url "$SOURCE_URL" --out "$RESOLVE_T/mixed.out" --fetched-at 1700000000 >/dev/null 2>&1
mixed_rc=$?
set -e
[[ "$mixed_rc" -eq 4 ]] || fail "mixed public/private DNS set must fail closed (got $mixed_rc)"
[[ ! -e "$RH_TEST_CURL_LOG" ]] || fail "curl ran for mixed public/private DNS set"
[[ ! -e "$RESOLVE_T/mixed.out.source.err.resolved" ]] || fail "resolver scratch file leaked after rejected DNS set"

too_many_addresses="$(python3 -c 'print(",".join("8.8.8.%d" % n for n in range(1, 34)))')"
set +e
PATH="$RESOLVE_BIN:$PATH" RH_TEST_DNS_ADDRESSES="$too_many_addresses" \
  "$ROOT/build/rh_cli" forge normalize --connector github --url "$SOURCE_URL" --out "$RESOLVE_T/too-many.out" --fetched-at 1700000000 >/dev/null 2>&1
too_many_rc=$?
set -e
[[ "$too_many_rc" -eq 4 ]] || fail "oversized DNS answer set must fail closed (got $too_many_rc)"
[[ ! -e "$RH_TEST_CURL_LOG" ]] || fail "curl ran for oversized DNS answer set"
[[ ! -e "$RESOLVE_T/too-many.out.source.err.resolved" ]] || fail "resolver scratch file leaked after answer cap"

set +e
PATH="$RESOLVE_BIN:$PATH" RH_TEST_DNS_ADDRESSES="93.184.216.34,2606:2800:220:1:248:1893:25c8:1946" \
  "$ROOT/build/rh_cli" forge normalize --connector github --url "$SOURCE_URL" --out "$RESOLVE_T/public.out" --fetched-at 1700000000 >/dev/null 2>&1
public_rc=$?
set -e
[[ "$public_rc" -eq 4 ]] || fail "empty mocked HTTP body should fail normalization (got $public_rc)"
grep -Fxq -- "--disable" "$RH_TEST_CURL_LOG" || fail "curl user config was not disabled"
grep -Fxq -- "--noproxy" "$RH_TEST_CURL_LOG" || fail "curl proxy bypass missing"
grep -Fxq -- "*" "$RH_TEST_CURL_LOG" || fail "curl proxy bypass does not cover all hosts"
grep -Fxq -- "--resolve" "$RH_TEST_CURL_LOG" || fail "curl address pin missing"
grep -Fxq -- "api.github.com:443:93.184.216.34,[2606:2800:220:1:248:1893:25c8:1946]" "$RH_TEST_CURL_LOG" || fail "full validated IPv4/IPv6 answer set was not pinned"
! grep -Fxq -- "--location" "$RH_TEST_CURL_LOG" || fail "curl redirects were enabled"
! grep -Fxq -- "-L" "$RH_TEST_CURL_LOG" || fail "curl redirects were enabled"
[[ ! -e "$RESOLVE_T/public.out.source.err.resolved" ]] || fail "resolver scratch file leaked after successful pin"

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
dd = [s for s in d["sources"] if s["id"] == "deps-dev"]
assert len(dd) == 1 and dd[0]["redistribution"] == "metadata_only", dd
assert "version_metadata" in dd[0]["capabilities"] and "package_execution" in dd[0]["unsupported"], dd[0]
blob = json.dumps(d).lower()
for bad in ("token", "password", "secret", "api_key", "bearer"):
    assert bad not in blob, ("possible credential field", bad)
print("[m07] register validated:", len(d["sources"]), "sources")
PY

echo "[m07] honesty: STATUS.md marks M07 in progress"
grep -q 'M07 beta gate | `in_progress`' "$ROOT/STATUS.md" || fail "STATUS.md misstates M07"

echo "test_m07 OK"
