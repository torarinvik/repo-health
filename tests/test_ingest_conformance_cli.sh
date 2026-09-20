#!/usr/bin/env bash
# tests/test_ingest_conformance_cli.sh — RP-03 product-path ingestion replay.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-ingest-conformance"

fail() { echo "[ingest] FAIL: $1" >&2; exit 1; }

echo "[ingest] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T-root" "$T-root-2" "$T-root-overlap" "$T-root-bad" "$T-root-bad2" "$T-root-bad3" "$T-root-bad4" "$T-root-bad5" "$T-root-future" "$T-root-empty-pages" "$T-root-observed" "$T-root-unauthorized" "$T-root-unsupported" "$T-root-unavailable" "$T-root-undeclared" "$T-root-recovered" "$T-root-pending" "$T-input.json" "$T-out.json" "$T-out-2.json" "$T-bad.json" "$T-bad-status.json" "$T-x"
mkdir -p "$T"
python3 - "$T-input.json" <<'PY'
import json, sys
event = lambda ident, state: {"id": ident, "line": json.dumps({"id": ident, "state": state, "occurred_at": 999 if ident == "issue:1" else 1001, "observed_at": 1000 if ident == "issue:1" else 1002}, separators=(",", ":"))}
d = {
    "schema": "rh-ingest-input/1", "source": "github", "capability": "issues",
    "owner": "worker-a", "lease_now": 1000, "lease_ttl": 100, "collection_start": 1000,
    "collection_complete": False,
    "pages": [
        {"page": 1, "status": "complete", "commit": False, "events": [event("issue:1", "open")]},
        {"page": 1, "status": "complete", "commit": True, "events": [event("issue:1", "open"), event("issue:2", "closed")]},
        {"page": 2, "status": "empty", "commit": True, "events": []},
        {"page": 3, "status": "failed", "failure_kind": "rate_limit", "replaces_page": 2, "commit": True, "events": []},
        {"page": 4, "status": "partial", "commit": True, "events": [event("issue:4", "open")]},
        {"page": 5, "status": "complete", "commit": True, "token": 999, "events": [event("issue:5", "open")]},
        {"page": 6, "status": "failed", "failure_kind": "authorization", "commit": True, "events": []},
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
assert d["pages"][3]["replaces_page"] == 2 and d["pages"][3]["status"] == "failed", d
assert d["watermark"] == {"collection_start": 1000, "published_after_events": True, "backdated_events": 1, "updates_after_start": 1, "reconciliation_required": True}, d
assert d["attempts"] == {"pages": 7, "successful_acquisition_pages": 2}, d
c = d["conformance"]
assert c["appended"] == 2 and c["duplicates_absorbed"] == 1, c
assert c["committed_pages"] == 2 and c["successful_empty_pages"] == 1, c
assert c["failed_pages"] == 2 and c["partial_pages"] == 1, c
assert c["crash_before_cursor_replays"] == 1 and c["stale_token_rejected"] == 1, c
assert c["failure_kinds"] == {"rate_limit": 1, "authorization": 1, "unsupported": 0, "transient": 0}, c
assert d["conformance"]["stale_replacements"] == 1, d
assert d["conformance"]["pending_commit_page"] is None, d
assert d["coverage"] == {"state":"partial", "collection_complete":False, "refresh_last_success":False, "persisted":True}, d
assert d["pages"][0]["cursor_advanced"] is False, d
assert d["pages"][2]["status"] == "empty" and d["pages"][2]["cursor_advanced"] is True, d
assert "late or backdated events require reconciliation" in d["note"], d
print("[ingest] crash/replay, empty-vs-failure, and fencing semantics OK")
PY
[[ -f "$T-root/sources/github/cursors/issues.cursor" ]] || fail "cursor not stored in cursor namespace"
[[ "$(cat "$T-root/sources/github/cursors/issues.cursor" | head -n 1)" == "2" ]] || fail "cursor page mismatch"
[[ "$(cat "$T-root/sources/github/coverage/issues.interval")" == "1000 1000 partial" ]] || fail "mixed acquisition coverage interval not retained"

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
assert d["coverage"] == {"state":"partial", "collection_complete":False, "refresh_last_success":False, "persisted":True}, d
print("[ingest] replay result remains semantically stable")
PY
[[ "$(cat "$T-root-2/sources/github/coverage/issues.interval")" == "1000 2000 partial" ]] || fail "coverage interval does not retain acquisition bounds"

echo "[ingest] overlapping intervals keep each observation and absorb duplicate events"
cat > "$T/overlap-first.json" <<'JSON'
{"schema":"rh-ingest-input/1","source":"github","capability":"issues","owner":"worker-a","lease_now":200,"lease_ttl":100,"collection_start":100,"collection_complete":true,"pages":[{"page":1,"status":"complete","commit":true,"events":[{"id":"issue:shared","line":"{\"id\":\"issue:shared\",\"state\":\"open\"}"}]}]}
JSON
"$ROOT/build/rh_cli" ingest --root "$T-root-overlap" --input "$T/overlap-first.json" --out "$T/overlap-first.out" >/dev/null || fail "first overlapping ingest"
cat > "$T/overlap-second.json" <<'JSON'
{"schema":"rh-ingest-input/1","source":"github","capability":"issues","owner":"worker-a","lease_now":250,"lease_ttl":100,"collection_start":150,"collection_complete":true,"pages":[{"page":1,"status":"complete","commit":true,"events":[{"id":"issue:shared","line":"{\"id\":\"issue:shared\",\"state\":\"open\"}"}]},{"page":2,"status":"complete","commit":true,"events":[{"id":"issue:new","line":"{\"id\":\"issue:new\",\"state\":\"open\"}"}]}]}
JSON
"$ROOT/build/rh_cli" ingest --root "$T-root-overlap" --input "$T/overlap-second.json" --out "$T/overlap-second.out" >/dev/null || fail "overlapping ingest"
python3 - "$T/overlap-second.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["cursor"] == {"page":2, "event_count":2} and d["event_store_count"] == 2, d
assert d["conformance"]["appended"] == 1 and d["conformance"]["duplicates_absorbed"] == 1, d
assert d["coverage"] == {"state":"observed", "collection_complete":True, "refresh_last_success":True, "persisted":True}, d
print("[ingest] overlapping event identity is idempotent")
PY
[[ "$(cat "$T-root-overlap/sources/github/coverage/issues.interval")" == $'100 200 observed\n150 250 observed' ]] || fail "overlapping coverage intervals were not both retained"

echo "[ingest] per-capability coverage retains clean and typed failure states"
for state in observed unauthorized unsupported unavailable; do
  case "$state" in
    observed)
      page='{"page":1,"status":"complete","commit":true,"events":[{"id":"issue:ok","line":"{\"id\":\"issue:ok\"}"}]}'
      complete=true
      ;;
    unauthorized)
      page='{"page":1,"status":"failed","failure_kind":"authorization","commit":true,"events":[]}'
      complete=false
      ;;
    unsupported)
      page='{"page":1,"status":"failed","failure_kind":"unsupported","commit":true,"events":[]}'
      complete=false
      ;;
    unavailable)
      page='{"page":1,"status":"failed","failure_kind":"transient","commit":true,"events":[]}'
      complete=false
      ;;
  esac
  printf '{"schema":"rh-ingest-input/1","source":"github","capability":"issues","owner":"worker-a","lease_now":400,"lease_ttl":100,"collection_start":300,"collection_complete":%s,"pages":[%s]}\n' "$complete" "$page" > "$T/$state.json"
  "$ROOT/build/rh_cli" ingest --root "$T-root-$state" --input "$T/$state.json" --out "$T/$state.out" >/dev/null || fail "$state coverage ingest"
  python3 - "$T/$state.out" "$state" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["coverage"] == {"state":sys.argv[2], "collection_complete":sys.argv[2] == "observed", "refresh_last_success":sys.argv[2] == "observed", "persisted":True}, d
print("[ingest]", sys.argv[2], "coverage state OK")
PY
  [[ "$(cat "$T-root-$state/sources/github/coverage/issues.interval")" == "300 400 $state" ]] || fail "$state coverage interval not retained"
done

echo "[ingest] page success without collection completeness remains partial"
cat > "$T/undeclared.json" <<'JSON'
{"schema":"rh-ingest-input/1","source":"github","capability":"issues","owner":"worker-a","lease_now":400,"lease_ttl":100,"collection_start":300,"pages":[{"page":1,"status":"complete","commit":true,"events":[{"id":"issue:unknown-end","line":"{\"id\":\"issue:unknown-end\"}"}]}]}
JSON
"$ROOT/build/rh_cli" ingest --root "$T-root-undeclared" --input "$T/undeclared.json" --out "$T/undeclared.out" >/dev/null || fail "undeclared coverage ingest"
python3 - "$T/undeclared.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["coverage"] == {"state":"partial", "collection_complete":False, "refresh_last_success":False, "persisted":True}, d
print("[ingest] undeclared pagination end stays partial")
PY
[[ "$(cat "$T-root-undeclared/sources/github/coverage/issues.interval")" == "300 400 partial" ]] || fail "undeclared coverage interval not retained"

echo "[ingest] a retried crash clears its pending cursor state"
cat > "$T/recovered.json" <<'JSON'
{"schema":"rh-ingest-input/1","source":"github","capability":"issues","owner":"worker-a","lease_now":400,"lease_ttl":100,"collection_start":300,"collection_complete":true,"pages":[{"page":1,"status":"complete","commit":false,"events":[{"id":"issue:crash","line":"{\"id\":\"issue:crash\"}"}]},{"page":1,"status":"complete","commit":true,"events":[{"id":"issue:crash","line":"{\"id\":\"issue:crash\"}"}]}]}
JSON
"$ROOT/build/rh_cli" ingest --root "$T-root-recovered" --input "$T/recovered.json" --out "$T/recovered.out" >/dev/null || fail "recovered crash ingest"
python3 - "$T/recovered.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["conformance"]["pending_commit_page"] is None, d
assert d["coverage"] == {"state":"observed", "collection_complete":True, "refresh_last_success":True, "persisted":True}, d
assert d["cursor"] == {"page":1, "event_count":1} and d["event_store_count"] == 1, d
print("[ingest] recovered page publishes observed coverage")
PY
[[ "$(cat "$T-root-recovered/sources/github/coverage/issues.interval")" == "300 400 observed" ]] || fail "recovered crash coverage is not observed"

echo "[ingest] an unreplayed crash stays partial and names the pending page"
cat > "$T/pending.json" <<'JSON'
{"schema":"rh-ingest-input/1","source":"github","capability":"issues","owner":"worker-a","lease_now":400,"lease_ttl":100,"collection_start":300,"collection_complete":false,"pages":[{"page":1,"status":"complete","commit":false,"events":[{"id":"issue:crash","line":"{\"id\":\"issue:crash\"}"}]}]}
JSON
"$ROOT/build/rh_cli" ingest --root "$T-root-pending" --input "$T/pending.json" --out "$T/pending.out" >/dev/null || fail "pending crash ingest"
python3 - "$T/pending.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["conformance"]["pending_commit_page"] == 1, d
assert d["coverage"] == {"state":"partial", "collection_complete":False, "refresh_last_success":False, "persisted":True}, d
assert d["cursor"] == {"page":0, "event_count":0} and d["event_store_count"] == 1, d
print("[ingest] incomplete durable page stays partial")
PY
[[ "$(cat "$T-root-pending/sources/github/coverage/issues.interval")" == "300 400 partial" ]] || fail "unreplayed crash coverage is not partial"

echo "[ingest] malformed input fails closed"
set +e
sed 's/"lease_ttl":100/"lease_ttl":0/' "$T-input.json" > "$T-bad.json"
"$ROOT/build/rh_cli" ingest --root "$T-root-bad" --input "$T-bad.json" --out "$T-x" >/dev/null 2>&1; rc_ttl=$?
sed 's/"status":"failed"/"status":"broken"/' "$T-input.json" > "$T-bad-status.json"
"$ROOT/build/rh_cli" ingest --root "$T-root-bad2" --input "$T-bad-status.json" --out "$T-x" >/dev/null 2>&1; rc_status=$?
sed 's/"failure_kind":"rate_limit"/"failure_kind":"unknown"/' "$T-input.json" > "$T-bad-failure.json"
"$ROOT/build/rh_cli" ingest --root "$T-root-bad3" --input "$T-bad-failure.json" --out "$T-x" >/dev/null 2>&1; rc_failure=$?
sed 's/"collection_complete":false/"collection_complete":"yes"/' "$T-input.json" > "$T-bad-complete.json"
"$ROOT/build/rh_cli" ingest --root "$T-root-bad4" --input "$T-bad-complete.json" --out "$T-x" >/dev/null 2>&1; rc_complete=$?
sed 's/"collection_complete":false/"collection_complete":true/' "$T-input.json" > "$T-bad-completeness-claim.json"
"$ROOT/build/rh_cli" ingest --root "$T-root-bad5" --input "$T-bad-completeness-claim.json" --out "$T-x" >/dev/null 2>&1; rc_completeness_claim=$?
python3 - "$T-bad-future.json" "$T-empty-pages.json" <<'PY'
import json, sys
base = {"schema":"rh-ingest-input/1","source":"github","capability":"issues","owner":"worker-a","lease_now":1000,"lease_ttl":100,"collection_start":1000,"pages":[]}
future = dict(base); future["collection_start"] = 1001; future["pages"] = [{"page":1,"status":"empty","commit":True,"events":[]}]
json.dump(future, open(sys.argv[1], "w"))
json.dump(base, open(sys.argv[2], "w"))
PY
"$ROOT/build/rh_cli" ingest --root "$T-root-future" --input "$T-bad-future.json" --out "$T-x" >/dev/null 2>&1; rc_future=$?
"$ROOT/build/rh_cli" ingest --root "$T-root-empty-pages" --input "$T-empty-pages.json" --out "$T-x" >/dev/null 2>&1; rc_empty_pages=$?
set -e
[[ "$rc_ttl" -eq 4 && "$rc_status" -eq 4 && "$rc_failure" -eq 4 && "$rc_complete" -eq 4 && "$rc_completeness_claim" -eq 4 && "$rc_future" -eq 4 && "$rc_empty_pages" -eq 4 ]] || fail "invalid ingest must exit 4 (got $rc_ttl/$rc_status/$rc_failure/$rc_complete/$rc_completeness_claim/$rc_future/$rc_empty_pages)"
[[ ! -e "$T-root-bad2/sources/github/coverage/issues.interval" ]] || fail "malformed attempt published capability coverage"

echo "test_ingest_conformance_cli OK"
