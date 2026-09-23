#!/usr/bin/env bash
# tests/test_privacy_cli.sh — M07-07 publication suppression execution path:
# `rh_cli privacy` turns rh-privacy-input/1 cells into rh-privacy-result/2.
# A cell publishes only when every contributing subject is public and the
# threshold is met; private/authorized/unknown members withhold (unknown
# first); small public cells suppress. Nonpublished counts remain redacted.
# rh-privacy-history/1 stores published baselines and suppresses small repeated
# count changes for stable cell IDs; differently identified overlapping cells
# remain outside this limited composition control.
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
assert d["schema"] == "rh-privacy-result/2", d
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

echo "[privacy] repeated stable-cell releases suppress small count differences"
cat > "$T/release-1.json" <<'JSON'
{"schema":"rh-privacy-input/1","cells":[{"id":"cohort.public-contributors","public_count":10,"threshold":5}]}
JSON
"$ROOT/build/rh_cli" privacy --input "$T/release-1.json" --out "$T/release-1.out" --history "$T/history.json" >/dev/null || fail "initial history release"
[[ -f "$T/history.json.lock" ]] || fail "privacy history must use a persistent advisory lock file"
python3 - "$T/history.json" "$T/history.json.lock" <<'PY'
import os, stat, sys
for path in sys.argv[1:]:
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o600, (path, oct(stat.S_IMODE(os.stat(path).st_mode)))
print("[privacy] history and lock files are owner-only")
PY
set +e
"$ROOT/build/rh_cli" privacy --input "$T/release-1.json" --out "$T/history.json.lock" --history "$T/history.json" >/dev/null 2>&1; rc_lock_clobber=$?
set -e
[[ "$rc_lock_clobber" -eq 2 ]] || fail "privacy output must not overwrite its history lock"
cat > "$T/release-2.json" <<'JSON'
{"schema":"rh-privacy-input/1","cells":[{"id":"cohort.public-contributors","public_count":12,"threshold":5}]}
JSON
"$ROOT/build/rh_cli" privacy --input "$T/release-2.json" --out "$T/release-2.out" --history "$T/history.json" >/dev/null || fail "history follow-up release"
python3 - "$T/release-1.out" "$T/release-2.out" "$T/history.json" <<'PY'
import json, sys
first, second, history = (json.load(open(p)) for p in sys.argv[1:])
assert first["cells"][0]["decision"] == "publish", first
assert second["cells"][0]["decision"] == "suppress_repeated_release_difference", second
assert second["cells"][0]["counts"] is None, second
assert history["published_cells"] == [{"id":"cohort.public-contributors","public_count":10,"threshold":5}], history
print("[privacy] repeated small difference withheld; suppressed release does not advance history")
PY
cat > "$T/release-3.json" <<'JSON'
{"schema":"rh-privacy-input/1","cells":[{"id":"cohort.public-contributors","public_count":15,"threshold":5}]}
JSON
"$ROOT/build/rh_cli" privacy --input "$T/release-3.json" --out "$T/release-3.out" --history "$T/history.json" >/dev/null || fail "threshold-sized difference release"
python3 - "$T/release-3.out" "$T/history.json" <<'PY'
import json, sys
result, history = (json.load(open(p)) for p in sys.argv[1:])
assert result["cells"][0]["decision"] == "publish", result
assert history["published_cells"] == [{"id":"cohort.public-contributors","public_count":15,"threshold":5}], history
print("[privacy] threshold-sized change publishes and advances the stored baseline")
PY
echo "[privacy] concurrent publishers serialize on the history guard"
python3 - "$ROOT/build/rh_cli" "$T/release-3.json" "$T/concurrent.out" "$T/history.json" <<'PY'
import fcntl, subprocess, sys, time
cli, source, output, history = sys.argv[1:]
lock = open(history + ".lock", "r+")
fcntl.flock(lock, fcntl.LOCK_EX)
process = subprocess.Popen([cli, "privacy", "--input", source, "--out", output, "--history", history], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(0.2)
assert process.poll() is None, "publisher bypassed the held history lock"
fcntl.flock(lock, fcntl.LOCK_UN)
lock.close()
assert process.wait(timeout=10) == 0, "publisher failed after lock release"
print("[privacy] publisher waited for another process to release history lock")
PY
echo "[privacy] malformed and duplicate release history fail closed"
printf '{"schema":"rh-privacy-history/1","published_cells":[{"id":"same","public_count":10,"threshold":5},{"id":"same","public_count":11,"threshold":5}]}' > "$T/history-duplicate.json"
set +e
"$ROOT/build/rh_cli" privacy --input "$T/release-1.json" --out "$T/history-bad.out" --history "$T/history-duplicate.json" >/dev/null 2>&1; rc_history_duplicate=$?
printf '{"schema":"rh-privacy-history/1","published_cells":[{"id":"bad","public_count":"10","threshold":5}]}' > "$T/history-malformed.json"
"$ROOT/build/rh_cli" privacy --input "$T/release-1.json" --out "$T/history-bad.out" --history "$T/history-malformed.json" >/dev/null 2>&1; rc_history_malformed=$?
set -e
[[ "$rc_history_duplicate" -eq 4 && "$rc_history_malformed" -eq 4 ]] || fail "malformed/duplicate privacy history must fail closed"
printf 'preserve this lock target\n' > "$T/lock-target"
ln -s "$T/lock-target" "$T/history-symlink.json.lock"
set +e
"$ROOT/build/rh_cli" privacy --input "$T/release-1.json" --out "$T/history-link.out" --history "$T/history-symlink.json" >/dev/null 2>&1; rc_history_link=$?
set -e
[[ "$rc_history_link" -eq 4 && "$(cat "$T/lock-target")" == "preserve this lock target" ]] || fail "privacy history lock must refuse symlink targets"
printf '{"preserve":"state target"}\n' > "$T/state-target"
ln -s "$T/state-target" "$T/history-state-link.json"
set +e
"$ROOT/build/rh_cli" privacy --input "$T/release-1.json" --out "$T/history-state-link.out" --history "$T/history-state-link.json" >/dev/null 2>&1; rc_state_link=$?
set -e
[[ "$rc_state_link" -eq 4 && "$(cat "$T/state-target")" == '{"preserve":"state target"}' ]] || fail "privacy history must refuse symlink state files"
ln -s "$T/missing-state-target" "$T/history-dangling-link.json"
set +e
"$ROOT/build/rh_cli" privacy --input "$T/release-1.json" --out "$T/history-dangling.out" --history "$T/history-dangling-link.json" >/dev/null 2>&1; rc_state_dangling=$?
set -e
[[ "$rc_state_dangling" -eq 4 && ! -e "$T/missing-state-target" ]] || fail "privacy history must refuse dangling symlink state files"

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
printf '{"schema":"rh-privacy-input/1","cells":[{"id":"low-threshold","public_count":1,"threshold":1}]}' > "$T/low-threshold.json"
"$ROOT/build/rh_cli" privacy --input "$T/low-threshold.json" --out "$T/x" >/dev/null 2>&1; rc_threshold=$?
printf '{"schema":"rh-privacy-input/1","cells":[{"id":"same","public_count":10,"threshold":5},{"id":"same","public_count":11,"threshold":5}]}' > "$T/duplicate.json"
"$ROOT/build/rh_cli" privacy --input "$T/duplicate.json" --out "$T/x" >/dev/null 2>&1; rc_duplicate=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" privacy --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" privacy --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_cells" "$rc_id" "$rc_negative" "$rc_threshold" "$rc_duplicate" "$rc_json" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed privacy input must exit 4 (got $rc)"
done

echo "test_privacy_cli OK"
