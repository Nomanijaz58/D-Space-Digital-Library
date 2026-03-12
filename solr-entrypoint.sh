#!/bin/bash

# Solr Entrypoint for Render
# This script handles Render's persistent disk by syncing configurations from templates on every boot.

PORT="${PORT:-8983}"
DATA_DIR="/var/solr/data"
TEMPLATE_DIR="/opt/solr/core-templates"

echo "Checking Solr data directory: $DATA_DIR"

if [ ! -f "$DATA_DIR/solr.xml" ]; then
    echo "Initializing Solr data directory from templates..."
    cp /opt/solr/server/solr/solr.xml "$DATA_DIR/solr.xml"
fi

# Sync core configurations from templates to the data volume on every boot.
# This ensures stale/failing configurations on the persistent disk are overwritten by the fixed ones from the image.
for core in search statistics authority oai; do
    echo "Syncing configuration for core: $core"
    mkdir -p "$DATA_DIR/$core"
    
    # Clean and sync conf and lib (preserves any 'data' directory containing the index)
    rm -rf "$DATA_DIR/$core/conf" "$DATA_DIR/$core/lib"
    cp -r "$TEMPLATE_DIR/$core/conf" "$DATA_DIR/$core/"
    cp -r "$TEMPLATE_DIR/$core/lib" "$DATA_DIR/$core/"
    cp "$TEMPLATE_DIR/$core/core.properties" "$DATA_DIR/$core/"
done

# Ensure permissions are correct on the volume
echo "Ensuring Solr ownership of $DATA_DIR..."
chown -R solr:solr "$DATA_DIR"

echo "Launching DSpace Solr on port $PORT..."
# -f starts Solr in foreground
# -p specifies the port
# -h specifies the host
exec solr -f -p "$PORT" -h 0.0.0.0
