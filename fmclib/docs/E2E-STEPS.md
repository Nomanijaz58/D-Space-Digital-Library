# E2E ingestion and verification

## Step 1 — Load environment

```bash
cd ~/Downloads/DSpace-main/fmclib
source config/fmclib.env
echo $DSPACE_API_URL
echo $FMC_DEFAULT_COLLECTION
echo $FMC_REST_EMAIL
```

You should see real values (not empty). Set `FMC_REST_PASSWORD` if not in the file (export FMC_REST_PASSWORD=...).

## Step 2 — Confirm DSpace API is reachable

```bash
curl $DSPACE_API_URL
```

You should get a JSON HAL response with `_links`.

## Step 3 — Run E2E import and verify

```bash
bash scripts/e2e-import-and-verify.sh test-data "$FMC_DEFAULT_COLLECTION" http://localhost:5001
```

This will log in to DSpace, create a workspace item in the FMC collection, add FMC metadata, submit to workflow, and verify via the FMC adapter search.

- **Authentication errors** → check `FMC_REST_EMAIL` and `FMC_REST_PASSWORD` in `config/fmclib.env`.
- **403** → collection permissions: ensure the admin (or submitter) has Submit permission on the FMC collection.
- **422 on PATCH** → submission form section name may differ (e.g. `traditionalpageone` instead of `fmcpageone`); edit the script if needed.

## Step 4 — Verify in the UI

1. Open **http://localhost:4000**
2. Go to your FMC collection.
3. Confirm the test item appears and metadata (Author, Title, Type, Language) matches.

## Step 5 — Collection permissions (required for API submission)

1. Log in as admin: **http://localhost:4000/login**
2. Admin → Access Control → Groups.
3. Create (if needed) a group, e.g. **FMC Submitters**.
4. Give that group **Submit** permission on your FMC collection.
5. Add your admin (or API user) to that group.

Without this, automated deposits may fail with 403.

## Step 6 — Optional load test

```bash
bash scripts/load-test-import.sh test-data "$FMC_DEFAULT_COLLECTION" http://localhost:5001 5
```

Runs the E2E flow 5 times (default).

## Step 7 — MediaWiki integration

Copy the extension and configure:

```bash
cp -r mediawiki /path/to/your/mediawiki/extensions/FMCRepository
```

In `LocalSettings.php`:

```php
wfLoadExtension( 'FMCRepository' );
$wgFMCRepositoryAPIUrl = 'http://localhost:5001';
```

## FMC collection handle

If you don’t know the collection handle, see **FIND-FMC-COLLECTION-HANDLE.md**. Use your backend port (e.g. 8081):

```bash
curl -s "http://localhost:8081/server/api/core/collections" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for c in d.get('_embedded', {}).get('collections', []):
    print(c.get('handle'), c.get('name'))
"
```

Put the chosen handle in `config/fmclib.env` as `FMC_DEFAULT_COLLECTION=123456789/XX`.
