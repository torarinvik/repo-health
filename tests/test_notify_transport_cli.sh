#!/usr/bin/env bash
# M06-08: deterministic public-HTTPS notification delivery, policy gated and
# retryable when a receiver does not acknowledge the webhook.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-notify-transport-$$"

fail() { echo "[notify-transport] FAIL: $1" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

echo "[notify-transport] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
cd "$ROOT"

mkdir -p "$T/bin"
REAL_PYTHON="$(command -v python3)"
SYSTEM_PATH="$PATH"
cat > "$T/bin/python3" <<'SH'
#!/bin/sh
set -eu
[ "$1" = "-I" ] || exit 90
shift
[ "$1" = "-S" ] || exit 91
shift
[ "$1" = "-c" ] || exit 92
shift
resolver="$1"
shift
host="$1"
exec "$RH_TEST_SYSTEM_PYTHON" -I -S -c '
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
cat > "$T/bin/curl" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$@" > "$RH_NOTIFY_CURL_ARGS"
cat > "$RH_NOTIFY_CURL_CONFIG"
printf '%s' "$RH_NOTIFY_CURL_HTTP"
exit "$RH_NOTIFY_CURL_EXIT"
SH
chmod +x "$T/bin/python3" "$T/bin/curl"
export RH_TEST_SYSTEM_PYTHON="$REAL_PYTHON"
export RH_TEST_DNS_ADDRESSES="93.184.216.34"
export RH_NOTIFY_CURL_ARGS="$T/curl.args"
export RH_NOTIFY_CURL_CONFIG="$T/curl.stdin"
export RH_NOTIFY_CURL_HTTP=204
export RH_NOTIFY_CURL_EXIT=0
export PATH="$T/bin:$PATH"

INPUT="fixtures/notify-transport/input.json"
CONFIG="fixtures/notify-transport/config.json"
"$ROOT/build/rh_cli" notify-deliver --input "$INPUT" --transport "$CONFIG" --out "$T/sent.json" --state "$T/sent.state" >/dev/null || fail "successful delivery"
"$REAL_PYTHON" - "$T/sent.json" "$T/sent.state" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
state = json.load(open(sys.argv[2]))
assert result["schema"] == "rh-notify-delivery-result/1", result
assert result["deliveries"][0]["decision"] == "new", result
assert result["deliveries"][0]["delivery"] == "sent", result
assert result["deliveries"][0]["http_status"] == 204, result
assert len(result["deliveries"][0]["delivery_id"]) == 64, result
assert result["counts"] == {"sent": 1, "failed": 0, "unconfigured": 0, "not_attempted": 0}, result
assert len(state["rows"]) == 1 and state["rows"][0]["destination_id"] == 1, state
PY
cmp -s "$T/sent.json" "fixtures/notify-transport/result.json" || fail "deterministic delivery result changed"
[[ -f "$T/sent.json.transformations.json" ]] || fail "delivery transformation sidecar missing"
! grep -Fq -- "https://notifications.example.net" "$T/sent.json" || fail "endpoint appeared in public delivery result"
! grep -Fq -- "https://notifications.example.net" "$T/sent.json.transformations.json" || fail "endpoint appeared in public transformation sidecar"
grep -Fxq -- "--disable" "$T/curl.args" || fail "curl user config was not disabled"
grep -Fxq -- "--noproxy" "$T/curl.args" || fail "proxy bypass missing"
grep -Fxq -- "--proto" "$T/curl.args" || fail "HTTPS-only protocol constraint missing"
grep -Fxq -- "=https" "$T/curl.args" || fail "HTTPS-only protocol value missing"
grep -Fxq -- "--globoff" "$T/curl.args" || fail "URL globbing was not disabled"
grep -Fxq -- "--max-redirs" "$T/curl.args" || fail "redirect limit missing"
grep -Fxq -- "0" "$T/curl.args" || fail "redirect limit is not zero"
! grep -Fxq -- "--location" "$T/curl.args" || fail "redirect following was enabled"
! grep -Fxq -- "-L" "$T/curl.args" || fail "redirect following was enabled"
grep -Fxq -- "--resolve" "$T/curl.args" || fail "DNS pin missing"
grep -Fxq -- "notifications.example.net:443:93.184.216.34" "$T/curl.args" || fail "validated DNS address was not pinned"
grep -Fxq -- "--max-time" "$T/curl.args" || fail "request timeout missing"
grep -Fxq -- "15" "$T/curl.args" || fail "request timeout is not bounded"
grep -Fxq -- "--max-filesize" "$T/curl.args" || fail "response size cap missing"
grep -Fxq -- "16384" "$T/curl.args" || fail "response size cap is incorrect"
grep -Fq -- "Idempotency-Key: " "$T/curl.args" || fail "stable idempotency header missing"
grep -Fq -- "url = \"https://notifications.example.net/hooks/repo-health\"" "$T/curl.stdin" || fail "URL was not passed through curl config stdin"
grep -Fq -- 'request = "POST"' "$T/curl.stdin" || fail "webhook request method missing"
grep -Fq -- '\"schema\":\"rh-notification-webhook/1\"' "$T/curl.stdin" || fail "minimal webhook body missing"
grep -Fq -- '\"artifact_digest\":\"aaaaaaaaaaaaaaaa\"' "$T/curl.stdin" || fail "artifact digest missing from webhook"
! grep -Fq -- "https://notifications.example.net" "$T/curl.args" || fail "endpoint appeared in process arguments"
echo "[notify-transport] policy-gated HTTPS delivery and request bounds OK"

echo "[notify-transport] optional HMAC signing authenticates the exact body"
"$REAL_PYTHON" - "$T/signing.key" "$T/signed.json" <<'PY'
import json, os, sys
key_path, config_path = sys.argv[1:]
with open(key_path, "wb") as key_file:
    key_file.write(bytes(range(32)))
os.chmod(key_path, 0o644)
with open(config_path, "w", encoding="utf-8") as config_file:
    json.dump({"schema":"rh-notify-transport-config/1", "destinations":[{"id":1, "endpoint":"https://notifications.example.net/hooks/repo-health", "signing_key_file":key_path}]}, config_file, separators=(",", ":"))
PY
"$ROOT/build/rh_cli" notify-deliver --input "$INPUT" --transport "$T/signed.json" --out "$T/signed-result.json" --state "$T/signed.state" >/dev/null || fail "signed delivery"
"$REAL_PYTHON" - "$T/signing.key" "$T/signed.json" "$T/signed-result.json" "$T/signed-result.json.transformations.json" "$T/curl.args" "$T/curl.stdin" <<'PY'
import hashlib, hmac, json, os, re, stat, sys
key_path, config_path, result_path, sidecar_path, args_path, curl_config_path = sys.argv[1:]
key = open(key_path, "rb").read()
assert stat.S_IMODE(os.stat(key_path).st_mode) == 0o600
result = open(result_path, encoding="utf-8").read()
sidecar = open(sidecar_path, encoding="utf-8").read()
args = open(args_path, encoding="utf-8").read()
curl_config = open(curl_config_path, encoding="utf-8").read()
delivery_id = json.loads(result)["deliveries"][0]["delivery_id"]
payload = json.dumps({"schema":"rh-notification-webhook/1", "delivery_id":delivery_id, "destination_id":1, "rule_id":42, "subject_id":7, "artifact_digest":"aaaaaaaaaaaaaaaa", "occurred_at":1700000000}, separators=(",", ":"))
data_line = next(line for line in curl_config.splitlines() if line.startswith("data = "))
assert json.loads(data_line[len("data = "):]) == payload, data_line
header = re.search(r'^header = "X-Repo-Health-Signature: sha256=([0-9a-f]{64})"$', curl_config, re.M)
assert header, curl_config
assert header.group(1) == hmac.new(key, payload.encode(), hashlib.sha256).hexdigest()
assert header.group(1) not in args and key_path not in args
assert header.group(1) not in result and header.group(1) not in sidecar
assert key_path not in result and key_path not in sidecar
assert key.hex() not in result and key.hex() not in sidecar
PY

reject_signing_config() {
  local config_path="$1" label="$2" rc
  rm -f "$T/curl.args" "$T/rejected.state"
  set +e
  "$ROOT/build/rh_cli" notify-deliver --input "$INPUT" --transport "$config_path" --out "$T/rejected.out" --state "$T/rejected.state" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || fail "$label must fail closed (got $rc)"
  [[ ! -e "$T/curl.args" ]] || fail "$label reached curl"
  [[ ! -e "$T/rejected.state" ]] || fail "$label advanced notification state"
}

cat > "$T/missing-key.json" <<JSON
{"schema":"rh-notify-transport-config/1","destinations":[{"id":1,"endpoint":"https://notifications.example.net/hooks/repo-health","signing_key_file":"$T/missing.key"}]}
JSON
reject_signing_config "$T/missing-key.json" "missing signing key"
"$REAL_PYTHON" - "$T/short.key" <<'PY'
import sys
open(sys.argv[1], "wb").write(b"short signing key")
PY
cat > "$T/short-key.json" <<JSON
{"schema":"rh-notify-transport-config/1","destinations":[{"id":1,"endpoint":"https://notifications.example.net/hooks/repo-health","signing_key_file":"$T/short.key"}]}
JSON
reject_signing_config "$T/short-key.json" "short signing key"
"$REAL_PYTHON" - "$T/large.key" <<'PY'
import sys
open(sys.argv[1], "wb").write(bytes(4097))
PY
cat > "$T/large-key.json" <<JSON
{"schema":"rh-notify-transport-config/1","destinations":[{"id":1,"endpoint":"https://notifications.example.net/hooks/repo-health","signing_key_file":"$T/large.key"}]}
JSON
reject_signing_config "$T/large-key.json" "oversized signing key"
ln -s "$T/signing.key" "$T/symlink.key"
cat > "$T/symlink-key.json" <<JSON
{"schema":"rh-notify-transport-config/1","destinations":[{"id":1,"endpoint":"https://notifications.example.net/hooks/repo-health","signing_key_file":"$T/symlink.key"}]}
JSON
reject_signing_config "$T/symlink-key.json" "symlink signing key"
echo "[notify-transport] signing key bounds, permissions, and fail-closed paths OK"

echo "[notify-transport] failed delivery is retryable without cooldown advancement"
export RH_NOTIFY_CURL_HTTP=503
"$ROOT/build/rh_cli" notify-deliver --input "$INPUT" --transport "$CONFIG" --out "$T/failed.json" --state "$T/retry.state" >/dev/null || fail "HTTP failure report"
failed_delivery_id="$("$REAL_PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["deliveries"][0]["delivery_id"])' "$T/failed.json")"
"$REAL_PYTHON" - "$T/failed.json" "$T/retry.state" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
state = json.load(open(sys.argv[2]))
assert result["deliveries"][0]["delivery"] == "failed", result
assert result["deliveries"][0]["http_status"] == 503, result
assert result["counts"]["failed"] == 1, result
assert state["rows"] == [], state
PY
export RH_NOTIFY_CURL_HTTP=204 RH_NOTIFY_CURL_EXIT=22
"$ROOT/build/rh_cli" notify-deliver --input "$INPUT" --transport "$CONFIG" --out "$T/exit-failed.json" --state "$T/retry.state" >/dev/null || fail "curl exit failure report"
"$REAL_PYTHON" - "$T/exit-failed.json" "$T/retry.state" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
state = json.load(open(sys.argv[2]))
assert result["deliveries"][0]["delivery"] == "failed", result
assert result["deliveries"][0]["http_status"] is None, result
assert state["rows"] == [], state
PY
export RH_NOTIFY_CURL_HTTP=000 RH_NOTIFY_CURL_EXIT=0
"$ROOT/build/rh_cli" notify-deliver --input "$INPUT" --transport "$CONFIG" --out "$T/no-http-status.json" --state "$T/retry.state" >/dev/null || fail "missing HTTP status report"
"$REAL_PYTHON" - "$T/no-http-status.json" "$T/retry.state" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
state = json.load(open(sys.argv[2]))
assert result["deliveries"][0]["delivery"] == "failed", result
assert result["deliveries"][0]["http_status"] is None, result
assert state["rows"] == [], state
PY
export RH_NOTIFY_CURL_HTTP=204
export RH_NOTIFY_CURL_EXIT=0
"$ROOT/build/rh_cli" notify-deliver --input "$INPUT" --transport "$CONFIG" --out "$T/retry.json" --state "$T/retry.state" >/dev/null || fail "delivery retry"
"$REAL_PYTHON" - "$T/retry.json" "$failed_delivery_id" "$T/retry.state" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
state = json.load(open(sys.argv[3]))
assert result["deliveries"][0]["delivery"] == "sent", result
assert result["deliveries"][0]["delivery_id"] == sys.argv[2], result
assert len(state["rows"]) == 1, state
PY
echo "[notify-transport] failed send retries with the same idempotency key"

echo "[notify-transport] unauthorized and unconfigured events do not call curl"
cat > "$T/denied.json" <<'JSON'
{"schema":"rh-notify-input/3","destinations":[{"id":1,"target":"subscriber","authorized":false}],"events":[{"op":"notify","rule_id":42,"subject_id":7,"artifact_digest":"aaaaaaaaaaaaaaaa","destination_id":1,"now":1700000000}]}
JSON
rm -f "$T/curl.args"
"$ROOT/build/rh_cli" notify-deliver --input "$T/denied.json" --transport "$CONFIG" --out "$T/denied.out" --state "$T/denied.state" >/dev/null || fail "unauthorized delivery result"
[[ ! -e "$T/curl.args" ]] || fail "unauthorized event reached curl"
"$REAL_PYTHON" - "$T/denied.out" "$T/denied.state" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
state = json.load(open(sys.argv[2]))
assert result["deliveries"][0]["decision"] == "suppressed_unauthorized", result
assert result["deliveries"][0]["delivery"] == "not_attempted", result
assert result["counts"]["not_attempted"] == 1, result
assert state["rows"] == [], state
PY

cat > "$T/unconfigured.json" <<'JSON'
{"schema":"rh-notify-transport-config/1","destinations":[]}
JSON
"$ROOT/build/rh_cli" notify-deliver --input "$INPUT" --transport "$T/unconfigured.json" --out "$T/unconfigured.out" --state "$T/unconfigured.state" >/dev/null || fail "unconfigured delivery result"
[[ ! -e "$T/curl.args" ]] || fail "unconfigured event reached curl"
"$REAL_PYTHON" - "$T/unconfigured.out" "$T/unconfigured.state" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
state = json.load(open(sys.argv[2]))
assert result["deliveries"][0]["delivery"] == "unconfigured", result
assert result["counts"]["unconfigured"] == 1, result
assert state["rows"] == [], state
PY

echo "[notify-transport] private endpoint is rejected before curl"
cat > "$T/private.json" <<'JSON'
{"schema":"rh-notify-transport-config/1","destinations":[{"id":1,"endpoint":"https://127.0.0.1/hook"}]}
JSON
rm -f "$T/curl.args"
set +e
"$ROOT/build/rh_cli" notify-deliver --input "$INPUT" --transport "$T/private.json" --out "$T/private.out" --state "$T/private.state" >/dev/null 2>&1
private_rc=$?
set -e
[[ "$private_rc" -eq 4 ]] || fail "private endpoint must fail closed (got $private_rc)"
[[ ! -e "$T/curl.args" ]] || fail "private endpoint reached curl"
echo "[notify-transport] private endpoint rejected"

echo "[notify-transport] schema checks"
PATH="$SYSTEM_PATH" bash "$ROOT/tools/schema-check.sh" >/dev/null || fail "transport fixture schema"
echo "[notify-transport] OK"
