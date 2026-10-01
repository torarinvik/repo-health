#!/usr/bin/env bash
# tests/test_m01.sh — M01 exit gate: safe scan, replay, hostile fixtures.
# All fixture paths are allowlist-clean (no spaces/metachars) by construction.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/build/rh_cli"
T="/tmp/rh-m01-gate"

fail() { echo "[m01] FAIL: $1" >&2; exit 1; }
# expect <code> <command...>: asserts an expected nonzero exit under set -e.
expect() {
  local want="$1"; shift
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  [[ "$got" == "$want" ]] || fail "expected exit $want, got $got: $*"
}
need() { # need <file> <desc>
  [[ -f "$1" ]] || fail "missing $2 ($1)"
}

echo "[m01] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$CLI" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"

# --- usage / validation gates ---
expect 2 "$CLI" bogus
expect 3 "$CLI" scan --repo 'http://evil.example/x' --out "$T/r1"
expect 3 "$CLI" scan --repo 'ssh://example.com/a' --out "$T/r1"
expect 3 "$CLI" scan --repo 'https://127.0.0.1/repository.git' --out "$T/r1"
[[ ! -e "$T/r1" ]] || fail "disallowed HTTPS destination created a report directory"
expect 3 "$CLI" scan --repo 'https://192.168.1.7/repository.git' --out "$T/r1"
expect 3 "$CLI" scan --repo '/tmp/ok;id' --out "$T/r1"
expect 3 "$CLI" scan --repo '/tmp/ok$(id)' --out "$T/r1"
expect 4 "$CLI" scan --repo "$T/does-not-exist" --out "$T/r1"
echo "[m01] validation gates OK"

# --- F001: empty repository -> observed empty, honest unknowns ---
git init -q -b main "$T/empty"
"$CLI" scan --repo "$T/empty" --out "$T/rep-empty" >/dev/null || fail "empty scan"
python3 - "$T/rep-empty/report.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.commit_count"]["value"] == 0, m
assert m["contributors.raw_identity_count"]["value"] == 0, m
assert m["freshness.evidence_max_age_hours"]["status"] == "unavailable", m
assert "value" not in m["freshness.evidence_max_age_hours"], "unknown must carry no value"
default_revisions = m["history.revisions_reachable_default"]
assert default_revisions["status"] == "observed" and default_revisions["value"] == 0, default_revisions
assert default_revisions["evidence"] == ["evidence/git-default-count.txt"], default_revisions
assert default_revisions["quality_dimensions"] == {
    "completeness":"complete", "freshness":"unknown",
    "validity":"valid", "provenance":"evidence_backed",
}, default_revisions
for metric in d["metrics"]:
    assert isinstance(metric.get("evidence"), list), metric
    if metric["status"] == "error":
        assert metric["reason"] == "invalid-observation-contract" and not metric["evidence"], metric
    else:
        assert metric["evidence"], metric
    assert set(metric.get("quality_dimensions", {})) == {
        "completeness", "freshness", "validity", "provenance"
    }, metric
assert m["history.first_author_time"]["evidence"] == ["evidence/git-log.bin"], m
assert m["freshness.evidence_max_age_hours"]["quality_dimensions"]["validity"] == "unknown", m
print("[m01] F001 empty OK")
EOF

# --- F002: multi-author history, exact numbers + replay ---
mkdir -p "$T/fix2" && git init -q -b main "$T/fix2" && (
  cd "$T/fix2" && git config user.name "Alice" && git config user.email "alice@example.com"
  echo one > a.txt && git add a.txt
  GIT_AUTHOR_DATE="2024-03-10T12:00:00Z" GIT_COMMITTER_DATE="2024-03-10T12:00:00Z" git commit -qm "first"
  git config user.name "Bob" && git config user.email "bob@example.com"
  echo two > b.txt && git add b.txt
  GIT_AUTHOR_DATE="2024-06-15T12:00:00Z" GIT_COMMITTER_DATE="2024-06-20T12:00:00Z" git commit -qm "second"
  echo three >> a.txt && git add a.txt
  GIT_AUTHOR_DATE="2025-01-05T12:00:00Z" GIT_COMMITTER_DATE="2025-01-05T12:00:00Z" git commit -qm "third"
)
"$CLI" scan --repo "$T/fix2" --out "$T/rep-fix2" --window-days 36500 >/dev/null || fail "fix2 scan"
printf 'not a directory\n' > "$T/out-file"
expect 4 "$CLI" scan --repo "$T/fix2" --out "$T/out-file" --window-days 36500
python3 - "$T/rep-fix2" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
manifest = (root / "bundle.manifest").read_text()
assert manifest.startswith("repo-health-bundle-manifest 2\n")
assert (root / "evidence/emails.uniq").read_bytes() == b"alice@example.com\nbob@example.com\n"
for metadata in (
    "bundle-schema: rh-evidence-bundle/2",
    "report-schema: repo-health-m01/1.0.0",
    "rights-status: not-assessed",
    "retention-class: user-controlled-local",
    "identity-revision: not-applied",
    "mapping-revision: not-applied",
):
    assert metadata in manifest, metadata
for rel in ("evidence/git-default-count.txt", "evidence/git-files.txt",
            "evidence/git-log.bin", "evidence/git-shallow.txt", "evidence/git-version.txt",
            "evidence/git-partial.txt"):
    key = f"object-sha256-{rel}: "
    expected = hashlib.sha256((root / rel).read_bytes()).hexdigest()
    assert manifest.count(key + expected) == 1, key
expected = hashlib.sha256((root / "report.json").read_bytes()).hexdigest()
assert manifest.count("expected-output-sha256-report.json: " + expected) == 1
expected = hashlib.sha256((root / "report.md").read_bytes()).hexdigest()
assert manifest.count("expected-output-sha256-report.md: " + expected) == 1
print("[m01] evidence manifest hashes and metadata OK")
PY
python3 "$ROOT/tools/evidence-manifest-check.py" "$T/rep-fix2/bundle.manifest" >/dev/null || fail "manifest version-2 contract check"
cp "$T/rep-fix2/bundle.manifest" "$T/bad-manifest-order.txt"
python3 - "$T/bad-manifest-order.txt" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); rows = p.read_text().splitlines(); rows[2], rows[3] = rows[3], rows[2]; p.write_text("\n".join(rows) + "\n")
PY
if python3 "$ROOT/tools/evidence-manifest-check.py" "$T/bad-manifest-order.txt" >/dev/null 2>&1; then fail "manifest schema accepted noncanonical order"; fi
cp "$T/rep-fix2/bundle.manifest" "$T/bad-manifest-unknown.txt"
printf 'unreviewed-field: value\n' >> "$T/bad-manifest-unknown.txt"
if python3 "$ROOT/tools/evidence-manifest-check.py" "$T/bad-manifest-unknown.txt" >/dev/null 2>&1; then fail "manifest schema accepted unknown field"; fi
echo "[m01] independent manifest contract rejects noncanonical and unknown fields"
python3 - "$T/rep-fix2/report.json" "$ROOT" <<'EOF'
import glob, json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.commit_count"]["value"] == 3, m
assert m["history.commit_count"]["evidence"] == ["evidence/git-log.bin"], m
assert m["history.reachable_revisions"]["value"] == 3, m
assert m["history.revisions_reachable_default"]["value"] == 3, m
assert m["history.revisions_reachable_default"]["quality_dimensions"] == {
    "completeness":"complete", "freshness":"unknown",
    "validity":"valid", "provenance":"evidence_backed",
}, m["history.revisions_reachable_default"]
assert m["history.shallow_boundary_count"]["evidence"] == ["evidence/git-shallow.txt"], m
assert m["history.collection_complete_windows"]["value"] == {"complete": 1, "requested": 1}, m
assert m["history.collection_complete_windows"]["quality_dimensions"] == {
    "completeness":"complete", "freshness":"unknown",
    "validity":"valid", "provenance":"evidence_backed",
}, m["history.collection_complete_windows"]
assert m["history.collection_complete_windows"]["evidence"] == [
    "evidence/git-log.bin", "evidence/git-shallow.txt"
], m["history.collection_complete_windows"]
definitions = {}
for path in glob.glob(sys.argv[2] + "/metrics/definitions/*.json"):
    definition = json.load(open(path))
    definitions[(definition["key"], definition["version"])] = definition
identities = [(metric["key"], metric["version"]) for metric in d["metrics"]]
assert len(identities) == len(set(identities)) == 61, identities
for metric in d["metrics"]:
    identity = (metric["key"], metric["version"])
    definition = definitions[identity]
    assert definition["implementation_status"] == "implemented", (identity, definition)
    assert isinstance(definition.get("inputs"), list) and definition["inputs"], (identity, definition.get("inputs"))
    assert all(isinstance(value, str) and value.strip() for value in definition["inputs"]), (identity, definition["inputs"])
    assert len(definition["inputs"]) == len(set(definition["inputs"])), (identity, definition["inputs"])
    output = definition["output"]
    if "value" not in metric:
        assert metric["status"] != "observed", (identity, metric)
        continue
    value = metric["value"]
    value_type = output["type"]
    if value_type in ("integer", "timestamp"):
        assert type(value) is int and value >= 0, (identity, value)
    elif value_type == "boolean":
        assert type(value) is bool, (identity, value)
    elif value_type in ("ratio", "rational"):
        assert set(value) == {"num", "den"} and type(value["num"]) is int and type(value["den"]) is int and value["den"] > 0, (identity, value)
        if value_type == "ratio":
            assert 0 <= value["num"] <= value["den"], (identity, value)
    elif value_type == "enum":
        allowed_values = {entry["code"]: entry["label"] for entry in output["values"]}
        assert output["shape"] == "labeled_enum" and set(value) == {"code", "label"}, (identity, output, value)
        assert type(value["code"]) is int and allowed_values.get(value["code"]) == value["label"], (identity, value, allowed_values)
    elif value_type == "count_pair":
        members = output["members"]
        assert output["shape"] == "named_count_pair" and set(value) == set(members), (identity, output, value)
        assert all(type(value[name]) is int and value[name] >= 0 for name in members), (identity, value)
        assert value[members[0]] <= value[members[1]], (identity, value)
    else:
        raise AssertionError((identity, "unknown output type", value_type))
print("[m01] all 61 core report rows match implemented catalog output types and value shapes")
assert m["history.coverage_state"]["evidence"] == [
    "evidence/git-log.bin", "evidence/git-shallow.txt"
], m["history.coverage_state"]
assert m["history.coverage_state"]["value"] == {"code": 0, "label": "complete"}, m
assert m["source.manifest_presence"]["value"] == {"code": 0, "label": "none"}, m
assert m["history.rejected_record_count"]["value"] == 0, m
assert m["contributors.raw_identity_count"]["value"] == 2, m
assert m["activity.active_complete_months"]["value"] == 3, m
assert m["activity.accepted_changes"]["value"] == 3, m
assert m["activity.active_months"]["value"] == 3, m
assert m["contributor.source_accounts"]["value"] == 2, m
assert m["coverage.lineage_complete_share"]["value"] == {"num": 1, "den": 1}, m
assert m["coverage.lineage_complete_share"]["evidence"] == ["bundle.manifest", "evidence/git-log.bin"], m
assert m["documentation.readme_present"]["value"] is False, m
assert m["documentation.readme_present"]["evidence"] == ["evidence/git-files.txt"], m
assert m["source.manifest_presence"]["evidence"] == ["evidence/git-files.txt"], m
assert m["documentation.contributing_guide_present"]["value"] is False, m
assert m["licensing.license_declaration_present"]["value"] is False, m
expected_quality = {
    "completeness":"complete", "freshness":"unknown",
    "validity":"valid", "provenance":"evidence_backed",
}
for key in ("history.commit_count", "history.first_author_time", "history.coverage_state",
            "documentation.readme_present", "code.source_file_count", "coverage.lineage_complete_share"):
    assert m[key]["quality_dimensions"] == expected_quality, (key, m[key])
assert m["activity.weekly_count_slope"]["status"] in ("observed", "not_applicable"), m
assert m["activity.weekly_count_variance"]["status"] in ("observed", "not_applicable"), m
for key in ("activity.weekly_count_slope", "activity.weekly_count_variance",
            "activity.bot_event_share", "contributor.single_event_share"):
    if m[key]["status"] == "observed":
        assert m[key]["evidence"] == ["evidence/git-log.bin"], (key, m[key])
assert len(d["metrics"]) == 61, d
coverage = {(x["key"], x["version"]): x for x in d["metrics"] if x["key"] == "coverage.window_completeness"}
assert coverage[("coverage.window_completeness", "1.0.0")]["value"]["num"] == coverage[("coverage.window_completeness", "1.0.0")]["value"]["den"], coverage
assert coverage[("coverage.window_completeness", "2.0.0")]["value"]["num"] == coverage[("coverage.window_completeness", "2.0.0")]["value"]["den"], coverage
v1_definition = definitions[("coverage.window_completeness", "1.0.0")]
v2_definition = definitions[("coverage.window_completeness", "2.0.0")]
assert v1_definition["output"]["numerator"] == v1_definition["output"]["denominator"] == "complete_months_in_coverage_basis", v1_definition
assert "oldest retained history timestamp" in v1_definition["denominator_rule"], v1_definition
assert v2_definition["output"]["numerator"] == "complete_months_of_retained_history_in_window", v2_definition
assert v2_definition["output"]["denominator"] == "eligible_complete_months_in_window", v2_definition
coverage_inputs = ["requested_window", "retained_history_span", "shallow_history_state", "truncation_state"]
assert v1_definition["inputs"] == v2_definition["inputs"] == coverage_inputs, (v1_definition, v2_definition)
for metric_key in (
    "code.source_file_count", "documentation.api_reference_present",
    "documentation.contributing_guide_present", "documentation.example_program_count",
    "documentation.installation_guide_present", "documentation.readme_present",
    "governance.code_ownership_rules_present", "governance.governance_document_present",
    "governance.release_process_document_present", "governance.succession_process_document_present",
    "licensing.license_declaration_present", "licensing.license_file_count",
    "licensing.source_notice_presence", "release.release_note_presence",
    "security.security_policy_present", "source.manifest_presence",
):
    definition = next(value for (key, _), value in definitions.items() if key == metric_key)
    assert "retained-snapshot-paths" in definition["source_requirements"], (metric_key, definition)
for metric in coverage.values():
    assert metric["evidence"] == ["evidence/git-log.bin", "evidence/git-shallow.txt"], metric
valid = {"observed","not_observed","unavailable","unauthorized","partial","stale","not_applicable","error","conflicted","suppressed","unsupported"}
completeness = {"complete","partial","unknown"}
freshness = {"fresh","stale","unknown"}
validity = {"valid","invalid","unknown"}
provenance = {"evidence_backed","derived","unverified","unknown"}
evidence_objects = {
    "evidence/git-log.bin", "evidence/git-shallow.txt",
    "evidence/git-files.txt", "evidence/git-default-count.txt",
    "bundle.manifest",
}
for x in d["metrics"]:
    assert x["status"] in valid, x
    quality = x["quality_dimensions"]
    assert quality["completeness"] in completeness, (x, quality)
    assert quality["freshness"] in freshness, (x, quality)
    assert quality["validity"] in validity, (x, quality)
    assert quality["provenance"] in provenance, (x, quality)
    assert (x["status"] == "partial") == (quality["completeness"] == "partial"), (x, quality)
    assert (x["status"] == "stale") == (quality["freshness"] == "stale"), (x, quality)
    assert x["status"] != "observed" or quality["validity"] != "invalid", (x, quality)
    evidence = x["evidence"]
    if x["status"] == "error":
        assert x.get("reason") == "invalid-observation-contract" and not evidence, x
    assert all(link in evidence_objects for link in evidence), x
    assert len(evidence) == len(set(evidence)), x
    assert quality["provenance"] != "evidence_backed" or evidence, x
    if x["status"] not in ("observed","partial","stale"):
        assert "value" not in x, ("unknown carries value", x)
    if x["status"] in ("partial","stale"):
        assert x.get("reason"), x
    if "value" in x:
        value = x["value"]
        if isinstance(value, bool):
            pass
        elif isinstance(value, int):
            assert value >= 0, x
        elif isinstance(value, dict) and set(value) == {"num", "den"}:
            assert isinstance(value["num"], int) and value["den"] > 0, x
        elif isinstance(value, dict) and set(value) == {"code", "label"}:
            assert value["code"] >= 0 and isinstance(value["label"], str), x
        elif isinstance(value, dict) and set(value) == {"complete", "requested"}:
            assert 0 <= value["complete"] <= value["requested"], x
        else:
            raise AssertionError(("unclassified metric value", x))
print("[m01] F002 exact OK")
EOF

# Snapshot path observations come from the pinned Git tree for both worktrees
# and bare repositories; the file metric must not depend on checkout access.
mkdir -p "$T/manifest-fixture" && git init -q -b main "$T/manifest-fixture"
(
  cd "$T/manifest-fixture"
  git config user.name "Fixture"
  git config user.email "fixture@example.com"
  printf '{"name":"manifest-fixture"}\n' > package.json
  git add package.json
  GIT_AUTHOR_DATE="2025-01-05T12:00:00Z" GIT_COMMITTER_DATE="2025-01-05T12:00:00Z" git commit -qm "manifest fixture"
)
"$CLI" scan --repo "$T/manifest-fixture" --out "$T/manifest-worktree" --full-history >/dev/null || fail "manifest worktree scan"
git clone -q --bare "$T/manifest-fixture" "$T/manifest-bare.git"
"$CLI" scan --repo "$T/manifest-bare.git" --out "$T/manifest-bare" --full-history >/dev/null || fail "manifest bare scan"
python3 - "$T/manifest-worktree/report.json" "$T/manifest-bare/report.json" <<'PY'
import json, sys
worktree, bare = (json.load(open(path)) for path in sys.argv[1:])
def stable_metrics(report):
    return [
        (m["key"], m["version"], m["status"], m.get("value"), m["quality_dimensions"], m["evidence"])
        for m in report["metrics"] if m["key"] != "freshness.evidence_max_age_hours"
    ]
assert stable_metrics(worktree) == stable_metrics(bare), "worktree and bare tree observations differ"
manifest = next(m for m in bare["metrics"] if m["key"] == "source.manifest_presence")
assert manifest["value"] == {"code": 1, "label": "found"}, manifest
assert manifest["evidence"] == ["evidence/git-files.txt"], manifest
print("[m01] retained-tree manifest metric matches for worktree and bare repository")
PY

mkdir -p "$T/broken-tree" && git init -q -b main "$T/broken-tree"
(
  cd "$T/broken-tree"
  git config user.name "Fixture"
  git config user.email "fixture@example.com"
  printf 'tree snapshot required\n' > README.md
  git add README.md
  GIT_AUTHOR_DATE="2025-01-05T12:00:00Z" GIT_COMMITTER_DATE="2025-01-05T12:00:00Z" git commit -qm "tree snapshot fixture"
)
tree_oid="$(git -C "$T/broken-tree" rev-parse 'HEAD^{tree}')"
tree_object="$T/broken-tree/.git/objects/${tree_oid:0:2}/${tree_oid:2}"
[[ -f "$tree_object" ]] || fail "tree failure fixture is not a loose object"
rm "$tree_object"
expect 4 "$CLI" scan --repo "$T/broken-tree" --out "$T/broken-tree-report" --full-history
[[ ! -e "$T/broken-tree-report/report.json" ]] || fail "scan published a report without a readable tree snapshot"
echo "[m01] nonempty history fails closed when retained tree paths are unavailable"

echo "[m01] snapshot file classification is evidence-backed"
mkdir -p "$T/docs" && git init -q -b main "$T/docs" && (
  cd "$T/docs" && git config user.name "Docs" && git config user.email "docs@example.com"
  printf 'overview\n' > README.md
  printf 'guide\n' > CONTRIBUTING.md
  printf 'MIT\n' > LICENSE
  printf 'build\n' > INSTALL.md
  printf 'api\n' > API.md
  printf 'process\n' > GOVERNANCE.md
  mkdir -p .github && printf '* @maintainers\n' > .github/CODEOWNERS
  printf 'notice\n' > NOTICE
  printf 'release\n' > RELEASE.md
  printf 'handover\n' > HANDOVER.md
  mkdir -p examples/nested && printf 'hello\n' > examples/hello.md && printf 'demo\n' > examples/nested/demo.c
  mkdir -p tests .github/workflows && printf 'test\n' > tests/test_smoke.py && printf 'name: CI\n' > .github/workflows/ci.yml
  printf 'security\n' > SECURITY.md
  printf 'changes\n' > CHANGELOG.md
  git add README.md CONTRIBUTING.md LICENSE INSTALL.md API.md GOVERNANCE.md .github/CODEOWNERS .github/workflows/ci.yml NOTICE RELEASE.md HANDOVER.md SECURITY.md CHANGELOG.md examples tests
  GIT_AUTHOR_DATE="2024-05-01T00:00:00Z" GIT_COMMITTER_DATE="2024-05-01T00:00:00Z" git commit -qm "docs"
)
"$CLI" scan --repo "$T/docs" --out "$T/rep-docs" --window-days 36500 >/dev/null || fail "docs scan"
python3 - "$T/rep-docs/report.json" "$T/rep-docs/evidence/git-files.txt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["documentation.readme_present"] == {
    "key":"documentation.readme_present","version":"1.0.0","status":"observed","value":True,
    "quality_dimensions":{"completeness":"complete","freshness":"unknown","validity":"valid","provenance":"evidence_backed"},
    "evidence":["evidence/git-files.txt"]
}, m
assert m["documentation.contributing_guide_present"]["value"] is True, m
assert m["licensing.license_declaration_present"]["value"] is True, m
assert m["documentation.installation_guide_present"]["value"] is True, m
assert m["documentation.api_reference_present"]["value"] is True, m
assert m["governance.governance_document_present"]["value"] is True, m
assert m["governance.code_ownership_rules_present"]["value"] is True, m
assert m["licensing.source_notice_presence"]["value"] is True, m
assert m["governance.release_process_document_present"]["value"] is True, m
assert m["governance.succession_process_document_present"]["value"] is True, m
assert m["licensing.license_file_count"]["value"] == 1, m
assert m["documentation.example_program_count"]["value"] == 2, m
assert m["security.security_policy_present"]["value"] is True, m
assert m["release.release_note_presence"]["value"] is True, m
assert m["code.source_file_count"]["value"] == 2, m
assert m["build.ci_configuration_present"]["value"] is True, m
assert m["testing.test_files_observed"]["value"] == 1, m
assert m["code.source_bytes"]["value"] == 10, m
assert m["history.missing_object_count"] == {
    "key":"history.missing_object_count","version":"1.0.0","status":"observed","value":0,
    "quality_dimensions":{"completeness":"complete","freshness":"unknown","validity":"valid","provenance":"evidence_backed"},
    "evidence":["evidence/git-files.txt"]
}, m
assert b"\tREADME.md\0" in open(sys.argv[2], "rb").read(), "retained long-tree evidence missing README"
print("[m01] snapshot file classification OK")
PY
"$CLI" replay --bundle "$T/rep-fix2/bundle.manifest" --out "$T/replay-fix2" >/dev/null || fail "replay"
python3 -c "
import json; d = json.load(open('$T/replay-fix2/replay.json'))
assert d['verified'] is True, d
m = {x['key']: x for x in d['metrics']}
assert m['coverage.replay_match_share']['value'] == {'num': 1, 'den': 1}, m
assert m['coverage.replay_match_share']['evidence'] == ['bundle.manifest', 'evidence/git-log.bin'], m
assert m['coverage.replay_match_share']['quality_dimensions'] == {'completeness':'complete','freshness':'unknown','validity':'valid','provenance':'evidence_backed'}, m
assert open('$T/replay-fix2/report.md', 'rb').read() == open('$T/rep-fix2/report.md', 'rb').read()
assert open('$T/replay-fix2/report.json', 'rb').read() == open('$T/rep-fix2/report.json', 'rb').read()
print('[m01] replay verified OK')"
cp -R "$T/rep-fix2" "$T/rep-legacy-v1"
python3 - "$T/rep-legacy-v1/bundle.manifest" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
manifest = path.read_text().replace("repo-health-bundle-manifest 2\n", "repo-health-bundle-manifest 1\n", 1).replace("bundle-schema: rh-evidence-bundle/2\n", "bundle-schema: rh-evidence-bundle/1\n", 1)
manifest = "\n".join(line for line in manifest.splitlines() if not line.startswith("expected-output-sha256-report.md: ")) + "\n"
path.write_text(manifest)
PY
python3 "$ROOT/tools/evidence-manifest-check.py" "$T/rep-legacy-v1/bundle.manifest" >/dev/null || fail "manifest version-1 contract check"
"$CLI" replay --bundle "$T/rep-legacy-v1/bundle.manifest" --out "$T/replay-legacy-v1" >/dev/null || fail "legacy v1 replay"
cmp "$T/rep-legacy-v1/report.md" "$T/replay-legacy-v1/report.md" || fail "legacy v1 markdown regeneration"
cmp "$T/rep-legacy-v1/report.json" "$T/replay-legacy-v1/report.json" || fail "legacy v1 JSON regeneration"
echo "[m01] version-1 bundles replay with regenerated JSON and Markdown"
cp "$T/rep-fix2/bundle.manifest" "$T/inconsistent-schema.manifest"
python3 - "$T/inconsistent-schema.manifest" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text(path.read_text().replace("bundle-schema: rh-evidence-bundle/2", "bundle-schema: rh-evidence-bundle/1", 1))
PY
expect 4 "$CLI" replay --bundle "$T/inconsistent-schema.manifest" --out "$T/replay-inconsistent-schema"
echo "[m01] inconsistent bundle header/schema rejected"
mv "$T/rep-fix2/evidence/git-files.txt" "$T/rep-fix2/evidence/git-files.missing"
expect 4 "$CLI" replay --bundle "$T/rep-fix2/bundle.manifest" --out "$T/replay-missing-files"
mv "$T/rep-fix2/evidence/git-files.missing" "$T/rep-fix2/evidence/git-files.txt"
echo "[m01] replay requires retained file evidence OK"
# Rebinding a modified report digest must not make it replayable: replay
# regenerates report.json from retained evidence and compares the exact bytes.
cp -R "$T/rep-fix2" "$T/rep-forged-report"
python3 - "$T/rep-forged-report/report.json" "$T/rep-forged-report/bundle.manifest" <<'PY'
import hashlib, json, pathlib, sys
report_path, manifest_path = map(pathlib.Path, sys.argv[1:])
report = json.loads(report_path.read_bytes())
report["metrics"][0]["value"] = 999
report_bytes = (json.dumps(report, separators=(",", ":")) + "\n").encode()
report_path.write_bytes(report_bytes)
manifest = manifest_path.read_text()
old = next(line for line in manifest.splitlines() if line.startswith("expected-output-sha256-report.json: "))
new = "expected-output-sha256-report.json: " + hashlib.sha256(report_bytes).hexdigest()
manifest_path.write_text(manifest.replace(old, new, 1))
PY
expect 5 "$CLI" replay --bundle "$T/rep-forged-report/bundle.manifest" --out "$T/replay-forged-report"
echo "[m01] replay regenerates report despite rebound digest OK"
# Rebinding altered Markdown must not bypass regeneration from retained evidence.
cp -R "$T/rep-fix2" "$T/rep-forged-markdown"
python3 - "$T/rep-forged-markdown/report.md" "$T/rep-forged-markdown/bundle.manifest" <<'PY'
import hashlib, pathlib, sys
report_path, manifest_path = map(pathlib.Path, sys.argv[1:])
report_bytes = report_path.read_bytes() + b"\nforged summary\n"
report_path.write_bytes(report_bytes)
manifest = manifest_path.read_text()
old = next(line for line in manifest.splitlines() if line.startswith("expected-output-sha256-report.md: "))
new = "expected-output-sha256-report.md: " + hashlib.sha256(report_bytes).hexdigest()
manifest_path.write_text(manifest.replace(old, new, 1))
PY
expect 5 "$CLI" replay --bundle "$T/rep-forged-markdown/bundle.manifest" --out "$T/replay-forged-markdown"
echo "[m01] replay regenerates Markdown despite rebound digest OK"
# determinism: scan twice, same digest
"$CLI" scan --repo "$T/fix2" --out "$T/rep-fix2b" --window-days 36500 >/dev/null || fail "rescan"
a="$(grep digest-fnv1a64 "$T/rep-fix2/bundle.manifest")"; b="$(grep digest-fnv1a64 "$T/rep-fix2b/bundle.manifest")"
[[ "$a" == "$b" ]] || fail "non-deterministic digest: $a vs $b"
echo "[m01] determinism OK"

# --- hostile: unicode author, future timestamp, skew, merge ---
mkdir -p "$T/hostile" && git init -q -b main "$T/hostile" && (
  cd "$T/hostile" && git config user.name "Åsa Ö" && git config user.email "asa@example.com"
  echo x > f && git add f
  GIT_AUTHOR_DATE="2024-01-01T00:00:00Z" GIT_COMMITTER_DATE="2030-01-01T00:00:00Z" git commit -qm "skewed future"
  git checkout -qb side && echo y > g && git add g
  GIT_AUTHOR_DATE="2024-02-01T00:00:00Z" GIT_COMMITTER_DATE="2024-02-01T00:00:00Z" git commit -qm "side work"
  git checkout -q main && git merge -q --no-ff side -m "merge side"
  printf 'bad\xffsubject' > msg && git commit -q --allow-empty -F msg
)
out="$("$CLI" scan --repo "$T/hostile" --out "$T/rep-hostile" --window-days 36500)" || fail "hostile scan crashed"
echo "$out"
python3 - "$T/rep-hostile/report.md" <<'EOF'
import sys
md = open(sys.argv[1]).read()
assert "| future timestamps | flagged | " in md, md
print("[m01] hostile future-flagged OK")
EOF
python3 -c "
import json; d = json.load(open('$T/rep-hostile/report.json'))
m = {x['key']: x for x in d['metrics']}
assert m['history.commit_count']['value'] == 4, m"
echo "[m01] hostile counts OK"

# --- S001: the scanner never runs a source-controlled command ---
# A hostile repository can carry config/attribute traps that would run
# arbitrary code under a naive tool (e.g. `core.fsmonitor` as a command,
# `core.pager`, filter drivers). The scanner must ignore all of them.
# The canary file must NOT be created by the scan.
mkdir -p "$T/traps" && git init -q -b main "$T/traps" && (
  cd "$T/traps" && git config user.name "Eve" && git config user.email "eve@example.com"
  # config traps whose values are shell commands
  git config core.fsmonitor "$T/CANARY_FSMONITOR"
  git config core.pager "$T/CANARY_PAGER"
  git config core.hooksPath "$T/traps-hooks"
  git config filter.evil.clean "$T/CANARY_FILTER"
  git config diff.evil.textconv "$T/CANARY_TEXTconv"
  # attributes trap referencing the filter
  printf '*.evil filter=evil\n' > .gitattributes
  printf 'payload\n' > f.evil
  echo x > f && git add f .gitattributes f.evil
  GIT_AUTHOR_DATE="2024-04-01T00:00:00Z" GIT_COMMITTER_DATE="2024-04-01T00:00:00Z" git commit -qm "traps"
  # an executable .git/hooks/post-checkout that would fire on a checkout-based tool
  printf '#!/bin/sh\ntouch "%s"\n' "$T/CANARY_HOOK" > .git/hooks/post-checkout
  chmod +x .git/hooks/post-checkout
)
rm -f "$T"/CANARY_*
"$CLI" scan --repo "$T/traps" --out "$T/rep-traps" --window-days 36500 >/dev/null || fail "traps scan crashed"
if ls "$T"/CANARY_* >/dev/null 2>&1; then
  fail "S001: a source-controlled command executed during collection: $(ls "$T"/CANARY_*)"
fi
python3 -c "
import json; d = json.load(open('$T/rep-traps/report.json'))
m = {x['key']: x for x in d['metrics']}
assert m['history.commit_count']['value'] == 1, m
print('[m01] S001 no-source-command canaries intact OK')"

# --- S003: transport credentials never appear in report, evidence, or logs ---
# The canary is a CREDENTIAL (a git credential-store token), not committed
# history. It must never appear anywhere. (A token a project deliberately
# commits as author data is evidence, not a leaked credential — that case
# is covered by the transport guard rejecting userinfo in URLs.)
SECRET='ghp_CANARY0123456789CANARY0123456789'
mkdir -p "$T/secret" && git init -q -b main "$T/secret" && (
  cd "$T/secret" && git config user.name "Secret Holder" && git config user.email "secret@example.com"
  git config credential.helper "store --file=$T/credentials"
  printf 'https://user:%s@example.invalid\n' "$SECRET" > "$T/credentials"
  chmod 600 "$T/credentials"
  echo x > f && git add f
  GIT_AUTHOR_DATE="2024-07-01T00:00:00Z" GIT_COMMITTER_DATE="2024-07-01T00:00:00Z" git commit -qm "clean history"
  # a URL with embedded credentials in upstream config: the transport guard
  # must reject userinfo, and nothing should echo the secret.
  git remote add origin "https://user:${SECRET}@example.invalid/x.git"
)
"$CLI" scan --repo "$T/secret" --out "$T/rep-secret" --window-days 36500 >/dev/null || fail "secret scan crashed"
if grep -R -q -- "$SECRET" "$T/rep-secret" 2>/dev/null; then
  fail "S003: credential canary found in scan output: $(grep -Rl -- "$SECRET" "$T/rep-secret")"
fi
# The remote URL itself is not evidence the scan copies, and the credential
# store file must not be captured by the scanner.
if grep -R -q -- "$SECRET" "$T/rep-secret/evidence" 2>/dev/null; then
  fail "S003: credential canary found in evidence"
fi
out_secret="$("$CLI" scan --repo "$T/secret" --out "$T/rep-secret2" --window-days 36500 2>&1 || true)"
if printf '%s' "$out_secret" | grep -q -- "$SECRET"; then
  fail "S003: credential canary found on stdout/stderr"
fi
echo "[m01] S003 credential-canary absent OK"

# --- shallow clone: no complete-lifetime claim ---
git clone -q --depth 1 "file://$T/fix2" "$T/shallow" 2>/dev/null
"$CLI" scan --repo "$T/shallow" --out "$T/rep-shallow" --window-days 365 >/dev/null || fail "shallow scan"
python3 - "$T/rep-shallow/report.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.coverage_state"]["value"]["label"] == "shallow", m
assert m["coverage.window_completeness"]["status"] == "partial", m
assert m["coverage.window_completeness"]["reason"] == "history-coverage-incomplete", m
assert m["coverage.window_completeness"]["quality_dimensions"] == {
    "completeness": "partial", "freshness": "unknown",
    "validity": "valid", "provenance": "evidence_backed",
}, m["coverage.window_completeness"]
coverage = {(x["key"], x["version"]): x for x in d["metrics"] if x["key"] == "coverage.window_completeness"}
v1 = coverage[("coverage.window_completeness", "1.0.0")]
v2 = coverage[("coverage.window_completeness", "2.0.0")]
assert v1["reason"] == v2["reason"] == "history-coverage-incomplete", (v1, v2)
assert v1["evidence"] == v2["evidence"] == ["evidence/git-log.bin", "evidence/git-shallow.txt"], (v1, v2)
assert v1["value"]["num"] == v1["value"]["den"], (v1, v2)
assert v1["value"]["num"] > v2["value"]["den"], (v1, v2)
assert 0 <= v2["value"]["num"] <= v2["value"]["den"], (v1, v2)
print("[m01] shallow OK")
EOF

# --- clone-path equivalence: same history, different provenance ---
git clone -q "$T/fix2" "$T/fix2copy" 2>/dev/null
"$CLI" scan --repo "$T/fix2copy" --out "$T/rep-copy" --window-days 36500 >/dev/null || fail "copy scan"
python3 - "$T/rep-fix2/report.json" "$T/rep-copy/report.json" <<'EOF'
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
assert a["metrics"] == b["metrics"], "same history must yield same metrics"
assert a["source"] != b["source"], "provenance must differ"
print("[m01] clone equivalence OK")
EOF

# --- F004: missing blobs -> history observed, blob metrics partial ---
# A partial clone is marked via extensions.partialClone; the scanner must
# report blob-derived metrics PARTIAL while history stays observed. Both
# directions are checked: no marker -> not partial.
mkdir -p "$T/partial" && git init -q -b main "$T/partial" && (
  cd "$T/partial" && git config user.name "Pat" && git config user.email "pat@example.com"
  echo x > f && git add f
  GIT_AUTHOR_DATE="2024-05-01T00:00:00Z" GIT_COMMITTER_DATE="2024-05-01T00:00:00Z" git commit -qm "one"
  git config extensions.partialClone origin
  git config remote.origin.promisor true
)
"$CLI" scan --repo "$T/partial" --out "$T/rep-partial" --window-days 36500 >/dev/null || fail "partial scan"
python3 - "$T/rep-partial/report.json" "$T/rep-partial/report.md" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.commit_count"]["status"] == "observed", m
caps = d["capabilities"]
assert caps["blob_metrics"] == "partial-missing-blobs", caps
md = open(sys.argv[2]).read()
assert "blob-derived metrics | partial" in md, md
print("[m01] F004 partial-clone blob-partial OK")
EOF
echo "[m01] retained tree marks unavailable blob sizes as partial missing objects"
blob_id="$(git -C "$T/partial" rev-parse HEAD:f)"
rm "$T/partial/.git/objects/${blob_id:0:2}/${blob_id:2}"
"$CLI" scan --repo "$T/partial" --out "$T/rep-missing-object" --window-days 36500 >/dev/null || fail "missing object scan"
python3 - "$T/rep-missing-object/report.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.missing_object_count"]["status"] == "partial", m
assert m["history.missing_object_count"]["value"] == 1, m
assert m["history.missing_object_count"]["reason"] == "blob-size-unavailable", m
assert m["history.missing_object_count"]["quality_dimensions"] == {
    "completeness":"partial", "freshness":"unknown",
    "validity":"valid", "provenance":"evidence_backed",
}, m["history.missing_object_count"]
print("[m01] missing-object partial state OK")
EOF
"$CLI" scan --repo "$T/fix2" --out "$T/rep-nopart" --window-days 36500 >/dev/null || fail "nopart scan"
python3 - "$T/rep-nopart/report.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["blob_metrics"] == "not-derived", d["capabilities"]
print("[m01] F004 no-marker-not-partial OK")
EOF

# --- F006: identical-patch commits (cherry-pick-like) stay distinct ---
mkdir -p "$T/fix6" && git init -q -b main "$T/fix6" && (
  cd "$T/fix6" && git config user.name "Dev" && git config user.email "dev@example.com"
  echo base > base.txt && git add base.txt
  GIT_AUTHOR_DATE="2024-01-01T00:00:00Z" GIT_COMMITTER_DATE="2024-01-01T00:00:00Z" git commit -qm "base"
  echo shared > shared.txt && git add shared.txt
  GIT_AUTHOR_DATE="2024-02-01T00:00:00Z" GIT_COMMITTER_DATE="2024-02-01T00:00:00Z" git commit -qm "add shared"
  git checkout -q -b alt HEAD~1
  echo shared > shared.txt && git add shared.txt
  GIT_AUTHOR_DATE="2024-03-01T00:00:00Z" GIT_COMMITTER_DATE="2024-03-01T00:00:00Z" git commit -qm "add shared (re-created)"
)
"$CLI" scan --repo "$T/fix6" --out "$T/rep-fix6" --window-days 36500 >/dev/null || fail "fix6 scan"
python3 - "$T/rep-fix6/report.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["key"]: x for x in d["metrics"]}
assert m["history.commit_count"]["value"] == 3, m
assert m["history.reachable_revisions"]["value"] == 3, m
blob = json.dumps(d).lower()
assert "equivalent" not in blob, "must not claim revision equivalence without evidence"
print("[m01] F006 distinct-revisions OK")
EOF

# --- tamper evidence: appended byte -> exit 5, no fabricated success ---
cp -r "$T/rep-fix2" "$T/rep-tampered"
printf 'X' >> "$T/rep-tampered/evidence/git-log.bin"
expect 5 "$CLI" replay --bundle "$T/rep-tampered/bundle.manifest" --out "$T/replay-t"
cp -r "$T/rep-fix2" "$T/rep-files-tampered"
printf 'X' >> "$T/rep-files-tampered/evidence/git-files.txt"
expect 5 "$CLI" replay --bundle "$T/rep-files-tampered/bundle.manifest" --out "$T/replay-files-t"
cp -r "$T/rep-fix2" "$T/rep-shallow-tampered"
printf 'X' >> "$T/rep-shallow-tampered/evidence/git-shallow.txt"
expect 5 "$CLI" replay --bundle "$T/rep-shallow-tampered/bundle.manifest" --out "$T/replay-shallow-t"
cp -r "$T/rep-fix2" "$T/rep-version-tampered"
printf 'X' >> "$T/rep-version-tampered/evidence/git-version.txt"
expect 5 "$CLI" replay --bundle "$T/rep-version-tampered/bundle.manifest" --out "$T/replay-version-t"
cp -r "$T/rep-fix2" "$T/rep-report-tampered"
printf 'X' >> "$T/rep-report-tampered/report.json"
expect 5 "$CLI" replay --bundle "$T/rep-report-tampered/bundle.manifest" --out "$T/replay-report-t"
echo "[m01] tamper exit-5 OK"
# corrupt manifest -> exit 4 (fails closed)
cp "$T/rep-fix2/bundle.manifest" "$T/bad.manifest"
python3 -c "
src = open('$T/bad.manifest').read()
import re; src = re.sub(r'digest-fnv1a64: [0-9a-f]+', 'digest-fnv1a64: zzzzzzzzzzzzzzzz', src)
open('$T/bad.manifest','w').write(src)"
expect 4 "$CLI" replay --bundle "$T/bad.manifest" --out "$T/replay-b"
echo "[m01] corrupt-manifest exit-4 OK"
cp "$T/rep-fix2/bundle.manifest" "$T/duplicate-partial-clone.manifest"
python3 - "$T/duplicate-partial-clone.manifest" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
line = next(line for line in s.splitlines(keepends=True) if line.startswith("partial-clone: "))
open(p, "w").write(s + line)
PY
expect 4 "$CLI" replay --bundle "$T/duplicate-partial-clone.manifest" --out "$T/replay-duplicate-partial-clone"
cp "$T/rep-fix2/bundle.manifest" "$T/bad-partial-clone.manifest"
sed 's/partial-clone: false/partial-clone: maybe/' "$T/bad-partial-clone.manifest" > "$T/bad-partial-clone.tmp"
mv "$T/bad-partial-clone.tmp" "$T/bad-partial-clone.manifest"
expect 4 "$CLI" replay --bundle "$T/bad-partial-clone.manifest" --out "$T/replay-bad-partial-clone"
echo "[m01] replay requires unique typed report context OK"
cp "$T/rep-fix2/bundle.manifest" "$T/bad-object.manifest"
python3 - "$T/bad-object.manifest" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = "object-sha256-evidence/git-log.bin: "
assert s.count(needle) == 1
open(p, "w").write(s.replace(needle, "x" + needle, 1))
PY
expect 4 "$CLI" replay --bundle "$T/bad-object.manifest" --out "$T/replay-bad-object"
echo "[m01] malformed digest-field exit-4 OK"
cp "$T/rep-fix2/bundle.manifest" "$T/duplicate-object.manifest"
python3 - "$T/duplicate-object.manifest" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = "object-sha256-evidence/git-log.bin: "
line = next(line for line in s.splitlines(keepends=True) if line.startswith(needle))
open(p, "w").write(s + line)
PY
expect 4 "$CLI" replay --bundle "$T/duplicate-object.manifest" --out "$T/replay-duplicate-object"
echo "[m01] duplicate digest-field exit-4 OK"
cp "$T/rep-fix2/bundle.manifest" "$T/bad-fnv-prefix.manifest"
python3 - "$T/bad-fnv-prefix.manifest" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = "digest-fnv1a64: "
assert s.count(needle) == 1
open(p, "w").write(s.replace(needle, "x" + needle, 1))
PY
expect 4 "$CLI" replay --bundle "$T/bad-fnv-prefix.manifest" --out "$T/replay-bad-fnv-prefix"
cp "$T/rep-fix2/bundle.manifest" "$T/duplicate-fnv.manifest"
python3 - "$T/duplicate-fnv.manifest" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = "digest-fnv1a64: "
line = next(line for line in s.splitlines(keepends=True) if line.startswith(needle))
open(p, "w").write(s + line)
PY
expect 4 "$CLI" replay --bundle "$T/duplicate-fnv.manifest" --out "$T/replay-duplicate-fnv"
echo "[m01] malformed and duplicate FNV bindings exit-4 OK"

# --- R030: no universal score language anywhere in outputs ---
if grep -ril "health_score\|trust_score\|trustworthy\|health-rating" "$T/rep-fix2" "$T/rep-empty" "$T/rep-hostile" 2>/dev/null; then
  fail "universal-score language in reports"
fi
echo "[m01] R030 language scan OK"

if [[ "${RH_M01_LIVE:-0}" == "1" ]]; then
  live_url="${RH_M01_LIVE_URL:-https://github.com/octocat/Hello-World.git}"
  "$CLI" scan --repo "$live_url" --out "$T/live-remote" --full-history >/dev/null || fail "approved live HTTPS scan"
  "$CLI" scan --repo "$T/live-remote/evidence/remote.git" --out "$T/live-local" --full-history >/dev/null || fail "live clone local replay scan"
  "$CLI" replay --bundle "$T/live-remote/bundle.manifest" --out "$T/live-replay" >/dev/null || fail "live HTTPS bundle replay"
  cmp -s "$T/live-remote/report.json" "$T/live-replay/report.json" || fail "live HTTPS replay JSON differs"
  cmp -s "$T/live-remote/report.md" "$T/live-replay/report.md" || fail "live HTTPS replay Markdown differs"
  python3 - "$T/live-remote/report.json" "$T/live-local/report.json" <<'PY'
import json, sys
remote, local = (json.load(open(path)) for path in sys.argv[1:])
def stable_metrics(report):
    return [
        (m["key"], m["version"], m["status"], m.get("value"), m["quality_dimensions"], m["evidence"])
        for m in report["metrics"] if m["key"] != "freshness.evidence_max_age_hours"
    ]
assert stable_metrics(remote) == stable_metrics(local), "HTTPS and local scan metric observations differ"
print("[m01] approved HTTPS and cloned-local metric parity OK")
PY
fi

echo "test_m01 OK"
