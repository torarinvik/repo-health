#!/usr/bin/env bash
# tests/test_ecosystem_lookup_cli.sh — M03-10 bounded ecosyste.ms package
# lookup capture. Live provider calls stay disabled; captured input is mapped
# with explicit provenance, coverage and rejection accounting.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T="/tmp/rh-ecosystem-lookup"

fail() { echo "[ecosystem-lookup] FAIL: $1" >&2; exit 1; }

echo "[ecosystem-lookup] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

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
assert d["rejected"] == 1 and len(d["results"]) == 1, d
r = d["results"][0]
assert r["provider_id"] == 2822925 and r["mapping"] == {"status": "candidate", "basis": "provider_package_id"}, r
assert r["coverage"]["status"] == "observed", r
assert "manifest" in r["coverage"]["fields"] and r["versions_count"] == 30, r
assert "description" not in r and "title" not in r, r
assert "independent identity" in d["note"], d
print("[ecosystem-lookup] provenance + bounded enrichment OK")
PY

echo "[ecosystem-lookup] deterministic replay"
"$ROOT/build/rh_cli" ecosystem lookup --input "$T/input.json" --out "$T/out2.json" >/dev/null || fail "lookup replay"
cmp -s "$T/out.json" "$T/out2.json" || fail "lookup output not deterministic"

echo "[ecosystem-lookup] omitted optional fields remain explicit"
python3 - "$T/input.json" "$T/empty.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
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
