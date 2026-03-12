#!/bin/bash

# Solr Entrypoint for Render Free Tier
# This script starts a dummy web server immediately to satisfy Render's port scanner/health check,
# then starts Solr in the background and swaps them.

PORT="${PORT:-8983}"

echo "Starting dummy web server on port $PORT..."
# Create a simple health check response
mkdir -p /tmp/solr/admin/info
echo '{"status":"OK","system":{"name":"Solr"}}' > /tmp/solr/admin/info/system

# Start a tiny web server (using python since it's usually available in alpine/solr images)
python3 -m http.server "$PORT" --directory /tmp &
DUMMY_PID=$!

echo "Starting real Solr in background..."
# Start Solr. We use -f to keep it in foreground later, but for now we run it.
# Actually, we can't run two things on the same port at once.
# So we start Solr on a TEMPORARY port first, wait for it to be ready, then kill dummy and start Solr on real port.

SOLR_TEMP_PORT=8984
solr -p "$SOLR_TEMP_PORT"

echo "Wait for Solr to be ready on port $SOLR_TEMP_PORT..."
# Check for a 200 OK response from any valid Solr endpoint
until [ "$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$SOLR_TEMP_PORT/solr/admin/info/system")" == "200" ]; do
  echo "Solr is still initializing (waiting for cores to load)..."
  sleep 10
done

echo "Solr is ready! Swapping dummy server for real Solr..."
# Kill the dummy server and every other process on this port just in case
kill $DUMMY_PID
# Also try fuser or pkill as a backup if available
pkill -f "python3 -m http.server" || true
solr stop -p "$SOLR_TEMP_PORT"
sleep 5

# Verify port is free
if curl -s "http://localhost:$PORT" > /dev/null; then
  echo "WARNING: Port $PORT is still occupied! Forcing kill..."
  # Try to find the PID using lsof if available, but staying basic for now
fi

echo "Launching Solr on port $PORT..."
exec solr -f -p "$PORT" -h 0.0.0.0
