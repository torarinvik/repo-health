#!/usr/bin/env bash
# Exercise the production PostgreSQL/evidence backup and restore drivers
# against an ephemeral PostgreSQL 16 instance. The ordinary mock-client test
# remains dependency-free; set RH_PG_BACKUP_LIVE=1 to run this gate.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${RH_PG_BACKUP_IMAGE:-postgres:16-alpine}"
CONTAINER="rh-backup-live-${$}"
T="$(mktemp -d "/tmp/${CONTAINER}.XXXXXX")"

fail() { echo "[postgres-backup-live] FAIL: $1" >&2; exit 1; }
cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf -- "$T"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

if [[ "${RH_PG_BACKUP_LIVE:-0}" != "1" ]]; then
  echo "[postgres-backup-live] skipped (RH_PG_BACKUP_LIVE!=1)"
  exit 0
fi

command -v docker >/dev/null 2>&1 || fail "docker is required"
docker info >/dev/null 2>&1 || fail "docker daemon is unavailable"
docker image inspect "$IMAGE" >/dev/null 2>&1 || fail "image is unavailable: $IMAGE"
bash "$ROOT/tools/build.sh" >/dev/null || fail "build"

mkdir -p "$T/bin" "$T/evidence"
docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=repo-health-test -e POSTGRES_DB=repo_health "$IMAGE" >/dev/null || fail "container start"
ready_checks=0
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready -U postgres -d repo_health >/dev/null 2>&1; then
    ready_checks=$((ready_checks + 1))
    [[ "$ready_checks" -ge 3 ]] && break
  else
    ready_checks=0
  fi
  sleep 1
done
[[ "$ready_checks" -ge 3 ]] || fail "PostgreSQL did not become ready"
created=0
for _ in $(seq 1 15); do
  if docker exec "$CONTAINER" createdb -U postgres repo_health_restored >/dev/null 2>&1; then
    created=1
    break
  fi
  sleep 1
done
[[ "$created" == 1 ]] || fail "create clean restore database"
docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d repo_health <<'SQL' >/dev/null || fail "seed source database"
CREATE TABLE backup_probe (id integer PRIMARY KEY, value text NOT NULL);
INSERT INTO backup_probe VALUES (1, 'backup-and-restore-verified');
SQL

cat > "$T/bin/pg_dump" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${PGDATABASE:-}" == "postgresql://backup.test/repo_health" ]] || exit 31
[[ $# -eq 2 && "$1" == "--format=custom" && "$2" == --file=* ]] || exit 32
output="${2#--file=}"
inside="/tmp/${CONTAINER_NAME}.database.dump"
docker exec "$CONTAINER_NAME" pg_dump -U postgres -d repo_health --format=custom --file="$inside"
docker cp "$CONTAINER_NAME:$inside" "$output" >/dev/null
SH

cat > "$T/bin/psql" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${PGDATABASE:-}" == "postgresql:///repo_health_restored?user=postgres" ]] || exit 41
docker exec "$CONTAINER_NAME" psql -U postgres -d repo_health_restored "$@"
SH

cat > "$T/bin/pg_restore" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
inside="/tmp/${CONTAINER_NAME}.database.restore.dump"
if [[ "${1:-}" == "--list" ]]; then
  [[ $# -eq 2 && -f "$2" ]] || exit 52
  docker cp "$2" "$CONTAINER_NAME:$inside" >/dev/null
  docker exec "$CONTAINER_NAME" pg_restore --list "$inside" >/dev/null
  exit $?
fi
[[ $# -eq 4 && "$1" == "--dbname=service=repo-health-restore" && "$2" == "--exit-on-error" && "$3" == "--single-transaction" && -f "$4" ]] || exit 53
service_inside="/tmp/${CONTAINER_NAME}.restore.pg_service.conf"
docker cp "$4" "$CONTAINER_NAME:$inside" >/dev/null
docker cp "$PGSERVICEFILE" "$CONTAINER_NAME:$service_inside" >/dev/null
docker exec -e PGSERVICEFILE="$service_inside" "$CONTAINER_NAME" pg_restore --dbname=service=repo-health-restore --exit-on-error --single-transaction "$inside"
SH
chmod +x "$T/bin/pg_dump" "$T/bin/psql" "$T/bin/pg_restore"
export CONTAINER_NAME="$CONTAINER"

cat > "$T/identity-input.json" <<'JSON'
{"schema":"rh-identity-input/1","actor_count":3,"links":[{"a":0,"b":1,"state":"accepted","revision_added":1}],"actor_kinds":["human","human","unresolved"]}
JSON
evidence_name="$("$ROOT/build/rh_cli" store put --root "$T/evidence" --file "$T/identity-input.json" | awk '{print $3}')"
[[ "$evidence_name" =~ ^[0-9a-f]{16}$ ]] || fail "store evidence input"
printf '%s\n' "$evidence_name" > "$T/evidence.names"

echo "[postgres-backup-live] create a linked database/evidence backup"
PATH="$T/bin:$PATH" RH_DATABASE_URL=postgresql://backup.test/repo_health bash "$ROOT/tools/backup-postgres.sh" "$T/evidence" "$T/backup" >/dev/null || fail "backup workflow"
[[ -s "$T/backup/database.dump" && -s "$T/backup/evidence.bundle" ]] || fail "backup artifacts are empty"

echo "[postgres-backup-live] restore into a clean PostgreSQL database and evidence root"
PATH="$T/bin:$PATH" RH_RESTORE_DATABASE_URL='postgresql:///repo_health_restored?user=postgres' bash "$ROOT/tools/restore-postgres-backup.sh" "$T/backup" "$T/evidence-restored" >/dev/null || fail "restore workflow"
restored_row="$(docker exec "$CONTAINER" psql -At -U postgres -d repo_health_restored -c "SELECT id::text || ':' || value FROM backup_probe ORDER BY id")"
[[ "$restored_row" == "1:backup-and-restore-verified" ]] || fail "restored database row mismatch: $restored_row"
"$ROOT/build/rh_cli" store verify --root "$T/evidence-restored" --name "$evidence_name" >/dev/null || fail "restored evidence digest"
"$ROOT/build/rh_cli" identity --input "$T/identity-input.json" --out "$T/report-before.json" >/dev/null || fail "generate baseline report"
"$ROOT/build/rh_cli" identity --input "$T/evidence-restored/$evidence_name" --out "$T/report-after.json" >/dev/null || fail "replay restored report"
cmp -s "$T/report-before.json" "$T/report-after.json" || fail "restored evidence report differs byte-for-byte"
"$ROOT/build/rh_cli" ops verify-binding --root "$T/evidence-restored" --manifest "$T/backup/evidence.manifest" --database "$T/backup/database.dump" --input "$T/backup/backup-binding.json" >/dev/null || fail "restored database/evidence binding"

echo "[postgres-backup-live] restored database row, evidence digest, report replay, and pair binding verified"
