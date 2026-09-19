#!/usr/bin/env bash
# tests/test_parser_diff_cli.sh — M03-10 retained parser-adoption comparison.
# It compares native/candidate graph snapshots without executing a resolver,
# classifies losses, and includes parser/configuration/visibility in the cache
# identity. Unsupported candidate output is retained as a distinct status.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
T="/tmp/rh-parser-diff"

fail() { echo "[parser-diff] FAIL: $1" >&2; exit 1; }

echo "[parser-diff] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cp "$ROOT/fixtures/packages/cargo-graph.golden.json" "$T/native.json"

echo "[parser-diff] equal snapshots match"
"$ROOT/build/rh_cli" parser-diff --native "$T/native.json" --candidate "$T/native.json" --out "$T/match.json" \
  --native-parser native-lock/1 --candidate-parser alt-lock/2 --config cargo-default --visibility public >/dev/null || fail "equal diff"
python3 - "$T/match.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-parser-diff/1" and d["status"] == "match", d
assert d["summary"] == {"mismatches": 0, "mapping": 0, "context": 0, "parser_support": 0, "normalization": 0}, d["summary"]
assert d["parsers"] == {"native": "native-lock/1", "candidate": "alt-lock/2", "configuration": "cargo-default", "visibility": "public"}, d["parsers"]
assert len(d["cache_key"]) == 16, d
print("[parser-diff] equal snapshot + metadata OK")
PY

echo "[parser-diff] mapping/context/parser-support losses are classified"
python3 - "$T/native.json" "$T/candidate.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["nodes"][1]["name"] = "left-renamed"
d["nodes"][0]["dev"] = True
d["nodes"][3]["digest"] = False
d["unresolved"][0]["reason"] = "context"
d["nodes"].append({"id": 99, "name": "candidate-only", "version": "9.0.0", "source": "registry", "digest": False, "dev": False, "optional": False})
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" parser-diff --native "$T/native.json" --candidate "$T/candidate.json" --out "$T/different.json" \
  --native-parser native-lock/1 --candidate-parser alt-lock/2 --config cargo-default --visibility private >/dev/null || fail "different diff"
python3 - "$T/different.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "different", d
assert d["parsers"]["visibility"] == "private", d
assert d["summary"]["mapping"] >= 1, d["summary"]
assert d["summary"]["context"] >= 1, d["summary"]
assert d["summary"]["parser_support"] >= 1, d["summary"]
assert d["summary"]["normalization"] >= 2, d["summary"]
classes = {x["class"] for x in d["mismatches"]}
assert {"mapping", "context", "parser_support", "normalization"} <= classes, classes
print("[parser-diff] loss classes + visibility isolation OK")
PY

echo "[parser-diff] unsupported candidate is explicit and retained"
sed 's#rh-dep-graph/1#rh-dep-graph/2#' "$T/native.json" > "$T/unsupported.json"
set +e
"$ROOT/build/rh_cli" parser-diff --native "$T/native.json" --candidate "$T/unsupported.json" --out "$T/unsupported.out" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 3 ]] || fail "unsupported candidate must exit 3 (got $rc)"
python3 - "$T/unsupported.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "unsupported", d
assert "successful empty graph" in d["note"], d
assert d["summary"]["mismatches"] == 0, d
print("[parser-diff] unsupported state OK")
PY

echo "[parser-diff] malformed native fails closed without output"
printf '{"schema":"rh-dep-graph/1","nodes":42}' > "$T/bad-native.json"
set +e
"$ROOT/build/rh_cli" parser-diff --native "$T/bad-native.json" --candidate "$T/native.json" --out "$T/bad.out" >/dev/null 2>&1
rc_bad=$?
set -e
[[ "$rc_bad" -eq 4 ]] || fail "malformed native must exit 4 (got $rc_bad)"
[[ ! -f "$T/bad.out" ]] || fail "malformed native published output"

echo "test_parser_diff_cli OK"
