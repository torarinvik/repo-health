#!/usr/bin/env bash
# End-to-end test of the atomic PostgreSQL/evidence backup driver with a
# deterministic pg_dump stand-in; live database restoration remains opt-in.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-postgres-backup-$PPID-$$"
EXPECTED_PYTHON="$(command -v python3)"
trap 'rm -rf "$T"' EXIT

fail() { echo "[postgres-backup] FAIL: $1" >&2; exit 1; }

echo "[postgres-backup] build"
bash "$ROOT/tools/build.sh" >/dev/null
mkdir -p "$T/evidence" "$T/bin"
printf 'source evidence\n' > "$T/evidence.txt"
"$ROOT/build/rh_cli" store put --root "$T/evidence" --file "$T/evidence.txt" >/dev/null || fail "store evidence"
cat > "$T/bin/pg_dump" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${PGDATABASE:-}" == "${EXPECTED_DATABASE_URL:-}" ]] || exit 31
[[ "${PG_DUMP_FAIL:-0}" != "1" ]] || exit 32
[[ $# -eq 2 && "$1" == --format=custom && "$2" == --file=* ]] || exit 33
[[ "$*" != *"EXPECTED_DATABASE_URL"* ]] || exit 34
printf 'mock PostgreSQL custom dump\0bytes\n' > "${2#--file=}"
printf '%s\n' "$@" > "$PG_DUMP_ARGS"
SH
chmod +x "$T/bin/pg_dump"
cat > "$T/bin/psql" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${PGDATABASE:-}" == "${EXPECTED_DATABASE_URL:-}" ]] || exit 41
[[ "$*" != *"$EXPECTED_DATABASE_URL"* ]] || exit 42
printf '%s\n' "$*" >> "$PG_TOOL_ARGS"
printf '%s' "${PG_PSQL_OBJECTS:-0}"
SH
cat > "$T/bin/pg_restore" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" != *"$EXPECTED_DATABASE_URL"* ]] || exit 52
printf '%s\n' "$*" >> "$PG_TOOL_ARGS"
if [[ "${1:-}" == "--list" ]]; then
  [[ -f "$2" ]] || exit 53
  exit 0
fi
[[ $# -eq 4 && "$1" == "--dbname=service=repo-health-restore" && "$2" == "--exit-on-error" && "$3" == "--single-transaction" && -f "$4" ]] || exit 54
[[ -f "${PGSERVICEFILE:-}" ]] || exit 55
python3 - "$PGSERVICEFILE" <<'PY'
import os, sys
path = sys.argv[1]
assert os.stat(path).st_mode & 0o777 == 0o600, oct(os.stat(path).st_mode & 0o777)
text = open(path, encoding="utf-8").read()
assert "[repo-health-restore]" in text and "restore-secret" in text and "restored_db" in text, text
PY
SH
chmod +x "$T/bin/psql" "$T/bin/pg_restore"
cat > "$T/bin/python3" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
  [[ "$argument" != *"$EXPECTED_DATABASE_URL"* ]] || exit 61
done
exec "$EXPECTED_PYTHON" "$@"
SH
chmod +x "$T/bin/python3"

database_url='postgresql://backup-user:secret@example.test/repo_health'
export EXPECTED_DATABASE_URL="$database_url" EXPECTED_PYTHON PG_DUMP_ARGS="$T/pg_dump.args" PG_TOOL_ARGS="$T/pg-tool.args"
PATH="$T/bin:$PATH" RH_DATABASE_URL="$database_url" bash "$ROOT/tools/backup-postgres.sh" "$T/evidence" "$T/backup" >/dev/null || fail "backup workflow"
[[ -f "$T/backup/database.dump" && -f "$T/backup/evidence.manifest" && -f "$T/backup/evidence.bundle" && -f "$T/backup/backup-binding.json" ]] || fail "backup set is incomplete"
! rg -q 'secret|backup-user|example.test' "$T/backup" || fail "connection credentials leaked into backup artifacts"
"$ROOT/build/rh_cli" ops verify-binding --root "$T/evidence" --manifest "$T/backup/evidence.manifest" --database "$T/backup/database.dump" --input "$T/backup/backup-binding.json" >/dev/null || fail "published binding does not verify"
"$ROOT/build/rh_cli" ops import --dest "$T/restored-evidence" --input "$T/backup/evidence.bundle" >/dev/null || fail "restore evidence bundle"
"$ROOT/build/rh_cli" ops verify-binding --root "$T/restored-evidence" --manifest "$T/backup/evidence.manifest" --database "$T/backup/database.dump" --input "$T/backup/backup-binding.json" >/dev/null || fail "restored evidence does not verify against database binding"
[[ -z "$(find "$T" -maxdepth 1 -name '.repo-health-backup.*' -print -quit)" ]] || fail "staging directory remained after publish"
echo "[postgres-backup] atomic dump, portable evidence bundle, and binding verified after isolated restore"

restore_url='postgresql://restore-user:restore-secret@example.test/restored_db'
export EXPECTED_DATABASE_URL="$restore_url"
PATH="$T/bin:$PATH" RH_RESTORE_DATABASE_URL="$restore_url" bash "$ROOT/tools/restore-postgres-backup.sh" "$T/backup" "$T/evidence-restored" >/dev/null || fail "restore workflow"
"$ROOT/build/rh_cli" ops verify-binding --root "$T/evidence-restored" --manifest "$T/backup/evidence.manifest" --database "$T/backup/database.dump" --input "$T/backup/backup-binding.json" >/dev/null || fail "restored pair binding"
restore_calls="$(wc -l < "$PG_TOOL_ARGS" | tr -d ' ')"
[[ "$restore_calls" -eq 3 ]] || fail "expected target emptiness check plus dump inspection and restore"
! rg -q 'restore-secret|restore-user|example.test' "$PG_TOOL_ARGS" || fail "restore database URL leaked into command arguments"
echo "[postgres-backup] clean-target restore imports evidence and verifies the restored pair"

set +e
PATH="$T/bin:$PATH" RH_RESTORE_DATABASE_URL="$restore_url" PG_PSQL_OBJECTS=1 bash "$ROOT/tools/restore-postgres-backup.sh" "$T/backup" "$T/dirty-evidence" >/dev/null 2>&1
rc_dirty=$?
set -e
[[ "$rc_dirty" -eq 1 && ! -e "$T/dirty-evidence" ]] || fail "non-empty database must block restore before publication"
[[ "$(wc -l < "$PG_TOOL_ARGS" | tr -d ' ')" -eq 4 ]] || fail "restore touched pg_restore for a non-empty target"
echo "[postgres-backup] non-empty target fails before database restore or evidence publication"

set +e
PATH="$T/bin:$PATH" RH_DATABASE_URL="$database_url" PG_DUMP_FAIL=1 bash "$ROOT/tools/backup-postgres.sh" "$T/evidence" "$T/failed-backup" >/dev/null 2>&1
rc_dump=$?
set -e
[[ "$rc_dump" -eq 1 && ! -e "$T/failed-backup" ]] || fail "failed pg_dump published a backup"
[[ "$(cat "$T/pg_dump.args")" != *"$database_url"* ]] || fail "connection URL appeared in pg_dump arguments"
echo "[postgres-backup] failed capture leaves no published backup and credentials stay out of argv"
