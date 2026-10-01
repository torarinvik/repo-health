#!/usr/bin/env bash
# tests/test_inventory_cli.sh — M03-07 / M08 inventory interchange path:
# `rh_cli inventory --format cyclonedx|spdx` parses a standards-based
# inventory and writes rh-inventory/1. Asserts declared spec support (an
# unsupported version is reported, not interpreted), exact component counts,
# that only valid SHA-256 digests count as known, unknown-field awareness for
# SPDX, and fail-closed behavior.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-inventory"

fail() { echo "[inventory] FAIL: $1" >&2; exit 1; }

echo "[inventory] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT"/fixtures/inventory/*.json "$T"/

echo "[inventory] CycloneDX 1.5 (supported) -> observed"
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/cyclonedx-1.5.json" --out "$T/cdx.json" >/dev/null || fail "cyclonedx parse"
cmp -s "$T/cdx.json" "$ROOT/fixtures/inventory-results/cyclonedx-1.5.json" || fail "CycloneDX result differs from golden"
python3 - "$T/cdx.json" "$T/cyclonedx-1.5.json" "$ROOT" <<'PY'
import json, sys
import glob, hashlib
d = json.load(open(sys.argv[1]))
raw = open(sys.argv[2], "rb").read()
tr = json.load(open(sys.argv[1] + ".transformations.json"))
assert tr["schema"] == "rh-adapter-transformation-report/1" and tr["source_format"] == "cyclonedx", tr
assert tr["source_input_sha256"] == hashlib.sha256(raw).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/software-inventory/1" + bytes([0])).hexdigest(), tr
assert d["schema"] == "rh-inventory/1"
assert d["format"] == "cyclonedx" and d["spec_version"] == "1.5", d
assert d["status"] == "observed", d
assert d["provenance"] == {"input_sha256": __import__("hashlib").sha256(raw).hexdigest(),
                           "origin": "local_input", "locator_sha256": None}, d["provenance"]
c = d["counts"]
assert c == {"components": 2, "invalid": 1, "with_purl": 2, "with_hash": 2, "digest_known": 1, "unknown_top_keys": 0}, c
assert d["completeness"] == {
    "dependency_assertions": {"state": "declared", "count": 2, "complete": 1,
                              "incomplete": 1, "unknown": 0, "not_specified": 0},
    "compositions": [
        {"aggregate": "complete", "assemblies": 0, "dependencies": 2, "vulnerabilities": 0},
        {"aggregate": "incomplete_first_party_only", "assemblies": 1, "dependencies": 1, "vulnerabilities": 0},
        {"aggregate": "unknown", "assemblies": 0, "dependencies": 0, "vulnerabilities": 1},
    ],
}, d["completeness"]
metrics = {m["key"]: m for m in d["metrics"]}
assert len(metrics) == 7, metrics
for metric in metrics.values():
    assert metric["status"] == "observed", metric
    assert metric["evidence"] == ["inventory-input"], metric
    assert metric["quality_dimensions"] == {
        "completeness": "complete", "freshness": "unknown",
        "validity": "valid", "provenance": "evidence_backed",
    }, metric
assert {k: metrics[k]["value"] for k in metrics} == {
    "inventory.component_count": 2,
    "inventory.invalid_component_count": 1,
    "inventory.components_with_purl_count": 2,
    "inventory.components_with_hash_count": 2,
    "inventory.known_digest_count": 1,
    "provenance.artifact_digest_present_share": {"num": 2, "den": 2},
    "inventory.unknown_field_count": 0,
}, metrics
definitions = {}
for path in glob.glob(sys.argv[3] + "/metrics/definitions/*.json"):
    definition = json.load(open(path))
    definitions[(definition["key"], definition["version"])] = definition
expected_inputs = {
    "inventory.component_count": ["accepted_component_or_package_entries", "declared_spec_version", "format_required_identity_fields"],
    "inventory.invalid_component_count": ["cyclonedx_or_spdx_document", "declared_spec_version", "component_or_package_entries", "format_required_identity_fields"],
    "inventory.components_with_purl_count": ["accepted_component_or_package_entries", "nonempty_purl_field_or_spdx_purl_external_ref"],
    "inventory.components_with_hash_count": ["accepted_component_or_package_entries", "hash_or_checksum_entries"],
    "inventory.known_digest_count": ["accepted_component_or_package_entries", "sha256_hash_or_checksum_entries", "sha256_algorithm_and_hex_content"],
    "provenance.artifact_digest_present_share": ["accepted_component_or_package_entries", "hash_or_checksum_entries"],
    "inventory.unknown_field_count": ["cyclonedx_or_spdx_document", "declared_spec_version", "format_top_level_field_allowlist"],
}
assert len(d["metrics"]) == 7
for metric in d["metrics"]:
    identity = (metric["key"], metric["version"])
    definition = definitions[identity]
    assert definition["subject_kind"] == "project", (identity, definition)
    assert definition["source_requirements"] == ["captured-inventory-document"], (identity, definition)
    assert definition["inputs"] == expected_inputs[metric["key"]], (identity, definition.get("inputs"))
    assert metric["status"] == "observed" and metric["evidence"] == ["inventory-input"], metric
    output_type = definition["output"]["type"]
    if output_type == "integer":
        assert type(metric["value"]) is int and (definition["denominator_rule"] == "none" or definition["denominator_rule"].startswith("none;")), (identity, definition)
    else:
        assert output_type == "ratio" and set(metric["value"]) == {"num", "den"} and metric["value"]["den"] > 0, (identity, metric)
        assert definition["output"]["denominator"] and not definition["denominator_rule"].startswith("none"), (identity, definition)
known_digest = definitions[("inventory.known_digest_count", "1.0.0")]
assert known_digest["output"]["unit"] == "records", known_digest
assert "individual hash or checksum entries" in known_digest["params"]["scope"], known_digest
assert "not validated" in definitions[("inventory.components_with_purl_count", "1.0.0")]["params"]["scope"]
print("[inventory] all seven metric rows match catalog sources, inputs, types, and denominators")
by = {x["name"]: x for x in d["components"]}
assert by["serde"]["digest_known"] is True, by
assert by["left-pad"]["digest_known"] is False, by  # only valid SHA-256 counts
assert "valid != complete" in d["note"], d["note"]
print("[inventory] cyclonedx OK")
PY

for version in 1.4 1.6; do
  echo "[inventory] CycloneDX $version declared support -> observed"
  "$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/cyclonedx-$version.json" --out "$T/cdx-$version.json" >/dev/null || fail "CycloneDX $version parse"
  cmp -s "$T/cdx-$version.json" "$ROOT/fixtures/inventory-results/cyclonedx-$version.json" || fail "CycloneDX $version result differs from golden"
  python3 - "$T/cdx-$version.json" "$version" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["format"] == "cyclonedx" and d["spec_version"] == sys.argv[2], d
assert d["status"] == "observed" and d["counts"]["components"] == 1, d
assert len(d["metrics"]) == 7, d["metrics"]
for metric in d["metrics"]:
    assert metric["status"] == "observed", metric
    assert metric["evidence"] == ["inventory-input"], metric
    assert metric["quality_dimensions"] == {
        "completeness": "complete", "freshness": "unknown",
        "validity": "valid", "provenance": "evidence_backed",
    }, metric
print("[inventory] CycloneDX", sys.argv[2], "OK")
PY
done

echo "[inventory] digest count is per valid SHA-256 entry, not per component"
python3 - "$T/multiple-digests.json" <<'PY'
import json, sys
document = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "components": [{
        "type": "library",
        "name": "one-component",
        "version": "1.0.0",
        "purl": "not-a-validated-package-url",
        "hashes": [
            {"alg": "SHA-256", "content": "a" * 64},
            {"alg": "SHA-256", "content": "b" * 64},
            {"alg": "MD5", "content": "not-a-sha256"},
        ],
    }],
}
with open(sys.argv[1], "w") as output:
    json.dump(document, output, separators=(",", ":"))
PY
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/multiple-digests.json" --out "$T/multiple-digests.out" >/dev/null || fail "multiple digest input"
python3 - "$T/multiple-digests.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = {metric["key"]: metric for metric in d["metrics"]}
assert m["inventory.component_count"]["value"] == 1, m
assert m["inventory.components_with_hash_count"]["value"] == 1, m
assert m["inventory.known_digest_count"]["value"] == 2, m
assert m["inventory.components_with_purl_count"]["value"] == 1, m
assert m["provenance.artifact_digest_present_share"]["value"] == {"num": 1, "den": 1}, m
print("[inventory] per-entry SHA-256 and presence-only PURL counts OK")
PY

echo "[inventory] unmodeled top-level CycloneDX fields are counted, not dropped"
printf '{"bomFormat":"CycloneDX","specVersion":"1.5","components":[],"signature":{},"futureField":1}' > "$T/cdx-unknown.json"
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/cdx-unknown.json" --out "$T/cdx-unknown.out" >/dev/null || fail "cyclonedx unknown-keys run"
python3 - "$T/cdx-unknown.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["counts"]["unknown_top_keys"] == 2, d["counts"]
share = next(m for m in d["metrics"] if m["key"] == "provenance.artifact_digest_present_share")
assert share["status"] == "not_applicable" and share["value"] is None, share
assert share["reason"] == "no-parsed-components", share
assert share["evidence"] == ["inventory-input"], share
assert share["quality_dimensions"] == {
    "completeness": "unknown", "freshness": "unknown",
    "validity": "unknown", "provenance": "evidence_backed",
}, share
print("[inventory] cyclonedx unknown-keys counted OK")
PY

echo "[inventory] SPDX-2.3 (supported) -> observed, unknown keys counted"
"$ROOT/build/rh_cli" inventory --format spdx --input "$T/spdx-2.3.json" --out "$T/spdx.json" >/dev/null || fail "spdx parse"
cmp -s "$T/spdx.json" "$ROOT/fixtures/inventory-results/spdx-2.3.json" || fail "SPDX result differs from golden"
python3 - "$T/spdx.json" "$T/spdx-2.3.json" <<'PY'
import hashlib
import json, sys
d = json.load(open(sys.argv[1]))
tr = json.load(open(sys.argv[1] + ".transformations.json"))
assert tr["source_format"] == "spdx", tr
assert tr["source_input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/software-inventory/1" + bytes([1])).hexdigest(), tr
assert d["provenance"]["input_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), d
assert d["format"] == "spdx" and d["spec_version"] == "SPDX-2.3", d
assert d["status"] == "observed", d
assert d["provenance"]["origin"] == "local_input" and d["provenance"]["locator_sha256"] is None, d
assert d["completeness"]["dependency_assertions"]["state"] == "not_asserted", d
c = d["counts"]
assert c["packages"] == 2 and c["invalid"] == 1, c
assert c["unknown_top_keys"] == 1, c
metrics = {m["key"]: m for m in d["metrics"]}
assert len(metrics) == 7, metrics
for metric in metrics.values():
    assert metric["status"] == "observed", metric
    assert metric["evidence"] == ["inventory-input"], metric
    assert metric["quality_dimensions"] == {
        "completeness": "complete", "freshness": "unknown",
        "validity": "valid", "provenance": "evidence_backed",
    }, metric
assert metrics["inventory.component_count"]["value"] == 2, metrics
assert metrics["inventory.invalid_component_count"]["value"] == 1, metrics
assert metrics["inventory.known_digest_count"]["value"] == 1, metrics
assert metrics["provenance.artifact_digest_present_share"]["value"] == {"num": 2, "den": 2}, metrics
assert metrics["inventory.unknown_field_count"]["value"] == 1, metrics
print("[inventory] spdx OK")
PY

echo "[inventory] SPDX empty package set retains an explicit absent share"
python3 - "$T/spdx-empty.json" "$T/spdx-2.3.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[2]))
d["packages"] = []
with open(sys.argv[1], "w") as output:
    json.dump(d, output, separators=(",", ":"))
PY
"$ROOT/build/rh_cli" inventory --format spdx --input "$T/spdx-empty.json" --out "$T/spdx-empty.out" >/dev/null || fail "empty spdx parse"
python3 - "$T/spdx-empty.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
share = next(m for m in d["metrics"] if m["key"] == "provenance.artifact_digest_present_share")
assert share["status"] == "not_applicable" and share["value"] is None, share
assert share["reason"] == "no-parsed-packages", share
assert share["evidence"] == ["inventory-input"], share
assert share["quality_dimensions"] == {
    "completeness": "unknown", "freshness": "unknown",
    "validity": "unknown", "provenance": "evidence_backed",
}, share
print("[inventory] empty SPDX share OK")
PY

echo "[inventory] determinism"
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/cyclonedx-1.5.json" --out "$T/cdx2.json" >/dev/null || fail "rerun"
cmp -s "$T/cdx.json" "$T/cdx2.json" || fail "inventory output is not deterministic"

echo "[inventory] bounded --url capture retains source/status/error evidence"
source_url="file://$T/cyclonedx-1.5.json"
"$ROOT/build/rh_cli" inventory --format cyclonedx --url "$source_url" --out "$T/cdx-url.json" >/dev/null || fail "url parse"
cmp -s "$T/cyclonedx-1.5.json" "$T/cdx-url.json.source" || fail "url source evidence differs"
[[ -f "$T/cdx-url.json.source.status" && "$(cat "$T/cdx-url.json.source.status")" == "000" ]] || fail "url status evidence"
[[ -f "$T/cdx-url.json.source.err" && ! -s "$T/cdx-url.json.source.err" ]] || fail "url error evidence"
python3 - "$T/cdx.json" "$T/cdx-url.json" "$source_url" <<'PY'
import hashlib, json, sys
local, remote = (json.load(open(path)) for path in sys.argv[1:3])
assert remote["provenance"]["input_sha256"] == local["provenance"]["input_sha256"], remote
assert remote["provenance"]["origin"] == "captured_url", remote
assert remote["provenance"]["locator_sha256"] == hashlib.sha256(sys.argv[3].encode()).hexdigest(), remote
assert sys.argv[3] not in open(sys.argv[2]).read(), "raw source locator must not be published"
local.pop("provenance")
remote.pop("provenance")
assert local == remote, (local, remote)
PY
echo "[inventory] url capture OK"

echo "[inventory] unsupported spec version is reported, not interpreted"
printf '{"bomFormat":"CycloneDX","specVersion":"9.9","components":[{"type":"library","name":"x","version":"1"}]}' > "$T/badver.json"
set +e
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/badver.json" --out "$T/badver.out" >/dev/null 2>&1
rc_unsup=$?
set -e
[[ "$rc_unsup" -eq 3 ]] || fail "unsupported spec must exit 3 (got $rc_unsup)"
cmp -s "$T/badver.out" "$ROOT/fixtures/inventory-results/cyclonedx-unsupported.json" || fail "unsupported CycloneDX result differs from golden"
python3 - "$T/badver.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "unsupported", d
assert d["reason"] == "spec-version-not-in-declared-supported-set", d
assert d["spec_version"] == "9.9", d
assert "components" not in d, d
print("[inventory] unsupported-spec OK")
PY

echo "[inventory] wrong format / malformed input fail closed"
set +e
"$ROOT/build/rh_cli" inventory --format spdx --input "$T/cyclonedx-1.5.json" --out "$T/wrong.out" >/dev/null 2>&1; rc_wrong=$?
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/spdx-2.3.json" --out "$T/wrong2.out" >/dev/null 2>&1; rc_wrong2=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/notjson.json" --out "$T/bad.out" >/dev/null 2>&1; rc_json=$?
printf '{"bomFormat":"CycloneDX","specVersion":"1.5","components":[],"compositions":[{"aggregate":"future","dependencies":["x"]}]}' > "$T/bad-composition.json"
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/bad-composition.json" --out "$T/bad.out" >/dev/null 2>&1; rc_composition=$?
printf '{"bomFormat":"CycloneDX","specVersion":"1.5","components":[],"compositions":[{"aggregate":"complete","dependencies":[1]}]}' > "$T/bad-composition-ref.json"
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/bad-composition-ref.json" --out "$T/bad.out" >/dev/null 2>&1; rc_composition_ref=$?
"$ROOT/build/rh_cli" inventory --format sarif --input "$T/cyclonedx-1.5.json" --out "$T/bad.out" >/dev/null 2>&1; rc_fmt=$?
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/nope.json" --out "$T/bad.out" >/dev/null 2>&1; rc_missing=$?
"$ROOT/build/rh_cli" inventory --format cyclonedx --out "$T/bad.out" >/dev/null 2>&1; rc_neither=$?
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/cyclonedx-1.5.json" --url "$source_url" --out "$T/bad.out" >/dev/null 2>&1; rc_both=$?
set -e
[[ "$rc_wrong" -eq 4 ]] || fail "spdx reading cyclonedx must exit 4 (got $rc_wrong)"
[[ "$rc_wrong2" -eq 4 ]] || fail "cyclonedx reading spdx must exit 4 (got $rc_wrong2)"
[[ "$rc_json" -eq 4 ]] || fail "invalid JSON must exit 4 (got $rc_json)"
[[ "$rc_composition" -eq 4 ]] || fail "unknown composition aggregate must fail closed (got $rc_composition)"
[[ "$rc_composition_ref" -eq 4 ]] || fail "malformed composition targets must fail closed (got $rc_composition_ref)"
[[ "$rc_fmt" -eq 3 ]] || fail "unknown format must exit 3 (got $rc_fmt)"
[[ "$rc_missing" -eq 4 ]] || fail "missing input must exit 4 (got $rc_missing)"
[[ "$rc_neither" -eq 2 ]] || fail "missing input/url must exit 2 (got $rc_neither)"
[[ "$rc_both" -eq 2 ]] || fail "input and url together must exit 2 (got $rc_both)"

echo "[inventory] source-size cap is checked before parsing"
python3 - "$T/oversized.json" <<'PY'
import sys
with open(sys.argv[1], "wb") as output:
    output.truncate(64 * 1024 * 1024 + 1)
PY
set +e
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/oversized.json" --out "$T/oversized.out" >/dev/null 2>&1
rc_oversized=$?
set -e
[[ "$rc_oversized" -eq 4 ]] || fail "oversized inventory must fail closed (got $rc_oversized)"
[[ ! -e "$T/oversized.out" ]] || fail "oversized inventory wrote a partial result"

echo "test_inventory_cli OK"
