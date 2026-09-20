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
metrics = {item["key"]: item for item in m["metrics"]}
assert {key: metrics[key]["value"] for key in metrics} == {
    "dependencies.unsupported_range_count": 4,
    "dependencies.ecosystem_count": 2,
    "dependencies.declared_requirement_count": 15,
    "dependencies.resolved_edge_count": 10,
    "dependencies.unresolved_requirement_count": 3,
    "dependency.requirements_direct": 8,
    "dependency.resolved_direct_versions": 5,
    "dependency.unresolved_requirements": 1,
    "dependency.resolved_transitive_versions": 6,
    "dependency.runtime_requirements": 14,
    "dependency.development_requirements": 0,
    "dependency.optional_requirements": 0,
    "dependency.peer_requirements": 1,
    "dependency.unknown_scope_requirements": 0,
    "dependency.runtime_direct_count": 8,
    "dependency.build_direct_count": 0,
    "dependency.optional_direct_count": 0,
    "dependency.unknown_scope_count": 0,
    "dependency.unpinned_requirement_count": 13,
    "dependency.artifact_digest_coverage": {"num": 3, "den": 9},
    "dependency.maximum_observed_depth": 2,
    "dependency.resolution_complete": False,
    "graph.node_count": 14,
    "graph.edge_count": 10,
    "dependency.runtime_resolved_edges": 10,
    "dependency.development_resolved_edges": 0,
    "dependency.optional_resolved_edges": 0,
    "dependency.peer_resolved_edges": 0,
    "dependency.unknown_scope_resolved_edges": 0,
    "security.known_advisory_records": 3,
    "security.known_unique_advisories": 2,
    "security.affected_resolved_nodes": 2,
    "security.affected_direct_nodes": 1,
    "security.affected_transitive_nodes": 0,
    "security.affected_unreachable_nodes": 1,
    "security.advisory_match_unknown_nodes": 0,
    "security.fixed_version_available": True,
    "security.withdrawn_advisory_count": 2,
}, metrics
by = {b["ecosystem"]: b for b in m["by_ecosystem"]}
assert by["cargo"]["unsupported_range_count"] == 0, by["cargo"]
assert by["npm"]["unsupported_range_count"] == 4, by["npm"]
assert by["cargo"]["declared_requirements"] == 5, by["cargo"]
assert by["npm"]["declared_requirements"] == 10, by["npm"]
assert by["cargo"]["requirements_direct"] == 1, by["cargo"]
assert by["npm"]["requirements_direct"] == 7, by["npm"]
assert by["cargo"]["resolved_direct_versions"] == 0, by["cargo"]
assert by["npm"]["resolved_direct_versions"] == 5, by["npm"]
assert by["cargo"]["resolved_transitive_versions"] == 0, by["cargo"]
assert by["npm"]["resolved_transitive_versions"] == 6, by["npm"]
assert by["cargo"]["runtime_requirements"] == 5, by["cargo"]
assert by["npm"]["runtime_requirements"] == 9, by["npm"]
assert by["npm"]["peer_requirements"] == 1, by["npm"]
assert by["cargo"]["runtime_direct_count"] == 1, by["cargo"]
assert by["npm"]["runtime_direct_count"] == 7, by["npm"]
assert by["cargo"]["unpinned_requirement_count"] == 3, by["cargo"]
assert by["npm"]["unpinned_requirement_count"] == 10, by["npm"]
assert by["cargo"]["artifact_digest_coverage"] == {"num": 2, "den": 3}, by["cargo"]
assert by["npm"]["artifact_digest_coverage"] == {"num": 1, "den": 6}, by["npm"]
assert by["cargo"]["maximum_observed_depth"] == 0, by["cargo"]
assert by["npm"]["maximum_observed_depth"] == 2, by["npm"]
assert by["cargo"]["resolution_complete"] is False, by["cargo"]
assert by["npm"]["resolution_complete"] is False, by["npm"]
assert by["cargo"]["node_count"] == 7, by["cargo"]
assert by["npm"]["node_count"] == 7, by["npm"]
assert by["cargo"]["edge_count"] == 3, by["cargo"]
assert by["npm"]["edge_count"] == 7, by["npm"]
assert by["cargo"]["advisory_match_unknown_nodes"] == 0, by["cargo"]
assert by["npm"]["advisory_match_unknown_nodes"] == 0, by["npm"]
assert by["cargo"]["fixed_version_available"] is True, by["cargo"]
assert by["npm"]["fixed_version_available"] is True, by["npm"]
assert by["cargo"]["runtime_resolved_edges"] == 3, by["cargo"]
assert by["npm"]["runtime_resolved_edges"] == 7, by["npm"]
for eco in ("cargo", "npm"):
    assert by[eco]["development_requirements"] == 0, by[eco]
    assert by[eco]["optional_requirements"] == 0, by[eco]
    assert by[eco]["unknown_scope_requirements"] == 0, by[eco]
assert by["cargo"]["peer_requirements"] == 0, by["cargo"]
assert by["cargo"]["known_advisory_records"] == 2, by["cargo"]
assert by["npm"]["known_advisory_records"] == 1, by["npm"]
assert by["cargo"]["known_unique_advisories"] == 1, by["cargo"]
assert by["npm"]["known_unique_advisories"] == 1, by["npm"]
assert by["cargo"]["affected_resolved_nodes"] == 1, by["cargo"]
assert by["npm"]["affected_resolved_nodes"] == 1, by["npm"]
assert by["cargo"]["affected_direct_nodes"] == 0, by["cargo"]
assert by["cargo"]["affected_transitive_nodes"] == 0, by["cargo"]
assert by["cargo"]["affected_unreachable_nodes"] == 1, by["cargo"]
assert by["npm"]["affected_direct_nodes"] == 1, by["npm"]
assert by["npm"]["affected_transitive_nodes"] == 0, by["npm"]
assert by["npm"]["affected_unreachable_nodes"] == 0, by["npm"]
print("[deps] counts + unsupported-range classification OK")
PY

echo "[deps] offline advisories come only from --osv"
"$ROOT/build/rh_cli" deps --repo "$T/src" --out "$T/noosv" >/dev/null || fail "no-osv deps failed"
python3 - "$T/noosv" <<'PY'
import json, sys
cg = json.load(open(sys.argv[1] + "/deps-cargo-graph.json"))
assert cg["advisories"] == [], cg["advisories"]
m = json.load(open(sys.argv[1] + "/deps-metrics.json"))
for metric in m["metrics"][-9:]:
    assert metric["status"] == "unavailable" and "value" not in metric, metric
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
metrics = {item["key"]: item for item in m["metrics"]}
assert metrics["dependencies.ecosystem_count"]["value"] == 1, metrics
assert metrics["dependencies.declared_requirement_count"]["value"] == 7, metrics
assert metrics["dependencies.resolved_edge_count"]["value"] == 3, metrics
assert metrics["dependencies.unresolved_requirement_count"]["value"] == 5, metrics
assert by["pypi"]["declared_requirements"] == 7, by["pypi"]
assert by["pypi"]["resolved_edges"] == 3, by["pypi"]
assert by["pypi"]["unresolved_requirements"] == 5, by["pypi"]
assert by["pypi"]["requirements_direct"] == 7, by["pypi"]
assert by["pypi"]["resolved_direct_versions"] == 3, by["pypi"]
assert by["pypi"]["unresolved_direct_requirements"] == 5, by["pypi"]
assert by["pypi"]["resolved_transitive_versions"] == 3, by["pypi"]
assert by["pypi"]["runtime_requirements"] == 7, by["pypi"]
assert by["pypi"]["development_requirements"] == 0, by["pypi"]
assert by["pypi"]["optional_requirements"] == 0, by["pypi"]
assert by["pypi"]["peer_requirements"] == 0, by["pypi"]
assert by["pypi"]["unknown_scope_requirements"] == 0, by["pypi"]
assert by["pypi"]["unsupported_range_count"] == 1, by["pypi"]
assert m["metrics"][0]["value"] == 1, m["metrics"][0]
metrics = {item["key"]: item for item in m["metrics"]}
assert metrics["security.known_unique_advisories"]["value"] == 0, metrics
assert metrics["security.affected_resolved_nodes"]["value"] == 0, metrics
assert metrics["security.withdrawn_advisory_count"]["value"] == 1, metrics
print("[deps] pypi graph + per-ecosystem metrics OK")
PY

echo "[deps] PEP 621 pyproject.toml preserves optional dependency scope"
mkdir -p "$T/pep621src"
cat > "$T/pep621src/pyproject.toml" <<'EOF'
[project]
name = "app"
version = "1.0.0"
dependencies = [
  "Django==4.2.0",
  "requests>=2"
]

[project.optional-dependencies]
test = [
  "pytest==7.4.0",
  "coverage>=7"
]
EOF
"$ROOT/build/rh_cli" deps --repo "$T/pep621src" --out "$T/pep621out" \
  | grep -q "ecosystems=1 pypi=2/4 unresolved=2 unsupported=0" || fail "pep621 deps summary"
python3 - "$T/pep621out/deps-pypi-graph.json" "$T/pep621out/deps-metrics.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
metrics = {item["key"]: item for item in json.load(open(sys.argv[2]))["metrics"]}
assert g["ecosystem"] == "pypi", g
assert [n["name"] for n in g["nodes"]] == ["root", "Django", "pytest"], g["nodes"]
assert [(e["to"], e["scope"]) for e in g["edges"]] == [(1, "normal"), (2, "optional")], g["edges"]
assert sorted(u["name"] for u in g["unresolved"]) == ["coverage", "requests"], g["unresolved"]
assert metrics["dependency.runtime_requirements"]["value"] == 2, metrics
assert metrics["dependency.optional_requirements"]["value"] == 2, metrics
assert metrics["dependency.runtime_direct_count"]["value"] == 2, metrics
assert metrics["dependency.optional_direct_count"]["value"] == 2, metrics
assert metrics["dependency.unpinned_requirement_count"]["value"] == 2, metrics
assert metrics["dependency.artifact_digest_coverage"]["value"] == {"num": 0, "den": 2}, metrics
assert metrics["dependency.maximum_observed_depth"]["value"] == 1, metrics
assert metrics["dependency.resolution_complete"]["value"] is False, metrics
assert metrics["dependency.runtime_resolved_edges"]["value"] == 1, metrics
assert metrics["dependency.optional_resolved_edges"]["value"] == 1, metrics
print("[deps] PEP 621 graph + optional scope OK")
PY

echo "[deps] duplicate PyPI declaration sources fail closed"
cp "$T/pysrc/requirements.txt" "$T/pep621src/requirements.txt"
set +e
"$ROOT/build/rh_cli" deps --repo "$T/pep621src" --out "$T/pep621-bad" >/dev/null 2>&1
rc_both=$?
set -e
[[ "$rc_both" -eq 4 ]] || fail "requirements.txt + pyproject.toml must fail closed (got $rc_both)"

echo "[deps] unsupported PEP 621 dynamic arrays fail closed"
mkdir -p "$T/pep621bad"
printf '[project]\ndependencies = "dynamic"\n' > "$T/pep621bad/pyproject.toml"
set +e
"$ROOT/build/rh_cli" deps --repo "$T/pep621bad" --out "$T/pep621bad-out" >/dev/null 2>&1
rc_dynamic=$?
printf '[project]\ndependencies = [\n  "demo==1.0.0"\n' > "$T/pep621bad/pyproject.toml"
"$ROOT/build/rh_cli" deps --repo "$T/pep621bad" --out "$T/pep621bad-out2" >/dev/null 2>&1
rc_unclosed=$?
set -e
[[ "$rc_dynamic" -eq 4 && "$rc_unclosed" -eq 4 ]] || fail "unsupported PEP 621 forms must fail closed"

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

echo "[deps] Gemfile.lock and composer.lock preserve ecosystem-native scopes"
mkdir -p "$T/rubysrc"
cat > "$T/rubysrc/Gemfile.lock" <<'EOF'
GEM
  remote: https://rubygems.org/
  specs:
    rack (3.0.0)
      json (~> 2.0)
    json (2.6.3)

PLATFORMS
  ruby

DEPENDENCIES
  rack (~> 3.0)

BUNDLED WITH
   2.4.0
EOF
cat > "$T/rubysrc/composer.lock" <<'JSON'
{"packages":[{"name":"monolog/monolog","version":"2.9.1","require":{"php":">=7.2","psr/log":"^1.0"}}],"packages-dev":[{"name":"phpunit/phpunit","version":"10.0.0","require":{"php":">=8.1","monolog/monolog":"^2.0"}}]}
JSON
"$ROOT/build/rh_cli" deps --repo "$T/rubysrc" --out "$T/rubyout" \
  | grep -q "ecosystems=2 rubygems=2/2 unresolved=0 unsupported=0 composer=1/4 unresolved=3 unsupported=0" || fail "RubyGems/Composer summary"
python3 - "$T/rubyout" <<'PY'
import json, sys
out = sys.argv[1]
g = json.load(open(out + "/deps-rubygems-graph.json"))
c = json.load(open(out + "/deps-composer-graph.json"))
assert [n["name"] for n in g["nodes"]] == ["root", "rack", "json"], g["nodes"]
assert len(g["edges"]) == 2 and g["unresolved"] == [], g
assert [n["name"] for n in c["nodes"]] == ["root", "monolog/monolog", "phpunit/phpunit"], c["nodes"]
assert len(c["edges"]) == 1 and c["edges"][0]["scope"] == "dev", c["edges"]
assert sorted(u["reason"] for u in c["unresolved"]) == ["context", "context", "missing"], c["unresolved"]
assert c["nodes"][2]["dev"] is True, c["nodes"][2]
rm = json.load(open(out + "/deps-metrics.json"))
by = {b["ecosystem"]: b for b in rm["by_ecosystem"]}
assert by["rubygems"]["unknown_scope_requirements"] == 1, by
assert by["composer"]["development_requirements"] == 2, by
assert by["composer"]["development_resolved_edges"] == 1, by
print("[deps] RubyGems/Composer scopes + unresolved context OK")
PY

echo "[deps] packages.config resolves exact NuGet pins and preserves development scope"
mkdir -p "$T/nugetsrc"
cat > "$T/nugetsrc/packages.config" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="Newtonsoft.Json" version="13.0.3" targetFramework="net8.0" />
  <package id="NUnit" version="3.14.0" developmentDependency="true" />
  <package id="Serilog" version="[3.0.0,4.0.0)" />
</packages>
EOF
"$ROOT/build/rh_cli" deps --repo "$T/nugetsrc" --out "$T/nugetout" \
  | grep -q "ecosystems=1 nuget=2/3 unresolved=1 unsupported=1" || fail "NuGet summary"
python3 - "$T/nugetout" <<'PY'
import json, sys
out = sys.argv[1]
g = json.load(open(out + "/deps-nuget-graph.json"))
m = json.load(open(out + "/deps-metrics.json"))
assert g["ecosystem"] == "nuget", g["ecosystem"]
assert [n["name"] for n in g["nodes"]] == ["root", "Newtonsoft.Json", "NUnit"], g["nodes"]
assert [(e["to"], e["scope"]) for e in g["edges"]] == [(1, "normal"), (2, "dev")], g["edges"]
assert len(g["unresolved"]) == 1 and g["unresolved"][0]["name"] == "Serilog", g["unresolved"]
assert g["unresolved"][0]["reason"] == "missing", g["unresolved"]
by = {b["ecosystem"]: b for b in m["by_ecosystem"]}
assert by["nuget"]["declared_requirements"] == 3, by
assert by["nuget"]["resolved_edges"] == 2, by
assert by["nuget"]["unsupported_range_count"] == 1, by
assert by["nuget"]["runtime_requirements"] == 2, by
assert by["nuget"]["development_requirements"] == 1, by
assert by["nuget"]["runtime_direct_count"] == 2, by
assert by["nuget"]["build_direct_count"] == 1, by
assert by["nuget"]["unpinned_requirement_count"] == 1, by
assert by["nuget"]["runtime_resolved_edges"] == 1, by
assert by["nuget"]["development_resolved_edges"] == 1, by
print("[deps] NuGet graph + development scope OK")
PY

echo "[deps] pom.xml resolves exact Maven coordinates and preserves scopes"
mkdir -p "$T/mavensrc"
cat > "$T/mavensrc/pom.xml" <<'EOF'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.example</groupId>
  <artifactId>app</artifactId>
  <version>1.0.0</version>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.managed</groupId>
        <artifactId>managed-only</artifactId>
        <version>9.9.9</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>org.slf4j</groupId>
      <artifactId>slf4j-api</artifactId>
      <version>2.0.9</version>
    </dependency>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.13.2</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.foo</groupId>
      <artifactId>bar</artifactId>
      <version>${bar.version}</version>
    </dependency>
  </dependencies>
</project>
EOF
"$ROOT/build/rh_cli" deps --repo "$T/mavensrc" --out "$T/mavenout" \
  | grep -q "ecosystems=1 maven=2/3 unresolved=1 unsupported=1" || fail "Maven summary"
python3 - "$T/mavenout" <<'PY'
import json, sys
out = sys.argv[1]
g = json.load(open(out + "/deps-maven-graph.json"))
m = json.load(open(out + "/deps-metrics.json"))
assert g["ecosystem"] == "maven", g["ecosystem"]
assert [n["name"] for n in g["nodes"]] == ["org.example:app", "org.slf4j:slf4j-api", "junit:junit"], g["nodes"]
assert [(e["to"], e["scope"]) for e in g["edges"]] == [(1, "normal"), (2, "dev")], g["edges"]
assert g["unresolved"][0]["name"] == "org.foo:bar", g["unresolved"]
assert g["unresolved"][0]["requirement"] == "${bar.version}", g["unresolved"]
by = {b["ecosystem"]: b for b in m["by_ecosystem"]}
assert by["maven"]["declared_requirements"] == 3, by
assert by["maven"]["resolved_edges"] == 2, by
assert by["maven"]["unsupported_range_count"] == 1, by
assert by["maven"]["runtime_requirements"] == 2, by
assert by["maven"]["development_requirements"] == 1, by
assert by["maven"]["runtime_resolved_edges"] == 1, by
assert by["maven"]["development_resolved_edges"] == 1, by
print("[deps] Maven graph + dependency-management exclusion OK")
PY

echo "[deps] malformed pom.xml fails closed without a partial graph"
mkdir -p "$T/bad-maven"
cat > "$T/bad-maven/pom.xml" <<'EOF'
<project>
  <groupId>org.example</groupId>
  <artifactId>broken</artifactId>
  <dependencies>
    <dependency>
      <groupId>org.foo</groupId>
      <artifactId>bar</artifactId>
EOF
set +e
"$ROOT/build/rh_cli" deps --repo "$T/bad-maven" --out "$T/bad-maven-out" >/dev/null 2>&1
rc_bad_maven=$?
set -e
[[ "$rc_bad_maven" -eq 4 ]] || fail "malformed pom.xml must exit 4 (got $rc_bad_maven)"
[[ ! -f "$T/bad-maven-out/deps-maven-graph.json" ]] || fail "partial Maven graph written on parse failure"

echo "[deps] malformed packages.config fails closed without a partial graph"
mkdir -p "$T/bad-nuget"
cat > "$T/bad-nuget/packages.config" <<'EOF'
<packages>
  <package version="1.0.0" />
</packages>
EOF
set +e
"$ROOT/build/rh_cli" deps --repo "$T/bad-nuget" --out "$T/bad-nuget-out" >/dev/null 2>&1
rc_bad_nuget=$?
set -e
[[ "$rc_bad_nuget" -eq 4 ]] || fail "malformed packages.config must exit 4 (got $rc_bad_nuget)"
[[ ! -f "$T/bad-nuget-out/deps-nuget-graph.json" ]] || fail "partial NuGet graph written on parse failure"

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

echo "[deps] Cargo lock resolution distinguishes registry and exact version"
mkdir -p "$T/cargo-source-collision"
cp "$ROOT/fixtures/packages/cargo-source-collision.lock" "$T/cargo-source-collision/Cargo.lock"
"$ROOT/build/rh_cli" deps --repo "$T/cargo-source-collision" --out "$T/cargo-source-collision-out" >/dev/null || fail "Cargo source-collision deps failed"
python3 - "$T/cargo-source-collision-out/deps-cargo-graph.json" <<'PY'
import hashlib, json, sys
g = json.load(open(sys.argv[1]))
assert [n["name"] for n in g["nodes"]] == ["app", "shared", "shared", "shared"], g["nodes"]
assert [n["version"] for n in g["nodes"]] == ["0.1.0", "1.0.0", "1.0.0", "2.0.0"], g["nodes"]
assert [(e["from"], e["to"]) for e in g["edges"]] == [(0, 1), (0, 2), (0, 3)], g["edges"]
assert len(g["unresolved"]) == 1 and g["unresolved"][0]["reason"] == "missing", g["unresolved"]
assert g["nodes"][1]["source_identity_sha256"] == hashlib.sha256(b"registry+https://registry-a.example/index").hexdigest(), g["nodes"][1]
assert g["nodes"][2]["source_identity_sha256"] == hashlib.sha256(b"registry+https://registry-b.example/index").hexdigest(), g["nodes"][2]
assert g["nodes"][3]["source_identity_sha256"] == g["nodes"][1]["source_identity_sha256"], g["nodes"][3]
print("[deps] Cargo source identity and exact locked version OK")
PY

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
