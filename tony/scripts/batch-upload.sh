#!/usr/bin/env bash
# DSpace batch PDF upload with CSV metadata mapping.
# Builds SAF packages and runs dspace import inside the container.
# Supports resume via state file and logs all operations.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$PROJECT_ROOT}"
CONTAINER_NAME="${DSPACE_CONTAINER:-dspace}"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
STATE_FILE="${STATE_FILE:-$PROJECT_ROOT/.batch-upload-state}"
SAF_ROOT="${SAF_ROOT:-$PROJECT_ROOT/saf-import}"
EPERSON="${DSPACE_EPERSON:-admin@example.com}"

usage() {
  cat <<EOF
Usage: $0 CSV_FILE [COLLECTION_HANDLE]

  CSV_FILE         Path to CSV with columns: file, dc.title, dc.contributor.author, ...
  COLLECTION_HANDLE Optional. Target collection handle (e.g. 123456789/4). Prompted if omitted.

  Environment:
    COMPOSE_DIR       Directory containing docker-compose.yml (default: project root)
    DSPACE_CONTAINER  DSpace container name (default: dspace)
    DSPACE_EPERSON    E-person email for import (default: admin@example.com)
    LOG_DIR           Log directory (default: \$PROJECT_ROOT/logs)
    STATE_FILE        Resume state file (default: \$PROJECT_ROOT/.batch-upload-state)
    SAF_ROOT          Where to build SAF packages (default: \$PROJECT_ROOT/saf-import)
    RESUME            Set to 1 to skip rows already in STATE_FILE (default: 1)
    DRY_RUN           Set to 1 to only build SAF and log, do not run import (default: 0)

  CSV format: header row required. "file" = path to PDF (relative to CWD or absolute).
  DC columns: dc.title, dc.contributor.author, dc.date.issued, dc.type (element.qualifier).
EOF
  exit 0
}

log_ts() { date "+%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date "+%Y-%m-%d %H:%M:%S"; }
log_msg() { echo "[$(log_ts)] $*" | tee -a "$LOG_FILE"; }
log_err() { echo "[$(log_ts)] ERROR: $*" | tee -a "$LOG_FILE" >&2; }

# Escape XML
xml_esc() {
  echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# dc.element or dc.element.qualifier -> element [qualifier]
dc_to_parts() {
  local key="$1"
  local rest="${key#dc.}"
  local el="${rest%%.*}"
  local qual=""
  [[ "$rest" == *.* ]] && qual="${rest#*.}"
  echo "$el $qual"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; fi
CSV_FILE="${1:-}"
if [[ -z "$CSV_FILE" || ! -f "$CSV_FILE" ]]; then
  echo "ERROR: CSV_FILE required and must exist." >&2
  usage
fi
COLLECTION_HANDLE="${2:-}"
RESUME="${RESUME:-1}"
DRY_RUN="${DRY_RUN:-0}"

mkdir -p "$LOG_DIR" "$SAF_ROOT"
LOG_FILE="$LOG_DIR/batch-upload-$(date +%Y%m%d-%H%M%S).log"
log_msg "Starting batch upload. CSV=$CSV_FILE COLLECTION=$COLLECTION_HANDLE RESUME=$RESUME DRY_RUN=$DRY_RUN"

if ! docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
  log_err "Container $CONTAINER_NAME is not running. Start: docker compose -f $COMPOSE_DIR/docker-compose.yml up -d"
  exit 1
fi

HEADER="$(head -n 1 "$CSV_FILE")"
if [[ -z "$HEADER" ]]; then
  log_err "CSV has no header."
  exit 1
fi

if [[ -z "$COLLECTION_HANDLE" ]]; then
  echo "Enter target collection handle (e.g. 123456789/4):"
  read -r COLLECTION_HANDLE
fi
if [[ -z "$COLLECTION_HANDLE" ]]; then
  log_err "Collection handle required."
  exit 1
fi

RUN_ID="run-$(date +%Y%m%d-%H%M%S)"
SAF_DIR="$SAF_ROOT/$RUN_ID"
RUN_STATE="$SAF_DIR/.row-keys"
mkdir -p "$SAF_DIR"
touch "$STATE_FILE"
: > "$RUN_STATE"

ITEM_COUNT=0
row=0
while IFS= read -r line; do
  ((row++)) || true
  [[ $row -eq 1 ]] && continue
  [[ -z "$line" ]] && continue

  if [[ "$RESUME" == "1" ]]; then
    key="$(echo -n "$line" | md5sum 2>/dev/null | cut -d' ' -f1 || echo -n "$line" | md5)"
    key="${key:-$row}"
    if grep -q "^$key$" "$STATE_FILE" 2>/dev/null; then
      log_msg "Row $row: skipped (already in state file)."
      continue
    fi
  fi

  IFS=',' read -ra COLS <<< "$line"
  FILE_VAL=""
  declare -A DC
  COL_IDX=0
  for h in $(echo "$HEADER" | tr ',' '\n'); do
    h="${h//\"/}"
    val="${COLS[$COL_IDX]:-}"
    val="${val//\"/}"
    if [[ "$h" == "file" ]]; then
      FILE_VAL="$val"
    else
      [[ -n "$val" ]] && DC["$h"]="${DC[$h]:-}$val|||"
    fi
    ((COL_IDX++)) || true
  done

  for k in "${!DC[@]}"; do
    DC["$k"]="${DC[$k]%|||}"
  done

  if [[ -z "$FILE_VAL" ]]; then
    log_err "Row $row: missing 'file' column. Skipping."
    continue
  fi
  if [[ ! -f "$FILE_VAL" ]]; then
    log_err "Row $row: file not found: $FILE_VAL. Skipping."
    continue
  fi

  ((ITEM_COUNT++)) || true
  key="$(echo -n "$line" | md5sum 2>/dev/null | cut -d' ' -f1)"
  key="${key:-$row}"
  echo "$key" >> "$RUN_STATE"
  ITEM_DIR="$SAF_DIR/item_$ITEM_COUNT"
  mkdir -p "$ITEM_DIR"
  cp "$FILE_VAL" "$ITEM_DIR/"
  echo "$(basename "$FILE_VAL")" > "$ITEM_DIR/contents"
  echo "$COLLECTION_HANDLE" > "$ITEM_DIR/collection"

  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<dublin_core>'
    for key in "${!DC[@]}"; do
      read -r el qual <<< "$(dc_to_parts "$key")"
      IFS='|' read -ra VALS <<< "${DC[$key]}"
      for v in "${VALS[@]}"; do
        v="$(xml_esc "$v")"
        if [[ -n "$qual" ]]; then
          echo "  <dcvalue element=\"$el\" qualifier=\"$qual\">$v</dcvalue>"
        else
          echo "  <dcvalue element=\"$el\">$v</dcvalue>"
        fi
      done
    done
    echo '</dublin_core>'
  } > "$ITEM_DIR/dublin_core.xml"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_msg "Row $row: SAF prepared (dry run) for $FILE_VAL"
    key="$(echo -n "$line" | md5sum 2>/dev/null | cut -d' ' -f1)"
    echo "$key" >> "$STATE_FILE"
    continue
  fi
done < <(cat "$CSV_FILE")

if [[ "$DRY_RUN" == "1" ]]; then
  log_msg "Dry run complete. SAF at $SAF_DIR"
  exit 0
fi

if [[ $ITEM_COUNT -eq 0 ]]; then
  log_msg "No new items to import (all rows skipped or empty)."
  exit 0
fi

# Copy full SAF into container and run single import
CONTAINER_SAF="/tmp/saf-$RUN_ID"
docker cp "$SAF_DIR" "$CONTAINER_NAME:$CONTAINER_SAF"
log_msg "Running import for $ITEM_COUNT items (source=$CONTAINER_SAF)."

if docker exec "$CONTAINER_NAME" /dspace/bin/dspace import --add --eperson="$EPERSON" --collection="$COLLECTION_HANDLE" --source="$CONTAINER_SAF" --mapfile=/tmp/saf-mapfile-"$RUN_ID".txt 2>>"$LOG_FILE"; then
  log_msg "Import completed successfully."
  cat "$RUN_STATE" >> "$STATE_FILE"
else
  log_err "Import failed. Check log and DSpace container logs. Rows in this run were not added to state (safe to retry)."
fi

docker exec "$CONTAINER_NAME" rm -rf "$CONTAINER_SAF" 2>/dev/null || true
log_msg "Batch upload finished. Log: $LOG_FILE"
echo "Done. Log: $LOG_FILE"
