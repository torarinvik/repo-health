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
python3 - "$T/cdx.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-inventory/1"
assert d["format"] == "cyclonedx" and d["spec_version"] == "1.5", d
assert d["status"] == "observed", d
c = d["counts"]
assert c == {"components": 2, "invalid": 1, "with_purl": 2, "with_hash": 2, "digest_known": 1, "unknown_top_keys": 0}, c
metrics = {m["key"]: m for m in d["metrics"]}
assert {k: metrics[k]["value"] for k in metrics} == {
    "inventory.component_count": 2,
    "inventory.invalid_component_count": 1,
    "inventory.components_with_purl_count": 2,
    "inventory.components_with_hash_count": 2,
    "inventory.known_digest_count": 1,
    "provenance.artifact_digest_present_share": {"num": 2, "den": 2},
    "inventory.unknown_field_count": 0,
}, metrics
by = {x["name"]: x for x in d["components"]}
assert by["serde"]["digest_known"] is True, by
assert by["left-pad"]["digest_known"] is False, by  # only valid SHA-256 counts
assert "valid != complete" in d["note"], d["note"]
print("[inventory] cyclonedx OK")
PY

echo "[inventory] unmodeled top-level CycloneDX fields are counted, not dropped"
printf '{"bomFormat":"CycloneDX","specVersion":"1.5","components":[],"signature":{},"futureField":1}' > "$T/cdx-unknown.json"
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/cdx-unknown.json" --out "$T/cdx-unknown.out" >/dev/null || fail "cyclonedx unknown-keys run"
python3 - "$T/cdx-unknown.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["counts"]["unknown_top_keys"] == 2, d["counts"]
print("[inventory] cyclonedx unknown-keys counted OK")
PY

echo "[inventory] SPDX-2.3 (supported) -> observed, unknown keys counted"
"$ROOT/build/rh_cli" inventory --format spdx --input "$T/spdx-2.3.json" --out "$T/spdx.json" >/dev/null || fail "spdx parse"
python3 - "$T/spdx.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["format"] == "spdx" and d["spec_version"] == "SPDX-2.3", d
assert d["status"] == "observed", d
c = d["counts"]
assert c["packages"] == 2 and c["invalid"] == 1, c
assert c["unknown_top_keys"] == 1, c
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["inventory.component_count"]["value"] == 2, metrics
assert metrics["inventory.invalid_component_count"]["value"] == 1, metrics
assert metrics["inventory.known_digest_count"]["value"] == 1, metrics
assert metrics["provenance.artifact_digest_present_share"]["value"] == {"num": 2, "den": 2}, metrics
assert metrics["inventory.unknown_field_count"]["value"] == 1, metrics
print("[inventory] spdx OK")
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
cmp -s "$T/cdx.json" "$T/cdx-url.json" || fail "url inventory differs"
echo "[inventory] url capture OK"

echo "[inventory] unsupported spec version is reported, not interpreted"
printf '{"bomFormat":"CycloneDX","specVersion":"9.9","components":[{"type":"library","name":"x","version":"1"}]}' > "$T/badver.json"
set +e
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/badver.json" --out "$T/badver.out" >/dev/null 2>&1
rc_unsup=$?
set -e
[[ "$rc_unsup" -eq 3 ]] || fail "unsupported spec must exit 3 (got $rc_unsup)"
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
"$ROOT/build/rh_cli" inventory --format sarif --input "$T/cyclonedx-1.5.json" --out "$T/bad.out" >/dev/null 2>&1; rc_fmt=$?
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/nope.json" --out "$T/bad.out" >/dev/null 2>&1; rc_missing=$?
"$ROOT/build/rh_cli" inventory --format cyclonedx --out "$T/bad.out" >/dev/null 2>&1; rc_neither=$?
"$ROOT/build/rh_cli" inventory --format cyclonedx --input "$T/cyclonedx-1.5.json" --url "$source_url" --out "$T/bad.out" >/dev/null 2>&1; rc_both=$?
set -e
[[ "$rc_wrong" -eq 4 ]] || fail "spdx reading cyclonedx must exit 4 (got $rc_wrong)"
[[ "$rc_wrong2" -eq 4 ]] || fail "cyclonedx reading spdx must exit 4 (got $rc_wrong2)"
[[ "$rc_json" -eq 4 ]] || fail "invalid JSON must exit 4 (got $rc_json)"
[[ "$rc_fmt" -eq 3 ]] || fail "unknown format must exit 3 (got $rc_fmt)"
[[ "$rc_missing" -eq 4 ]] || fail "missing input must exit 4 (got $rc_missing)"
[[ "$rc_neither" -eq 2 ]] || fail "missing input/url must exit 2 (got $rc_neither)"
[[ "$rc_both" -eq 2 ]] || fail "input and url together must exit 2 (got $rc_both)"

echo "test_inventory_cli OK"
