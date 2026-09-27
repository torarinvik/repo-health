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
cmp "$T/first/roles/input.json" "$T/second/roles/input.json" || fail "role events not deterministic"
git -C "$T/first/history/repo" rev-list --all > "$T/first-commits"
git -C "$T/second/history/repo" rev-list --all > "$T/second-commits"
cmp "$T/first-commits" "$T/second-commits" || fail "history commit IDs not deterministic"

bash "$ROOT/tools/build.sh" >/dev/null
CLI="$ROOT/build/rh_cli"
"$CLI" scan --repo "$T/first/history/repo" --out "$T/history-report" --window-days 36500 >/dev/null || fail "scan generated history"
"$CLI" snapshot --input "$T/first/graph/input.json" --out "$T/graph-result.json" >/dev/null || fail "snapshot generated graph"
"$CLI" roles --input "$T/first/roles/input.json" --out "$T/roles-result.json" >/dev/null || fail "analyze generated role events"

python3 - "$T/first/expected.json" "$T/history-report/report.json" "$T/graph-result.json" "$T/roles-result.json" <<'PY'
import json, sys
expected = json.load(open(sys.argv[1]))
report = json.load(open(sys.argv[2]))
metrics = {metric["key"]: metric for metric in report["metrics"]}
assert metrics["history.commit_count"]["value"] == expected["history"]["commits"], metrics
assert metrics["contributors.raw_identity_count"]["value"] == expected["history"]["distinct_authors"], metrics
assert metrics["activity.active_months"]["value"] == expected["history"]["active_months"], metrics

graph = json.load(open(sys.argv[3]))
assert graph["row_counts"] == {"nodes": expected["graph"]["nodes"], "edges": expected["graph"]["edges"]}, graph

roles = json.load(open(sys.argv[4]))
assert roles["declaration_count"] == expected["roles"]["declarations"], roles
assert roles["role_tally"]["owner"] == expected["roles"]["owners"], roles
assert roles["role_tally"]["member"] == expected["roles"]["members"], roles
assert roles["action_events_by_actor_type"]["release"]["human"] == expected["roles"]["release_events"], roles
assert roles["action_events_by_actor_type"]["review"]["human"] == expected["roles"]["review_events"], roles
print("[synthetic] history, graph, role events match independent expectations")
PY

echo "test_synthetic_fixtures OK"
