#!/usr/bin/env bash
# tests/test_continuity_cli.sh — M04 execution path: `rh_cli continuity`
# turns a pinned scan bundle into continuity.json + continuity-metrics.json.
# Asserts the exact retention ratio for full history, the honest
# `unsupported` state for a windowed scan (first observation cannot be
# established), and that no raw author email leaks into published output.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-continuity"

fail() { echo "[continuity] FAIL: $1" >&2; exit 1; }
ago() { python3 -c 'import time,sys; print(int(time.time())-int(sys.argv[1])*86400)' "$1"; }

echo "[continuity] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T/src"
git init -q -b main "$T/src"
(
  cd "$T/src"
  git config user.name "Dev"
  git config user.email "dev@example.test"
  commit() { # author-name author-email days-ago
    echo "$1 $3" > "f-$1-$3"
    git add "f-$1-$3"
    GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2" \
      GIT_AUTHOR_DATE="@$(ago "$3") +0000" GIT_COMMITTER_DATE="@$(ago "$3") +0000" \
      git commit -qm "$1 $3"
  }
  # alice: retained (returns within 90-120d); bob: not retained; carol:
  # not retained (window complete); dave: censored (window not yet elapsed).
  commit Alice alice@example.test 400
  commit Alice alice@example.test 300
  commit Bob   bob@example.test   400
  commit Carol carol@example.test 200
  commit Dave  dave@example.test  20
)

echo "[continuity] full-history scan -> observed retention"
"$ROOT/build/rh_cli" scan --repo "$T/src" --out "$T/full" --full-history >/dev/null || fail "scan failed"
"$ROOT/build/rh_cli" continuity --bundle "$T/full/bundle.manifest" --out "$T/full-cont" >/dev/null || fail "continuity failed"
CJ="$T/full-cont/continuity.json"; CM="$T/full-cont/continuity-metrics.json"
[[ -f "$CJ" && -f "$CM" ]] || fail "continuity outputs missing"
grep -q '"schema":"rh-continuity/1"' "$CJ" || fail "missing schema"
grep -q '"key":"persistence.retained_90d"' "$CM" || fail "missing metric key"
grep -q '"status":"observed"' "$CM" || fail "expected observed retention"
grep -q '"num":1' "$CM" || fail "expected retained numerator 1"
grep -q '"den":3' "$CM" || fail "expected eligible denominator 3"
grep -q '"censored":1' "$CM" || fail "expected one censored actor"
grep -q '"first_seen_supported":true' "$CM" || fail "full history should support first-seen"
grep -q '"first_observation_basis":"first-ever"' "$CJ" || fail "full history must label first-ever basis"
grep -q '"actors_total":4' "$CM" || fail "expected 4 raw actors"
if grep -q '"first_month_index":0' "$CJ"; then
  fail "first_month_index must be a real calendar month index, not 0"
fi

echo "[continuity] concentration metrics are published with exact values"
python3 - "$CM" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
by = {m["key"]: m for m in d["metrics"]}
# alice 2 commits, bob/carol/dave 1 each -> HHI = 7/25, effective 25/7, 50% -> 2
assert by["concentration.change_hhi"]["status"] == "observed", by
assert by["concentration.change_hhi"]["value"] == {"num": 7, "den": 25}, by["concentration.change_hhi"]
assert by["concentration.change_effective_actor_count"]["value"] == {"num": 25, "den": 7}, by
assert by["concentration.change_absence_factor_50"]["value"] == 2, by
assert by["concentration.top1_event_share"]["value"] == {"num": 2, "den": 5}, by
assert by["concentration.top3_event_share"]["value"] == {"num": 4, "den": 5}, by
assert by["concentration.top5_event_share"]["value"] == {"num": 5, "den": 5}, by
assert by["concentration.hhi"]["value"] == {"num": 7, "den": 25}, by
assert by["concentration.effective_actor_count"]["value"] == {"num": 25, "den": 7}, by
assert by["concentration.absence_factor_50"]["value"] == 2, by
assert by["concentration.actor_count_80"]["value"] == 3, by
assert by["persistence.retained_365d"]["status"] == "observed", by
assert by["persistence.retained_365d"]["value"] == {"num": 0, "den": 2}, by["persistence.retained_365d"]
assert by["persistence.persistent_24m"]["status"] == "unsupported", by["persistence.persistent_24m"]
assert by["persistence.returning_after_gap"]["status"] == "observed", by
assert by["persistence.returning_after_gap"]["value"] == 1, by["persistence.returning_after_gap"]
for key in ("persistence.active_3_of_12_months", "persistence.active_6_of_12_months", "persistence.active_9_of_12_months", "persistence.median_observed_tenure_days"):
    assert by[key]["status"] == "observed", (key, by[key])
assert by["persistence.persistent_event_share"]["value"] == {"num": 0, "den": 5}, by
print("[continuity] concentration values OK")
PY

echo "[continuity] the [9,3] oracle holds on the real path (HHI 5/8, effective 8/5)"
mkdir -p "$T/csrc"
git init -q -b main "$T/csrc"
(
  cd "$T/csrc"; git config user.name Dev; git config user.email dev@example.test
  n=0
  while [[ $n -lt 9 ]]; do echo "a$n" > "a$n"; git add "a$n"; \
    GIT_AUTHOR_NAME=Alice GIT_AUTHOR_EMAIL=alice@example.test GIT_COMMITTER_NAME=Alice GIT_COMMITTER_EMAIL=alice@example.test \
    GIT_AUTHOR_DATE="@$(ago $((300 + n))) +0000" GIT_COMMITTER_DATE="@$(ago $((300 + n))) +0000" git commit -qm "a$n"; n=$((n+1)); done
  n=0
  while [[ $n -lt 3 ]]; do echo "b$n" > "b$n"; git add "b$n"; \
    GIT_AUTHOR_NAME=Bob GIT_AUTHOR_EMAIL=bob@example.test GIT_COMMITTER_NAME=Bob GIT_COMMITTER_EMAIL=bob@example.test \
    GIT_AUTHOR_DATE="@$(ago $((200 + n))) +0000" GIT_COMMITTER_DATE="@$(ago $((200 + n))) +0000" git commit -qm "b$n"; n=$((n+1)); done
)
"$ROOT/build/rh_cli" scan --repo "$T/csrc" --out "$T/c" --full-history >/dev/null || fail "concentration scan"
"$ROOT/build/rh_cli" continuity --bundle "$T/c/bundle.manifest" --out "$T/c-cont" >/dev/null || fail "concentration continuity"
python3 - "$T/c-cont/continuity-metrics.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
by = {m["key"]: m for m in d["metrics"]}
assert by["concentration.change_hhi"]["value"] == {"num": 5, "den": 8}, by["concentration.change_hhi"]
assert by["concentration.change_effective_actor_count"]["value"] == {"num": 8, "den": 5}, by
assert by["concentration.change_absence_factor_50"]["value"] == 1, by
# top-1 share: Alice 9 of 12 commit events -> exact stored rational 9/12
assert by["concentration.change_top1_share"]["value"] == {"num": 9, "den": 12}, by["concentration.change_top1_share"]
print("[continuity] [9,3] oracle OK")
PY

echo "[continuity] privacy: no raw author email in published output"
if grep -q "alice@example.test" "$CJ" "$CM"; then
  fail "raw author email leaked into published report"
fi

echo "[continuity] windowed scan -> unsupported first-seen, not a rate"
"$ROOT/build/rh_cli" scan --repo "$T/src" --out "$T/win" --window-days 365 >/dev/null || fail "windowed scan failed"
"$ROOT/build/rh_cli" continuity --bundle "$T/win/bundle.manifest" --out "$T/win-cont" >/dev/null || fail "windowed continuity failed"
grep -q '"status":"unsupported"' "$T/win-cont/continuity-metrics.json" || fail "windowed must be unsupported"
grep -q '"first_seen_supported":false' "$T/win-cont/continuity-metrics.json" || fail "windowed first-seen flag"
grep -q '"first_observation_basis":"first-observed"' "$T/win-cont/continuity.json" || fail "windowed must label first-observed basis"
# R029: a windowed basis must never imply activity-change claims
grep -q '"basis":"windowed"' "$T/win-cont/continuity.json" || fail "windowed basis label missing"
grep -q '"activity_change_claims_supported":false' "$T/win-cont/continuity.json" || fail "windowed must not support activity-change claims"
python3 - "$T/win-cont/continuity-metrics.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
by = {m["key"]: m for m in d["metrics"]}
for key in ("persistence.active_3_of_12_months", "persistence.active_6_of_12_months", "persistence.active_9_of_12_months", "persistence.persistent_event_share", "persistence.median_observed_tenure_days"):
    assert by[key]["status"] == "partial", (key, by[key])
print("[continuity] persistence window states OK")
PY

echo "[continuity] full scan declares a full coverage basis (R029)"
grep -q '"basis":"full"' "$CJ" || fail "full basis label missing"
grep -q '"activity_change_claims_supported":true' "$CJ" || fail "full basis should support activity-change claims"

echo "[continuity] negative control: missing bundle fails closed"
set +e
"$ROOT/build/rh_cli" continuity --bundle "$T/does-not-exist" --out "$T/none" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 4 ]] || fail "missing bundle must exit 4 (got $rc)"

echo "test_continuity_cli OK"
