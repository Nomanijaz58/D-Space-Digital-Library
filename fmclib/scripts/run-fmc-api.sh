#!/bin/bash
# Start FMC Adapter API on FMC_API_PORT (default 5001).
# Run from repo root: ./fmclib/scripts/run-fmc-api.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FMC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
API_DIR="$FMC_DIR/api"
CONFIG="$FMC_DIR/config/fmclib.env"

cd "$API_DIR"
if [ -f "$CONFIG" ]; then
  set -a
  source "$CONFIG"
  set +a
fi

export FMC_API_PORT="${FMC_API_PORT:-5001}"
echo "Starting FMC Adapter on port $FMC_API_PORT"

if [ -d "venv" ]; then
  source venv/bin/activate
else
  echo "No venv found. Create with: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
  exit 1
fi

if command -v gunicorn &>/dev/null; then
  exec gunicorn -b "0.0.0.0:$FMC_API_PORT" app:app
else
  exec python run.py
fi
