#!/usr/bin/env bash
set -e
DSPACE_HOME="${DSPACE_HOME:-/usr/local/tomcat/dspace}"
DB_HOST="${DB_HOST:-dspacedb}"
DB_PORT="${DB_PORT:-5432}"

echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}..."
while ! (echo > "/dev/tcp/${DB_HOST}/${DB_PORT}") 2>/dev/null; do
  echo "  ... waiting"
  sleep 2
done
echo "PostgreSQL is up."

DSpace_CLI=""
for candidate in "/dspace/bin/dspace" "${DSPACE_HOME}/bin/dspace"; do
  if [ -x "$candidate" ]; then
    DSpace_CLI="$candidate"
    break
  fi
done
if [ -n "$DSpace_CLI" ]; then
  echo "Running DSpace database migration..."
  "$DSpace_CLI" database migrate || true
else
  echo "DSpace CLI not found (/dspace/bin/dspace or ${DSPACE_HOME}/bin/dspace); skipping migration."
fi

exec "$@"
