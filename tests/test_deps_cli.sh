#!/usr/bin/env bash
# tests/test_deps_cli.sh — M03 dependency-graph execution path:
# `rh_cli deps` resolves Cargo.lock and package.json/package-lock.json into
# version-aware `rh-dep-graph/1` reports plus `rh-deps-metrics/1`. Asserts
# exact node/edge/unresolved counts, the declared unsupported-range count,
# offline advisory matching, and fail-closed behavior with no partial graph.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-deps"

fail() { echo "[deps] FAIL: $1" >&2; exit 1; }

echo "[deps] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T/src"
cp "$ROOT/fixtures/packages/cargo-diamond.lock" "$T/src/Cargo.lock"
cp "$ROOT/fixtures/packages/npm-diamond.lock.json" "$T/src/package-lock.json"
cp "$ROOT/fixtures/packages/osv-response.json" "$T/src/osv-response.json"
# package.json re-declares existing lock names with four expressions outside
# the declared supported subset (alias, workspace, path, dist-tag) and one
# plain range, so no extra unresolved node is introduced.
cat > "$T/src/package.json" <<'JSON'
{"name":"app","version":"1.0.0","dependencies":{"left":"npm:other@^1","right":"workspace:*","shared":"file:../s","opt":"latest","peer":"^4.0.0"}}
JSON

echo "[deps] resolve both ecosystems"
"$ROOT/build/rh_cli" deps --repo "$T/src" --out "$T/out" --osv "$T/src/osv-response.json" \
  | grep -q "ecosystems=2" || fail "expected two ecosystems"
for f in deps-cargo-graph.json deps-npm-graph.json deps-metrics.json; do
  [[ -f "$T/out/$f" ]] || fail "missing $f"
done

python3 - "$T/out" <<'PY'
import json, sys
out = sys.argv[1]
cg = json.load(open(out + "/deps-cargo-graph.json"))
ng = json.load(open(out + "/deps-npm-graph.json"))
m = json.load(open(out + "/deps-metrics.json"))
assert cg["schema"] == "rh-dep-graph/1" and cg["ecosystem"] == "cargo"
assert ng["schema"] == "rh-dep-graph/1" and ng["ecosystem"] == "npm"
assert len(cg["nodes"]) == 7, cg["nodes"]
assert len(cg["edges"]) == 3, cg["edges"]
assert len(cg["unresolved"]) == 2, cg["unresolved"]
# every unresolved carries a reason and is NOT an edge (no guessed edge)
reasons = sorted(u["reason"] for u in cg["unresolved"])
assert reasons == ["ambiguous", "missing"], reasons
assert len(cg["advisories"]) == 1, cg["advisories"]
adv = cg["advisories"][0]
assert adv["advisory"], adv
# The app root reaches only the unresolved `ghost`, so the advisory on
# `shared 1.0.0` is present but NOT reachable from the root: an empty
# witness, not a fabricated path. Advisory presence != affected reachability.
assert adv["witness"] == [], adv
assert len(ng["nodes"]) == 7, ng["nodes"]
assert len(ng["edges"]) >= 6, ng["edges"]
assert len(ng["unresolved"]) == 1, ng["unresolved"]
assert ng["unresolved"][0]["reason"] == "context", ng["unresolved"]
assert len(ng["advisories"]) == 1, ng["advisories"]
assert m["schema"] == "rh-deps-metrics/1"
met = m["metrics"][0]
assert met["key"] == "dependencies.unsupported_range_count" and met["version"] == "1.0.0"
assert met["status"] == "observed" and met["value"] == 4, met
by = {b["ecosystem"]: b for b in m["by_ecosystem"]}
assert by["cargo"]["unsupported_range_count"] == 0, by["cargo"]
assert by["npm"]["unsupported_range_count"] == 4, by["npm"]
assert by["cargo"]["declared_requirements"] == 5, by["cargo"]
assert by["npm"]["declared_requirements"] == 10, by["npm"]
print("[deps] counts + unsupported-range classification OK")
PY

echo "[deps] offline advisories come only from --osv"
"$ROOT/build/rh_cli" deps --repo "$T/src" --out "$T/noosv" >/dev/null || fail "no-osv deps failed"
python3 - "$T/noosv" <<'PY'
import json, sys
cg = json.load(open(sys.argv[1] + "/deps-cargo-graph.json"))
assert cg["advisories"] == [], cg["advisories"]
print("[deps] no --osv -> no advisories fabricated")
PY

echo "[deps] bounded OSV URL capture retains source evidence before matching"
osv_url="file://$T/src/osv-response.json"
"$ROOT/build/rh_cli" deps --repo "$T/src" --out "$T/urlout" --osv-url "$osv_url" >/dev/null || fail "osv URL deps failed"
python3 - "$T" <<'PY'
import json, pathlib, sys
t = pathlib.Path(sys.argv[1])
status = json.load(open(t / "urlout" / "osv-fetch-status.txt"))
assert status["schema"] == "rh-osv-fetch/1", status
assert status["state"] == "collected" and status["body_file"] == "osv-fetch-body.json", status
assert status["source_url"].startswith("file://"), status
assert json.load(open(t / "urlout" / "deps-cargo-graph.json"))["advisories"], "URL response was not matched"
assert (t / "urlout" / "osv-fetch.err").exists(), "transport error evidence missing"
print("[deps] URL provenance + advisory matching OK")
PY
cmp -s "$T/src/osv-response.json" "$T/urlout/osv-fetch-body.json" || fail "OSV URL body evidence differs"

echo "[deps] pypi requirements.txt in a third ecosystem (M08)"
mkdir -p "$T/pysrc"
cp "$ROOT/fixtures/packages/python-requirements.txt" "$T/pysrc/requirements.txt"
"$ROOT/build/rh_cli" deps --repo "$T/pysrc" --out "$T/pyout" --osv "$T/src/osv-response.json" \
  | grep -q "ecosystems=1 pypi=3/7 unresolved=5 unsupported=1" || fail "pypi deps summary"
[[ -f "$T/pyout/deps-pypi-graph.json" ]] || fail "missing pypi graph"
[[ -f "$T/pyout/deps-metrics.json" ]] || fail "missing pypi metrics"
python3 - "$T/pyout" <<'PY'
import json, sys
out = sys.argv[1]
pg = json.load(open(out + "/deps-pypi-graph.json"))
m = json.load(open(out + "/deps-metrics.json"))
assert pg["ecosystem"] == "pypi", pg["ecosystem"]
# root + 3 exact pins; ranges/extras/markers/URLs/options stay unresolved
assert len(pg["nodes"]) == 4, pg["nodes"]
assert [n["name"] for n in pg["nodes"]] == ["root", "Django", "Click", "flask"], pg["nodes"]
assert len(pg["edges"]) == 3, pg["edges"]
assert all(e["from"] == 0 for e in pg["edges"]), pg["edges"]
reasons = sorted(u["reason"] for u in pg["unresolved"])
assert reasons == ["context", "context", "context", "context", "missing"], reasons
# extras form urllib3[secure] is not resolved and not counted as unsupported
extras = [u for u in pg["unresolved"] if u["name"] == "urllib3"]
assert extras and extras[0]["requirement"] == "==2.0.7", extras
by = {b["ecosystem"]: b for b in m["by_ecosystem"]}
assert set(by) == {"pypi"}, by
assert by["pypi"]["declared_requirements"] == 7, by["pypi"]
assert by["pypi"]["resolved_edges"] == 3, by["pypi"]
assert by["pypi"]["unresolved_requirements"] == 5, by["pypi"]
assert by["pypi"]["unsupported_range_count"] == 1, by["pypi"]
assert m["metrics"][0]["value"] == 1, m["metrics"][0]
print("[deps] pypi graph + per-ecosystem metrics OK")
PY

echo "[deps] go.mod resolves exact pins, keeps pseudo/directives unresolved (M08)"
mkdir -p "$T/gosrc"
cp "$ROOT/fixtures/packages/go.mod.txt" "$T/gosrc/go.mod"
printf 'github.com/pkg/errors v0.9.1 h1:%s=\ngithub.com/pkg/errors v0.9.1/go.mod h1:%s=\ngithub.com/unknown/module v1.0.0 h1:%s=\n' \
  "$(printf 'A%.0s' {1..43})" "$(printf 'B%.0s' {1..43})" "$(printf 'C%.0s' {1..43})" > "$T/gosrc/go.sum"
"$ROOT/build/rh_cli" deps --repo "$T/gosrc" --out "$T/goout" --osv "$T/src/osv-response.json" \
  | grep -q "ecosystems=1 go=4/6 unresolved=4 unsupported=0" || fail "go deps summary"
[[ -f "$T/goout/deps-go-graph.json" ]] || fail "missing go graph"
python3 - "$T/goout" <<'PY'
import json, sys
out = sys.argv[1]
g = json.load(open(out + "/deps-go-graph.json"))
m = json.load(open(out + "/deps-metrics.json"))
assert g["ecosystem"] == "go", g["ecosystem"]
assert g["nodes"][0]["name"] == "example.com/app", g["nodes"][0]
assert len(g["nodes"]) == 5 and len(g["edges"]) == 4, (g["nodes"], g["edges"])
names = sorted(n["name"] for n in g["nodes"][1:])
assert names == ["github.com/google/uuid", "github.com/pkg/errors", "github.com/stretchr/testify", "golang.org/x/text"], names
reasons = {u["name"]: u["reason"] for u in g["unresolved"]}
assert reasons["github.com/old/module"] == "missing", reasons
assert reasons["github.com/inc/module"] == "missing", reasons
assert reasons["github.com/pkg/errors"] == "context", reasons
assert reasons["github.com/bad/module"] == "context", reasons
digests = {n["name"]: n["digest"] for n in g["nodes"]}
assert digests["github.com/pkg/errors"] is True, digests
assert digests["github.com/google/uuid"] is False, digests
by = {b["ecosystem"]: b for b in m["by_ecosystem"]}
assert by["go"]["resolved_edges"] == 4 and by["go"]["unresolved_requirements"] == 4, by["go"]
print("[deps] go.mod graph + unresolved reasons OK")
PY

echo "[deps] malformed go.sum fails closed without a partial graph"
mkdir -p "$T/bad-go"
cp "$ROOT/fixtures/packages/go.mod.txt" "$T/bad-go/go.mod"
printf 'not a checksum record\n' > "$T/bad-go/go.sum"
set +e
"$ROOT/build/rh_cli" deps --repo "$T/bad-go" --out "$T/bad-go-out" >/dev/null 2>&1
rc_bad_sum=$?
set -e
[[ "$rc_bad_sum" -eq 4 ]] || fail "malformed go.sum must exit 4 (got $rc_bad_sum)"
[[ ! -f "$T/bad-go-out/deps-go-graph.json" ]] || fail "partial graph written on malformed go.sum"

echo "[deps] negative: no manifests fails closed"
mkdir -p "$T/empty"
set +e
"$ROOT/build/rh_cli" deps --repo "$T/empty" --out "$T/empty-out" >/dev/null 2>&1
rc_missing=$?
set -e
[[ "$rc_missing" -eq 4 ]] || fail "no-manifest repo must exit 4 (got $rc_missing)"

echo "[deps] negative: malformed lock fails closed with no partial graph"
mkdir -p "$T/bad"
printf '[[package]]\nname = "x"\nversion = "1.0.0"\ndependencies = [\n foo\n]\n' > "$T/bad/Cargo.lock"
set +e
"$ROOT/build/rh_cli" deps --repo "$T/bad" --out "$T/bad-out" >/dev/null 2>&1
rc_bad=$?
set -e
[[ "$rc_bad" -eq 4 ]] || fail "malformed lock must exit 4 (got $rc_bad)"
[[ ! -f "$T/bad-out/deps-cargo-graph.json" ]] || fail "partial graph written on parse failure"

echo "test_deps_cli OK"
