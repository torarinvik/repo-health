#!/usr/bin/env bash
# Verify and restore one repo-health PostgreSQL/evidence backup into a clean
# target database and a new evidence directory.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "postgres-restore: $1" >&2; exit 1; }

[[ $# -eq 2 ]] || fail "usage: tools/restore-postgres-backup.sh <backup-directory> <new-evidence-directory>"
BACKUP_DIR="$1"
EVIDENCE_DEST="$2"
[[ -n "${RH_RESTORE_DATABASE_URL:-}" ]] || fail "RH_RESTORE_DATABASE_URL must be set in the environment"
command -v psql >/dev/null 2>&1 || fail "psql not found"
command -v pg_restore >/dev/null 2>&1 || fail "pg_restore not found"
[[ -f "$BACKUP_DIR/database.dump" && -f "$BACKUP_DIR/evidence.manifest" && -f "$BACKUP_DIR/evidence.bundle" && -f "$BACKUP_DIR/backup-binding.json" ]] || fail "backup directory is incomplete"
[[ ! -e "$EVIDENCE_DEST" && ! -L "$EVIDENCE_DEST" ]] || fail "evidence destination already exists"

umask 077
mkdir -p -- "$(dirname -- "$EVIDENCE_DEST")"
PARENT="$(cd -- "$(dirname -- "$EVIDENCE_DEST")" && pwd)"
DEST="$PARENT/$(basename -- "$EVIDENCE_DEST")"
[[ ! -e "$DEST" && ! -L "$DEST" ]] || fail "evidence destination already exists"
STAGE="$(mktemp -d "$PARENT/.repo-health-restore.XXXXXX")"
cleanup() { [[ -z "$STAGE" ]] || rm -rf -- "$STAGE"; }
trap cleanup EXIT
trap 'exit 1' INT TERM

"$ROOT/build/rh_cli" ops import --dest "$STAGE/evidence" --input "$BACKUP_DIR/evidence.bundle" >/dev/null || fail "evidence bundle verification failed"
"$ROOT/build/rh_cli" ops verify-binding --root "$STAGE/evidence" --manifest "$BACKUP_DIR/evidence.manifest" --database "$BACKUP_DIR/database.dump" --input "$BACKUP_DIR/backup-binding.json" >/dev/null || fail "database/evidence binding verification failed"

# Refuse a non-empty target before pg_restore. The connection URL stays in the
# environment, not the command line. The operator must create a fresh database.
USER_OBJECTS="$(PGDATABASE="$RH_RESTORE_DATABASE_URL" psql --tuples-only --no-align --set=ON_ERROR_STOP=1 --command="SELECT count(*) FROM (SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast') UNION ALL SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') UNION ALL SELECT t.oid FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast') AND t.typtype IN ('e', 'd', 'c', 'r')) AS user_objects;")" || fail "cannot check target database"
[[ "$USER_OBJECTS" == "0" ]] || fail "target database is not empty"
pg_restore --list "$BACKUP_DIR/database.dump" >/dev/null || fail "database dump is not a readable custom-format archive"
PGDATABASE="$RH_RESTORE_DATABASE_URL" pg_restore --exit-on-error --single-transaction "$BACKUP_DIR/database.dump" || fail "database restore failed"
mv -- "$STAGE/evidence" "$DEST" || fail "cannot publish restored evidence"
STAGE=""
"$ROOT/build/rh_cli" ops verify-binding --root "$DEST" --manifest "$BACKUP_DIR/evidence.manifest" --database "$BACKUP_DIR/database.dump" --input "$BACKUP_DIR/backup-binding.json" >/dev/null || fail "restored database/evidence binding does not verify"
echo "postgres-restore: verified evidence restored at $DEST; database restore completed"
