#!/usr/bin/env bash
pkill -f "gunicorn.*wsgi:app" || true
echo "FMC Adapter stopped."
