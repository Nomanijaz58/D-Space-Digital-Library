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
  - Metadata PATCH succeeds (200) using the correct section (`fmcpageone` for the FMC-mapped collection).  
  - Workflow submit succeeds (201).  
  - Verification via FMC adapter `/search` succeeds (item found in discovery).  
  - End-to-end run prints: `E2E test PASSED`.

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

### 2.1 Remaining Work

- (Optional) Add an `/items` endpoint to the FMC adapter (or update any docs/tests to consistently use `/search`).

### 2.3 Collection Permissions (Medium priority)

- **To do:** In DSpace UI (Admin → Access Control → Groups), create or use a group (e.g. “FMC Submitters”), give it **Submit** on the FMC collection, and add the API user (e.g. `admin@example.com`) to that group.  
- **Why:** Avoids 403 on workspace item creation or workflow for automated submissions.

### 2.4 Usage Statistics / Optional Config (Low priority)

- **Seen in logs:** `The required 'dbfile' configuration is missing in usage-statistics.cfg!`  
- **To do:** Configure `usage-statistics.cfg` (or disable usage stats) if you need statistics; otherwise this can be left as-is.

### 2.5 MediaWiki Integration (When ready)

- Completed: MediaWiki integration is working via Docker and `Special:FMCRepository`.

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
| MediaWiki (Docker) | http://localhost:8082/html/index.php/Main_Page |
| Admin login     | Email/password in `fmclib/config/fmclib.env` |
| E2E run         | `cd fmclib && source config/fmclib.env && bash scripts/e2e-import-and-verify.sh test-data "$FMC_DEFAULT_COLLECTION" http://localhost:5001` |
| Adapter run     | `cd fmclib && ./scripts/run-fmc-api.sh` |

---

## 4. File Locations (implementation-related)

- **DSpace:** `dspace/config/submission-forms.xml`, `item-submission.xml`, `spring/api/addon-validation-services.xml`.  
- **Compose:** `docker-compose.yml`, `docker-compose.angular-8081.yml`.  
- **FMC:** `fmclib/config/fmclib.env`, `fmclib/api/app.py`, `fmclib/scripts/e2e-import-and-verify.sh`, `fmclib/scripts/run-fmc-api.sh`.  
- **Docs:** `fmclib/docs/E2E-STEPS.md`, `fmclib/docs/FIND-FMC-COLLECTION-HANDLE.md`, `fmclib/README-IMPLEMENTATION.md` (this file).
