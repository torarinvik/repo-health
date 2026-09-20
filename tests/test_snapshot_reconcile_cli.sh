#!/usr/bin/env bash
# Scope-safe snapshot reconciliation: only complete/successful-empty snapshots
# clear unseen current-state IDs, and only inside their exact declared scope.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-snapshot-reconcile"

fail() { echo "[snapshot-reconcile] FAIL: $1" >&2; exit 1; }

echo "[snapshot-reconcile] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
run() { "$ROOT/build/rh_cli" snapshot-reconcile --input "$1" --out "$2" >/dev/null; }

echo "[snapshot-reconcile] complete snapshot reconciles exact scope"
cat > "$T/complete.json" <<'JSON'
{"schema":"rh-snapshot-reconcile-input/1","source":"forge-a","capability":"issues","scope":"project-17","captured_at":1700000000,"acquisition":"complete","prior":["old-a","shared"],"observed":["shared","new-b"]}
JSON
run "$T/complete.json" "$T/complete.out" || fail "complete snapshot"
python3 - "$T/complete.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-snapshot-reconcile-result/1", d
assert d["scope"] == {"source":"forge-a", "capability":"issues", "scope":"project-17"}, d
assert d["captured_at"] == 1700000000 and d["acquisition"] == "complete", d
assert d["successful_acquisition"] is True and d["refresh_last_success"] is True and d["clear_unseen_in_scope"] is True, d
assert d["counts"] == {"prior":2, "observed":2, "absent":1, "retained_unconfirmed":0, "current":3}, d
assert d["records"] == [
    {"native_id":"old-a", "state":"absent"},
    {"native_id":"shared", "state":"present"},
    {"native_id":"new-b", "state":"present"},
], d
print("[snapshot-reconcile] complete scope OK")
PY
run "$T/complete.json" "$T/complete-again.out" || fail "repeat complete snapshot"
cmp -s "$T/complete.out" "$T/complete-again.out" || fail "snapshot replay not deterministic"

echo "[snapshot-reconcile] successful empty snapshot clears covered scope"
cat > "$T/empty.json" <<'JSON'
{"schema":"rh-snapshot-reconcile-input/1","source":"forge-a","capability":"issues","scope":"project-18","captured_at":1700000001,"acquisition":"empty","prior":["old-a","old-b"],"observed":[]}
JSON
run "$T/empty.json" "$T/empty.out" || fail "empty snapshot"
python3 - "$T/empty.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["scope"]["scope"] == "project-18", d
assert d["successful_acquisition"] and d["refresh_last_success"] and d["clear_unseen_in_scope"], d
assert d["counts"]["absent"] == 2 and d["counts"]["retained_unconfirmed"] == 0, d
assert all(x["state"] == "absent" for x in d["records"]), d
print("[snapshot-reconcile] successful empty OK")
PY

echo "[snapshot-reconcile] partial, failed, and unsupported preserve unseen IDs"
for acquisition in partial failed unsupported; do
  observed='["new"]'
  [[ "$acquisition" == partial ]] || observed='[]'
  printf '{"schema":"rh-snapshot-reconcile-input/1","source":"forge-a","capability":"issues","scope":"project-19","captured_at":1700000002,"acquisition":"%s","prior":["old-a","old-b"],"observed":%s}\n' "$acquisition" "$observed" > "$T/$acquisition.json"
  run "$T/$acquisition.json" "$T/$acquisition.out" || fail "$acquisition snapshot"
  python3 - "$T/$acquisition.out" "$acquisition" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
acquisition = sys.argv[2]
assert d["acquisition"] == acquisition, d
assert d["successful_acquisition"] is False and d["refresh_last_success"] is False and d["clear_unseen_in_scope"] is False, d
assert d["counts"]["absent"] == 0 and d["counts"]["retained_unconfirmed"] == 2, d
assert all(x["state"] == "retained_unconfirmed" for x in d["records"][:2]), d
assert d["records"][-1] == {"native_id":"new", "state":"present"} if acquisition == "partial" else len(d["records"]) == 2, d
print(f"[snapshot-reconcile] {acquisition} preserves unseen IDs")
PY
done

echo "[snapshot-reconcile] malformed or ambiguous snapshots fail closed"
set +e
check_bad() {
  printf '%s' "$1" > "$T/bad.json"
  "$ROOT/build/rh_cli" snapshot-reconcile --input "$T/bad.json" --out "$T/bad.out" >/dev/null 2>&1
  echo $?
}
rc_schema=$(check_bad '{"schema":"rh-snapshot-reconcile-input/2"}')
rc_duplicate_prior=$(check_bad '{"schema":"rh-snapshot-reconcile-input/1","source":"s","capability":"c","scope":"x","captured_at":1,"acquisition":"complete","prior":["x","x"],"observed":["y"]}')
rc_duplicate_observed=$(check_bad '{"schema":"rh-snapshot-reconcile-input/1","source":"s","capability":"c","scope":"x","captured_at":1,"acquisition":"complete","prior":[],"observed":["y","y"]}')
rc_bad_complete=$(check_bad '{"schema":"rh-snapshot-reconcile-input/1","source":"s","capability":"c","scope":"x","captured_at":1,"acquisition":"complete","prior":["x"],"observed":[]}')
rc_bad_empty=$(check_bad '{"schema":"rh-snapshot-reconcile-input/1","source":"s","capability":"c","scope":"x","captured_at":1,"acquisition":"empty","prior":["x"],"observed":["x"]}')
rc_bad_failure=$(check_bad '{"schema":"rh-snapshot-reconcile-input/1","source":"s","capability":"c","scope":"x","captured_at":1,"acquisition":"failed","prior":["x"],"observed":["x"]}')
rc_bad_time=$(check_bad '{"schema":"rh-snapshot-reconcile-input/1","source":"s","capability":"c","scope":"x","captured_at":-1,"acquisition":"empty","prior":[],"observed":[]}')
set -e
for rc in "$rc_schema" "$rc_duplicate_prior" "$rc_duplicate_observed" "$rc_bad_complete" "$rc_bad_empty" "$rc_bad_failure" "$rc_bad_time"; do
  [[ "$rc" -eq 4 ]] || fail "malformed snapshot must exit 4 (got $rc)"
done
[[ ! -e "$T/bad.out" ]] || fail "failed reconciliation wrote partial output"

echo "test_snapshot_reconcile_cli OK"
