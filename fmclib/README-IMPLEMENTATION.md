# FMC + DSpace Implementation Status

Overview of what has been implemented and what remains for the FMC Library (fmclib) integration with DSpace 7.

---

## 1. What Has Been Implemented

### 1.1 DSpace Backend & Configuration

- **Submission form `fmcpageone`**  
  - Added full form with four rows in `dspace/config/submission-forms.xml`: Author (`dc.contributor.author`), Title (`dc.title`), Type (dropdown `fmc_types`), Language (dropdown `common_iso_languages`).  
  - Resolved startup error: *Form fmcpageone has no rows*.

- **Validation service**  
  - Enabled `dspace/config/spring/api/addon-validation-services.xml` (was `.disabled`).  
  - Resolved *ValidationService bean not found* at startup.

- **Docker & ports**  
  - `docker-compose.yml`: custom subnet `172.28.0.0/16` to avoid conflicts; PostgreSQL published on **5433**; DSpace REST on **8081** (UI points to 8081).  
  - Angular UI override: `docker-compose.angular-8081.yml` so the UI uses `http://localhost:8081/server` for the API.

- **Admin account**  
  - Admin created in the correct backend (container `dspace`).  
  - Login at **http://localhost:4000** with `admin@example.com` and the password set in `fmclib.env` (e.g. `admin5858`).

### 1.2 FMC Adapter API

- **Restored API**  
  - `fmclib/api/` was empty except `venv`; the adapter was recreated with:
    - `app.py`: Flask app with `/`, `/health`, `/search` (proxy to DSpace discovery).
    - `requirements.txt`: flask, requests, gunicorn.
    - `run.py`: loads `../config/fmclib.env`, runs on `FMC_API_PORT` (default **5001**).
  - **Run:** from `fmclib`: `./scripts/run-fmc-api.sh`, or from `fmclib/api`: `source venv/bin/activate && python run.py`.  
  - **Check:** `curl http://localhost:5001/health` → `{"status":"ok"}`.

- **Config**  
  - `fmclib/config/fmclib.env`: `DSPACE_API_URL`, `DSPACE_REST_URL`, `FMC_REST_EMAIL`, `FMC_REST_PASSWORD`, `FMC_DEFAULT_COLLECTION`, `FMC_API_PORT=5001`.

### 1.3 E2E Import & Verification

- **Scripts**  
  - `scripts/e2e-import-and-verify.sh`: CSRF + Bearer auth, resolve collection by handle, create workspace item (`?owningCollection=UUID`), PATCH metadata, submit to workflow, verify via FMC adapter `/search`.  
  - `scripts/load-test-import.sh`: runs E2E N times (default 5).  
  - macOS-safe: `sed '$d'` instead of `head -n -1`; CSRF from header `DSPACE-XSRF-TOKEN`; Bearer from login response header `Authorization`; CSRF refreshed after login and before each modifying request.

- **Test data**  
  - `test-data/sample-item.json`: sample title, author, type, language.

- **Current E2E behaviour**  
  - Login OK, collection resolved, workspace item created (201).  
  - PATCH step returns **500** (server exception) when using `traditionalpageone`; section/field paths need to match the collection’s actual submission form.

### 1.4 Documentation & Scripts

- **Docs**  
  - `fmclib/docs/E2E-STEPS.md`: env, DSpace check, E2E run, UI verify, permissions, load test, MediaWiki.  
  - `fmclib/docs/FIND-FMC-COLLECTION-HANDLE.md`: how to get collection handle.  
  - `fmclib/docs/DSpace-admin-login.md`: admin creation and login.  
  - `fmclib/api/README.md`: adapter quick start and endpoints.

- **Helper script**  
  - `verify-and-fix-dspace-config.sh` (project root): compare container vs host `submission-forms.xml` and advise if volume mount is wrong.

---

## 2. What Is Still Left to Implement

### 2.1 E2E Metadata PATCH (High priority)

- **Issue:** PATCH to `/server/api/submission/workspaceitems/{id}` returns **500** (or previously 422).  
- **Cause:** Section name and/or JSON Patch paths do not match the submission form used by the collection (e.g. `traditionalpageone` vs `fmcpageone`, or different field names).  
- **To do:**  
  1. Capture full stack trace: `docker logs dspace --tail 200` after a failing E2E run.  
  2. Align PATCH paths in `e2e-import-and-verify.sh` with the collection’s form in `submission-forms.xml` and, if used, `item-submission.xml` (step names / section names).  
  3. Optionally: try `fmcpageone` only when the collection is explicitly mapped to the FMC submission (see below).

### 2.2 FMC Collection Mapping (High priority)

- **Current:** `FMC_DEFAULT_COLLECTION=123456789/2` is used; the collection may still use the default submission (e.g. “traditional”), not the FMC form.  
- **To do:**  
  1. In `dspace/config/item-submission.xml`, add a `<name-map>` for the FMC collection, e.g.  
     `collection-handle="123456789/2"` → `submission-name="FMC"` (or whatever name points to a submission definition that uses `fmcpageone`).  
  2. Ensure the submission definition exists and references the `fmcpageone` form.  
  3. Restart DSpace, then re-run E2E with PATCH using `fmcpageone` if that’s the section name for that submission.

### 2.3 Collection Permissions (Medium priority)

- **To do:** In DSpace UI (Admin → Access Control → Groups), create or use a group (e.g. “FMC Submitters”), give it **Submit** on the FMC collection, and add the API user (e.g. `admin@example.com`) to that group.  
- **Why:** Avoids 403 on workspace item creation or workflow for automated submissions.

### 2.4 Usage Statistics / Optional Config (Low priority)

- **Seen in logs:** `The required 'dbfile' configuration is missing in usage-statistics.cfg!`  
- **To do:** Configure `usage-statistics.cfg` (or disable usage stats) if you need statistics; otherwise this can be left as-is.

### 2.5 MediaWiki Integration (When ready)

- **To do:**  
  1. Copy `fmclib/mediawiki` to the MediaWiki `extensions` directory (e.g. `FMCRepository`).  
  2. In `LocalSettings.php`: `wfLoadExtension('FMCRepository');` and `$wgFMCRepositoryAPIUrl = 'http://localhost:5001';` (or your adapter URL).  
  3. Test search/browse from MediaWiki to the FMC adapter.

### 2.6 Production Hardening (Optional)

- Run FMC adapter under Gunicorn (already supported) with a process manager (e.g. systemd) and proper logging.  
- Harden DSpace (HTTPS, firewall, backup).  
- Optional: batch PDF import and any FMC-specific ingest scripts referenced in project docs.

---

## 3. Quick Reference

| Component        | URL / Command |
|-----------------|----------------|
| DSpace UI       | http://localhost:4000 |
| DSpace REST API | http://localhost:8081/server |
| FMC Adapter     | http://localhost:5001 |
| Admin login     | Email/password in `fmclib/config/fmclib.env` |
| E2E run         | `cd fmclib && source config/fmclib.env && bash scripts/e2e-import-and-verify.sh test-data "$FMC_DEFAULT_COLLECTION" http://localhost:5001` |
| Adapter run     | `cd fmclib && ./scripts/run-fmc-api.sh` |

---

## 4. File Locations (implementation-related)

- **DSpace:** `dspace/config/submission-forms.xml`, `item-submission.xml`, `spring/api/addon-validation-services.xml`.  
- **Compose:** `docker-compose.yml`, `docker-compose.angular-8081.yml`.  
- **FMC:** `fmclib/config/fmclib.env`, `fmclib/api/app.py`, `fmclib/scripts/e2e-import-and-verify.sh`, `fmclib/scripts/run-fmc-api.sh`.  
- **Docs:** `fmclib/docs/E2E-STEPS.md`, `fmclib/docs/FIND-FMC-COLLECTION-HANDLE.md`, `fmclib/README-IMPLEMENTATION.md` (this file).
