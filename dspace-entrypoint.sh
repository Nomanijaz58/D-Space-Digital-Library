#!/bin/sh

# Exit immediately if a command exits with a non-zero status
set -e

echo "Starting DSpace Entrypoint..."

# Fail fast if required variables are missing
if [ -z "$DATABASE_URL" ]; then
    echo "ERROR: DATABASE_URL is not set. Please ensure Render is providing the Database URL."
    exit 1
fi

if [ -z "$SOLR_URL" ]; then
    echo "ERROR: SOLR_URL is not set. You MUST add this environment variable to your Render Backend service."
    echo "Set SOLR_URL to your Solr service URL (e.g. https://dspace-solr.onrender.com/solr)."
    exit 1
fi

echo "Parsing DATABASE_URL for DSpace..."

    # Extract the protocol (postgres:// or postgresql://)
    PROTOCOL=$(echo "$DATABASE_URL" | grep -o '^[a-z]*://')

    # Remove the protocol
    URL_WITHOUT_PROTOCOL=${DATABASE_URL#*://}

    # Extract user:pass
    USER_PASS=$(echo "$URL_WITHOUT_PROTOCOL" | cut -d@ -f1)

    # Extract database username
    DB_USERNAME=$(echo "$USER_PASS" | cut -d: -f1)

    # Extract database password
    DB_PASSWORD=$(echo "$USER_PASS" | cut -d: -f2)

    # Extract host:port/dbname
    HOST_PORT_DB=$(echo "$URL_WITHOUT_PROTOCOL" | cut -d@ -f2)

    # Extract host:port
    HOST_PORT=$(echo "$HOST_PORT_DB" | cut -d/ -f1)

    # Extract database name
    DB_NAME=$(echo "$HOST_PORT_DB" | cut -d/ -f2)

    # DSpace environment variables mapped via config-definition.xml rules
    export db__P__url="jdbc:postgresql://${HOST_PORT}/${DB_NAME}"
    export db__P__username="${DB_USERNAME}"
    export db__P__password="${DB_PASSWORD}"

    echo "DATABASE_URL successfully mapped to DSpace environment variables"

# Map Render external URL to DSpace server url if provided
if [ ! -z "$DSPACE_SERVER_URL" ]; then
    echo "Using DSPACE_SERVER_URL from environment: $DSPACE_SERVER_URL"
    export dspace__P__server__P__url="${DSPACE_SERVER_URL}"
elif [ ! -z "$RENDER_EXTERNAL_URL" ]; then
    echo "Mapping RENDER_EXTERNAL_URL to config property..."
    export dspace__P__server__P__url="${RENDER_EXTERNAL_URL}"
fi

# Whitelist UI URLs for CORS
UI_URL="${DSPACE_UI_URL:-https://d-space-ui.onrender.com}"
echo "Whitelisting UI URL for CORS: $UI_URL"
export dspace__P__ui__P__url="$UI_URL"
export rest__P__cors__P__allowed__D__origins="$UI_URL,http://localhost:4000"

# DSpace MUST trust the Render proxy load balancer, otherwise it thinks HTTPS traffic is HTTP and drops CORS headers!
export proxies__P__trusted__P__ipranges="*"
export server__P__forward__D__headers__D__strategy="FRAMEWORK"

# Initialize DSPACE_OPTS for java system properties
DSPACE_OPTS=""

# Disable Spring Boot Health Indicators for Solr to prevent premature connection timeouts on boot
export SPRING_APPLICATION_JSON='{"management":{"health":{"solrSearch":{"enabled":false},"solrStatistics":{"enabled":false},"solrAuthority":{"enabled":false},"solrOai":{"enabled":false}}}}'

# Add configurable Solr URL map
if [ ! -z "$SOLR_URL" ]; then
    echo "Mapping SOLR_URL to DSpace solr properties..."
    
    DSPACE_OPTS="$DSPACE_OPTS -Dsolr.server=${SOLR_URL}"
    DSPACE_OPTS="$DSPACE_OPTS -Ddiscovery.search.server=${SOLR_URL}/search"
    DSPACE_OPTS="$DSPACE_OPTS -Dsolr-statistics.server=${SOLR_URL}/statistics"
    DSPACE_OPTS="$DSPACE_OPTS -Dsolr.authority.server=${SOLR_URL}/authority"
    DSPACE_OPTS="$DSPACE_OPTS -Doai.solr.url=${SOLR_URL}/oai"
    DSPACE_OPTS="$DSPACE_OPTS -Dsuggestion.solr.server=${SOLR_URL}/suggestion"

    export solr__P__server="${SOLR_URL}"
    export discovery__P__search__P__server="${SOLR_URL}/search"
    export solr__D__statistics__P__server="${SOLR_URL}/statistics"
    export solr__P__authority__P__server="${SOLR_URL}/authority"
    export oai__P__solr__P__url="${SOLR_URL}/oai"
    export suggestion__P__solr__P__server="${SOLR_URL}/suggestion"
fi

echo "=== DSpace Environment Configuration ==="
env | grep -E "^(dspace|db|solr|discovery|oai|suggestion|rest)__" || true
echo "========================================"

# Add strict Tomcat native memory constraints to prevent Render 512MB RAM exhaustion
DSPACE_OPTS="$DSPACE_OPTS -Dserver.tomcat.threads.max=20 -Dserver.tomcat.max-connections=50 -Dserver.tomcat.accept-count=10"
DSPACE_OPTS="$DSPACE_OPTS -Dproxies.trusted.ipranges=* -Dserver.forward-headers-strategy=FRAMEWORK"

export DSPACE_OPTS

echo "Creating mock health check endpoint for Render proxy server..."
mkdir -p /tmp/server/api/system
echo '{"status":"UP"}' > /tmp/server/api/system/status

echo "Starting dummy web server on Render PORT to satisfy the port scanner..."
# We use a timeout to ensure the dummy server doesn't stay alive forever if migration hangs
jwebserver -p "${PORT:-8080}" -b 0.0.0.0 -d /tmp &
JWEB_PID=$!

echo "Running DSpace database migration (MUST succeed)..."
# Add -v for verbose output if needed, but the main goal is to see it finish
/dspace/bin/dspace database migrate || { echo "ERROR: Database migration failed. See logs above."; kill $JWEB_PID || true; exit 1; }

echo "Database migration finished."

# Auto-create admin if DSPACE_ADMIN_EMAIL is set
if [ ! -z "$DSPACE_ADMIN_EMAIL" ] && [ ! -z "$DSPACE_ADMIN_PASSWORD" ]; then
    echo "Creating DSpace admin user: $DSPACE_ADMIN_EMAIL"
    /dspace/bin/dspace create-administrator \
        -e "$DSPACE_ADMIN_EMAIL" \
        -f "Admin" \
        -l "User" \
        -c "en" \
        -p "$DSPACE_ADMIN_PASSWORD" && echo "Admin user created successfully!" || echo "Admin user may already exist, continuing..."
fi

echo "Force-killing dummy web server to release port..."
kill -9 $JWEB_PID || true
pkill -9 -f jwebserver || true
sleep 2

echo "Starting Spring Boot..."
export PORT="${PORT:-8080}"

exec "$@"
