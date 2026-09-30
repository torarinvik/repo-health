#!/usr/bin/env bash
# tests/test_store_cli.sh — M02 store + M07 ops execution paths:
# `rh_cli store put|verify` and `rh_cli ops backup|verify|restore`. Asserts
# content addressing + digest verification fail closed on missing/corrupt
# evidence, a clean backup verifies, restore copies only verified objects,
# and missing objects are counted separately from corrupt ones.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-store-$PPID-$$"
trap 'rm -rf "$T"' EXIT

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
concurrent_failure=0
for index in "${!pids[@]}"; do
  if ! wait "${pids[$index]}"; then
    echo "[store] concurrent worker ${index} failed:" >&2
    cat "$T/race-$((index + 1)).log" >&2
    concurrent_failure=1
  fi
done
[[ "$concurrent_failure" -eq 0 ]] || fail "concurrent identical put worker failed"
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

echo "[store] restored evidence reproduces a pinned identity report"
mkdir -p "$T/replay-source" "$T/replay-restored"
cat > "$T/replay-input.json" <<'JSON'
{"schema":"rh-identity-input/1","actor_count":3,"links":[{"a":0,"b":1,"state":"accepted","revision_added":1}],"actor_kinds":["human","human","unresolved"]}
JSON
replay_name="$("$ROOT/build/rh_cli" store put --root "$T/replay-source" --file "$T/replay-input.json" | awk '{print $3}')"
printf '%s\n' "$replay_name" > "$T/replay-names.txt"
"$ROOT/build/rh_cli" ops backup --root "$T/replay-source" --manifest "$T/replay.manifest" --names "$T/replay-names.txt" >/dev/null || fail "replay backup"
"$ROOT/build/rh_cli" ops verify --root "$T/replay-source" --manifest "$T/replay.manifest" | grep -q "verified=1 missing=0 corrupt=0" || fail "replay backup verification"
"$ROOT/build/rh_cli" ops restore --root "$T/replay-source" --dest "$T/replay-restored" --manifest "$T/replay.manifest" >/dev/null || fail "replay restore"
"$ROOT/build/rh_cli" identity --input "$T/replay-input.json" --out "$T/replay-original.out" >/dev/null || fail "original replay report"
"$ROOT/build/rh_cli" identity --input "$T/replay-restored/$replay_name" --out "$T/replay-restored.out" >/dev/null || fail "restored replay report"
cmp -s "$T/replay-original.out" "$T/replay-restored.out" || fail "restored evidence changed pinned report output"

echo "[store] database snapshot binds to an exact verified evidence manifest"
printf 'postgres dump snapshot\000v1\n' > "$T/database.snapshot"
"$ROOT/build/rh_cli" ops bind --root "$T/replay-source" --manifest "$T/replay.manifest" --database "$T/database.snapshot" --out "$T/backup-binding.json" >/dev/null || fail "create backup binding"
"$ROOT/build/rh_cli" ops verify-binding --root "$T/replay-source" --manifest "$T/replay.manifest" --database "$T/database.snapshot" --input "$T/backup-binding.json" >/dev/null || fail "verify backup binding"
python3 - "$T/database.snapshot" "$T/replay.manifest" "$T/backup-binding.json" <<'PY'
import hashlib, json, sys
database, manifest, binding = sys.argv[1:]
d = json.load(open(binding))
assert d == {
    "schema": "rh-backup-binding/1",
    "database_snapshot_sha256": hashlib.sha256(open(database, "rb").read()).hexdigest(),
    "evidence_manifest_sha256": hashlib.sha256(open(manifest, "rb").read()).hexdigest(),
    "evidence_object_count": 1,
}, d
print("[store] database/evidence pair is digest-bound")
PY
printf ' changed' >> "$T/database.snapshot"
set +e
"$ROOT/build/rh_cli" ops verify-binding --root "$T/replay-source" --manifest "$T/replay.manifest" --database "$T/database.snapshot" --input "$T/backup-binding.json" >/dev/null 2>&1; rc_binding=$?
set -e
[[ "$rc_binding" -eq 5 ]] || fail "changed database snapshot must fail binding verification (got $rc_binding)"

echo "[store] binding streams a database dump beyond the 64 MiB read bound"
python3 - "$T/large-database.snapshot" "$T/large-database.sha256" <<'PY'
import hashlib, sys
path, digest_path = sys.argv[1:]
block = bytes((index * 31 + 7) & 255 for index in range(65536))
remaining = 67108864 + 257
digest = hashlib.sha256()
with open(path, "wb") as output:
    while remaining >= len(block):
        output.write(block)
        digest.update(block)
        remaining -= len(block)
    if remaining:
        tail = block[:remaining]
        output.write(tail)
        digest.update(tail)
open(digest_path, "w").write(digest.hexdigest())
PY
"$ROOT/build/rh_cli" ops bind --root "$T/replay-source" --manifest "$T/replay.manifest" --database "$T/large-database.snapshot" --out "$T/large-binding.json" >/dev/null || fail "bind large database dump"
"$ROOT/build/rh_cli" ops verify-binding --root "$T/replay-source" --manifest "$T/replay.manifest" --database "$T/large-database.snapshot" --input "$T/large-binding.json" >/dev/null || fail "verify large database dump binding"
python3 - "$T/large-database.snapshot" "$T/large-database.sha256" "$T/replay.manifest" "$T/large-binding.json" <<'PY'
import hashlib, json, sys
database, digest_path, manifest, binding = sys.argv[1:]
with open(digest_path) as expected:
    expected_database_sha = expected.read()
assert json.load(open(binding)) == {
    "schema": "rh-backup-binding/1",
    "database_snapshot_sha256": expected_database_sha,
    "evidence_manifest_sha256": hashlib.sha256(open(manifest, "rb").read()).hexdigest(),
    "evidence_object_count": 1,
}
print("[store] streamed dump digest matches independent SHA-256 oracle")
PY
python3 - "$T/padding-boundary.snapshot" <<'PY'
import sys
open(sys.argv[1], "wb").write(bytes(range(60)))
PY
"$ROOT/build/rh_cli" ops bind --root "$T/replay-source" --manifest "$T/replay.manifest" --database "$T/padding-boundary.snapshot" --out "$T/padding-boundary-binding.json" >/dev/null || fail "bind SHA-256 two-block padding boundary"
python3 - "$T/padding-boundary.snapshot" "$T/replay.manifest" "$T/padding-boundary-binding.json" <<'PY'
import hashlib, json, sys
database, manifest, binding = sys.argv[1:]
assert json.load(open(binding))["database_snapshot_sha256"] == hashlib.sha256(open(database, "rb").read()).hexdigest()
print("[store] streaming SHA-256 two-block padding matches oracle")
PY
python3 - "$T/large-database.snapshot" <<'PY'
import sys
with open(sys.argv[1], "r+b") as dump:
    dump.seek(-1, 2)
    byte = dump.read(1)
    dump.seek(-1, 2)
    dump.write(bytes([byte[0] ^ 1]))
PY
set +e
"$ROOT/build/rh_cli" ops verify-binding --root "$T/replay-source" --manifest "$T/replay.manifest" --database "$T/large-database.snapshot" --input "$T/large-binding.json" >/dev/null 2>&1; rc_large_tamper=$?
set -e
[[ "$rc_large_tamper" -eq 5 ]] || fail "tampered large dump must fail binding verification (got $rc_large_tamper)"

printf 'preserve this file\n' > "$T/outside"
printf 'rh-backup/1 fnv1a-64-hex\n../outside\n' > "$T/path-traversal.manifest"
set +e
"$ROOT/build/rh_cli" ops restore --root "$T/ev" --dest "$T/restore" --manifest "$T/path-traversal.manifest" >/dev/null 2>&1
rc_traversal=$?
set -e
[[ "$rc_traversal" -eq 4 ]] || fail "path-like backup name must fail closed (got $rc_traversal)"
[[ "$(cat "$T/outside")" == "preserve this file" ]] || fail "restore changed a path outside the evidence root"

echo "[store] duplicate and unsorted backup names fail before restore"
printf 'rh-backup/1 fnv1a-64-hex\n%s\n%s\n' "${names[0]}" "${names[0]}" > "$T/duplicate.manifest"
printf 'rh-backup/1 fnv1a-64-hex\n%s\n%s\n' "${names[1]}" "${names[0]}" > "$T/unsorted.manifest"
mkdir -p "$T/reject-duplicate" "$T/reject-unsorted"
set +e
"$ROOT/build/rh_cli" ops restore --root "$T/ev" --dest "$T/reject-duplicate" --manifest "$T/duplicate.manifest" >/dev/null 2>&1; rc_duplicate=$?
"$ROOT/build/rh_cli" ops restore --root "$T/ev" --dest "$T/reject-unsorted" --manifest "$T/unsorted.manifest" >/dev/null 2>&1; rc_unsorted=$?
set -e
[[ "$rc_duplicate" -eq 4 && "$rc_unsorted" -eq 4 ]] || fail "noncanonical backup names must fail closed ($rc_duplicate/$rc_unsorted)"
[[ -z "$(find "$T/reject-duplicate" -type f -print -quit)" && -z "$(find "$T/reject-unsorted" -type f -print -quit)" ]] || fail "invalid manifests partially restored objects"

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

echo "[store] optional detached signature authenticates transfer before publication"
printf 'operator transfer signing key 0123456789abcdef' > "$T/transfer.key"
chmod 600 "$T/transfer.key"
"$ROOT/build/rh_cli" ops export --root "$T/transfer-source" --manifest "$T/transfer.manifest" --out "$T/signed.bundle" --key "$T/transfer.key" --sig "$T/signed.bundle.sig" >/dev/null || fail "signed portable export"
cp "$T/transfer.manifest" "$T/transfer.manifest.before-collision"
set +e
"$ROOT/build/rh_cli" ops export --root "$T/transfer-source" --manifest "$T/transfer.manifest" --out "$T/signed.bundle" --key "$T/transfer.key" --sig "$T/transfer.manifest" >/dev/null 2>&1
rc_manifest_collision=$?
set -e
[[ "$rc_manifest_collision" -eq 3 ]] || fail "signature output must not overwrite the manifest"
cmp -s "$T/transfer.manifest" "$T/transfer.manifest.before-collision" || fail "signature path collision modified the manifest"
"$ROOT/build/rh_cli" ops import --dest "$T/signed-destination" --input "$T/signed.bundle" --key "$T/transfer.key" --sig "$T/signed.bundle.sig" >/dev/null || fail "authenticated portable import"
for n in "$transfer_a" "$transfer_b"; do
  "$ROOT/build/rh_cli" store verify --root "$T/signed-destination" --name "$n" >/dev/null || fail "authenticated transfer blob $n does not verify"
done
cp "$T/signed.bundle" "$T/signed-tampered.bundle"
printf X | dd of="$T/signed-tampered.bundle" bs=1 seek=45 conv=notrunc status=none
set +e
"$ROOT/build/rh_cli" ops import --dest "$T/signed-tampered-destination" --input "$T/signed-tampered.bundle" --key "$T/transfer.key" --sig "$T/signed.bundle.sig" >/dev/null 2>&1
rc_signature=$?
set -e
[[ "$rc_signature" -eq 4 ]] || fail "tampered signed package must fail before import (got $rc_signature)"
for n in "$transfer_a" "$transfer_b"; do
  set +e
  "$ROOT/build/rh_cli" store verify --root "$T/signed-tampered-destination" --name "$n" >/dev/null 2>&1
  rc_signed_unpublished=$?
  set -e
  [[ "$rc_signed_unpublished" -eq 5 ]] || fail "tampered signed package partially published $n"
done

echo "[store] ops delete removes one validated evidence object and is idempotent"
mkdir -p "$T/delete-store"
"$ROOT/build/rh_cli" store put --root "$T/delete-store" --file "$T/transfer-a.bin" > "$T/delete-put.out" || fail "prepare deletable evidence"
delete_name="$(awk '{print $3}' "$T/delete-put.out")"
"$ROOT/build/rh_cli" ops delete --root "$T/delete-store" --name "$delete_name" | grep -q "deleted or already absent" || fail "delete existing evidence"
[[ ! -e "$T/delete-store/$delete_name" ]] || fail "delete left evidence object"
"$ROOT/build/rh_cli" ops delete --root "$T/delete-store" --name "$delete_name" >/dev/null || fail "repeat deletion should be idempotent"
set +e
"$ROOT/build/rh_cli" store verify --root "$T/delete-store" --name "$delete_name" >/dev/null 2>&1
rc_deleted=$?
"$ROOT/build/rh_cli" ops delete --root "$T/delete-store" --name ../outside >/dev/null 2>&1
rc_delete_traversal=$?
set -e
[[ "$rc_deleted" -eq 5 ]] || fail "deleted evidence must verify as missing (got $rc_deleted)"
[[ "$rc_delete_traversal" -eq 4 ]] || fail "path-like deletion key must fail closed (got $rc_delete_traversal)"
[[ "$(cat "$T/outside")" == "preserve this file" ]] || fail "delete changed a path outside the evidence root"
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
