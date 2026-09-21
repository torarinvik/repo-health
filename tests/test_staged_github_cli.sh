#!/usr/bin/env bash
# Replay committed PostgreSQL GitHub issue and proposal rows through rh-forge-events/1.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-staged-github-issues"
fail() { echo "[staged-github-issues] FAIL: $1" >&2; exit 1; }

echo "[staged-github-issues] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"
rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/postgres/staged-github-issues-input.json" "$T/input.json"
cp "$ROOT/fixtures/postgres/staged-github-issues-output.json" "$T/expected.json"
cp "$ROOT/fixtures/postgres/staged-github-proposals-input.json" "$T/proposals-input.json"

echo "[staged-github-issues] replay binds the exact stage input and preserves provenance"
"$ROOT/build/rh_cli" staged-normalize --input "$T/input.json" --out "$T/output.json" >/dev/null || fail "valid staged rows"
python3 - "$T/output.json" "$T/expected.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == json.load(open(sys.argv[2])), "result differs from checked-in replay"
PY
python3 - "$T/input.json" "$T/output.json" <<'PY'
import hashlib, json, sys
raw = open(sys.argv[1], "rb").read()
d = json.load(open(sys.argv[2]))
assert d["schema"] == "rh-postgres-staged-normalize-result/1", d
assert d["input_sha256"] == hashlib.sha256(raw).hexdigest(), d["input_sha256"]
assert (d["source_id"], d["collection_run_id"]) == ("source-github-example", "run-github-example-001"), d
assert d["canonical_capability"] == "issues" and d["collector_label"] == "issues-page-v1", d
assert d["record_count"] == 2 and d["staged_records"] == [
    {"page_number": 0, "record_ordinal": 0}, {"page_number": 1, "record_ordinal": 0}
], d["staged_records"]
n = d["normalized"]
assert n["schema"] == "rh-forge-events-result/1" and n["capabilities"]["issues"]["duplicate_replacements"] == 1, n
assert n["capabilities"]["issues"]["count"] == 1 and n["events"][0]["native_id"] == "github:101", n
assert n["events"][0]["status"] == "closed", n["events"]
assert all(n["capabilities"][k]["status"] == "not_attempted" for k in ("proposals", "reviews", "releases")), n
PY
"$ROOT/build/rh_cli" staged-normalize --input "$T/input.json" --out "$T/replay.json" >/dev/null || fail "deterministic replay"
cmp -s "$T/output.json" "$T/replay.json" || fail "replay changed output bytes"

echo "[staged-github-issues] explicit pull-request binding normalizes proposals"
"$ROOT/build/rh_cli" staged-normalize --input "$T/proposals-input.json" --out "$T/proposals-output.json" >/dev/null || fail "valid staged pull requests"
python3 - "$T/proposals-input.json" "$T/proposals-output.json" "$ROOT/fixtures/postgres/staged-github-proposals-output.json" <<'PY'
import hashlib, json, sys
got = json.load(open(sys.argv[2]))
expected = json.load(open(sys.argv[3]))
assert got == expected, (got, expected)
assert got["input_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), got
assert got["canonical_capability"] == "proposals" and got["record_count"] == 1, got
n = got["normalized"]
assert n["capabilities"]["proposals"]["status"] == "observed" and n["capabilities"]["proposals"]["count"] == 1, n
assert n["events"][0]["kind"] == "proposals" and n["events"][0]["native_id"] == "github:17", n["events"]
assert n["capabilities"]["issues"]["status"] == "not_attempted", n["capabilities"]
PY

echo "[staged-github-issues] committed empty pages remain observed empty"
python3 - "$T/input.json" "$T/empty.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["pages"] = [{"page_number": 3, "committed": True, "completeness": "empty", "records": []}]
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" staged-normalize --input "$T/empty.json" --out "$T/empty.out" >/dev/null || fail "valid empty page"
python3 - "$T/empty.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["record_count"] == 0 and d["pages"] == [{"page_number": 3, "completeness": "empty", "record_count": 0}], d
issues = d["normalized"]["capabilities"]["issues"]
assert issues["status"] == "observed" and issues["count"] == 0 and issues["rejected"] == 0, issues
PY

echo "[staged-github-issues] uncommitted, partial, misbound, and malformed rows fail closed"
python3 - "$T/input.json" "$T" <<'PY'
import copy, json, os, sys
base = json.load(open(sys.argv[1]))
out = sys.argv[2]
cases = {}
d = copy.deepcopy(base); d["pages"][0]["committed"] = False; cases["uncommitted"] = d
d = copy.deepcopy(base); d["pages"][0]["completeness"] = "partial"; cases["partial"] = d
d = copy.deepcopy(base); d["pages"][0]["records"][0]["collector_label"] = "other-capability"; cases["misbound"] = d
d = copy.deepcopy(base); d["pages"][0]["records"][0]["record_ordinal"] = 1; cases["ordinal"] = d
d = copy.deepcopy(base); d["pages"][0]["records"][0]["raw_payload"] = "[]"; cases["non-object-payload"] = d
d = copy.deepcopy(base); d["canonical_capability"] = "proposals"; cases["schema-capability-mismatch"] = d
for name, value in cases.items():
    with open(os.path.join(out, name + ".json"), "w", encoding="utf-8") as f:
        json.dump(value, f, separators=(",", ":"))
PY
for name in uncommitted partial misbound ordinal non-object-payload schema-capability-mismatch; do
  if "$ROOT/build/rh_cli" staged-normalize --input "$T/$name.json" --out "$T/$name.out" >/dev/null 2>&1; then
    fail "$name stage input was accepted"
  fi
  [[ ! -e "$T/$name.out" ]] || fail "$name wrote an output despite rejection"
done

grep -q "rh-postgres-staged-github-issues-input/1" "$ROOT/src/rh_staged_github.elisa" || fail "issue input contract token missing"
grep -q "rh-postgres-staged-github-proposals-input/1" "$ROOT/src/rh_staged_github.elisa" || fail "proposal input contract token missing"
grep -q "rh-postgres-staged-normalize-result/1" "$ROOT/src/rh_staged_github.elisa" || fail "result contract token missing"
echo "test_staged_github_cli OK"
