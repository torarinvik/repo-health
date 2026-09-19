#!/usr/bin/env bash
# tests/test_properties.sh — property layer: exact bounds and monotonicity
# invariants over many inputs, reversible identity, graph subset/monotone
# reachability. Complements the oracle/unit suites; never replaces them.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[properties] FAIL: $1" >&2; exit 1; }

echo "[properties] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_properties" ]] || fail "test_properties not built"

echo "[properties] bounds, reorder independence, monotonicity, reversal"
out="$("$ROOT/build/test_properties")" || fail "test_properties: $out"
[[ "$out" == *"PROPERTIES OK"* ]] || fail "test_properties: $out"
echo "$out"

echo "[properties] each property category is present"
for prop in bounds hhi-reorder conc-reorder-equal conc-monotone-threshold \
            empty-not-applicable unknown-status-must-reject-value \
            zero-denominator-rejects identity-revoke-reverses depth-limit-monotone \
            public-subset-of-private; do
  grep -q "$prop" "$ROOT/src/test_properties.elisa" || fail "missing property: $prop"
done
echo "[properties] categories OK"

echo "test_properties OK"
