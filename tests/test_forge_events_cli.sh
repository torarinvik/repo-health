#!/usr/bin/env bash
# tests/test_forge_events_cli.sh — M02-05 bounded workflow-event import.
# Public contract: rh-forge-events-result/1.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-forge-events"
fail() { echo "[forge-events] FAIL: $1" >&2; exit 1; }

echo "[forge-events] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/connectors/forge-events-input.json" "$T/input.json"
cp "$ROOT/fixtures/connectors/forge-events-gitlab-input.json" "$T/gitlab.json"
cp "$ROOT/fixtures/connectors/forge-events-forgejo-input.json" "$T/forgejo.json"
cp "$ROOT/fixtures/connectors/forge-events-gitea-input.json" "$T/gitea.json"
cp "$ROOT/fixtures/connectors/forge-events-bitbucket-input.json" "$T/bitbucket.json"
cp "$ROOT/fixtures/connectors/forge-events-result.json" "$T/expected.json"

echo "[forge-events] valid capture reproduces the checked-in result"
"$ROOT/build/rh_cli" forge events --input "$T/input.json" --out "$T/out.json" >/dev/null || fail "valid capture"
python3 - "$T/out.json" "$T/expected.json" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
expected = json.load(open(sys.argv[2]))
assert got == expected, (got, expected)
assert all(e["native_id"].startswith("github:") for e in got["events"])
assert all("title" not in e and "body" not in e for e in got["events"])
print("[forge-events] result and provider-native boundary OK")
PY

echo "[forge-events] replay is deterministic"
"$ROOT/build/rh_cli" forge events --input "$T/input.json" --out "$T/out2.json" >/dev/null || fail "replay"
cmp -s "$T/out.json" "$T/out2.json" || fail "replay changed bytes"

echo "[forge-events] GitLab native ids and release fallback remain distinct"
"$ROOT/build/rh_cli" forge events --input "$T/gitlab.json" --out "$T/gitlab.out" >/dev/null || fail "GitLab capture"
python3 - "$T/gitlab.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["provider"] == "gitlab" and d["authorization"]["state"] == "not_requested", d
assert [e["native_id"] for e in d["events"]] == ["gitlab:12", "gitlab:8", "gitlab:56", "gitlab:10"], d
assert d["events"][-1]["created_at"] == 1699900100 and d["events"][-1]["status"] == "published", d
assert d["events"][-1]["tag"] == "v2.0.0" and d["events"][-1]["url"].startswith("https://gitlab.com/"), d
print("[forge-events] GitLab boundary OK")
PY

echo "[forge-events] Forgejo keeps its own provider namespace"
"$ROOT/build/rh_cli" forge events --input "$T/forgejo.json" --out "$T/forgejo.out" >/dev/null || fail "Forgejo capture"
python3 - "$T/forgejo.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["provider"] == "forgejo" and d["authorization"]["state"] == "unknown", d
assert [e["native_id"] for e in d["events"]] == ["forgejo:21", "forgejo:11", "forgejo:66", "forgejo:12"], d
assert d["events"][-1]["status"] == "published" and d["events"][-1]["tag"] == "v3.0.0", d
print("[forge-events] Forgejo boundary OK")
PY

echo "[forge-events] Gitea keeps its own provider namespace and authorization"
"$ROOT/build/rh_cli" forge events --input "$T/gitea.json" --out "$T/gitea.out" >/dev/null || fail "Gitea capture"
python3 - "$T/gitea.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["provider"] == "gitea" and d["authorization"]["state"] == "unauthorized", d
assert [e["native_id"] for e in d["events"]] == ["gitea:31", "gitea:13", "gitea:76", "gitea:14"], d
assert d["events"][1]["status"] == "closed" and d["events"][3]["tag"] == "v4.0.0", d
print("[forge-events] Gitea boundary OK")
PY

echo "[forge-events] Bitbucket captured issues/proposals keep provider IDs"
"$ROOT/build/rh_cli" forge events --input "$T/bitbucket.json" --out "$T/bitbucket.out" >/dev/null || fail "Bitbucket capture"
python3 - "$T/bitbucket.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["provider"] == "bitbucket", d
assert d["capabilities"]["issues"] == {"status": "observed", "count": 1, "rejected": 0}, d
assert d["capabilities"]["proposals"] == {"status": "observed", "count": 1, "rejected": 0}, d
assert d["capabilities"]["reviews"]["status"] == "unsupported" and d["capabilities"]["releases"]["status"] == "unsupported", d
assert [e["native_id"] for e in d["events"]] == ["bitbucket:301", "bitbucket:17"], d["events"]
assert d["events"][1]["status"] == "MERGED", d["events"][1]
assert d["events"][0]["url"].startswith("https://bitbucket.org/"), d["events"][0]
print("[forge-events] Bitbucket provider identity + unsupported states OK")
PY

echo "[forge-events] rejected records are counted per capability"
python3 - "$T/input.json" "$T/malformed.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["issues"].append({"state": "open", "created_at": 1700000000})
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/malformed.json" --out "$T/malformed.out" >/dev/null || fail "malformed record capture"
python3 - "$T/malformed.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["issues"] == {"status": "observed", "count": 1, "rejected": 1}, d
assert d["capabilities"]["proposals"]["rejected"] == 0, d
assert len(d["events"]) == 4, d
print("[forge-events] per-capability rejection count OK")
PY

echo "[forge-events] duplicate page observations replace by provider-native identity"
python3 - "$T/input.json" "$T/duplicate-page.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["issues"].append({"number": 101, "state": "closed", "created_at": 1699000000, "updated_at": 1699999999, "closed_at": 1699999999, "html_url": "https://github.com/example/project/issues/101"})
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/duplicate-page.json" --out "$T/duplicate-page.out" >/dev/null || fail "duplicate page capture"
python3 - "$T/duplicate-page.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["issues"] == {"status": "observed", "count": 1, "rejected": 0}, d
assert len(d["events"]) == 4, d
issue = [e for e in d["events"] if e["kind"] == "issues"][0]
assert issue["status"] == "closed" and issue["updated_at"] == 1699999999, issue
print("[forge-events] duplicate replacement + count idempotence OK")
PY

echo "[forge-events] opaque pagination state is retained"
python3 - "$T/input.json" "$T/paginated.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["pagination"] = {
    "issues": {"next": "issues-page-2", "complete": False},
    "proposals": {"next": None, "complete": True},
    "reviews": {"next": "reviews-page-2", "complete": False},
    "releases": {"next": "", "complete": True},
}
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/paginated.json" --out "$T/paginated.out" >/dev/null || fail "pagination capture"
python3 - "$T/paginated.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["pagination"]["issues"] == {"next": "issues-page-2", "complete": False}, d
assert d["pagination"]["proposals"] == {"next": None, "complete": True}, d
assert d["pagination"]["releases"] == {"next": "", "complete": True}, d
print("[forge-events] pagination cursor + completion state OK")
PY

python3 - "$T/input.json" "$T/negative-time.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["issues"][0]["updated_at"] = -1
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/negative-time.json" --out "$T/negative-time.out" >/dev/null || fail "negative timestamp capture"
python3 - "$T/negative-time.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["issues"] == {"status": "observed", "count": 0, "rejected": 1}, d
print("[forge-events] negative timestamp rejection OK")
PY

echo "[forge-events] missing capabilities remain explicit unsupported"
python3 - "$T/input.json" "$T/partial.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d.pop("releases")
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" forge events --input "$T/partial.json" --out "$T/partial.out" >/dev/null || fail "partial capture"
python3 - "$T/partial.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["capabilities"]["releases"] == {"status": "unsupported", "count": None, "rejected": 0}, d
print("[forge-events] unsupported boundary OK")
PY

echo "[forge-events] malformed envelopes fail closed"
set +e
printf '%s\n' '{"schema":"rh-forge-events-input/1","provider":"github","captured_at":1,"issues":{}}' > "$T/wrong-array-shape.json"
"$ROOT/build/rh_cli" forge events --input "$T/wrong-array-shape.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
printf '%s\n' '{"schema":"wrong","provider":"github","captured_at":1}' > "$T/wrong-schema.json"
"$ROOT/build/rh_cli" forge events --input "$T/wrong-schema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '%s\n' '{"schema":"rh-forge-events-input/1","provider":"bogus","captured_at":1}' > "$T/wrong-provider.json"
"$ROOT/build/rh_cli" forge events --input "$T/wrong-provider.json" --out "$T/x" >/dev/null 2>&1; rc_provider=$?
set -e
[[ "$rc_missing" -eq 4 ]] || fail "wrong capability array shape must exit 4 (got $rc_missing)"
[[ "$rc_schema" -eq 4 ]] || fail "wrong schema must exit 4 (got $rc_schema)"
[[ "$rc_provider" -eq 4 ]] || fail "wrong provider must exit 4 (got $rc_provider)"
echo "test_forge_events_cli OK"
