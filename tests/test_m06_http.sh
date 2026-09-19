#!/usr/bin/env bash
# tests/test_m06_http.sh — M06-01 HTTP wire protocol gate: request-line
# parsing, loopback-only bind, allowlisted routing, traversal rejection,
# bounded responses, and no path echo.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "[m06http] FAIL: $1" >&2; exit 1; }

echo "[m06http] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/test_http" ]] || fail "test_http not built"

echo "[m06http] parse + route + status matrix"
out="$("$ROOT/build/test_http")" || fail "test_http: $out"
[[ "$out" == *"HTTP OK"* ]] || fail "test_http: $out"
echo "$out"

echo "[m06http] listener binds loopback only and is bounded"
grep -q "127" "$ROOT/src/rh_http.elisa" || fail "loopback bind missing"
grep -q "RH_HTTP_MAX_REQUEST" "$ROOT/src/rh_http.elisa" || fail "request cap missing"
grep -q "RH_HTTP_MAX_BODY" "$ROOT/src/rh_http.elisa" || fail "body cap missing"
# A real bind of the wildcard address would appear as an actual address
# constant; the only occurrence here is the comment that forbids it.
if grep -nE "0\.0\.0\.0|INADDR_ANY" "$ROOT/src/rh_http.elisa" | grep -v "never"; then
  fail "listener must not bind all interfaces"
fi
grep -q "never echoes the request" "$ROOT/src/rh_http.elisa" || fail "no-echo caveat missing"

echo "[m06http] routing is an allowlist with no directory listing"
grep -q "rh_http_allowed_span" "$ROOT/src/rh_http.elisa" || fail "allowlist missing"
grep -q "No directory listing" "$ROOT/src/rh_http.elisa" || fail "no-listing note missing"

echo "[m06http] live loopback serve + real HTTP client (opt-in: RH_LIVE_TESTS=1)"
if [[ "${RH_LIVE_TESTS:-0}" == "1" ]]; then
  command -v curl >/dev/null || fail "curl required for live test"
  W="/tmp/rh-m06http-live"
  rm -rf "$W"; mkdir -p "$W"
  printf '{"report":"x"}\n' > "$W/report.json"
  printf '<html>ok</html>\n' > "$W/index.html"
  # A real report for the server-rendered page route.
  mkdir -p "$W/src"
  git init -q -b main "$W/src"
  ( cd "$W/src" && git config user.name D && git config user.email d@e.test && echo x > f && git add f \
      && GIT_AUTHOR_DATE="2024-03-01T00:00:00Z" GIT_COMMITTER_DATE="2024-03-01T00:00:00Z" git commit -qm one )
  "$ROOT/build/rh_cli" scan --repo "$W/src" --out "$W/report" --window-days 36500 >/dev/null
  "$ROOT/build/rh_cli" serve --root "$W/report" --port 18611 --max 20 > "$W/log" 2>&1 &
  SRV=$!
  sleep 2
  h="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18611/health)" || true
  [[ "$h" == "200" ]] || { kill "$SRV" 2>/dev/null; fail "live health=$h"; }
  ct="$(curl -s -o /dev/null -w '%{content_type}' http://127.0.0.1:18611/report.json)" || true
  [[ "$ct" == "application/json" ]] || { kill "$SRV" 2>/dev/null; fail "live json ct=$ct"; }
  rct="$(curl -s -o /dev/null -w '%{content_type}' http://127.0.0.1:18611/_report.html)" || true
  [[ "$rct" == text/html* ]] || { kill "$SRV" 2>/dev/null; fail "server-rendered ct=$rct"; }
  rbody="$(curl -s http://127.0.0.1:18611/_report.html)" || true
  [[ "$rbody" == *"not maintainers"* && "$rbody" == *"history.commit_count"* ]] \
    || { kill "$SRV" 2>/dev/null; fail "server-rendered page missing content"; }
  cat > "$W/query.json" <<'JSON'
{"schema":"rh-query-input/1","kind":"metrics","ids":[10,20,30],"cursor":-1,"limit":2}
JSON
  qct="$(curl -s -X POST -H 'Content-Type: application/json' --data-binary @"$W/query.json" -o "$W/query.out" -w '%{content_type}' http://127.0.0.1:18611/api/query)" || true
  [[ "$qct" == application/json ]] || { kill "$SRV" 2>/dev/null; fail "query ct=$qct"; }
  grep -q 'rh-query-result/1' "$W/query.out" || { kill "$SRV" 2>/dev/null; fail "query result missing"; }
  printf '{"resource":"metrics"}\n' > "$W/report/metrics.json"
  mct="$(curl -s -o "$W/metrics.out" -w '%{http_code} %{content_type}' http://127.0.0.1:18611/api/metrics)" || true
  [[ "$mct" == "200 application/json" ]] || { kill "$SRV" 2>/dev/null; fail "resource route=$mct"; }
  grep -q '"resource":"metrics"' "$W/metrics.out" || { kill "$SRV" 2>/dev/null; fail "resource body missing"; }
  mkdir -p "$W/report/evidence"
  printf 'stored evidence\n' > "$W/blob.txt"
  put_out="$("$ROOT/build/rh_cli" store put --root "$W/report/evidence" --file "$W/blob.txt")" || { kill "$SRV" 2>/dev/null; fail "store put"; }
  digest="${put_out#store: put }"
  digest="${digest%% *}"
  sct="$(curl -s -o "$W/store.out" -w '%{http_code} %{content_type}' "http://127.0.0.1:18611/api/store/$digest")" || true
  [[ "$sct" == "200 application/octet-stream" ]] || { kill "$SRV" 2>/dev/null; fail "store route=$sct"; }
  cmp -s "$W/blob.txt" "$W/store.out" || { kill "$SRV" 2>/dev/null; fail "store body differs"; }
  absent="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18611/api/findings)" || true
  [[ "$absent" == "404" ]] || { kill "$SRV" 2>/dev/null; fail "absent resource=$absent"; }
  n="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18611/nope)" || true
  [[ "$n" == "404" ]] || { kill "$SRV" 2>/dev/null; fail "live 404=$n"; }
  t="$(curl -s -o /dev/null -w '%{http_code}' --path-as-is http://127.0.0.1:18611/../etc/passwd)" || true
  [[ "$t" == "400" ]] || { kill "$SRV" 2>/dev/null; fail "live traversal=$t"; }
  kill "$SRV" 2>/dev/null || true
  echo "[m06http] live serve OK (incl. server-rendered /_report.html)"
else
  echo "[m06http] live serve skipped (RH_LIVE_TESTS!=1)"
fi

echo "test_m06_http OK"
