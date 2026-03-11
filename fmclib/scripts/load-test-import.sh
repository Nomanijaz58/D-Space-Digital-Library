#!/bin/bash
# Run E2E import multiple times. Usage: bash scripts/load-test-import.sh test-data "123456789/2" http://localhost:5001 [count]
set -e
DATA_DIR="${1:-test-data}"
COLLECTION_HANDLE="${2:-$FMC_DEFAULT_COLLECTION}"
FMC_URL="${3:-http://localhost:5001}"
COUNT="${4:-5}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Load test: $COUNT runs"
for i in $(seq 1 "$COUNT"); do
  echo "--- Run $i/$COUNT ---"
  bash "$SCRIPT_DIR/e2e-import-and-verify.sh" "$DATA_DIR" "$COLLECTION_HANDLE" "$FMC_URL" || true
done
echo "Done."
