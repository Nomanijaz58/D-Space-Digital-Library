# FMC Adapter API

Thin proxy to DSpace REST API (search/browse). Serves on **port 5001** by default (`FMC_API_PORT` in `../config/fmclib.env`).

## Quick start

```bash
# From DSpace-main/fmclib
cd api
rm -rf venv
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Load config and run (from fmclib root)
cd ..
./scripts/run-fmc-api.sh
```

Or from `fmclib/api`:

```bash
source venv/bin/activate
export $(grep -v '^#' ../config/fmclib.env | xargs)  # optional: load FMC_API_PORT, DSPACE_REST_URL
python run.py
# or: gunicorn -b 0.0.0.0:5001 app:app
```

## Endpoints

| Path     | Description        |
|----------|--------------------|
| `GET /`  | API info (JSON)   |
| `GET /health` | Health check (E2E) |
| `GET /search?query=...&size=20&page=0` | Proxy to DSpace discovery |

## Verify

```bash
curl http://localhost:5001/health
# => {"status":"ok"}

curl http://localhost:5001/
# => JSON with name, version, endpoints
```
