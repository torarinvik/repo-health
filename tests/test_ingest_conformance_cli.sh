#!/usr/bin/env bash
# tests/test_ingest_conformance_cli.sh — RP-03 product-path ingestion replay.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-ingest-conformance"

fail() { echo "[ingest] FAIL: $1" >&2; exit 1; }

echo "[ingest] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T-root" "$T-root-2" "$T-root-bad" "$T-root-bad2" "$T-input.json" "$T-out.json" "$T-out-2.json" "$T-bad.json" "$T-bad-status.json" "$T-x"
python3 - "$T-input.json" <<'PY'
import json, sys
event = lambda ident, state: {"id": ident, "line": json.dumps({"id": ident, "state": state, "occurred_at": 999 if ident == "issue:1" else 1001, "observed_at": 1000 if ident == "issue:1" else 1002}, separators=(",", ":"))}
d = {
    "schema": "rh-ingest-input/1", "source": "github", "capability": "issues",
    "owner": "worker-a", "lease_now": 1000, "lease_ttl": 100, "collection_start": 1000,
    "pages": [
        {"page": 1, "status": "complete", "commit": False, "events": [event("issue:1", "open")]},
        {"page": 1, "status": "complete", "commit": True, "events": [event("issue:1", "open"), event("issue:2", "closed")]},
        {"page": 2, "status": "empty", "commit": True, "events": []},
        {"page": 3, "status": "failed", "commit": True, "events": []},
        {"page": 4, "status": "partial", "commit": True, "events": [event("issue:4", "open")]},
        {"page": 5, "status": "complete", "commit": True, "token": 999, "events": [event("issue:5", "open")]},
    ],
}
json.dump(d, open(sys.argv[1], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" ingest --root "$T-root" --input "$T-input.json" --out "$T-out.json" >/dev/null || fail "ingest run"
python3 - "$T-out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-ingest-result/1", d
assert d["cursor"] == {"page": 2, "event_count": 2}, d
assert d["event_store_count"] == 2, d
assert d["watermark"] == {"collection_start": 1000, "published_after_events": True, "backdated_events": 1, "updates_after_start": 1, "reconciliation_required": True}, d
assert d["attempts"] == {"pages": 6, "successful_acquisition_pages": 2}, d
c = d["conformance"]
assert c["appended"] == 2 and c["duplicates_absorbed"] == 1, c
assert c["committed_pages"] == 2 and c["successful_empty_pages"] == 1, c
assert c["failed_pages"] == 1 and c["partial_pages"] == 1, c
assert c["crash_before_cursor_replays"] == 1 and c["stale_token_rejected"] == 1, c
assert d["pages"][0]["cursor_advanced"] is False, d
assert d["pages"][2]["status"] == "empty" and d["pages"][2]["cursor_advanced"] is True, d
assert "late or backdated events require reconciliation" in d["note"], d
print("[ingest] crash/replay, empty-vs-failure, and fencing semantics OK")
PY
[[ -f "$T-root/sources/github/cursors/issues.cursor" ]] || fail "cursor not stored in cursor namespace"
[[ "$(cat "$T-root/sources/github/cursors/issues.cursor" | head -n 1)" == "2" ]] || fail "cursor page mismatch"

echo "[ingest] deterministic rerun with a fresh store"
python3 - "$T-input.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["lease_now"] = 2000
json.dump(d, open(sys.argv[1], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" ingest --root "$T-root-2" --input "$T-input.json" --out "$T-out-2.json" >/dev/null || fail "second ingest run"
cmp -s "$T-out.json" "$T-out-2.json" || fail "semantic replay output is not deterministic"
python3 - "$T-out-2.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["cursor"] == {"page": 2, "event_count": 2}, d
assert d["conformance"]["duplicates_absorbed"] == 1, d
print("[ingest] replay result remains semantically stable")
PY

echo "[ingest] malformed input fails closed"
set +e
sed 's/"lease_ttl":100/"lease_ttl":0/' "$T-input.json" > "$T-bad.json"
"$ROOT/build/rh_cli" ingest --root "$T-root-bad" --input "$T-bad.json" --out "$T-x" >/dev/null 2>&1; rc_ttl=$?
sed 's/"status":"failed"/"status":"broken"/' "$T-input.json" > "$T-bad-status.json"
"$ROOT/build/rh_cli" ingest --root "$T-root-bad2" --input "$T-bad-status.json" --out "$T-x" >/dev/null 2>&1; rc_status=$?
set -e
[[ "$rc_ttl" -eq 4 && "$rc_status" -eq 4 ]] || fail "invalid ingest must exit 4 (got $rc_ttl/$rc_status)"

echo "test_ingest_conformance_cli OK"
