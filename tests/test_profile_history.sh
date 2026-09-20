#!/usr/bin/env bash
# Optional real-history profiling reads local Git history without fetching.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-profile-history"

fail() { echo "[profile-history] FAIL: $1" >&2; exit 1; }

echo "[profile-history] build"
bash "$ROOT/tools/build.sh" >/dev/null
rm -rf "$T"; mkdir -p "$T/repo" "$T/profile"
git -C "$T/repo" init -q
for day in 1 2 3 4; do
  printf 'revision %s\n' "$day" > "$T/repo/history.txt"
  git -C "$T/repo" add history.txt
  date="2001-01-0${day}T00:00:00Z"
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" git -C "$T/repo" -c user.name="Bench Fixture" -c user.email="history-secret@example.invalid" commit -q -m "history sample $day"
done

echo "[profile-history] full local history is measured without retaining raw identities"
RH_BENCH_REPS=2 RH_BENCH_CONCURRENT_JOBS=2 RH_PROFILE_REPO="$T/repo" bash "$ROOT/tools/profile.sh" "$T/profile" >/dev/null || fail "profile run"
python3 - "$T/profile/profile-manifest.json" "$T/repo" <<'PY'
import json, subprocess, sys
manifest = json.load(open(sys.argv[1]))
assert manifest["profile"] == "rh-profile/3", manifest
history = manifest["repository_history"]
revision = subprocess.check_output(["git", "-C", sys.argv[2], "rev-parse", "HEAD"], text=True).strip()
assert history["source"] == "local git history", history
assert history["repository_revision"] == revision, history
assert history["commits"] == 4 and history["identities"] == 1, history
assert history["active_months"] == 1 and history["history_digest"].startswith("fnv1a64:"), history
assert len(history["latency"]["samples_ms"]) == 2, history
assert len(history["peak_rss"]["samples_bytes"]) == 2, history
assert len(history["concurrent_peak_rss_upper_bound"]["samples_bytes"]) == 2, history
assert len(history["sampled_concurrent_peak_rss"]["samples_bytes"]) == 2, history
assert history["outcomes"] == {"successful_repetitions": 2, "failed_repetitions": 0, "concurrent_processes_per_repetition": 2}, history
assert "no remote fetch" in history["scope"], history
assert "history-secret@example.invalid" not in json.dumps(history), history
print("[profile-history] local revision, workload digest, resource samples, and identity isolation OK")
PY

echo "test_profile_history OK"
