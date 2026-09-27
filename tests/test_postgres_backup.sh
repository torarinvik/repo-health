#!/usr/bin/env bash
# End-to-end test of the atomic PostgreSQL/evidence backup driver with a
# deterministic pg_dump stand-in; live database restoration remains opt-in.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-postgres-backup-$PPID-$$"
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

database_url='postgresql://backup-user:secret@example.test/repo_health'
export EXPECTED_DATABASE_URL="$database_url" PG_DUMP_ARGS="$T/pg_dump.args"
PATH="$T/bin:$PATH" RH_DATABASE_URL="$database_url" bash "$ROOT/tools/backup-postgres.sh" "$T/evidence" "$T/backup" >/dev/null || fail "backup workflow"
[[ -f "$T/backup/database.dump" && -f "$T/backup/evidence.manifest" && -f "$T/backup/backup-binding.json" ]] || fail "backup set is incomplete"
! rg -q 'secret|backup-user|example.test' "$T/backup" || fail "connection credentials leaked into backup artifacts"
"$ROOT/build/rh_cli" ops verify-binding --root "$T/evidence" --manifest "$T/backup/evidence.manifest" --database "$T/backup/database.dump" --input "$T/backup/backup-binding.json" >/dev/null || fail "published binding does not verify"
[[ -z "$(find "$T" -maxdepth 1 -name '.repo-health-backup.*' -print -quit)" ]] || fail "staging directory remained after publish"
echo "[postgres-backup] atomic dump, evidence manifest, and binding verified"

set +e
PATH="$T/bin:$PATH" RH_DATABASE_URL="$database_url" PG_DUMP_FAIL=1 bash "$ROOT/tools/backup-postgres.sh" "$T/evidence" "$T/failed-backup" >/dev/null 2>&1
rc_dump=$?
set -e
[[ "$rc_dump" -eq 1 && ! -e "$T/failed-backup" ]] || fail "failed pg_dump published a backup"
[[ "$(cat "$T/pg_dump.args")" != *"$database_url"* ]] || fail "connection URL appeared in pg_dump arguments"
echo "[postgres-backup] failed capture leaves no published backup and credentials stay out of argv"
