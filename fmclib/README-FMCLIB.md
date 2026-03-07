
# FMC Library (fmclib)

## What has been implemented

- **DSpace submission integration**
  - FMC submission form and collection mapping configured.
  - E2E submission + workflow + discovery verification is working.

- **FMC Adapter API (Flask)**
  - Endpoints:
    - `GET /health`
    - `GET /search` (unchanged)
    - `GET /items/<uuid>` (optional)
  - Request logging enabled.

- **MediaWiki integration**
  - `FMCRepository` extension installed and `Special:FMCRepository` works end-to-end against the adapter.

For detailed status, see: `fmclib/README-IMPLEMENTATION.md`.

## Quick URLs

- **DSpace UI**: `http://localhost:4000`
- **DSpace REST API**: `http://localhost:8081/server`
- **FMC Adapter**: `http://localhost:5001`
- **MediaWiki**: `http://localhost:8082/html/index.php/Main_Page`
- **MediaWiki FMC page**: `http://localhost:8082/html/index.php?title=Special:FMCRepository`

## Running FMC Adapter (Production)

```bash
./scripts/start-fmc-production.sh
```

This replaces:

```bash
python run.py
```

Uses Gunicorn instead of Flask dev server.

Stop:

```bash
./scripts/stop-fmc.sh
```
