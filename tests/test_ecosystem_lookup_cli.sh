#!/usr/bin/env bash
# tests/test_ecosystem_lookup_cli.sh — M03-10 bounded ecosyste.ms package
# lookup adapter. Captured input stays deterministic; pure harness cases cover
# fixed URL construction and normalization of one live response without network.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T="/tmp/rh-ecosystem-lookup"

fail() { echo "[ecosystem-lookup] FAIL: $1" >&2; exit 1; }
expect() {
  local want="$1"; shift
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  [[ "$got" == "$want" ]] || fail "expected exit $want, got $got: $*"
}

echo "[ecosystem-lookup] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
[[ -x "$ROOT/build/test_ecosystem_lookup" ]] || fail "contract harness not built"
[[ "$("$ROOT/build/test_ecosystem_lookup")" == "ECOSYSTEM LOOKUP OK" ]] || fail "query/live contract harness"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/packages/ecosyste-ms-lookup.json" "$T/input.json"

echo "[ecosystem-lookup] captured result preserves candidate mapping and coverage"
"$ROOT/build/rh_cli" ecosystem lookup --input "$T/input.json" --out "$T/out.json" >/dev/null || fail "lookup adapter"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-ecosystem-lookup-result/1", d
assert d["provider"] == "ecosyste.ms", d
assert d["query"] == {"ecosystem": "pypi", "name": "numpy"}, d
assert d["origin"] == {"transport": "captured", "source_url": None, "status": None, "data_license": "CC-BY-SA-4.0", "license_url": "https://creativecommons.org/licenses/by-sa/4.0/", "attribution_required": True, "attribution_url": "https://ecosyste.ms/", "modifications_made": True, "modification_note": "filtered to allowlisted package fields; unselected provider fields are omitted"}, d
assert d["rejected"] == 1 and len(d["results"]) == 1, d
r = d["results"][0]
assert r["provider_id"] == 2822925 and r["mapping"] == {"status": "candidate", "basis": "provider_package_id"}, r
assert r["coverage"]["status"] == "observed", r
assert "manifest" in r["coverage"]["fields"] and r["versions_count"] == 30, r
assert "description" not in r and "title" not in r, r
assert "independently review" in d["note"] and "link CC-BY-SA-4.0" in d["note"] and "indicate filtering" in d["note"], d
print("[ecosystem-lookup] provenance + bounded enrichment OK")
PY

echo "[ecosystem-lookup] deterministic replay"
"$ROOT/build/rh_cli" ecosystem lookup --input "$T/input.json" --out "$T/out2.json" >/dev/null || fail "lookup replay"
cmp -s "$T/out.json" "$T/out2.json" || fail "lookup output not deterministic"

echo "[ecosystem-lookup] fixed live route retains evidence and attribution (offline fake transport)"
mkdir -p "$T/bin"
cat > "$T/bin/python3" <<'SH'
#!/bin/sh
printf '93.184.216.34\n'
SH
cat > "$T/bin/curl" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$@" > "$ECOSYSTEM_LOOKUP_CURL_CAPTURE"
body=''; url=''; pin=''; accept=''; redirects=''; proto=''; max_bytes=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --resolve) shift; pin="$1" ;;
    --proto) shift; proto="$1" ;;
    --max-redirs) shift; redirects="$1" ;;
    --max-filesize) shift; max_bytes="$1" ;;
    -H) shift; [ "$1" = 'Accept: application/json' ] && accept="$1" ;;
    -o) shift; body="$1" ;;
    https://*) url="$1" ;;
  esac
  shift
done
[ "$pin" = 'packages.ecosyste.ms:443:93.184.216.34' ] || exit 89
[ "$redirects" = '0' ] && [ "$proto" = '=https,file' ] || exit 91
[ "$max_bytes" = '8388608' ] && [ "$accept" = 'Accept: application/json' ] || exit 92
[ "$url" = 'https://packages.ecosyste.ms/api/v1/packages/lookup?ecosystem=npm&name=%40scope%2fpkg' ] || exit 93
cp "$ECOSYSTEM_LOOKUP_FAKE_BODY" "$body"
printf '%s' "$ECOSYSTEM_LOOKUP_FAKE_HTTP"
SH
chmod +x "$T/bin/python3" "$T/bin/curl"
cat > "$T/provider-array.json" <<'JSON'
[{"id":43,"name":"@scope/pkg","ecosystem":"npm","latest_release_number":"1.2.3","repository_url":"https://example.org/source","versions_count":3,"maintainers":[{"email":"private@example.org"}]}]
JSON
PATH="$T/bin:$PATH" \
ECOSYSTEM_LOOKUP_CURL_CAPTURE="$T/live-curl.args" \
ECOSYSTEM_LOOKUP_FAKE_BODY="$T/provider-array.json" \
ECOSYSTEM_LOOKUP_FAKE_HTTP=200 \
  "$ROOT/build/rh_cli" ecosystem lookup --ecosystem npm --name '@scope/pkg' --out "$T/live-result.json" >/dev/null || fail "live lookup"
python3 - "$T" <<'PY'
import json, pathlib, sys
t = pathlib.Path(sys.argv[1])
args = (t / "live-curl.args").read_text().splitlines()
assert args[args.index("--resolve") + 1] == "packages.ecosyste.ms:443:93.184.216.34", args
assert args[args.index("--max-redirs") + 1] == "0", args
assert args[args.index("-H") + 1] == "User-Agent: repo-health-m02", args
assert args[args.index("-H", args.index("-H") + 1) + 1] == "Accept: application/json", args
assert "-L" not in args and not any(a.startswith("Authorization:") for a in args), args
d = json.load(open(t / "live-result.json"))
assert d["origin"]["transport"] == "live" and d["origin"]["status"] == "200", d
assert d["origin"]["source_url"] == "https://packages.ecosyste.ms/api/v1/packages/lookup?ecosystem=npm&name=%40scope%2fpkg", d
assert d["origin"]["data_license"] == "CC-BY-SA-4.0" and d["origin"]["modifications_made"] is True, d
assert d["query"] == {"ecosystem": "npm", "name": "@scope/pkg"}, d
assert len(d["results"]) == 1 and d["results"][0]["provider_id"] == 43, d
assert "maintainers" not in json.dumps(d) and "private@example.org" not in json.dumps(d), d
assert (t / "ecosystem-lookup-fetch-status.txt").read_text() == "200"
assert (t / "ecosystem-lookup-fetch.err").exists()
assert json.loads((t / "ecosystem-lookup-fetch-body.json").read_text())[0]["id"] == 43
print("[ecosystem-lookup] guarded request + retained response/status/error + attributed output OK")
PY

set +e
PATH="$T/bin:$PATH" \
ECOSYSTEM_LOOKUP_CURL_CAPTURE="$T/rate-curl.args" \
ECOSYSTEM_LOOKUP_FAKE_BODY="$T/provider-array.json" \
ECOSYSTEM_LOOKUP_FAKE_HTTP=429 \
  "$ROOT/build/rh_cli" ecosystem lookup --ecosystem npm --name '@scope/pkg' --out "$T/rate-limited.json" >/dev/null 2>&1
rc_rate=$?
set -e
[[ "$rc_rate" -eq 4 && ! -f "$T/rate-limited.json" ]] || fail "429 must fail closed without result publication"
[[ "$(cat "$T/ecosystem-lookup-fetch-status.txt")" == "429" ]] || fail "429 status evidence not retained"
[[ -f "$T/ecosystem-lookup-fetch-body.json" && -f "$T/ecosystem-lookup-fetch.err" ]] || fail "429 body/error evidence not retained"

expect 3 env PATH="$T/bin:$PATH" ECOSYSTEM_LOOKUP_CURL_CAPTURE="$T/unknown-curl.args" ECOSYSTEM_LOOKUP_FAKE_BODY="$T/provider-array.json" ECOSYSTEM_LOOKUP_FAKE_HTTP=200 \
  "$ROOT/build/rh_cli" ecosystem lookup --ecosystem unknown --name x --out "$T/unknown.out"
[[ ! -f "$T/unknown.out" && ! -f "$T/unknown-curl.args" ]] || fail "unsupported ecosystem reached transport"
expect 2 "$ROOT/build/rh_cli" ecosystem lookup --input "$T/input.json" --ecosystem npm --name pkg --out "$T/mixed.out"
[[ ! -f "$T/mixed.out" ]] || fail "mixed capture/live modes accepted"

echo "[ecosystem-lookup] omitted optional fields remain explicit"
python3 - "$T/input.json" "$T/empty.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["query"]["name"] = "minimal"
d["results"] = [{"id": 1, "name": "minimal", "ecosystem": "pypi", "versions_count": None}]
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" ecosystem lookup --input "$T/empty.json" --out "$T/empty.out" >/dev/null || fail "minimal lookup"
python3 - "$T/empty.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
r = d["results"][0]
assert r["version"] is None and r["manifest"] is None and r["versions_count"] is None and r["coverage"]["fields"] == ["provider_id", "name", "ecosystem"], r
assert d["rejected"] == 0, d
print("[ecosystem-lookup] explicit null coverage OK")
PY

echo "[ecosystem-lookup] non-matching search candidates are rejected"
python3 - "$T/input.json" "$T/wrong-coordinate.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["results"] = [{"id": 7, "name": "numpy-extra", "ecosystem": "pypi"}]
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" ecosystem lookup --input "$T/wrong-coordinate.json" --out "$T/wrong-coordinate.out" >/dev/null || fail "search candidate accounting"
python3 - "$T/wrong-coordinate.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["results"] == [] and d["rejected"] == 1, d
PY

echo "[ecosystem-lookup] malformed envelopes fail closed"
python3 - "$T/input.json" "$T/bad-schema.json" "$T/bad-provider.json" "$T/bad-query.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for path, change in zip(sys.argv[2:], (lambda x: x.update(schema="rh-ecosystem-lookup-input/2"), lambda x: x.update(provider="other"), lambda x: x.update(query={"ecosystem": "pypi"}))):
    c = json.loads(json.dumps(d))
    change(c)
    json.dump(c, open(path, "w"), separators=(",", ":"))
PY
set +e
"$ROOT/build/rh_cli" ecosystem lookup --input "$T/bad-schema.json" --out "$T/bad-schema.out" >/dev/null 2>&1; rc_schema=$?
"$ROOT/build/rh_cli" ecosystem lookup --input "$T/bad-provider.json" --out "$T/bad-provider.out" >/dev/null 2>&1; rc_provider=$?
"$ROOT/build/rh_cli" ecosystem lookup --input "$T/bad-query.json" --out "$T/bad-query.out" >/dev/null 2>&1; rc_query=$?
set -e
[[ "$rc_schema" -eq 4 && "$rc_provider" -eq 4 && "$rc_query" -eq 4 ]] || fail "invalid capture must exit 4 (got $rc_schema/$rc_provider/$rc_query)"
[[ ! -f "$T/bad-schema.out" && ! -f "$T/bad-provider.out" && ! -f "$T/bad-query.out" ]] || fail "invalid capture published"

echo "test_ecosystem_lookup_cli OK"
