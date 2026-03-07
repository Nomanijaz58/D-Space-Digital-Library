"""
FMC Adapter API: thin proxy to DSpace REST API for search/browse.
Serves on FMC_API_PORT (default 5001). Use with: gunicorn -b 0.0.0.0:5001 app:app
"""
import logging
import os
import requests
from flask import Flask, request, jsonify


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Load from env (set by fmclib.env or shell)
DSPACE_API_URL = os.environ.get(
    "DSPACE_API_URL",
    os.environ.get("DSPACE_REST_URL", "http://localhost:8081/server/api"),
)
FMC_API_PORT = int(os.environ.get("FMC_API_PORT", "5001"))


@app.before_request
def log_request():
    logger.info(f"{request.method} {request.path}")


@app.route("/")
def index():
    return jsonify({
        "name": "FMC Adapter API",
        "version": "1.0",
        "dspace_rest": DSPACE_API_URL,
        "endpoints": ["/health", "/search", "/"],
    })


@app.route("/health")
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/search")
def search():
    """Proxy search to DSpace discovery. query= optional; omit for 'match all'."""
    q = (request.args.get("query") or request.args.get("q") or "").strip()
    size = request.args.get("size", "20")
    page = request.args.get("page", "0")
    # DSpace discovery: omit query param for match-all to avoid 400
    params = {"size": size, "page": page}
    if q and q != "*":
        params["query"] = q
    try:
        r = requests.get(
            f"{DSPACE_API_URL}/discover/search/objects",
            params=params,
            timeout=15,
        )
        r.raise_for_status()
        return jsonify(r.json())
    except requests.RequestException as e:
        return jsonify({"error": str(e)}), 502


@app.route("/items/<uuid>", methods=["GET"])
def get_item(uuid):
    try:
        url = f"{DSPACE_API_URL}/core/items/{uuid}"
        r = requests.get(url)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        logger.error(f"Item fetch failed: {e}")
        return {"error": str(e)}, 500


if __name__ == "__main__":
    port = int(os.environ.get("FMC_API_PORT", "5001"))
    app.run(host="0.0.0.0", port=port, debug=True)
