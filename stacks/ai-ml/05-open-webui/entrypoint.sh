#!/bin/sh
# Entrypoint wrapper: reads Docker secrets and exports them as env vars
# before starting Open WebUI.
# This is the standard pattern for Docker Swarm + secrets + apps
# that don't natively support *_FILE env var conventions.

set -e

# Read secrets and export as environment variables
if [ -f /run/secrets/pg_openwebui_pass ]; then
    PG_PASS=$(cat /run/secrets/pg_openwebui_pass)
    export DATABASE_URL="postgresql://openwebui:${PG_PASS}@192.168.80.200:5432/openwebui"
fi

if [ -f /run/secrets/openwebui_secret_key ]; then
    export WEBUI_SECRET_KEY=$(cat /run/secrets/openwebui_secret_key)
fi

if [ -f /run/secrets/qdrant_api_key ]; then
    export QDRANT_API_KEY=$(cat /run/secrets/qdrant_api_key)
fi

# Bootstrap admin account on first startup (no-op if admin already exists).
# Open WebUI creates the admin account from these env vars when the DB is empty.
# ENABLE_SIGNUP stays "false" so no other users can self-register.
if [ -f /run/secrets/openwebui_admin_email ]; then
    export WEBUI_ADMIN_EMAIL=$(cat /run/secrets/openwebui_admin_email)
fi

if [ -f /run/secrets/openwebui_admin_pass ]; then
    export WEBUI_ADMIN_PASSWORD=$(cat /run/secrets/openwebui_admin_pass)
fi

# Start Open WebUI (default entrypoint)
exec bash start.sh
