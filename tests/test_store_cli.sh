#!/usr/bin/env bash
# tests/test_store_cli.sh — M02 store + M07 ops execution paths:
# `rh_cli store put|verify` and `rh_cli ops backup|verify|restore`. Asserts
# content addressing + digest verification fail closed on missing/corrupt
# evidence, a clean backup verifies, restore copies only verified objects,
# and missing objects are counted separately from corrupt ones.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-store"

fail() { echo "[store] FAIL: $1" >&2; exit 1; }

echo "[store] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T/ev" "$T/restore"
printf 'hello evidence\n' > "$T/a.txt"
printf 'second object\n' > "$T/b.txt"
"$ROOT/build/rh_cli" store put --root "$T/ev" --file "$T/a.txt" >/dev/null || fail "put a"
"$ROOT/build/rh_cli" store put --root "$T/ev" --file "$T/b.txt" >/dev/null || fail "put b"
"$ROOT/build/rh_cli" store put --root "$T/ev" --file "$T/a.txt" >/dev/null || fail "put a idempotent"
names=($(ls "$T/ev"))
[[ "${#names[@]}" -eq 2 ]] || fail "expected two blobs (got ${#names[@]})"

echo "[store] concurrent identical puts publish one complete immutable blob"
mkdir -p "$T/race"
pids=()
for worker in {1..12}; do
  "$ROOT/build/rh_cli" store put --root "$T/race" --file "$T/a.txt" >"$T/race-$worker.log" 2>&1 &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid" || fail "concurrent put $pid"
done
[[ "$(find "$T/race" -type f ! -name '.rh-evidence.lock' | wc -l | tr -d ' ')" -eq 1 ]] || fail "concurrent puts left multiple published objects"
[[ -z "$(find "$T/race" -name '*.stage.*' -print -quit)" ]] || fail "concurrent puts left a staging object"
race_name="$(basename "$(find "$T/race" -type f ! -name '.rh-evidence.lock' -print -quit)")"
"$ROOT/build/rh_cli" store verify --root "$T/race" --name "$race_name" >/dev/null || fail "concurrent published blob does not verify"

echo "[store] verify a stored blob; missing name fails closed"
"$ROOT/build/rh_cli" store verify --root "$T/ev" --name "${names[0]}" >/dev/null || fail "verify present"
set +e
"$ROOT/build/rh_cli" store verify --root "$T/ev" --name 0000000000000000 >/dev/null 2>&1
rc_missing=$?
set -e
[[ "$rc_missing" -eq 5 ]] || fail "missing blob must exit 5 (got $rc_missing)"

echo "[store] backup manifest + clean verify"
printf '%s\n' "${names[@]}" > "$T/names.txt"
"$ROOT/build/rh_cli" ops backup --root "$T/ev" --manifest "$T/backup.manifest" --names "$T/names.txt" >/dev/null || fail "backup"
grep -q "rh-backup/1 fnv1a-64-hex" "$T/backup.manifest" || fail "manifest header"
"$ROOT/build/rh_cli" ops verify --root "$T/ev" --manifest "$T/backup.manifest" | grep -q "verified=2 missing=0 corrupt=0" || fail "clean verify"

echo "[store] restore copies only verified objects"
"$ROOT/build/rh_cli" ops restore --root "$T/ev" --dest "$T/restore" --manifest "$T/backup.manifest" | grep -q "restored=2" || fail "restore count"
for n in "${names[@]}"; do
  [[ -f "$T/restore/$n" ]] || fail "restored object $n missing"
  "$ROOT/build/rh_cli" store verify --root "$T/restore" --name "$n" >/dev/null || fail "restored $n does not verify"
done
"$ROOT/build/rh_cli" ops restore --root "$T/ev" --dest "$T/restore" --manifest "$T/backup.manifest" | grep -q "restored=2" || fail "idempotent restore into populated destination"
echo "[store] repeated distribution is idempotent and no-clobber"

printf 'preserve this file\n' > "$T/outside"
printf 'rh-backup/1 fnv1a-64-hex\n../outside\n' > "$T/path-traversal.manifest"
set +e
"$ROOT/build/rh_cli" ops restore --root "$T/ev" --dest "$T/restore" --manifest "$T/path-traversal.manifest" >/dev/null 2>&1
rc_traversal=$?
set -e
[[ "$rc_traversal" -eq 4 ]] || fail "path-like backup name must fail closed (got $rc_traversal)"
[[ "$(cat "$T/outside")" == "preserve this file" ]] || fail "restore changed a path outside the evidence root"

mkdir -p "$T/restore-conflict"
printf 'destination conflict\n' > "$T/restore-conflict/${names[0]}"
set +e
"$ROOT/build/rh_cli" ops restore --root "$T/ev" --dest "$T/restore-conflict" --manifest "$T/backup.manifest" >/dev/null 2>&1
rc_conflict=$?
set -e
[[ "$rc_conflict" -eq 4 ]] || fail "conflicting destination object must fail closed (got $rc_conflict)"
[[ "$(cat "$T/restore-conflict/${names[0]}")" == "destination conflict" ]] || fail "restore overwrote a conflicting destination object"

echo "[store] corrupt evidence fails closed"
printf 'X' >> "$T/ev/${names[0]}"
set +e
"$ROOT/build/rh_cli" ops verify --root "$T/ev" --manifest "$T/backup.manifest" >/dev/null 2>&1
rc_corrupt=$?
set -e
[[ "$rc_corrupt" -eq 5 ]] || fail "corrupt evidence must exit 5 (got $rc_corrupt)"
# A corrupt object is skipped by restore (never silently becomes live).
rm -rf "$T/restore2"; mkdir -p "$T/restore2"
"$ROOT/build/rh_cli" ops restore --root "$T/ev" --dest "$T/restore2" --manifest "$T/backup.manifest" | grep -q "restored=1" || fail "restore must skip the corrupt object"

echo "[store] missing object is counted missing, not corrupt"
rm -f "$T/ev/${names[1]}"
out="$("$ROOT/build/rh_cli" ops verify --root "$T/ev" --manifest "$T/backup.manifest" 2>/dev/null || true)"
case "$out" in
  "ops verify: verified=0 missing=1 corrupt=1") : ;;
  *) fail "expected one missing and one corrupt, got: $out" ;;
esac

printf '../outside\n' > "$T/path-like-names.txt"
if "$ROOT/build/rh_cli" ops backup --root "$T/ev" --manifest "$T/path-like-backup.manifest" --names "$T/path-like-names.txt" >/dev/null 2>&1; then
  fail "backup accepted a path-like blob name"
fi
[[ ! -e "$T/path-like-backup.manifest" ]] || fail "invalid backup names wrote a manifest"

echo "[store] negatives fail closed"
set +e
"$ROOT/build/rh_cli" ops backup --root "$T/ev" --manifest "$T/m.manifest" --names "$T/nope.txt" >/dev/null 2>&1; rc1=$?
"$ROOT/build/rh_cli" ops verify --root "$T/ev" --manifest "$T/nope.manifest" >/dev/null 2>&1; rc2=$?
"$ROOT/build/rh_cli" ops restore --root "$T/ev" --dest "$T/x" --manifest "$T/nope.manifest" >/dev/null 2>&1; rc3=$?
"$ROOT/build/rh_cli" store put --root "$T/ev" --file "$T/nope.txt" >/dev/null 2>&1; rc4=$?
set -e
for rc in "$rc1" "$rc2" "$rc3" "$rc4"; do
  [[ "$rc" -eq 4 ]] || fail "missing input must exit 4 (got $rc)"
done

echo "[store] portable transfer crosses isolated store roots"
mkdir -p "$T/transfer-source"
printf 'binary\0evidence\nwith newline\n' > "$T/transfer-a.bin"
printf 'second transfer object\n' > "$T/transfer-b.bin"
transfer_a="$("$ROOT/build/rh_cli" store put --root "$T/transfer-source" --file "$T/transfer-a.bin" | awk '{print $3}')"
transfer_b="$("$ROOT/build/rh_cli" store put --root "$T/transfer-source" --file "$T/transfer-b.bin" | awk '{print $3}')"
printf '%s\n%s\n' "$transfer_a" "$transfer_b" | sort > "$T/transfer-names.txt"
"$ROOT/build/rh_cli" ops backup --root "$T/transfer-source" --manifest "$T/transfer.manifest" --names "$T/transfer-names.txt" >/dev/null || fail "transfer backup manifest"
"$ROOT/build/rh_cli" ops export --root "$T/transfer-source" --manifest "$T/transfer.manifest" --out "$T/evidence.bundle" >/dev/null || fail "portable export"
grep -a -q "rh-evidence-transfer/1 fnv1a-64-hex" "$T/evidence.bundle" || fail "transfer package version header"
"$ROOT/build/rh_cli" ops import --dest "$T/transfer-destination" --input "$T/evidence.bundle" | grep -q "imported=2" || fail "portable import count"
for n in "$transfer_a" "$transfer_b"; do
  "$ROOT/build/rh_cli" store verify --root "$T/transfer-destination" --name "$n" >/dev/null || fail "transferred blob $n does not verify"
done
cmp "$T/transfer-a.bin" "$T/transfer-destination/$transfer_a" || fail "binary transfer changed NUL/newline bytes"
cmp "$T/transfer-b.bin" "$T/transfer-destination/$transfer_b" || fail "text transfer changed bytes"
"$ROOT/build/rh_cli" ops import --dest "$T/transfer-destination" --input "$T/evidence.bundle" | grep -q "imported=2" || fail "repeated portable import"

echo "[store] damaged package is rejected before publishing any object"
cp "$T/evidence.bundle" "$T/damaged.bundle"
bundle_size="$(wc -c < "$T/damaged.bundle" | tr -d ' ')"
printf X | dd of="$T/damaged.bundle" bs=1 seek="$((bundle_size - 2))" conv=notrunc status=none
set +e
"$ROOT/build/rh_cli" ops import --dest "$T/damaged-destination" --input "$T/damaged.bundle" >/dev/null 2>&1
rc_damaged=$?
set -e
[[ "$rc_damaged" -eq 4 ]] || fail "damaged package must fail closed (got $rc_damaged)"
for n in "$transfer_a" "$transfer_b"; do
  set +e
  "$ROOT/build/rh_cli" store verify --root "$T/damaged-destination" --name "$n" >/dev/null 2>&1
  rc_unpublished=$?
  set -e
  [[ "$rc_unpublished" -eq 5 ]] || fail "damaged package partially published $n"
done

echo "test_store_cli OK"
