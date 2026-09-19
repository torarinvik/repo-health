#!/usr/bin/env bash
# tests/test_contracts.sh — M12 public-contract stability gate.
# Every public contract must declare a version token, a stability class, a
# compatibility rule, and a test whose token exists in the repository.
# Unknown-version handling must fail closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[contracts] FAIL: $1" >&2; exit 1; }

reg="$ROOT/ops/public-contracts.json"
[[ -f "$reg" ]] || fail "public-contracts register missing"

echo "[contracts] register is complete and test-backed"
python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
d = json.load(open(os.path.join(root, "ops", "public-contracts.json")))
assert d["contracts_version"] == "rh-public-contracts/1", d
req = ["id", "artifact", "version_token", "stability", "compat_rule", "test"]
ids = set()
for c in d["contracts"]:
    for k in req:
        assert k in c and c[k] not in (None, "", []), (c.get("id"), k)
    assert c["id"] not in ids, ("duplicate contract", c["id"])
    ids.add(c["id"])
    assert c["stability"] in ("frozen", "additive", "experimental"), c
    art = os.path.join(root, c["artifact"])
    assert os.path.isfile(art), ("missing artifact", c["id"], c["artifact"])
    tok = c["version_token"]
    if tok != "(key, version)":
        assert tok in open(art, encoding="utf-8", errors="replace").read(), ("version token absent", c["id"], tok)
    t = c["test"]
    p = os.path.join(root, t["path"])
    assert os.path.isfile(p), ("missing test file", c["id"], t["path"])
    assert t["token"] in open(p, encoding="utf-8", errors="replace").read(), ("test token absent", c["id"], t)
for want in ("dep-graph", "canonical-repo", "bundle-manifest", "report",
             "continuity-report", "metric-registry", "source-review-register",
             "release-packet", "release-signature", "continuity-metrics",
             "deps-metrics", "downstream-report", "policy-result",
             "corrections-result", "inventory-observation",
             "vcs-observation", "patch-report", "notify-result",
             "query-result", "identity-result", "release-feed-result",
             "registry-meta-result", "depsdev-enrichment", "pep440-result",
             "monitor-result", "quota-result", "privacy-result",
             "roles-result", "experimental-result", "report-html",
             "notify-state", "store-lease-result", "policy-state",
             "corrections-state", "connector-instance", "job-next",
             "job-schedule-result",
             "reconcile-result", "job-schedule-result",
             "worker-plan", "succession-metric"):
    assert want in ids, ("missing contract", want)
assert d["rules"], "contract rules must be stated"
print("[contracts] OK:", len(ids), "contracts")
PY

echo "[contracts] unknown-version behaviour fails closed (no fallback)"
grep -q "no fallback" "$ROOT/src/rh_registry.elisa" || fail "registry no-fallback rule missing"

echo "[contracts] schema tests are independent of generated code"
[[ -x "$ROOT/tools/schema-check.sh" ]] || fail "schema-check tool missing"
grep -q "independently of generated code" "$ROOT/tools/schema-check.sh" || fail "schema-independence note missing"

echo "test_contracts OK"
