#!/usr/bin/env bash
# M00-08: deterministic independent histories, graphs, and role-event fixtures.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/rh-synthetic.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fail() { echo "[synthetic] FAIL: $1" >&2; exit 1; }

python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/first" || fail "generate first pack"
python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/second" || fail "generate second pack"
cmp "$T/first/expected.json" "$T/second/expected.json" || fail "expected results not deterministic"
cmp "$T/first/graph/input.json" "$T/second/graph/input.json" || fail "graph not deterministic"
cmp "$T/first/graph/chain-input.json" "$T/second/graph/chain-input.json" || fail "chain graph not deterministic"
cmp "$T/first/roles/input.json" "$T/second/roles/input.json" || fail "role events not deterministic"
git -C "$T/first/history/repo" rev-list --all > "$T/first-commits"
git -C "$T/second/history/repo" rev-list --all > "$T/second-commits"
cmp "$T/first-commits" "$T/second-commits" || fail "history commit IDs not deterministic"
python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/single" --history-commits 1 || fail "generate single-commit scenario"
python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/multi" --history-commits 5 || fail "generate multi-commit scenario"
python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/graph-role-variant" --graph-chain-nodes 7 --role-revoked-at 180 || fail "generate graph/role scenario"
if python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/invalid" --history-commits 13 >/dev/null 2>&1; then
  fail "out-of-bound scenario size accepted"
fi
python3 - "$T/single/expected.json" "$T/multi/expected.json" "$T/graph-role-variant/expected.json" <<'PY'
import json, sys
single, multi = (json.load(open(path))["history"] for path in sys.argv[1:3])
assert single == {"commits": 1, "distinct_authors": 1, "active_months": 1}, single
assert multi == {"commits": 5, "distinct_authors": 2, "active_months": 5}, multi
variant = json.load(open(sys.argv[3]))
assert variant["graph_chain"] == {
    "nodes": 7, "edges": 6, "max_out_degree": 1, "max_in_degree": 1, "max_in_node": 1
}, variant
assert variant["roles"]["revoked_at"] == 180, variant
assert variant["roles"]["revocation_boundary"] == ["maintainer", "unknown"], variant
print("[synthetic] parameterized history expectations OK")
PY

bash "$ROOT/tools/build.sh" >/dev/null
CLI="$ROOT/build/rh_cli"
"$CLI" scan --repo "$T/first/history/repo" --out "$T/history-report" --window-days 36500 >/dev/null || fail "scan generated history"
"$CLI" snapshot --input "$T/first/graph/input.json" --out "$T/graph-result.json" >/dev/null || fail "snapshot generated graph"
"$CLI" index --input "$T/first/graph/input.json" --out "$T/graph-index.json" >/dev/null || fail "index generated graph"
"$CLI" roles --input "$T/first/roles/input.json" --out "$T/roles-result.json" >/dev/null || fail "analyze generated role events"
"$CLI" snapshot --input "$T/first/graph/chain-input.json" --out "$T/chain-result.json" >/dev/null || fail "snapshot generated chain graph"
"$CLI" index --input "$T/first/graph/chain-input.json" --out "$T/chain-index.json" >/dev/null || fail "index generated chain graph"
"$CLI" roles --input "$T/graph-role-variant/roles/input.json" --out "$T/variant-roles-result.json" >/dev/null || fail "analyze parameterized role scenario"
"$CLI" scan --repo "$T/single/history/repo" --out "$T/single-history-report" --window-days 36500 >/dev/null || fail "scan single-commit history"
"$CLI" scan --repo "$T/multi/history/repo" --out "$T/multi-history-report" --window-days 36500 >/dev/null || fail "scan multi-commit history"

python3 - "$T/first/expected.json" "$T/history-report/report.json" "$T/graph-result.json" "$T/graph-index.json" "$T/roles-result.json" "$T/single/expected.json" "$T/single-history-report/report.json" "$T/multi/expected.json" "$T/multi-history-report/report.json" "$T/chain-result.json" "$T/chain-index.json" "$T/variant-roles-result.json" <<'PY'
import json, sys
expected = json.load(open(sys.argv[1]))
report = json.load(open(sys.argv[2]))
metrics = {metric["key"]: metric for metric in report["metrics"]}
assert metrics["history.commit_count"]["value"] == expected["history"]["commits"], metrics
assert metrics["contributors.raw_identity_count"]["value"] == expected["history"]["distinct_authors"], metrics
assert metrics["activity.active_months"]["value"] == expected["history"]["active_months"], metrics

graph = json.load(open(sys.argv[3]))
assert graph["row_counts"] == {"nodes": expected["graph"]["nodes"], "edges": expected["graph"]["edges"]}, graph
index = json.load(open(sys.argv[4]))
assert index["degree_summary"] == {
    "max_out": expected["graph"]["max_out_degree"],
    "max_out_node": 0,
    "max_in": expected["graph"]["max_in_degree"],
    "max_in_node": expected["graph"]["max_in_node"],
}, index

roles = json.load(open(sys.argv[5]))
assert roles["declaration_count"] == expected["roles"]["declarations"], roles
assert roles["role_tally"]["owner"] == expected["roles"]["owners"], roles
assert roles["role_tally"]["member"] == expected["roles"]["members"], roles
assert roles["role_tally"]["maintainer"] == expected["roles"]["maintainers"], roles
assert roles["action_events_by_actor_type"]["release"]["human"] == expected["roles"]["release_events"], roles
assert roles["action_events_by_actor_type"]["review"]["human"] == expected["roles"]["review_events"], roles
assert [query["declared_role"] for query in roles["queries"][:2]] == expected["roles"]["effective_boundary"], roles
assert [query["declared_role"] for query in roles["queries"][2:]] == expected["roles"]["revocation_boundary"], roles
chain = json.load(open(sys.argv[10]))
chain_index = json.load(open(sys.argv[11]))
chain_expected = expected["graph_chain"]
assert chain["row_counts"] == {"nodes": chain_expected["nodes"], "edges": chain_expected["edges"]}, chain
assert chain_index["degree_summary"] == {
    "max_out": chain_expected["max_out_degree"],
    "max_out_node": 0,
    "max_in": chain_expected["max_in_degree"],
    "max_in_node": chain_expected["max_in_node"],
}, chain_index
variant_roles = json.load(open(sys.argv[12]))
assert [query["declared_role"] for query in variant_roles["queries"][2:]] == expected["roles"]["revocation_boundary"], variant_roles
for expected_path, report_path in ((sys.argv[6], sys.argv[7]), (sys.argv[8], sys.argv[9])):
    history_expected = json.load(open(expected_path))["history"]
    history_report = json.load(open(report_path))
    history_metrics = {metric["key"]: metric for metric in history_report["metrics"]}
    assert history_metrics["history.commit_count"]["value"] == history_expected["commits"], history_metrics
    assert history_metrics["contributors.raw_identity_count"]["value"] == history_expected["distinct_authors"], history_metrics
    assert history_metrics["activity.active_months"]["value"] == history_expected["active_months"], history_metrics
print("[synthetic] history, graph, role events match independent expectations")
PY

echo "test_synthetic_fixtures OK"
