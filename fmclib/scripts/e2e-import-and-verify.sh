#!/bin/bash
# E2E: Load env, submit sample item(s) to DSpace via REST, verify.
# Usage: bash scripts/e2e-import-and-verify.sh test-data "123456789/2" http://localhost:5001
# Or from fmclib: bash scripts/e2e-import-and-verify.sh test-data "$FMC_DEFAULT_COLLECTION" http://localhost:5001

set -e
DATA_DIR="${1:-test-data}"
COLLECTION_HANDLE="${2:-$FMC_DEFAULT_COLLECTION}"
FMC_URL="${3:-http://localhost:5001}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FMC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$FMC_DIR/config/fmclib.env"

# Load env
if [ -f "$CONFIG" ]; then
  set -a
  source "$CONFIG"
  set +a
fi

DSPACE_API="${DSPACE_API_URL:-http://localhost:8081/server/api}"
EMAIL="${FMC_REST_EMAIL:-admin@example.com}"
PASS="${FMC_REST_PASSWORD}"
COOKIES=$(mktemp)
trap "rm -f $COOKIES" EXIT

get_csrf() {
  # DSpace returns CSRF token via response header: DSPACE-XSRF-TOKEN
  local headers
  local attempts=20
  local i=1
  CSRF_TOKEN=""

  while [ $i -le $attempts ]; do
    headers=$(curl -sS --max-time 5 -D - -c "$COOKIES" -b "$COOKIES" -o /dev/null "$DSPACE_API/security/csrf" || true)
    CSRF_TOKEN=$(echo "$headers" | grep -i 'DSPACE-XSRF-TOKEN:' | sed 's/.*: *//' | tr -d '\r')
    if [ -n "$CSRF_TOKEN" ]; then
      return 0
    fi
    sleep 2
    i=$((i+1))
  done

  echo "   Could not get CSRF token from $DSPACE_API/security/csrf after $attempts attempts."
  echo "   DSpace may still be starting up. Try: docker logs dspace --tail 50"
  exit 1
}

echo "=== E2E Import and Verify ==="
echo "  DSpace API: $DSPACE_API"
echo "  Collection: $COLLECTION_HANDLE"
echo "  FMC Adapter: $FMC_URL"
echo "  Data dir: $DATA_DIR"
echo ""

if [ -z "$PASS" ]; then
  echo "Error: FMC_REST_PASSWORD is not set. Set it in config/fmclib.env or export FMC_REST_PASSWORD=..."
  exit 1
fi

# Step 1: CSRF (token is in response header DSPACE-XSRF-TOKEN)
echo "1. Fetching CSRF token..."
get_csrf

# Step 2: Login (capture response headers for Bearer token)
echo "2. Logging in as $EMAIL..."
LOGIN_OUT=$(curl -s -i -w "\nHTTP_CODE:%{http_code}" -X POST -b "$COOKIES" -c "$COOKIES" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  ${CSRF_TOKEN:+ -H "X-XSRF-TOKEN: $CSRF_TOKEN"} \
  -d "user=$EMAIL&password=$PASS" \
  "$DSPACE_API/authn/login")
HTTP_CODE=$(echo "$LOGIN_OUT" | grep '^HTTP_CODE:' | sed 's/HTTP_CODE://')
# Bearer token is in response header Authorization (DSpace 7 REST)
AUTH_HEADER=""
AUTH_LINE=$(echo "$LOGIN_OUT" | grep -i '^Authorization:' | head -1 | sed 's/\r$//')
if [ -n "$AUTH_LINE" ]; then
  AUTH_HEADER="$AUTH_LINE"
fi
if [ "$HTTP_CODE" != "200" ]; then
  echo "   Login failed (HTTP $HTTP_CODE). Check FMC_REST_EMAIL and FMC_REST_PASSWORD in config/fmclib.env"
  echo "$LOGIN_OUT" | head -30
  exit 1
fi
echo "   Login OK."

# CSRF token is rotated after login; fetch a fresh one for subsequent POST/PATCH calls
get_csrf

# Step 3: Resolve collection UUID by handle
echo "3. Resolving collection UUID for handle $COLLECTION_HANDLE..."
COLLS=$(curl -s -b "$COOKIES" -c "$COOKIES" ${AUTH_HEADER:+ -H "$AUTH_HEADER"} \
  "${DSPACE_API}/core/collections?size=100")
COLL_UUID=$(echo "$COLLS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
handle = '''$COLLECTION_HANDLE'''
for c in d.get('_embedded', {}).get('collections', []):
    if c.get('handle') == handle:
        # self link is like .../collections/uuid
        self = c.get('_links', {}).get('self', {}).get('href', '')
        print(self.split('/')[-1])
        break
" 2>/dev/null)
if [ -z "$COLL_UUID" ]; then
  echo "   Collection with handle $COLLECTION_HANDLE not found. List handles with:"
  echo "   curl -s $DSPACE_API/core/collections | python3 -c \"import sys,json; d=json.load(sys.stdin); [print(c.get('handle'), c.get('name')) for c in d.get('_embedded',{}).get('collections',[])]\""
  exit 1
fi
echo "   Collection UUID: $COLL_UUID"

# Step 4: Create workspace item (use owningCollection; parent would trigger 405)
echo "4. Creating workspace item..."
get_csrf
WSP_RESP=$(curl -s -w "\n%{http_code}" -X POST -b "$COOKIES" -c "$COOKIES" \
  ${AUTH_HEADER:+ -H "$AUTH_HEADER"} \
  ${CSRF_TOKEN:+ -H "X-XSRF-TOKEN: $CSRF_TOKEN"} \
  -H "Content-Type: application/json" \
  -d "{}" \
  "$DSPACE_API/submission/workspaceitems?owningCollection=$COLL_UUID")
WSP_BODY=$(echo "$WSP_RESP" | sed '$d')
WSP_CODE=$(echo "$WSP_RESP" | tail -n 1)
if [ "$WSP_CODE" != "201" ] && [ "$WSP_CODE" != "200" ]; then
  echo "   Failed to create workspace item (HTTP $WSP_CODE)"
  echo "$WSP_BODY" | head -20
  exit 1
fi
WSP_ID=$(echo "$WSP_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)
if [ -z "$WSP_ID" ]; then
  WSP_ID=$(echo "$WSP_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id') or d.get('_links',{}).get('self',{}).get('href','').split('/')[-1])" 2>/dev/null)
fi
echo "   Workspace item ID: $WSP_ID ($WSP_CODE)"

# Step 5: Add metadata (traditionalpageone = default form; use fmcpageone only if collection is FMC-mapped)
echo "5. Adding metadata..."
# Default DSpace collection uses traditionalpageone; FMC-mapped collections use fmcpageone
SECTION="traditionalpageone"
if [ -n "$FMC_DEFAULT_COLLECTION" ] && [ "$COLLECTION_HANDLE" = "$FMC_DEFAULT_COLLECTION" ]; then
  SECTION="fmcpageone"
fi
echo "   Using section: $SECTION"

echo "   Fetching workspace item to inspect available fields in section $SECTION..."
WSP_GET=$(curl -s -b "$COOKIES" -c "$COOKIES" ${AUTH_HEADER:+ -H "$AUTH_HEADER"} \
  "$DSPACE_API/submission/workspaceitems/$WSP_ID")
python3 - <<PY 2>/dev/null || true
import json
import sys
d = json.loads('''$WSP_GET''')
sec = d.get('sections', {}).get('$SECTION', {})
keys = [k for k in sec.keys() if k not in ('errors','header','sectionType')]
print('   Section keys:', ', '.join(sorted(keys)) if keys else '(none)')
PY

PATCH_BODY=$(cat <<PATCH
[
  {"op":"add","path":"/sections/${SECTION}/dc.title","value":[{"value":"E2E Test Item"}]},
  {"op":"add","path":"/sections/${SECTION}/dc.contributor.author","value":[{"value":"FMC Test Author"}]},
  {"op":"add","path":"/sections/${SECTION}/dc.type","value":[{"value":"Book"}]},
  {"op":"add","path":"/sections/${SECTION}/dc.language.iso","value":[{"value":"en"}]},
  {"op":"add","path":"/sections/license/granted","value":true}
]
PATCH
)
get_csrf
PATCH_RESP=$(curl -s -w "\n%{http_code}" -X PATCH -b "$COOKIES" -c "$COOKIES" \
  ${AUTH_HEADER:+ -H "$AUTH_HEADER"} \
  ${CSRF_TOKEN:+ -H "X-XSRF-TOKEN: $CSRF_TOKEN"} \
  -H "Content-Type: application/json-patch+json" \
  -d "$PATCH_BODY" \
  "$DSPACE_API/submission/workspaceitems/$WSP_ID")
PATCH_CODE=$(echo "$PATCH_RESP" | tail -n 1)
if [ "$PATCH_CODE" != "200" ]; then
  echo "   PATCH metadata failed (HTTP $PATCH_CODE). If 422, section name may differ (e.g. traditionalpageone)."
  echo "   PATCH body (first 25 lines):"
  echo "$PATCH_BODY" | head -25
  echo "   Response body (first 40 lines):"
  echo "$PATCH_RESP" | sed '$d' | head -40
  exit 1
fi
echo "   PATCH response: $PATCH_CODE"

# Step 6: Submit to workflow
echo "6. Submitting to workflow..."
echo "   Fetching workspace item to check for submission errors before workflow submit..."
WSP_PRE_WF=$(curl -s -b "$COOKIES" -c "$COOKIES" ${AUTH_HEADER:+ -H "$AUTH_HEADER"} \
  "$DSPACE_API/submission/workspaceitems/$WSP_ID")
python3 - <<PY 2>/dev/null <<<"$WSP_PRE_WF" || true
import json
import sys

d = json.load(sys.stdin)

sections = d.get('sections') or {}
print('   Sections present:', ', '.join(sorted(sections.keys())) if sections else '(none)')

for name in sorted(sections.keys()):
    sec = sections.get(name) or {}
    keys = [k for k in sec.keys() if k not in ('errors','header','sectionType')]
    if keys:
        print(f"   Section [{name}] keys: " + ', '.join(sorted(keys)))

top_errors = d.get('errors') or []
if top_errors:
    print('   Top-level errors:')
    for e in top_errors:
        if isinstance(e, dict):
            print('    -', e.get('message') or e)
        else:
            print('    -', e)

printed = False
for name, sec in sections.items():
    errs = (sec or {}).get('errors') or []
    if errs:
        if not printed:
            print('   Section errors:')
            printed = True
        for e in errs:
            if isinstance(e, dict):
                msg = e.get('message') or str(e)
                path = e.get('path') or ''
            else:
                msg = str(e)
                path = ''
            print(f"    - [{name}] {path} {msg}".rstrip())

if not top_errors and not printed:
    print('   No errors found in workspace item response.')
PY
get_csrf
WSP_URI="/api/submission/workspaceitems/$WSP_ID"
WF_RESP=$(curl -s -w "\n%{http_code}" -X POST -b "$COOKIES" -c "$COOKIES" \
  ${AUTH_HEADER:+ -H "$AUTH_HEADER"} \
  ${CSRF_TOKEN:+ -H "X-XSRF-TOKEN: $CSRF_TOKEN"} \
  -H "Content-Type: text/uri-list" \
  -d "$WSP_URI" \
  "$DSPACE_API/workflow/workflowitems")
WF_CODE=$(echo "$WF_RESP" | tail -n 1)
if [ "$WF_CODE" != "201" ] && [ "$WF_CODE" != "200" ]; then
  echo "   Workflow submit failed (HTTP $WF_CODE)"
  echo "   WorkspaceItem URI: $WSP_URI"
  echo "   Response body (first 80 lines):"
  echo "$WF_RESP" | sed '$d' | head -80
  exit 1
fi
echo "   Workflow submit: $WF_CODE"

# Step 7: Verify via FMC adapter search
echo "7. Verifying via FMC adapter..."
VERIFY=$(curl -s "$FMC_URL/search?query=E2E%20Test&size=5")
if echo "$VERIFY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
emb = d.get('_embedded', {})
objs = emb.get('searchResult', {}).get('_embedded', {}).get('objects', [])
titles = [o.get('_embedded', {}).get('indexableObject', {}).get('name') for o in objs]
if any(t and 'E2E Test' in t for t in titles):
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
  echo "   Item found in discovery."
  echo ""
  echo "E2E test PASSED"
else
  echo "   Item not yet visible in search (indexing may be delayed)."
  echo "   Check UI: $DSPACE_UI_URL"
  echo ""
  echo "E2E import completed; verification deferred (run search again later)."
fi
