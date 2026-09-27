#!/usr/bin/env bash
# Capture one PostgreSQL dump and its exact verified content-addressed evidence
# manifest as an atomically published backup directory.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "postgres-backup: $1" >&2; exit 1; }

[[ $# -eq 2 ]] || fail "usage: tools/backup-postgres.sh <evidence-root> <new-backup-directory>"
EVIDENCE_ROOT="$1"
BACKUP_DIR="$2"
[[ -n "${RH_DATABASE_URL:-}" ]] || fail "RH_DATABASE_URL must be set in the environment"
command -v pg_dump >/dev/null 2>&1 || fail "pg_dump not found"
[[ -x "$ROOT/build/rh_cli" ]] || fail "build/rh_cli is missing; run tools/build.sh first"
[[ -d "$EVIDENCE_ROOT" ]] || fail "evidence root is not a directory"
[[ ! -e "$BACKUP_DIR" && ! -L "$BACKUP_DIR" ]] || fail "backup destination already exists"

umask 077
mkdir -p -- "$(dirname -- "$BACKUP_DIR")"
PARENT="$(cd -- "$(dirname -- "$BACKUP_DIR")" && pwd)"
DEST="$PARENT/$(basename -- "$BACKUP_DIR")"
[[ ! -e "$DEST" && ! -L "$DEST" ]] || fail "backup destination already exists"
STAGE="$(mktemp -d "$PARENT/.repo-health-backup.XXXXXX")"
cleanup() { [[ -z "$STAGE" ]] || rm -rf -- "$STAGE"; }
trap cleanup EXIT
trap 'exit 1' INT TERM

python3 - "$EVIDENCE_ROOT" "$STAGE/evidence.names" <<'PY'
import os
import re
import sys

root, output = sys.argv[1:]
names = []
for entry in os.scandir(root):
    if not re.fullmatch(r"[0-9a-f]{16}", entry.name):
        continue
    if entry.is_symlink() or not entry.is_file(follow_symlinks=False):
        raise SystemExit("postgres-backup: content key is not a regular file: " + entry.name)
    names.append(entry.name)
with open(output, "w", encoding="ascii", newline="\n") as stream:
    stream.writelines(name + "\n" for name in sorted(names))
PY

# PGDATABASE keeps connection details out of pg_dump's argument list.
PGDATABASE="$RH_DATABASE_URL" pg_dump --format=custom --file="$STAGE/database.dump" || fail "pg_dump failed"
"$ROOT/build/rh_cli" ops backup --root "$EVIDENCE_ROOT" --manifest "$STAGE/evidence.manifest" --names "$STAGE/evidence.names" >/dev/null || fail "evidence manifest creation failed"
"$ROOT/build/rh_cli" ops verify --root "$EVIDENCE_ROOT" --manifest "$STAGE/evidence.manifest" >/dev/null || fail "evidence verification failed"
"$ROOT/build/rh_cli" ops export --root "$EVIDENCE_ROOT" --manifest "$STAGE/evidence.manifest" --out "$STAGE/evidence.bundle" >/dev/null || fail "evidence bundle creation failed"
"$ROOT/build/rh_cli" ops bind --root "$EVIDENCE_ROOT" --manifest "$STAGE/evidence.manifest" --database "$STAGE/database.dump" --out "$STAGE/backup-binding.json" >/dev/null || fail "database/evidence binding failed"
"$ROOT/build/rh_cli" ops verify-binding --root "$EVIDENCE_ROOT" --manifest "$STAGE/evidence.manifest" --database "$STAGE/database.dump" --input "$STAGE/backup-binding.json" >/dev/null || fail "database/evidence binding verification failed"
rm -f -- "$STAGE/evidence.names"
mv -- "$STAGE" "$DEST" || fail "cannot publish backup directory"
STAGE=""
echo "postgres-backup: verified backup published at $DEST"
