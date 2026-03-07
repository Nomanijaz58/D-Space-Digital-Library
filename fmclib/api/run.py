#!/usr/bin/env python3
"""Run FMC Adapter with Flask dev server. For production use: gunicorn -b 0.0.0.0:5001 app:app"""
import os
import sys

# Load fmclib.env if present (parent dir)
_env = os.path.join(os.path.dirname(__file__), "..", "config", "fmclib.env")
if os.path.isfile(_env):
    with open(_env) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())

from app import app, FMC_API_PORT

if __name__ == "__main__":
    port = int(os.environ.get("FMC_API_PORT", str(FMC_API_PORT)))
    print(f"FMC Adapter starting on http://0.0.0.0:{port}")
    app.run(host="0.0.0.0", port=port, debug=True)
