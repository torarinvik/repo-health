#!/usr/bin/env bash
# tests/test_privacy_cli.sh — M07-07 publication suppression execution path:
# `rh_cli privacy` turns rh-privacy-input/1 cells into rh-privacy-result/1.
# A cell publishes only when every contributing subject is public and the
# threshold is met; private/authorized/unknown members withhold (unknown
# first); small public cells suppress. Nonpublished counts remain redacted.
# The explanation carries "suppression is not anonymization".
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-privacy"

fail() { echo "[privacy] FAIL: $1" >&2; exit 1; }

echo "[privacy] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/in.json" <<'JSON'
{"schema":"rh-privacy-input/1","cells":[{"id":"history.commit_count","public_count":12,"threshold":5},{"id":"dependents","public_count":1,"threshold":5},{"id":"private_dep","public_count":10,"private_count":1,"threshold":5},{"id":"unknown_dep","public_count":10,"unknown_count":1,"threshold":5},{"id":"empty","threshold":5},{"id":"auth_only","public_count":2,"authorized_count":10,"threshold":5},{"id":"priv_and_unknown","public_count":10,"private_count":1,"unknown_count":1,"threshold":5}]}
JSON
"$ROOT/build/rh_cli" privacy --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-privacy-result/1", d
by = {c["id"]: c for c in d["cells"]}
assert by["history.commit_count"]["decision"] == "publish" and by["history.commit_count"]["publishable"] is True, by
assert by["dependents"]["decision"] == "suppress_small_cell" and by["dependents"]["publishable"] is False, by
assert by["private_dep"]["decision"] == "withhold_private_member", by
assert by["unknown_dep"]["decision"] == "withhold_unknown_visibility", by
assert by["empty"]["decision"] == "unavailable", by
assert by["auth_only"]["decision"] == "withhold_authorized_member", by
# unknown-visibility withholds before private
assert by["priv_and_unknown"]["decision"] == "withhold_unknown_visibility", by
for c in d["cells"]:
    assert "suppression is not anonymization" in c["explanation"], c
    if c["decision"] == "publish":
        assert c["counts"] == {"public": 12, "authorized": 0, "private": 0, "unknown": 0}, c
    else:
        assert c["counts"] is None, c
        assert "counts=withheld" in c["explanation"], c
assert "no formal-anonymity claim" in d["note"], d["note"]
print("[privacy] decisions + caveat OK")
PY

echo "[privacy] determinism"
"$ROOT/build/rh_cli" privacy --input "$T/in.json" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "privacy output not deterministic"

echo "[privacy] malformed input fails closed"
set +e
printf '{"schema":"rh-privacy-input/2","cells":[]}' > "$T/badschema.json"
"$ROOT/build/rh_cli" privacy --input "$T/badschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-privacy-input/1","cells":42}' > "$T/badcells.json"
"$ROOT/build/rh_cli" privacy --input "$T/badcells.json" --out "$T/x" >/dev/null 2>&1; rc_cells=$?
printf '{"schema":"rh-privacy-input/1","cells":[{"public_count":1}]}' > "$T/noid.json"
"$ROOT/build/rh_cli" privacy --input "$T/noid.json" --out "$T/x" >/dev/null 2>&1; rc_id=$?
printf '{"schema":"rh-privacy-input/1","cells":[{"id":"bad","public_count":10,"private_count":-1,"threshold":5}]}' > "$T/negative.json"
"$ROOT/build/rh_cli" privacy --input "$T/negative.json" --out "$T/x" >/dev/null 2>&1; rc_negative=$?
printf '{"schema":"rh-privacy-input/1","cells":[{"id":"same","public_count":10,"threshold":5},{"id":"same","public_count":11,"threshold":5}]}' > "$T/duplicate.json"
"$ROOT/build/rh_cli" privacy --input "$T/duplicate.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" privacy --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" privacy --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_cells" "$rc_id" "$rc_negative" "$rc_duplicate" "$rc_json" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed privacy input must exit 4 (got $rc)"
done

echo "test_privacy_cli OK"
