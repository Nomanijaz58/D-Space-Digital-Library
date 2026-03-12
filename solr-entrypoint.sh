#!/bin/bash

# Solr Entrypoint for Render
# This script handles Render's persistent disk by initializing it from templates if empty.

PORT="${PORT:-8983}"
DATA_DIR="/var/solr/data"
TEMPLATE_DIR="/opt/solr/core-templates"

echo "Checking Solr data directory: $DATA_DIR"

if [ ! -f "$DATA_DIR/solr.xml" ]; then
    echo "Initializing Solr data directory from templates..."
    cp /opt/solr/server/solr/solr.xml "$DATA_DIR/solr.xml"
fi

# Copy core templates if they don't exist in the data volume
for core in search statistics authority oai; do
    if [ ! -d "$DATA_DIR/$core" ]; then
        echo "Initializing core: $core"
        mkdir -p "$DATA_DIR/$core"
        cp -r "$TEMPLATE_DIR/$core/." "$DATA_DIR/$core/"
    fi
done

# Ensure permissions are correct on the volume
echo "Ensuring Solr ownership of $DATA_DIR..."
chown -R solr:solr "$DATA_DIR"

echo "Launching DSpace Solr on port $PORT..."
# -f starts Solr in foreground
# -p specifies the port
# -h specifies the host
exec solr -f -p "$PORT" -h 0.0.0.0
