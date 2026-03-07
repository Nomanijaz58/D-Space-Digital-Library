#!/usr/bin/env bash
# Recreate the Solr "search" core with DSpace's solrconfig.xml and schema.xml.
# Builds the core dir inside the container (avoids macOS volume/cp issues with create_core).
set -euo pipefail

DSPACE_CONTAINER="${DSPACE_CONTAINER:-tony-dspace-1}"
SOLR_CONTAINER="${SOLR_CONTAINER:-dspace-solr}"
DSpace_CONFIG_DIR="/usr/local/tomcat/dspace/config"
SOLR_CORE_CONF="/var/solr/data/search/conf"

echo "1. Deleting existing 'search' core and any stale new_core..."
docker exec "$SOLR_CONTAINER" solr delete -c search 2>/dev/null || true
docker exec "$SOLR_CONTAINER" rm -rf /var/solr/data/search /var/solr/data/new_core 2>/dev/null || true

echo "2. Creating core directory and copying _default configset (inside container)..."
docker exec "$SOLR_CONTAINER" bash -c 'mkdir -p /var/solr/data/search/conf && cp -r /opt/solr/server/solr/configsets/_default/conf/* /var/solr/data/search/conf/'

echo "3. Registering core (core.properties)..."
docker exec "$SOLR_CONTAINER" bash -c 'echo "name=search" > /var/solr/data/search/core.properties'

echo "4. Copying DSpace Solr config (solrconfig.xml, schema.xml) into core..."
SOLRCONF_SRC=""
for dir in "/usr/local/tomcat/dspace/config" "/dspace/config" "/opt/dspace/config"; do
  if docker exec "$DSPACE_CONTAINER" test -f "$dir/solrconfig.xml" 2>/dev/null; then
    SOLRCONF_SRC="$dir"
    break
  fi
done
if [[ -n "$SOLRCONF_SRC" ]]; then
  docker cp "$DSPACE_CONTAINER:$SOLRCONF_SRC/solrconfig.xml" /tmp/solrconfig.xml
  docker cp "$DSPACE_CONTAINER:$SOLRCONF_SRC/schema.xml" /tmp/schema.xml
  echo "   Using config from container: $SOLRCONF_SRC"
else
  echo "   Not found in container; downloading DSpace 7 search config from GitHub..."
  DSpace_RAW="https://raw.githubusercontent.com/DSpace/DSpace/main/dspace/solr/search/conf"
  curl -sSL -o /tmp/solrconfig.xml "$DSpace_RAW/solrconfig.xml"
  curl -sSL -o /tmp/schema.xml "$DSpace_RAW/schema.xml"
fi
docker cp /tmp/solrconfig.xml "$SOLR_CONTAINER:$SOLR_CORE_CONF/"
docker cp /tmp/schema.xml "$SOLR_CONTAINER:$SOLR_CORE_CONF/"
rm -f /tmp/solrconfig.xml /tmp/schema.xml

echo "5. Restarting Solr so it loads the new core..."
docker restart "$SOLR_CONTAINER"

echo "Waiting for Solr and search core (up to 90s)..."
sleep 5
MAX_WAIT=90
WAITED=0
while [[ $WAITED -lt $MAX_WAIT ]]; do
  if curl -s "http://localhost:8983/solr/admin/cores?action=STATUS&core=search" 2>/dev/null | grep -q '"name":"search"'; then
    echo "  Search core is ready."
    break
  fi
  echo "  waiting... (${WAITED}s)"
  sleep 5
  WAITED=$((WAITED + 5))
done
if [[ $WAITED -ge $MAX_WAIT ]]; then
  echo "  Timeout. Solr may still be starting. Check: curl -s http://localhost:8983/solr/admin/cores?action=STATUS"
fi

echo "Done. Restart DSpace: docker compose restart dspace"
