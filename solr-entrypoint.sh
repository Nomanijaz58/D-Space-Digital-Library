#!/bin/bash

# Solr Entrypoint for Render
# Since we pre-create the cores in the Dockerfile, Solr will start normally on the assigned port.

PORT="${PORT:-8983}"

echo "Launching DSpace Solr on port $PORT..."
# -f starts Solr in foreground
# -p specifies the port
# -h specifies the host
exec solr -f -p "$PORT" -h 0.0.0.0
