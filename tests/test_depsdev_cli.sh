#!/usr/bin/env bash
# tests/test_depsdev_cli.sh — M03-09 optional deps.dev source adapter.
# The adapter retains origin and per-field coverage, while a provider failure
# leaves the local graph path independent and fails the enrichment command
# closed without publishing a partial record.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-depsdev"

fail() { echo "[depsdev] FAIL: $1" >&2; exit 1; }

echo "[depsdev] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/packages/depsdev-version.json" "$T/in.json"

echo "[depsdev] offline adapter preserves complete coverage"
"$ROOT/build/rh_cli" depsdev --input "$T/in.json" --out "$T/offline.json" >/dev/null || fail "offline adapter"
python3 - "$T/offline.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-depsdev-enrichment/1", d
assert d["origin"] == {"provider": "deps.dev", "transport": "offline", "source_url": None, "status": None}, d["origin"]
assert d["coverage"] == {"scope": "one-version", "status": "complete", "fields": ["name", "version", "published_at", "dependency_count", "advisory_keys"]}, d["coverage"]
assert d["package"] == {"system": "npm", "name": "left", "version": "1.0.0", "published_at": "2024-03-10T12:00:00Z"}, d["package"]
assert d["dependency_count"] == 3, d
assert d["advisory_keys"] == ["GHSA-aaaa-bbbb-cccc", "CVE-2025-0002"], d
import hashlib
tr = json.load(open(sys.argv[1] + ".transformations.json"))
assert tr["schema"] == "rh-adapter-transformation-report/1" and tr["adapter"] == "deps.dev-version", tr
assert tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[1].replace("offline.json", "in.json"), "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert any(x["state"] == "unknown" for x in tr["fields"]), tr
print("[depsdev] origin + coverage OK")
PY

echo "[depsdev] bounded file transport evidence"
"$ROOT/build/rh_cli" depsdev --url "file://$T/in.json" --out "$T/online.json" >/dev/null || fail "file transport"
python3 - "$T/online.json" "$T/depsdev-fetch-status.txt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["origin"] == {"provider": "deps.dev", "transport": "online", "source_url": "file:///tmp/rh-depsdev/in.json", "status": "000"}, d["origin"]
s = json.load(open(sys.argv[2]))
assert s["schema"] == "rh-depsdev-fetch/1" and s["status"] == "000", s
assert s["state"] == "collected" and s["body_file"] == "depsdev-fetch-body.json", s
tr = json.load(open(sys.argv[1] + ".transformations.json"))
assert tr["source_input_sha256"] == __import__("hashlib").sha256(open("/tmp/rh-depsdev/depsdev-fetch-body.json", "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == __import__("hashlib").sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
print("[depsdev] transport provenance OK")
PY
cmp -s "$T/in.json" "$T/depsdev-fetch-body.json" || fail "body evidence not retained"
cmp -s "$T/offline.json" <(sed 's/"transport":"online"/"transport":"offline"/; s/"source_url":"file:[^"]*"/"source_url":null/; s/"status":"000"/"status":null/' "$T/online.json") || fail "adapter fields differ"

echo "[depsdev] partial coverage stays explicit"
printf '{"system":"pypi","name":"demo","version":"1.0"}' > "$T/partial.json"
"$ROOT/build/rh_cli" depsdev --input "$T/partial.json" --out "$T/partial.out" >/dev/null || fail "partial adapter"
python3 - "$T/partial.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["coverage"]["status"] == "partial", d
assert d["package"]["published_at"] is None and d["dependency_count"] is None and d["advisory_keys"] == [], d
print("[depsdev] partial coverage OK")
PY

echo "[depsdev] malformed and blocked sources fail closed"
printf '{"name":42,"version":"1"}' > "$T/bad.json"
set +e
"$ROOT/build/rh_cli" depsdev --input "$T/bad.json" --out "$T/bad.out" >/dev/null 2>&1; rc_bad=$?
"$ROOT/build/rh_cli" depsdev --url "https://127.0.0.1/nope" --out "$T/blocked.out" >/dev/null 2>&1; rc_blocked=$?
set -e
[[ "$rc_bad" -eq 4 ]] || fail "malformed response must exit 4 (got $rc_bad)"
[[ "$rc_blocked" -eq 4 ]] || fail "blocked provider must exit 4 (got $rc_blocked)"
[[ ! -f "$T/bad.out" && ! -f "$T/blocked.out" ]] || fail "partial enrichment published"

echo "test_depsdev_cli OK"
