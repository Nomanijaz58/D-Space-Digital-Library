#!/usr/bin/env bash

set -e

cd "$(dirname "$0")/../api"

source venv/bin/activate
export $(grep -v '^#' ../config/fmclib.env | xargs)

echo "Starting FMC Adapter (Gunicorn)…"

exec gunicorn \
  --workers 3 \
  --bind 0.0.0.0:${FMC_API_PORT:-5001} \
  --timeout 120 \
  --log-level info \
  wsgi:app
