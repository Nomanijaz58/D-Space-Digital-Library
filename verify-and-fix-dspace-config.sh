#!/bin/bash
# Verify the dspace container sees the fixed submission-forms.xml and fix the mount if not.
# Run this from the DSpace-main project directory: ./verify-and-fix-dspace-config.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Project directory: $SCRIPT_DIR ==="
echo ""

# What the container sees (first 15 lines after fmcpageone form start)
echo "=== Content of fmcpageone in CONTAINER (/dspace/config/submission-forms.xml) ==="
docker exec dspace sed -n '/<form name="fmcpageone">/,/<\/form>/p' /dspace/config/submission-forms.xml | head -20
echo ""

# What we have on host
echo "=== Content of fmcpageone on HOST ($SCRIPT_DIR/dspace/config/submission-forms.xml) ==="
sed -n '/<form name="fmcpageone">/,/<\/form>/p' "$SCRIPT_DIR/dspace/config/submission-forms.xml" | head -20
echo ""

if docker exec dspace grep -q "your FMC fields here" /dspace/config/submission-forms.xml 2>/dev/null; then
    echo "*** Container still has the OLD config (placeholder with no rows). ***"
    echo "*** You started Docker from a different directory, so the volume mount points elsewhere. ***"
    echo ""
    echo "Fix: from THIS directory, recreate the dspace container so it uses this project's config:"
    echo "  cd $SCRIPT_DIR"
    echo "  docker compose down"
    echo "  docker compose up -d"
    echo ""
    echo "(If you originally used a project name, e.g. 'docker compose -p d7 up', use the same: docker compose -p d7 down && docker compose -p d7 up -d)"
    exit 1
fi

if docker exec dspace grep -q "<row>" /dspace/config/submission-forms.xml 2>/dev/null; then
    echo "*** Container has the updated config (form has rows). Restart DSpace to load it: ***"
    echo "  docker restart dspace"
    exit 0
fi

echo "*** Could not determine state. Check the output above. ***"
exit 2
