# DSpace Docker Deployment

Production-hardened Docker Compose setup for [DSpace](https://dspace.lyrasis.org/) with PostgreSQL, Solr, persistent volumes, and optional SSL reverse proxy support.

---

## What's implemented

Summary of what is in place in this repo:

| Area | Implementation |
|------|----------------|
| **Compose** | Three services: `dspacedb` (PostgreSQL 15), `solr` (Solr 9.3), `dspace` (image `dspace/dspace:dspace-7_x`). Run from project root so Compose finds `docker-compose.yml`. |
| **PostgreSQL** | Database `dspace`, user `dspace`, healthcheck so other services wait for a ready DB. Persistent volume `dspace_pgdata`. |
| **DB migration** | DSpace runs Flyway migration on startup. Custom entrypoint `scripts/entrypoint-dspace.sh`: waits for `dspacedb`, runs `dspace database migrate`, then starts Tomcat. Ensures schema exists before the app starts. |
| **pgcrypto** | DSpace 7 requires PostgreSQL `pgcrypto` extension. `scripts/init-pgcrypto.sql` is mounted into Postgres as `/docker-entrypoint-initdb.d/01-pgcrypto.sql` so new installs get the extension automatically. For existing DBs, one-time: `docker compose exec dspacedb psql -U dspace -d dspace -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto;'` then restart DSpace. |
| **Solr** | Solr service with persistent `solr_data`. If the "search" core is missing or broken, `scripts/fix-solr-search-core.sh` fixes it; then `docker compose restart dspace`. |
| **DSpace config** | Env in Compose: `DB_URL` / `db__P__url` → `dspacedb:5432/dspace`, `SOLR_URL` / `solr__P__server` → `solr:8983`. |
| **Scripts** | `entrypoint-dspace.sh` (startup), `init-pgcrypto.sql` (Postgres init), `fix-solr-search-core.sh`, `batch-upload.sh`, `ocr-pipeline.sh`, `backup.sh`. |
| **Docs** | First-time setup (entrypoint, pgcrypto, Solr core), troubleshooting (pgcrypto error, missing table `bitstream`, logs), backup/restore, upgrade workflow, file layout. |

**First run:** From project root: `chmod +x scripts/entrypoint-dspace.sh`, then `docker compose up -d`. Backend when ready: http://127.0.0.1:8080/server (startup can take ~1–2 minutes).

---

## Contents

- **docker-compose.yml** – Orchestration for DSpace, PostgreSQL, and Solr with healthchecks and restart policies
- **.env.example** – Template for environment variables (copy to `.env`)
- **scripts/batch-upload.sh** – Bulk PDF upload with CSV metadata and resume support
- **scripts/ocr-pipeline.sh** – OCR (OCRmyPDF + Tesseract) and Solr reindex
- **scripts/backup.sh** – Backup and restore for PostgreSQL and assetstore

---

## Requirements

- Docker Engine 20.10+ and Docker Compose v2
- For building from source: DSpace source tree with `dspace/config`, `dspace/solr`, and `dspace/src/main/docker/dspace-solr`
- For scripts: Bash, and (for OCR) `ocrmypdf`, `tesseract`, optionally `pdftotext`/`pdftoppm`

---

## Installation

### 1. Clone or place files

Ensure you have:

- This repo (or at least `docker-compose.yml` and `.env.example`)
- If building images: full DSpace source tree in the same directory (e.g. `./dspace/` with config and Solr configs)

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env and set at least:
#   POSTGRES_PASSWORD=<strong-password>
# Adjust other variables as needed (bind addresses, site name, etc.).
```

**Important:** Never commit `.env`; it may contain secrets.

### 3. First-time setup (pre-built image)

- **Always run Compose from the project root** so `docker-compose.yml` is found:
  ```bash
  cd /path/to/tony
  docker compose up -d
  ```
- **Entrypoint:** Ensure the DB-migration script is executable:
  ```bash
  chmod +x scripts/entrypoint-dspace.sh
  ```
  The DSpace container runs this script on startup: it waits for PostgreSQL, runs `dspace database migrate` (when the CLI is present at `/dspace/bin/dspace` or `$DSPACE_HOME/bin/dspace`), then starts Tomcat. This creates the DSpace schema on first run.
- **PostgreSQL pgcrypto:** DSpace 7 requires the `pgcrypto` extension in the database. For **new** installs, `scripts/init-pgcrypto.sql` is run automatically when the Postgres data directory is first created. If you already had a database (existing volume) and see a "pgcrypto extension must be installed" error, run once then restart DSpace:
  ```bash
  docker compose exec dspacedb psql -U dspace -d dspace -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto;'
  docker compose restart dspace
  ```
- **Solr search core:** If the backend fails with Solr "search" core errors, fix the core then restart:
  ```bash
  ./scripts/fix-solr-search-core.sh
  docker compose restart dspace
  ```

### 4. Start the stack

```bash
docker compose up -d
```

To build images from source (when DSpace source is present):

```bash
docker compose up -d --build
```

### 5. Verify

- Backend: http://127.0.0.1:8080/server (or the host/port you set in `.env`)
- Solr: http://127.0.0.1:8983/solr (if exposed)
- Check containers: `docker compose ps`

---

## Configuration

### Environment variables (.env)

| Variable | Description | Default |
|----------|-------------|--------|
| `POSTGRES_PASSWORD` | **Required.** PostgreSQL password | (none) |
| `POSTGRES_DB` | Database name | `dspace` |
| `POSTGRES_USER` | Database user | `dspace` |
| `POSTGRES_VERSION` | PostgreSQL image tag | `15` |
| `POSTGRES_BIND` | Host to bind DB port | `127.0.0.1` |
| `DSPACE_VER` | DSpace image tag | `latest-test` |
| `DSPACE_SITE_NAME` | Site name in DSpace | `DSpace` |
| `DSPACE_SERVER_BIND` | Host for port 8080 | `127.0.0.1` |
| `DSPACE_DEBUG_BIND` | Host for port 8000 | `127.0.0.1` |
| `SOLR_BIND` | Host for Solr 8983 | `127.0.0.1` |
| `DSPACE_TRUSTED_IPRANGES` | Trusted proxy IP prefix | `172.23.0` |
| `DSPACE_NETWORK_SUBNET` | Docker network subnet | `172.23.0.0/16` |

Binding to `127.0.0.1` limits access to the host. For a reverse proxy on the same host, keep that. To expose on all interfaces (e.g. proxy on another host), set `*_BIND=0.0.0.0` (or omit the host in the mapping).

### Persistent volumes

- **pgdata** – PostgreSQL data
- **assetstore** – DSpace bitstream storage
- **solr_data** – Solr indexes

Data survives `docker compose down`. Use `docker compose down -v` only if you intend to remove volumes (destructive).

### Optional SSL reverse proxy

The Compose file does not include a proxy. To add HTTPS:

1. Keep services bound to `127.0.0.1` (or a private network) so only the proxy is public.
2. Run a reverse proxy (e.g. Traefik, nginx, Caddy) on the same host or another host.
3. Point the proxy to:
   - Backend: `http://dspace:8080` (or `http://<host>:8080` if proxy is off-host)
   - Optionally Solr for admin: `http://dspacesolr:8983`
4. Set `DSPACE_TRUSTED_IPRANGES` to the proxy’s IP range so DSpace trusts forwarded headers.

---

## Backup and restore

### Backup (PostgreSQL + assetstore)

```bash
./scripts/backup.sh
```

- Backups go to `BACKUP_DIR` (default: `./backups/`).
- Files: `dspace-db-YYYYMMDD-HHMMSS.sql.gz`, `dspace-assetstore-YYYYMMDD-HHMMSS.tar.gz`.
- Backups older than `RETENTION_DAYS` (default: 30) are removed.

Backup only DB or only assetstore:

```bash
./scripts/backup.sh --db-only
./scripts/backup.sh --assetstore-only
```

### Restore

**Database:**

```bash
# Stop DSpace app if desired to avoid writes during restore
docker compose stop dspace
./scripts/backup.sh restore-db ./backups/dspace-db-YYYYMMDD-HHMMSS.sql.gz
docker compose start dspace
# Rebuild discovery index
docker exec dspace /dspace/bin/dspace index-discovery -b
```

**Assetstore:**

```bash
./scripts/backup.sh restore-assetstore ./backups/dspace-assetstore-YYYYMMDD-HHMMSS.tar.gz
```

If your Compose project name is not `dspace`, set `COMPOSE_PROJECT_NAME` (and optionally `PGDATA_VOLUME` / `ASSETSTORE_VOLUME`) when running the backup script.

---

## Upgrade workflow

1. **Back up:** run `./scripts/backup.sh`.
2. **Review release notes** for the target DSpace version and any DB migrations.
3. **Set new image version** in `.env`, e.g. `DSPACE_VER=8.0` (or the tag you use).
4. **Pull/rebuild:**
   - Pre-built: `docker compose pull`
   - From source: `docker compose build --no-cache`
5. **Stop and recreate:**
   ```bash
   docker compose down
   docker compose up -d
   ```
6. **Migrations:** DSpace runs `database migrate` on startup; check logs: `docker compose logs dspace`.
7. **Reindex if needed:** `docker exec dspace /dspace/bin/dspace index-discovery -b`.
8. **Smoke-test** UI and search.

---

## Scripts

### batch-upload.sh

Bulk import of PDFs with metadata from a CSV (SAF-based import inside the container).

```bash
./scripts/batch-upload.sh metadata.csv 123456789/4
```

- **CSV:** Header row with column `file` (path to PDF) and Dublin Core columns: `dc.title`, `dc.contributor.author`, `dc.date.issued`, etc.
- **Resume:** Successful runs are recorded in `.batch-upload-state`; re-run with the same CSV to skip already-imported rows.
- **Logs:** Under `logs/batch-upload-*.log`.
- **Environment:** `DSPACE_EPERSON`, `DSPACE_CONTAINER`, `STATE_FILE`, `SAF_ROOT`, `RESUME`, `DRY_RUN`.

### ocr-pipeline.sh

Run OCR on PDFs (OCRmyPDF + Tesseract), write `.txt` sidecars, and optionally run DSpace discovery reindex.

```bash
./scripts/ocr-pipeline.sh /path/to/pdfs
```

- **Options:** `OCR_OUTPUT_DIR`, `SKIP_EXISTING=1`, `REINDEX=1`, `DSPACE_CONTAINER`, `LOG_DIR`.
- **Requires:** `ocrmypdf`, `tesseract`; for better TXT extraction, `pdftotext`/`pdftoppm`.

### backup.sh

See [Backup and restore](#backup-and-restore) above.

---

## Troubleshooting

### Containers not starting

- **Database:** Ensure `POSTGRES_PASSWORD` is set in `.env` (required).
- **Port in use:** Change `*_BIND` or the published port in `docker-compose.yml`.
- **Build fails:** If using build from source, ensure `./dspace/config`, `./dspace/solr`, and `./dspace/src/main/docker/dspace-solr` exist and match your DSpace version.

### DSpace fails to start

- **DB connection:** Wait for DB healthcheck; DSpace depends on `dspacedb` with `condition: service_healthy`.
- **"pgcrypto extension must be installed":** DSpace 7 requires the PostgreSQL `pgcrypto` extension. For a **new** install, the init script `scripts/init-pgcrypto.sql` is mounted and runs when the DB is first created. If you already had a database (e.g. existing `dspace_pgdata` volume), run once: `docker compose exec dspacedb psql -U dspace -d dspace -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto;'` then `docker compose restart dspace`.
- **Schema-validation: missing table [bitstream]:** The database schema was not created—often because migration failed earlier (e.g. missing `pgcrypto`). Ensure `scripts/entrypoint-dspace.sh` is executable (`chmod +x scripts/entrypoint-dspace.sh`) and that the DSpace image has the CLI at `/dspace/bin/dspace` or `$DSPACE_HOME/bin/dspace`. Check startup logs for "Running DSpace database migration...", "DSpace CLI not found", or "pgcrypto extension must be installed"; fix any migration error then restart.
- **Logs:** `docker compose logs dspace` and `docker compose logs dspacedb`.
- **Config:** Check `./dspace/config` and env overrides (e.g. `db__P__url`, `solr__P__server`).

### Solr / search issues

- **Reindex:** `docker exec dspace /dspace/bin/dspace index-discovery -b`.
- **Solr cores:** Solr entrypoint creates cores on first run; to apply config changes, rebuild: `docker compose up -d --build dspacesolr`.

### Backup / restore

- **Volume not found:** Set `COMPOSE_PROJECT_NAME` to the project name you use for `docker compose` (often the directory name). Volume names are `<project>_pgdata` and `<project>_assetstore`.
- **Restore overwrites data:** Restore replaces or merges into existing DB/assetstore; ensure you have a backup before restoring.

### Batch import

- **“Container not running”:** Start stack with `docker compose up -d`.
- **Import fails:** Check `logs/batch-upload-*.log` and `docker compose logs dspace`. Ensure collection handle and e-person email exist.
- **Resume:** To start over, remove `.batch-upload-state` (or set `RESUME=0`).

---

## File layout (reference)

```
.
├── docker-compose.yml   # Services, volumes, networks
├── .env                 # Your secrets and overrides (do not commit)
├── .env.example         # Template
├── README.md            # This file
├── dspace/              # Optional: DSpace source for build
│   ├── config/
│   ├── solr/
│   └── src/main/docker/dspace-solr/
├── scripts/
│   ├── entrypoint-dspace.sh   # DB wait + database migrate on startup
│   ├── init-pgcrypto.sql     # Postgres init: enable pgcrypto for DSpace 7
│   ├── fix-solr-search-core.sh
│   ├── batch-upload.sh
│   ├── ocr-pipeline.sh
│   └── backup.sh
├── logs/                # Created by scripts
├── backups/             # Created by backup.sh
└── saf-import/          # Created by batch-upload.sh
```

---

## License and attribution

DSpace is licensed under the BSD 3-Clause License. This Compose and scripts are provided as-is for deployment and automation; modify as needed for your environment.
