#!/usr/bin/env bash
# Backup PostgreSQL database and DSpace assetstore volume.
# Uses docker to run pg_dump and tar; keeps backups in a configurable directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$PROJECT_ROOT}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dspace}"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-dspacedb}"
POSTGRES_USER="${POSTGRES_USER:-dspace}"
POSTGRES_DB="${POSTGRES_DB:-dspace}"
PGDATA_VOLUME="${PGDATA_VOLUME:-${COMPOSE_PROJECT_NAME}_pgdata}"
ASSETSTORE_VOLUME="${ASSETSTORE_VOLUME:-${COMPOSE_PROJECT_NAME}_assetstore}"

usage() {
  cat <<EOF
Usage: $0 [--db-only | --assetstore-only]
       $0 restore-db BACKUP_FILE
       $0 restore-assetstore BACKUP_FILE

  Default: backup both PostgreSQL and assetstore to BACKUP_DIR with timestamp.
  --db-only         Backup only PostgreSQL
  --assetstore-only Backup only assetstore volume
  restore-db        Restore PostgreSQL from BACKUP_FILE (.sql or .sql.gz)
  restore-assetstore Restore assetstore from BACKUP_FILE (.tar or .tar.gz)

  Environment:
    BACKUP_DIR       Output directory (default: \$PROJECT_ROOT/backups)
    RETENTION_DAYS   Delete backups older than N days (default: 30)
    POSTGRES_CONTAINER  DB container name (default: dspacedb)
    POSTGRES_USER    PostgreSQL user (default: dspace)
    POSTGRES_DB      Database name (default: dspace)
    PGDATA_VOLUME    Volume name for pgdata (default: \${COMPOSE_PROJECT_NAME}_pgdata)
    ASSETSTORE_VOLUME   Volume name for assetstore (default: \${COMPOSE_PROJECT_NAME}_assetstore)
    COMPOSE_PROJECT_NAME  Used for volume names if not overridden (default: dspace)
EOF
  exit 0
}

log_ts() { date "+%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date "+%Y-%m-%d %H:%M:%S"; }
log_msg() { echo "[$(log_ts)] $*"; }
log_err() { echo "[$(log_ts)] ERROR: $*" >&2; }

# Resolve volume name (compose v2 uses project_prefix_volumename)
get_volume_name() {
  local want="$1"
  docker volume ls -q | grep -E "${want}$|${want}" | head -1
}

run_backup() {
  local db_only=0
  local asset_only=0
  for arg in "$@"; do
    [[ "$arg" == "--db-only" ]] && db_only=1
    [[ "$arg" == "--assetstore-only" ]] && asset_only=1
  done
  # If no option given, backup both
  if [[ $db_only -eq 0 && $asset_only -eq 0 ]]; then
    db_only=1
    asset_only=1
  fi

  mkdir -p "$BACKUP_DIR"
  STAMP="$(date +%Y%m%d-%H%M%S)"

  if [[ $db_only -eq 1 ]]; then
    if ! docker inspect -f '{{.State.Running}}' "$POSTGRES_CONTAINER" 2>/dev/null | grep -q true; then
      log_err "PostgreSQL container $POSTGRES_CONTAINER is not running. Start stack first."
      exit 1
    fi
    SQL_FILE="$BACKUP_DIR/dspace-db-$STAMP.sql"
    log_msg "Backing up database to $SQL_FILE"
    docker exec "$POSTGRES_CONTAINER" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-acl > "$SQL_FILE"
    gzip -f "$SQL_FILE"
    log_msg "Database backup: ${SQL_FILE}.gz"
  fi

  if [[ $asset_only -eq 1 ]]; then
    VOL="$(get_volume_name "assetstore")"
    if [[ -z "$VOL" ]]; then
      VOL="$ASSETSTORE_VOLUME"
    fi
    if ! docker volume inspect "$VOL" &>/dev/null; then
      log_err "Volume $VOL not found. Is the stack running or has it been created?"
      exit 1
    fi
    TAR_FILE="$BACKUP_DIR/dspace-assetstore-$STAMP.tar"
    log_msg "Backing up assetstore ($VOL) to $TAR_FILE"
    docker run --rm -v "$VOL:/data:ro" -v "$BACKUP_DIR:/backup" alpine tar -cf "/backup/$(basename "$TAR_FILE")" -C /data .
    gzip -f "$TAR_FILE"
    log_msg "Assetstore backup: ${TAR_FILE}.gz"
  fi

  # Prune old backups
  if [[ -n "${RETENTION_DAYS:-}" && "$RETENTION_DAYS" -gt 0 ]]; then
    find "$BACKUP_DIR" -name "dspace-db-*.sql.gz" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
    find "$BACKUP_DIR" -name "dspace-assetstore-*.tar.gz" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
    log_msg "Pruned backups older than $RETENTION_DAYS days."
  fi
}

restore_db() {
  local file="${1:-}"
  if [[ -z "$file" || ! -f "$file" ]]; then
    log_err "Usage: $0 restore-db BACKUP_FILE"
    exit 1
  fi
  if ! docker inspect -f '{{.State.Running}}' "$POSTGRES_CONTAINER" 2>/dev/null | grep -q true; then
    log_err "Start PostgreSQL container first."
    exit 1
  fi
  log_msg "Restoring database from $file (existing data may be overwritten)."
  if [[ "$file" == *.gz ]]; then
    gunzip -c "$file" | docker exec -i "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
  else
    docker exec -i "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$file"
  fi
  log_msg "Database restore completed. Consider running: docker exec dspace /dspace/bin/dspace index-discovery -b"
}

restore_assetstore() {
  local file="${1:-}"
  if [[ -z "$file" || ! -f "$file" ]]; then
    log_err "Usage: $0 restore-assetstore BACKUP_FILE"
    exit 1
  fi
  VOL="$(get_volume_name "assetstore")"
  [[ -z "$VOL" ]] && VOL="$ASSETSTORE_VOLUME"
  if ! docker volume inspect "$VOL" &>/dev/null; then
    log_err "Volume $VOL not found."
    exit 1
  fi
  log_msg "Restoring assetstore from $file into $VOL (existing content will be merged/overwritten)."
  if [[ "$file" == *.gz ]]; then
    gunzip -c "$file" | docker run -i --rm -v "$VOL:/data" -v "$(dirname "$file"):/backup:ro" alpine tar -xf - -C /data
  else
    docker run --rm -v "$VOL:/data" -v "$(dirname "$file"):/backup:ro" alpine tar -xf "/backup/$(basename "$file")" -C /data
  fi
  log_msg "Assetstore restore completed."
}

case "${1:-}" in
  -h|--help) usage ;;
  restore-db) restore_db "${2:-}" ;;
  restore-assetstore) restore_assetstore "${2:-}" ;;
  *) run_backup "$@" ;;
esac
