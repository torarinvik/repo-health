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
python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/max-history" --history-commits 12 || fail "generate maximum history scenario"
python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/graph-role-variant" --graph-chain-nodes 7 --role-revoked-at 180 || fail "generate graph/role scenario"
python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/min-graph-role" --graph-chain-nodes 2 --role-revoked-at 91 || fail "generate minimum graph/role scenario"
python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/max-graph-role" --graph-chain-nodes 32 --role-revoked-at 1000 || fail "generate maximum graph/role scenario"
if python3 "$ROOT/tools/generate_synthetic_fixtures.py" --out "$T/invalid" --history-commits 13 >/dev/null 2>&1; then
  fail "out-of-bound scenario size accepted"
fi
python3 - "$T/single/expected.json" "$T/multi/expected.json" "$T/max-history/expected.json" "$T/graph-role-variant/expected.json" "$T/min-graph-role/expected.json" "$T/max-graph-role/expected.json" <<'PY'
import json, sys
single, multi = (json.load(open(path))["history"] for path in sys.argv[1:3])
assert single == {"commits": 1, "distinct_authors": 1, "active_months": 1}, single
assert multi == {"commits": 5, "distinct_authors": 2, "active_months": 5}, multi
maximum = json.load(open(sys.argv[3]))["history"]
assert maximum == {"commits": 12, "distinct_authors": 2, "active_months": 12}, maximum
variant = json.load(open(sys.argv[4]))
assert variant["graph_chain"] == {
    "nodes": 7, "edges": 6, "max_out_degree": 1, "max_in_degree": 1, "max_in_node": 1
}, variant
assert variant["roles"]["revoked_at"] == 180, variant
assert variant["roles"]["revocation_boundary"] == ["maintainer", "unknown"], variant
minimum, maximum = (json.load(open(path)) for path in sys.argv[5:7])
assert minimum["graph_chain"]["nodes"] == 2 and minimum["graph_chain"]["edges"] == 1, minimum
assert minimum["roles"]["revoked_at"] == 91, minimum
assert minimum["roles"]["revocation_boundary"] == ["maintainer", "unknown"], minimum
assert maximum["graph_chain"]["nodes"] == 32 and maximum["graph_chain"]["edges"] == 31, maximum
assert maximum["roles"]["revoked_at"] == 1000, maximum
assert maximum["roles"]["revocation_boundary"] == ["maintainer", "unknown"], maximum
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
"$CLI" scan --repo "$T/max-history/history/repo" --out "$T/max-history-report" --window-days 36500 >/dev/null || fail "scan maximum history"
"$CLI" snapshot --input "$T/min-graph-role/graph/chain-input.json" --out "$T/min-chain-result.json" >/dev/null || fail "snapshot minimum chain"
"$CLI" index --input "$T/min-graph-role/graph/chain-input.json" --out "$T/min-chain-index.json" >/dev/null || fail "index minimum chain"
"$CLI" snapshot --input "$T/max-graph-role/graph/chain-input.json" --out "$T/max-chain-result.json" >/dev/null || fail "snapshot maximum chain"
"$CLI" index --input "$T/max-graph-role/graph/chain-input.json" --out "$T/max-chain-index.json" >/dev/null || fail "index maximum chain"
"$CLI" roles --input "$T/min-graph-role/roles/input.json" --out "$T/min-roles-result.json" >/dev/null || fail "analyze minimum revocation boundary"
"$CLI" roles --input "$T/max-graph-role/roles/input.json" --out "$T/max-roles-result.json" >/dev/null || fail "analyze maximum revocation boundary"

python3 - "$T/first/expected.json" "$T/history-report/report.json" "$T/graph-result.json" "$T/graph-index.json" "$T/roles-result.json" "$T/single/expected.json" "$T/single-history-report/report.json" "$T/multi/expected.json" "$T/multi-history-report/report.json" "$T/chain-result.json" "$T/chain-index.json" "$T/variant-roles-result.json" "$T/max-history/expected.json" "$T/max-history-report/report.json" "$T/min-graph-role/expected.json" "$T/min-chain-result.json" "$T/min-chain-index.json" "$T/min-roles-result.json" "$T/max-graph-role/expected.json" "$T/max-chain-result.json" "$T/max-chain-index.json" "$T/max-roles-result.json" <<'PY'
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
maximum_history = json.load(open(sys.argv[13]))["history"]
maximum_history_report = json.load(open(sys.argv[14]))
maximum_history_metrics = {metric["key"]: metric for metric in maximum_history_report["metrics"]}
assert maximum_history_metrics["history.commit_count"]["value"] == maximum_history["commits"], maximum_history_metrics
assert maximum_history_metrics["contributors.raw_identity_count"]["value"] == maximum_history["distinct_authors"], maximum_history_metrics
assert maximum_history_metrics["activity.active_months"]["value"] == maximum_history["active_months"], maximum_history_metrics
for expected_path, graph_path, index_path, roles_path in (
    (sys.argv[15], sys.argv[16], sys.argv[17], sys.argv[18]),
    (sys.argv[19], sys.argv[20], sys.argv[21], sys.argv[22]),
):
    boundary = json.load(open(expected_path))
    chain_result = json.load(open(graph_path))
    chain_index = json.load(open(index_path))
    assert chain_result["row_counts"] == {"nodes": boundary["graph_chain"]["nodes"], "edges": boundary["graph_chain"]["edges"]}, chain_result
    assert chain_index["degree_summary"]["max_in_node"] == boundary["graph_chain"]["max_in_node"], chain_index
    boundary_roles = json.load(open(roles_path))
    assert [query["declared_role"] for query in boundary_roles["queries"][2:]] == boundary["roles"]["revocation_boundary"], boundary_roles
print("[synthetic] history, graph, role events match independent expectations")
PY

echo "test_synthetic_fixtures OK"
