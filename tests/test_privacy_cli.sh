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
cp "$ROOT/fixtures/m07/privacy-contract-input.json" "$T/in.json"
"$ROOT/build/rh_cli" privacy --input "$T/in.json" --out "$T/out.json" >/dev/null || fail "run"
cmp -s "$T/out.json" "$ROOT/fixtures/m07/privacy-contract-result.json" || fail "privacy output differs from the public contract fixture"
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

echo "[privacy] deployment-keyed member tokens detect overlapping cohorts"
python3 - "$T/cohort-a.json" "$T/cohort-overlap.json" "$T/cohort-disjoint.json" "$T/cohort-a-changed.json" <<'PY'
import json, sys
tok = [format(i, "064x") for i in range(14)]
def write(path, ident, members):
    value = {"schema":"rh-privacy-input/1", "cells":[{"id":ident, "public_count":len(members), "threshold":5, "public_member_tokens":[tok[i] for i in members]}]}
    with open(path,"w") as f: json.dump(value,f,separators=(",",":"))
write(sys.argv[1], "cohort-a", [0,1,2,3,4])
write(sys.argv[2], "cohort-overlap", [3,4,5,6,7])
write(sys.argv[3], "cohort-disjoint", [5,6,7,8,9])
write(sys.argv[4], "cohort-a", [4,10,11,12,13])
PY
"$ROOT/build/rh_cli" privacy --input "$T/cohort-a.json" --out "$T/cohort-a.out" --history "$T/cohort-history.json" >/dev/null || fail "initial member-token release"
python3 - "$T/cohort-history.json" <<'PY'
import json, sys
h=json.load(open(sys.argv[1]))
assert len(h["published_cells"]) == 1 and len(h["published_cells"][0]["public_member_tokens"]) == 5, h
print("[privacy] history retains only keyed member tokens for overlap review")
PY
"$ROOT/build/rh_cli" privacy --input "$T/cohort-a.json" --out "$T/cohort-a-replay.out" --history "$T/cohort-history.json" >/dev/null || fail "same population replay"
python3 - "$T/cohort-a-replay.out" <<'PY'
import json, sys
c=json.load(open(sys.argv[1]))["cells"][0]
assert c["decision"] == "publish" and c["overlap_check"] == "same_population", c
print("[privacy] exact same-ID population replay remains explicit")
PY
"$ROOT/build/rh_cli" privacy --input "$T/cohort-overlap.json" --out "$T/cohort-overlap.out" --history "$T/cohort-history.json" >/dev/null || fail "overlap review"
python3 - "$T/cohort-overlap.out" "$T/cohort-history.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1])); h=json.load(open(sys.argv[2])); c=r["cells"][0]
assert c["decision"] == "suppress_overlapping_population" and c["counts"] is None, c
assert c["overlap_check"] == "overlap_suppressed", c
assert len(h["published_cells"]) == 1 and h["published_cells"][0]["id"] == "cohort-a", h
print("[privacy] intersecting population under another ID is suppressed")
PY
"$ROOT/build/rh_cli" privacy --input "$T/cohort-disjoint.json" --out "$T/cohort-disjoint.out" --history "$T/cohort-history.json" >/dev/null || fail "disjoint review"
python3 - "$T/cohort-disjoint.out" <<'PY'
import json, sys
c=json.load(open(sys.argv[1]))["cells"][0]
assert c["decision"] == "publish" and c["overlap_check"] == "checked_no_overlap", c
print("[privacy] disjoint member sets remain publishable with checked status")
PY
"$ROOT/build/rh_cli" privacy --input "$T/cohort-a-changed.json" --out "$T/cohort-a-changed.out" --history "$T/cohort-history.json" >/dev/null || fail "same-ID population change review"
python3 - "$T/cohort-a-changed.out" <<'PY'
import json, sys
c=json.load(open(sys.argv[1]))["cells"][0]
assert c["decision"] == "suppress_overlapping_population" and c["overlap_check"] == "overlap_suppressed", c
print("[privacy] reused cell ID cannot bypass overlap checks when membership changes")
PY
printf '{"schema":"rh-privacy-history/1","published_cells":[{"id":"legacy","public_count":5,"threshold":5}]}' > "$T/cohort-legacy-history.json"
"$ROOT/build/rh_cli" privacy --input "$T/cohort-overlap.json" --out "$T/cohort-legacy.out" --history "$T/cohort-legacy-history.json" >/dev/null || fail "legacy overlap history handling"
python3 - "$T/cohort-legacy.out" <<'PY'
import json, sys
c=json.load(open(sys.argv[1]))["cells"][0]
assert c["decision"] == "suppress_incomplete_overlap_history" and c["overlap_check"] == "incomplete_history", c
print("[privacy] legacy history without member tokens fails closed for token-enabled publication")
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
printf '{"schema":"rh-privacy-input/1","cells":[{"id":"bad-token","public_count":5,"threshold":5,"public_member_tokens":["not-a-hmac"]}]}' > "$T/bad-token.json"
"$ROOT/build/rh_cli" privacy --input "$T/bad-token.json" --out "$T/x" >/dev/null 2>&1; rc_token=$?
python3 - "$T/unsorted-tokens.json" <<'PY'
import json, sys
tokens=[format(i,"064x") for i in range(5)]
tokens.reverse()
json.dump({"schema":"rh-privacy-input/1","cells":[{"id":"unsorted","public_count":5,"threshold":5,"public_member_tokens":tokens}]},open(sys.argv[1],"w"))
PY
"$ROOT/build/rh_cli" privacy --input "$T/unsorted-tokens.json" --out "$T/x" >/dev/null 2>&1; rc_token_order=$?
printf 'not json' > "$T/notjson.json"
"$ROOT/build/rh_cli" privacy --input "$T/notjson.json" --out "$T/x" >/dev/null 2>&1; rc_json=$?
"$ROOT/build/rh_cli" privacy --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_cells" "$rc_id" "$rc_negative" "$rc_threshold" "$rc_duplicate" "$rc_token" "$rc_token_order" "$rc_json" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed privacy input must exit 4 (got $rc)"
done

echo "test_privacy_cli OK"
