#!/usr/bin/env bash
# tests/test_connector_cli.sh — M02 connector-instance execution path:
# `rh_cli connector check --instance <file> --out <file>` reads an
# rh-connector-instance/1 document and writes rh-connector-instance-result/1
# with the connector capability table (unsupported stated, never omitted),
# the operator-declared capabilities, and a usability verdict. Approval and
# transport are separate gates: an arbitrary approved self-hosted base URL is
# usable (R007), but a URL in loopback/private space is transport-rejected
# even when approved (S002). Unknown connectors, unknown capability keys, and
# capabilities the connector does not declare fail closed (exit 4).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-connector"

fail() { echo "[connector] FAIL: $1" >&2; exit 1; }

echo "[connector] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT"/fixtures/connectors/instance-*.json "$T"/

echo "[connector] arbitrary approved self-hosted base URL is usable"
"$ROOT/build/rh_cli" connector check \
  --instance "$T/instance-gitea-selfhosted.json" --out "$T/gt.out" | grep -q "verdict=usable" \
  || fail "approved self-hosted gitea instance must be usable"
python3 - "$T/gt.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-connector-instance-result/1", d
assert d["connector_id"] == "gitea", d
assert d["base_url"] == "https://codeberg.example.org", d
assert d["approved"] is True and d["verdict"] == "usable", d
# The connector's full capability table is stated; unsupported is explicit.
assert d["capabilities"]["history"] == "read", d
assert d["capabilities"]["issues"] == "read", d
assert d["capabilities"]["reviews"] == "read", d
assert d["capabilities"]["permissions"] == "unsupported", d
assert d["capabilities"]["traffic"] == "unsupported", d
assert set(d["declared_capabilities"]) == {"history", "issues", "reviews", "releases"}, d
assert "approval never overrides transport" in d["note"], d
print("[connector] self-hosted usable OK")
PY

echo "[connector] approval and transport are separate gates"
# Approved, but loopback: transport policy wins.
"$ROOT/build/rh_cli" connector check \
  --instance "$T/instance-forgejo-loopback.json" --out "$T/lb.out" | grep -q "verdict=transport-rejected" \
  || fail "approved loopback instance must be transport-rejected"
# Unapproved public instance: reported unapproved, not usable.
cat > "$T/unapproved.json" <<'JSON'
{"schema":"rh-connector-instance/1","connector_id":"forgejo","base_url":"https://code.example.net","approved":false}
JSON
"$ROOT/build/rh_cli" connector check --instance "$T/unapproved.json" --out "$T/un.out" | grep -q "verdict=unapproved" \
  || fail "unapproved instance must be unapproved"
# Various hostile-but-approved URLs all fail the transport gate.
for u in "https://10.0.0.5" "https://192.168.1.1" "https://169.254.169.254" \
         "http://git.example.org" "https://user@git.example.org" "https://intranet"; do
  python3 - "$T/url.json" "$u" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({
  "schema": "rh-connector-instance/1", "connector_id": "gitea",
  "base_url": sys.argv[2], "approved": True}))
PY
  "$ROOT/build/rh_cli" connector check --instance "$T/url.json" --out "$T/url.out" \
    | grep -q "verdict=transport-rejected" || fail "approved URL $u must be transport-rejected"
done
python3 - "$T/lb.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["verdict"] == "transport-rejected", d
assert d["approved"] is True, d
print("[connector] transport gate OK")
PY

echo "[connector] determinism and connector-specific capability tables"
a="$("$ROOT/build/rh_cli" connector check --instance "$T/instance-gitea-selfhosted.json" --out "$T/d1.out" >/dev/null; cat "$T/d1.out")"
b="$("$ROOT/build/rh_cli" connector check --instance "$T/instance-gitea-selfhosted.json" --out "$T/d2.out" >/dev/null; cat "$T/d2.out")"
[[ "$a" == "$b" ]] || fail "connector check must be deterministic"
# GitHub declares a windowed traffic capability; Gitea does not (no traffic API).
cat > "$T/gh.json" <<'JSON'
{"schema":"rh-connector-instance/1","connector_id":"github","base_url":"https://github.example.com","approved":true,"capabilities":["history","traffic"]}
JSON
"$ROOT/build/rh_cli" connector check --instance "$T/gh.json" --out "$T/gh.out" >/dev/null
python3 - "$T/gh.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["traffic"] == "windowed", d
assert d["capabilities"]["permissions"] == "authorized-only", d
assert "traffic" in d["declared_capabilities"], d
print("[connector] capability tables OK")
PY

echo "[connector] unsupported capability declarations and malformed input fail closed"
check_rc() { # payload
  printf '%s' "$1" > "$T/bad.json"
  "$ROOT/build/rh_cli" connector check --instance "$T/bad.json" --out "$T/bad.out" >/dev/null 2>&1
  echo $?
}
set +e
rc1=$(check_rc '{"schema":"rh-connector-instance/1","connector_id":"sourceforge","base_url":"https://x.example.com","approved":true}')
rc2=$(check_rc '{"schema":"rh-connector-instance/1","connector_id":"gitea","base_url":"https://x.example.com","approved":true,"capabilities":["traffic"]}')
rc3=$(check_rc '{"schema":"rh-connector-instance/1","connector_id":"gitea","base_url":"https://x.example.com","approved":true,"capabilities":["telepathy"]}')
rc4=$(check_rc '{"schema":"rh-connector-instance/2","connector_id":"gitea","base_url":"https://x.example.com"}')
rc5=$(check_rc '{"schema":"rh-connector-instance/1","connector_id":"gitea"}')
rc6=$(check_rc '{"schema":"rh-connector-instance/1","connector_id":"gitea","base_url":"https://x.example.com","approved":true,"capabilities":[5]}')
rc7=$(check_rc 'not json')
"$ROOT/build/rh_cli" connector check --instance "$T/nope.json" --out "$T/x.out" >/dev/null 2>&1
rc8=$?
set -e
for rc in "$rc1" "$rc2" "$rc3" "$rc4" "$rc5" "$rc6" "$rc7" "$rc8"; do
  [[ "$rc" -eq 4 ]] || fail "malformed connector instance must exit 4 (got $rc)"
done

echo "test_connector_cli OK"
