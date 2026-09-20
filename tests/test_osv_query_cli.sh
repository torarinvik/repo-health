#!/usr/bin/env bash
# Offline OSV transport integration: fake resolver and curl; no package data leaves the host.
# The fixtures exercise rh-osv-query-input/1 plus single-query and bounded graph-batch contracts.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T="/tmp/rh-osv-query-cli"
fail() { echo "[osv-query] FAIL: $1" >&2; exit 1; }
expect() {
  local want="$1"; shift
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  [[ "$got" == "$want" ]] || fail "expected exit $want, got $got: $*"
}

echo "[osv-query] build and pure contract tests"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_osv_query" ]] || fail "OSV query harness not built"
[[ "$("$ROOT/build/test_osv_query")" == "OSV QUERY OK" ]] || fail "request/response contract"

rm -rf "$T"
mkdir -p "$T/bin" "$T/repo"
cp "$ROOT/fixtures/packages/osv-query-cargo.json" "$T/query.json"
cp "$ROOT/fixtures/packages/cargo-diamond.lock" "$T/repo/Cargo.lock"
cat > "$T/bin/python3" <<'SH'
#!/bin/sh
# Stand in for the bounded DNS resolver; fake curl checks the resulting pin.
printf '93.184.216.34\n'
SH
cat > "$T/bin/curl" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$@" >> "$OSV_QUERY_CAPTURE"
payload=''
body=''
url=''
pin=''
proto=''
redirects=''
content_type=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --resolve) shift; pin="$1" ;;
    --proto) shift; proto="$1" ;;
    --max-redirs) shift; redirects="$1" ;;
    --data-binary) shift; payload="$1" ;;
    -H) shift; case "$1" in 'Content-Type: application/json') content_type="$1" ;; esac ;;
    -o) shift; body="$1" ;;
    https://*) url="$1" ;;
  esac
  shift
done
[ "$url" = "${OSV_QUERY_FAKE_ENDPOINT:-https://api.osv.dev/v1/query}" ] || exit 88
[ "$pin" = 'api.osv.dev:443:93.184.216.34' ] || exit 89
[ "$proto" = '=https' ] || exit 90
[ "$redirects" = '0' ] || exit 91
[ "$content_type" = 'Content-Type: application/json' ] || exit 92
case "$payload" in @*) request_path="$(printf '%s' "$payload" | cut -c2-)"; cat "$request_path" >> "$OSV_QUERY_REQUEST_CAPTURE"; printf '\n' >> "$OSV_QUERY_REQUEST_CAPTURE" ;; *) exit 93 ;; esac
request_body="$(cat "$request_path")"
response="$OSV_QUERY_FAKE_RESPONSE"
http="$OSV_QUERY_FAKE_HTTP"
case "$request_body" in
  *'"page_token":"batch-left-4"'*) response="${OSV_QUERY_FAKE_BATCH_PAGE4_RESPONSE:-$response}" ;;
  *'"page_token":"batch-left-3"'*) response="${OSV_QUERY_FAKE_BATCH_PAGE3_RESPONSE:-$response}" ;;
  *'"page_token":"batch-left-2"'*) response="${OSV_QUERY_FAKE_BATCH_PAGE2_RESPONSE:-$response}" ;;
  *'"page_token":"batch-shared-2"'*) response="${OSV_QUERY_FAKE_BATCH_PAGE2_RESPONSE:-$response}" ;;
  *'"page_token":"page-2"'*) response="${OSV_QUERY_FAKE_PAGE2_RESPONSE:-$response}"; http="${OSV_QUERY_FAKE_PAGE2_HTTP:-$http}" ;;
  *'"page_token":"page-3"'*) response="${OSV_QUERY_FAKE_PAGE3_RESPONSE:-$response}"; http="${OSV_QUERY_FAKE_PAGE3_HTTP:-$http}" ;;
  *'"page_token":"page-4"'*) response="${OSV_QUERY_FAKE_PAGE4_RESPONSE:-$response}"; http="${OSV_QUERY_FAKE_PAGE4_HTTP:-$http}" ;;
esac
cp "$response" "$body"
printf '%s' "$http"
exit 0
SH
chmod +x "$T/bin/python3" "$T/bin/curl"

echo "[osv-query] fixed endpoint, DNS pin, evidence, and deps handoff"
PATH="$T/bin:$PATH" \
OSV_QUERY_FAKE_RESPONSE="$ROOT/fixtures/packages/osv-response.json" \
OSV_QUERY_FAKE_HTTP=200 \
OSV_QUERY_CAPTURE="$T/curl.args" \
OSV_QUERY_REQUEST_CAPTURE="$T/request.sent.json" \
  "$ROOT/build/rh_cli" osv-query --input "$T/query.json" --out "$T/out" >/dev/null
python3 - "$T" <<'PY'
import hashlib, json, pathlib, sys
t = pathlib.Path(sys.argv[1]); out = t / "out"
request = json.load(open(out / "osv-query-request.json"))
assert request == {"package":{"ecosystem":"crates.io","name":"shared"},"version":"1.0.0"}, request
assert json.load(open(t / "request.sent.json")) == request
args = open(t / "curl.args").read().splitlines()
assert "--disable" in args and "--noproxy" in args and "--max-redirs" in args
assert args[args.index("--resolve") + 1] == "api.osv.dev:443:93.184.216.34", args
assert args[args.index("--data-binary") + 1].startswith("@"), args
assert "-L" not in args and not any(x.startswith("Authorization:") for x in args)
result = json.load(open(out / "osv-query-result.json"))
assert result["schema"] == "rh-osv-query-result/1" and result["state"] == "collected", result
assert result["query_kind"] == "package_version", result
assert result["http_status"] == 200 and result["pagination"] == "complete", result
raw = (out / "osv-query-response.raw.json").read_bytes()
assert result["raw_response_sha256"] == hashlib.sha256(raw).hexdigest(), result
assert json.load(open(out / "osv-query-response.json"))["vulns"], "normalized response missing advisories"
assert (out / "osv-query-http-status.txt").read_text() == "200"
assert (out / "osv-query.err").exists()
print("[osv-query] pinned POST evidence OK")
PY

echo "[osv-query] bounded graph batch retains IDs-only positional summaries"
cp "$ROOT/fixtures/packages/cargo-graph.golden.json" "$T/graph.json"
PATH="$T/bin:$PATH" \
OSV_QUERY_FAKE_ENDPOINT=https://api.osv.dev/v1/querybatch \
OSV_QUERY_FAKE_RESPONSE="$ROOT/fixtures/packages/osv-query-batch-response.json" \
OSV_QUERY_FAKE_HTTP=200 \
OSV_QUERY_CAPTURE="$T/batch.args" \
OSV_QUERY_REQUEST_CAPTURE="$T/batch.sent.json" \
  "$ROOT/build/rh_cli" osv-query --graph "$T/graph.json" --out "$T/batch-out" >/dev/null
python3 - "$T" <<'PY'
import hashlib, json, pathlib, sys
t = pathlib.Path(sys.argv[1]); out = t / "batch-out"
request = json.load(open(out / "osv-query-batch-request.json"))
assert len(request["queries"]) == 6, request
assert request["queries"][0] == {"package":{"ecosystem":"crates.io","name":"app"},"version":"0.1.0"}
assert request["queries"][-1] == {"package":{"ecosystem":"crates.io","name":"top"},"version":"0.2.0"}
assert json.load(open(t / "batch.sent.json")) == request
args = open(t / "batch.args").read().splitlines()
assert "https://api.osv.dev/v1/querybatch" in args, args
assert args[args.index("--resolve") + 1] == "api.osv.dev:443:93.184.216.34", args
r = json.load(open(out / "osv-query-batch-result.json"))
assert r["schema"] == "rh-osv-query-batch-result/1" and r["state"] == "partial", r
assert r["response_detail"] == "advisory_ids_only", r
assert r["query_count"] == 6 and r["skipped_node_count"] == 1 and r["omitted_node_count"] == 0, r
assert [(q["query_index"], q["graph_node_index"], q["node_id"]) for q in r["query_nodes"]] == [(0,0,0),(1,1,1),(2,2,2),(3,3,3),(4,4,4),(5,5,5)], r
assert r["advisory_id_count"] == 3 and r["page_token_count"] == 1, r
raw = (out / r["raw_response_file"]).read_bytes()
assert r["raw_response_sha256"] == hashlib.sha256(raw).hexdigest(), r
assert json.loads(raw)["results"][3]["next_page_token"] == "node-four-next"
assert (out / r["http_status_file"]).read_text() == "200"
assert (out / r["stderr_file"]).exists()
assert not (out / "osv-query-response.json").exists(), "IDs-only response must not look matcher-ready"
print("[osv-query] bounded graph batch and IDs-only response evidence OK")
PY

echo "[osv-query] empty graph batch avoids an unnecessary request"
cat > "$T/empty-graph.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"cargo","nodes":[],"edges":[],"unresolved":[],"advisories":[]}
JSON
PATH="$T/bin:$PATH" \
OSV_QUERY_FAKE_ENDPOINT=https://api.osv.dev/v1/querybatch \
OSV_QUERY_FAKE_RESPONSE="$ROOT/fixtures/packages/osv-query-batch-response.json" \
OSV_QUERY_FAKE_HTTP=200 \
OSV_QUERY_CAPTURE="$T/empty-batch.args" \
OSV_QUERY_REQUEST_CAPTURE="$T/empty-batch.sent.json" \
  "$ROOT/build/rh_cli" osv-query --graph "$T/empty-graph.json" --out "$T/empty-batch-out" >/dev/null
python3 - "$T" <<'PY'
import json, pathlib, sys
t = pathlib.Path(sys.argv[1]); out = t / "empty-batch-out"
r = json.load(open(out / "osv-query-batch-result.json"))
assert json.load(open(out / r["request_file"])) == {"queries": []}
assert r["state"] == "empty" and r["query_count"] == 0 and r["query_nodes"] == [], r
assert r["http_status"] is None and r["raw_response_file"] is None and r["raw_response_sha256"] is None, r
assert not (t / "empty-batch.args").exists() and not (out / "osv-query-batch-http-status.txt").exists()
print("[osv-query] empty batch state and no-network path OK")
PY

echo "[osv-query] graph batch follows only queries with page cursors"
cat > "$T/batch-page1.json" <<'JSON'
{"results":[{"vulns":[{"id":"OSV-A"}]},{"vulns":[],"next_page_token":"batch-left-2"},{"vulns":[]},{"vulns":[]},{"vulns":[],"next_page_token":"batch-shared-2"},{"vulns":[]}]}
JSON
cat > "$T/batch-page2.json" <<'JSON'
{"results":[{"vulns":[{"id":"OSV-C"}],"next_page_token":"batch-left-3"},{"vulns":[{"id":"OSV-E"}]}]}
JSON
cat > "$T/batch-page3.json" <<'JSON'
{"results":[{"vulns":[{"id":"OSV-D"}]}]}
JSON
PATH="$T/bin:$PATH" \
OSV_QUERY_FAKE_ENDPOINT=https://api.osv.dev/v1/querybatch \
OSV_QUERY_FAKE_RESPONSE="$T/batch-page1.json" \
OSV_QUERY_FAKE_BATCH_PAGE2_RESPONSE="$T/batch-page2.json" \
OSV_QUERY_FAKE_BATCH_PAGE3_RESPONSE="$T/batch-page3.json" \
OSV_QUERY_FAKE_HTTP=200 OSV_QUERY_CAPTURE="$T/batch-pages.args" \
OSV_QUERY_REQUEST_CAPTURE="$T/batch-pages.sent.jsonl" \
  "$ROOT/build/rh_cli" osv-query --graph "$T/graph.json" --out "$T/batch-pages-out" --continue-pagination >/dev/null
python3 - "$T" <<'PY'
import hashlib, json, pathlib, sys
t = pathlib.Path(sys.argv[1]); out = t / "batch-pages-out"
r = json.load(open(out / "osv-query-batch-result.json"))
assert r["schema"] == "rh-osv-query-batch-result/2", r
assert r["state"] == "partial" and r["pagination"] == "complete", r
assert r["page_count"] == 3 and r["page_limit"] == 4, r
assert r["query_count"] == 6 and r["advisory_id_count"] == 4 and r["page_token_count"] == 3, r
assert [p["query_indexes"] for p in r["page_evidence"]] == [[0,1,2,3,4,5],[1,4],[1]], r
assert [len(json.load(open(out / p["request_file"]))["queries"]) for p in r["page_evidence"]] == [6,2,1]
page2 = json.load(open(out / r["page_evidence"][1]["request_file"]))["queries"]
assert [q["page_token"] for q in page2] == ["batch-left-2", "batch-shared-2"], page2
assert page2[0]["package"]["name"] == "left" and page2[1]["version"] == "2.0.0", page2
page3 = json.load(open(out / r["page_evidence"][2]["request_file"]))["queries"]
assert page3 == [{"package":{"ecosystem":"crates.io","name":"left"},"version":"1.0.0","page_token":"batch-left-3"}], page3
for page in r["page_evidence"]:
    raw = (out / page["raw_response_file"]).read_bytes()
    assert page["raw_response_sha256"] == hashlib.sha256(raw).hexdigest(), page
    assert (out / page["http_status_file"]).read_text() == "200"
sent = [json.loads(line) for line in open(t / "batch-pages.sent.jsonl") if line.strip()]
assert len(sent) == 3, sent
print("[osv-query] per-query pagination and positional evidence OK")
PY

echo "[osv-query] graph batch stops at four rounds and retains remaining work"
cat > "$T/single-graph.json" <<'JSON'
{"schema":"rh-dep-graph/1","ecosystem":"cargo","nodes":[{"id":0,"name":"capped","version":"1.0.0","source":"registry"}],"edges":[],"unresolved":[],"advisories":[]}
JSON
for page in 1 2 3 4; do
  following_page=$((page + 1))
  cat > "$T/batch-cap-page$page.json" <<JSON
{"results":[{"vulns":[],"next_page_token":"batch-left-$following_page"}]}
JSON
done
PATH="$T/bin:$PATH" \
OSV_QUERY_FAKE_ENDPOINT=https://api.osv.dev/v1/querybatch \
OSV_QUERY_FAKE_RESPONSE="$T/batch-cap-page1.json" \
OSV_QUERY_FAKE_BATCH_PAGE2_RESPONSE="$T/batch-cap-page2.json" \
OSV_QUERY_FAKE_BATCH_PAGE3_RESPONSE="$T/batch-cap-page3.json" \
OSV_QUERY_FAKE_BATCH_PAGE4_RESPONSE="$T/batch-cap-page4.json" \
OSV_QUERY_FAKE_HTTP=200 OSV_QUERY_CAPTURE="$T/batch-cap.args" \
OSV_QUERY_REQUEST_CAPTURE="$T/batch-cap.sent.jsonl" \
  "$ROOT/build/rh_cli" osv-query --graph "$T/single-graph.json" --out "$T/batch-cap-out" --continue-pagination >/dev/null
python3 - "$T" <<'PY'
import json, pathlib, sys
t = pathlib.Path(sys.argv[1]); out = t / "batch-cap-out"
r = json.load(open(out / "osv-query-batch-result.json"))
assert r["state"] == "partial" and r["pagination"] == "more_available", r
assert r["page_count"] == r["page_limit"] == 4 and len(r["page_evidence"]) == 4, r
assert r["next_request_file"] == "osv-query-batch-next-request.json", r
assert json.load(open(out / r["next_request_file"]))["queries"][0]["page_token"] == "batch-left-5"
assert len([line for line in open(t / "batch-cap.sent.jsonl") if line.strip()]) == 4
print("[osv-query] four-round cap and retained pending query OK")
PY

echo "[osv-query] full commit-hash query uses the same guarded endpoint"
cp "$ROOT/fixtures/packages/osv-query-commit.json" "$T/commit-query.json"
PATH="$T/bin:$PATH" \
OSV_QUERY_FAKE_RESPONSE="$ROOT/fixtures/packages/osv-response.json" \
OSV_QUERY_FAKE_HTTP=200 \
OSV_QUERY_CAPTURE="$T/commit.args" \
OSV_QUERY_REQUEST_CAPTURE="$T/commit.sent.json" \
  "$ROOT/build/rh_cli" osv-query --input "$T/commit-query.json" --out "$T/commit-out" >/dev/null
python3 - "$T/commit-out" "$ROOT/fixtures/packages/osv-query-commit.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
commit_input = json.load(open(sys.argv[2]))
assert commit_input["schema"] == "rh-osv-query-input/2", commit_input
expected = {"commit": "6879efc2c1596d11a6a6ad296f80063b558d5e0f"}
assert json.load(open(p / "osv-query-request.json")) == expected
assert json.load(open(p / "osv-query-result.json"))["query_kind"] == "commit"
assert json.load(open(pathlib.Path(sys.argv[1]).parent / "commit.sent.json")) == expected
print("[osv-query] commit request and query kind retained")
PY
"$ROOT/build/rh_cli" deps --repo "$T/repo" --out "$T/deps" --osv "$T/out/osv-query-response.json" >/dev/null
python3 - "$T/deps/deps-cargo-graph.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
assert len(g["advisories"]) == 1, g["advisories"]
assert g["advisories"][0]["advisory"] == "CVE-2025-0001", g["advisories"]
print("[osv-query] response feeds offline matcher OK")
PY

echo "[osv-query] pagination and empty-result normalization"
cat > "$T/paginated.json" <<'JSON'
{"vulns":[{"id":"CVE-TEST"}],"next_page_token":"page-2"}
JSON
PATH="$T/bin:$PATH" \
OSV_QUERY_FAKE_RESPONSE="$T/paginated.json" \
OSV_QUERY_FAKE_HTTP=200 OSV_QUERY_CAPTURE="$T/paginated.args" \
OSV_QUERY_REQUEST_CAPTURE="$T/paginated.sent.json" \
  "$ROOT/build/rh_cli" osv-query --input "$T/query.json" --out "$T/paginated-out" >/dev/null
python3 - "$T/paginated-out" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
r = json.load(open(p / "osv-query-result.json"))
body = json.load(open(p / "osv-query-response.json"))
assert r["schema"] == "rh-osv-query-result/1" and r["state"] == "collected", r
assert r["pagination"] == "more_available" and body["next_page_token"] == "page-2", (r, body)
assert body["vulns"][0]["id"] == "CVE-TEST"
PY

echo "[osv-query] bounded continuation collects pages and retains evidence"
cat > "$T/page1.json" <<'JSON'
{"vulns":[{"id":"CVE-PAGE-1"}],"next_page_token":"page-2"}
JSON
cat > "$T/page2.json" <<'JSON'
{"vulns":[{"id":"CVE-PAGE-2"}],"next_page_token":"page-3"}
JSON
cat > "$T/page3.json" <<'JSON'
{"vulns":[{"id":"CVE-PAGE-3"}]}
JSON
PATH="$T/bin:$PATH" \
OSV_QUERY_FAKE_RESPONSE="$T/page1.json" \
OSV_QUERY_FAKE_PAGE2_RESPONSE="$T/page2.json" \
OSV_QUERY_FAKE_PAGE3_RESPONSE="$T/page3.json" \
OSV_QUERY_FAKE_HTTP=200 OSV_QUERY_CAPTURE="$T/pages.args" \
OSV_QUERY_REQUEST_CAPTURE="$T/pages.requests.jsonl" \
  "$ROOT/build/rh_cli" osv-query --input "$T/query.json" --out "$T/pages-out" --continue-pagination >/dev/null
python3 - "$T/pages-out" "$T/pages.args" "$T/pages.requests.jsonl" <<'PY'
import hashlib, json, pathlib, sys
p = pathlib.Path(sys.argv[1])
r = json.load(open(p / "osv-query-result.json"))
merged = json.load(open(p / "osv-query-response.json"))
args = open(sys.argv[2]).read().splitlines()
requests = [json.loads(line) for line in open(sys.argv[3]) if line.strip()]
assert r["schema"] == "rh-osv-query-result/2" and r["state"] == "collected", r
assert r["pagination"] == "complete" and r["page_count"] == 3 and r["page_limit"] == 4, r
assert r["advisory_count"] == 3 and len(r["page_evidence"]) == 3, r
assert [v["id"] for v in merged["vulns"]] == ["CVE-PAGE-1", "CVE-PAGE-2", "CVE-PAGE-3"], merged
assert "next_page_token" not in merged and not (p / "osv-query-next-page-token.txt").exists()
assert requests[1]["page_token"] == "page-2" and requests[2]["page_token"] == "page-3", requests
assert len(requests) == 3 and args.count("--data-binary") == 3, (requests, args)
for i, entry in enumerate(r["page_evidence"], 1):
    raw = (p / entry["raw_response_file"]).read_bytes()
    assert entry["page"] == i and entry["raw_response_sha256"] == hashlib.sha256(raw).hexdigest(), entry
    assert (p / entry["request_file"]).exists() and (p / entry["http_status_file"]).read_text() == "200"
print("[osv-query] three-page collection and evidence OK")
PY

echo "[osv-query] four-page cap remains explicit and never calls page five"
cat > "$T/page3-more.json" <<'JSON'
{"vulns":[{"id":"CVE-PAGE-3"}],"next_page_token":"page-4"}
JSON
cat > "$T/page4-more.json" <<'JSON'
{"vulns":[{"id":"CVE-PAGE-4"}],"next_page_token":"page-5"}
JSON
PATH="$T/bin:$PATH" \
OSV_QUERY_FAKE_RESPONSE="$T/page1.json" \
OSV_QUERY_FAKE_PAGE2_RESPONSE="$T/page2.json" \
OSV_QUERY_FAKE_PAGE3_RESPONSE="$T/page3-more.json" \
OSV_QUERY_FAKE_PAGE4_RESPONSE="$T/page4-more.json" \
OSV_QUERY_FAKE_HTTP=200 OSV_QUERY_CAPTURE="$T/cap.args" \
OSV_QUERY_REQUEST_CAPTURE="$T/cap.requests.jsonl" \
  "$ROOT/build/rh_cli" osv-query --input "$T/query.json" --out "$T/cap-out" --continue-pagination >/dev/null
python3 - "$T/cap-out" "$T/cap.args" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); r = json.load(open(p / "osv-query-result.json"))
assert r["state"] == "partial" and r["pagination"] == "more_available", r
assert r["page_count"] == r["page_limit"] == 4, r
assert (p / r["next_page_token_file"]).read_text() == "page-5"
assert open(sys.argv[2]).read().splitlines().count("--data-binary") == 4
print("[osv-query] pagination cap and continuation token retained")
PY

echo "[osv-query] repeated tokens and later-page transport failures fail closed"
cat > "$T/repeated.json" <<'JSON'
{"vulns":[{"id":"CVE-PAGE-2"}],"next_page_token":"page-2"}
JSON
expect 4 env PATH="$T/bin:$PATH" \
  OSV_QUERY_FAKE_RESPONSE="$T/page1.json" OSV_QUERY_FAKE_PAGE2_RESPONSE="$T/repeated.json" \
  OSV_QUERY_FAKE_HTTP=200 OSV_QUERY_CAPTURE="$T/repeat.args" \
  OSV_QUERY_REQUEST_CAPTURE="$T/repeat.requests.jsonl" \
  "$ROOT/build/rh_cli" osv-query --input "$T/query.json" --out "$T/repeat-out" --continue-pagination
[[ -f "$T/repeat-out/osv-query-page-2-response.raw.json" ]] || fail "repeated-token page raw evidence missing"
[[ ! -f "$T/repeat-out/osv-query-result.json" ]] || fail "repeated token emitted success"
expect 4 env PATH="$T/bin:$PATH" \
  OSV_QUERY_FAKE_RESPONSE="$T/page1.json" OSV_QUERY_FAKE_PAGE2_RESPONSE="$T/page2.json" \
  OSV_QUERY_FAKE_PAGE2_HTTP=503 OSV_QUERY_FAKE_HTTP=200 OSV_QUERY_CAPTURE="$T/page-error.args" \
  OSV_QUERY_REQUEST_CAPTURE="$T/page-error.requests.jsonl" \
  "$ROOT/build/rh_cli" osv-query --input "$T/query.json" --out "$T/page-error-out" --continue-pagination
[[ -f "$T/page-error-out/osv-query-page-2-response.raw.json" ]] || fail "later-page error body not retained"
[[ "$(cat "$T/page-error-out/osv-query-page-2-http-status.txt")" == "503" ]] || fail "later-page HTTP status not retained"
[[ ! -f "$T/page-error-out/osv-query-result.json" ]] || fail "later-page error emitted success"

printf '{}\n' > "$T/empty.json"
PATH="$T/bin:$PATH" \
OSV_QUERY_FAKE_RESPONSE="$T/empty.json" \
OSV_QUERY_FAKE_HTTP=200 OSV_QUERY_CAPTURE="$T/empty.args" \
OSV_QUERY_REQUEST_CAPTURE="$T/empty.sent.json" \
  "$ROOT/build/rh_cli" osv-query --input "$T/query.json" --out "$T/empty-out" >/dev/null
python3 - "$T/empty-out/osv-query-response.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == {"vulns": []}
PY

echo "[osv-query] non-200 and invalid-input cases fail closed"
expect 4 env PATH="$T/bin:$PATH" \
  OSV_QUERY_FAKE_RESPONSE="$ROOT/fixtures/packages/osv-response.json" \
  OSV_QUERY_FAKE_HTTP=503 OSV_QUERY_CAPTURE="$T/error.args" \
  OSV_QUERY_REQUEST_CAPTURE="$T/error.sent.json" \
  "$ROOT/build/rh_cli" osv-query --input "$T/query.json" --out "$T/error-out"
[[ -f "$T/error-out/osv-query-response.raw.json" ]] || fail "non-200 body not retained"
[[ ! -f "$T/error-out/osv-query-result.json" ]] || fail "non-200 emitted success"
cat > "$T/invalid.json" <<'JSON'
{"schema":"rh-osv-query-input/9","package":{"ecosystem":"cargo","name":"shared"},"version":"1.0.0"}
JSON
expect 3 env PATH="$T/bin:$PATH" \
  OSV_QUERY_FAKE_RESPONSE="$ROOT/fixtures/packages/osv-response.json" \
  OSV_QUERY_FAKE_HTTP=200 OSV_QUERY_CAPTURE="$T/invalid.args" \
  OSV_QUERY_REQUEST_CAPTURE="$T/invalid.sent.json" \
  "$ROOT/build/rh_cli" osv-query --input "$T/invalid.json" --out "$T/out"
[[ ! -f "$T/out/osv-query-result.json" ]] || fail "invalid input left stale result"
[[ ! -f "$T/out/osv-query-response.json" ]] || fail "invalid input left stale response"
[[ ! -f "$T/out/osv-query-response.raw.json" ]] || fail "invalid input left stale raw page evidence"

echo "test_osv_query_cli OK"
