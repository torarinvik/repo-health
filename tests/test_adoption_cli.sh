#!/usr/bin/env bash
# tests/test_adoption_cli.sh — M05 staged adoption and censoring evidence.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-adoption"

fail() { echo "[adoption] FAIL: $1" >&2; exit 1; }

echo "[adoption] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-adoption-input/1","cutoff":1000,"adoptions":[{"first_seen":100,"confirmed_introduction":null,"confirmed_removal":null},{"first_seen":100,"confirmed_introduction":200,"confirmed_removal":null},{"first_seen":100,"confirmed_introduction":200,"confirmed_removal":500},{"first_seen":null,"confirmed_introduction":null,"confirmed_removal":null}]}
JSON
"$ROOT/build/rh_cli" adoption --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "adoption run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-adoption-result/1", d
assert d["cutoff"] == 1000, d
assert [a["status"] for a in d["adoptions"]] == ["first_seen_only", "confirmed_introduced", "confirmed_removal", "unknown"], d
assert d["adoptions"][0]["duration_censored"] is True, d
assert d["adoptions"][2]["duration_censored"] == 300, d
assert d["status_counts"] == {"unknown": 1, "first_seen_only": 1, "confirmed_introduced": 1, "confirmed_removal": 1}, d
metrics = {m["key"]: m for m in d["metrics"]}
assert metrics["adoption.unknown_count"]["value"] == 1, metrics
assert metrics["adoption.first_seen_only_count"]["value"] == 1, metrics
assert metrics["adoption.confirmed_introduction_count"]["value"] == 1, metrics
assert metrics["adoption.confirmed_removal_count"]["value"] == 1, metrics
assert "not proof of migration" in d["note"], d
print("[adoption] staged states + right censoring OK")
PY

echo "[adoption] determinism + malformed input fails closed"
"$ROOT/build/rh_cli" adoption --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "adoption output not deterministic"
set +e
sed 's/"confirmed_removal":500/"confirmed_removal":50/' "$T/in.json" > "$T/bad-order.json"
"$ROOT/build/rh_cli" adoption --input "$T/bad-order.json" --out "$T/x" >/dev/null 2>&1; rc_order=$?
sed 's/"cutoff":1000/"cutoff":150/' "$T/in.json" > "$T/bad-cutoff.json"
"$ROOT/build/rh_cli" adoption --input "$T/bad-cutoff.json" --out "$T/x" >/dev/null 2>&1; rc_cutoff=$?
printf '{"schema":"rh-adoption-input/1","cutoff":1,"adoptions":[{"first_seen":null,"confirmed_introduction":null}]}' > "$T/missing.json"
"$ROOT/build/rh_cli" adoption --input "$T/missing.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
[[ "$rc_order" -eq 4 && "$rc_cutoff" -eq 4 && "$rc_missing" -eq 4 ]] || fail "invalid adoption must exit 4 (got $rc_order/$rc_cutoff/$rc_missing)"

echo "test_adoption_cli OK"
