#!/bin/sh
# Entrypoint wrapper: reads Docker secrets and exports them as env vars
# before starting Open WebUI. Also bootstraps the first admin account
# if no users exist yet.
#
# Bootstrap strategy:
#   Open WebUI blocks /api/v1/auths/signup when ENABLE_SIGNUP=false, even
#   for the very first user. To work around this we:
#     1. Start uvicorn temporarily with ENABLE_SIGNUP=true
#     2. Wait for the server to be ready
#     3. POST to /api/v1/auths/signup (first user gets role=admin automatically)
#     4. Kill the temporary uvicorn process
#     5. Re-exec the real server with ENABLE_SIGNUP=false (from env)
#   This is idempotent: if a user already exists the signup call returns 400
#   (email taken) and we skip silently.

set -e

# ── Read secrets ────────────────────────────────────────────────────────────

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

ADMIN_EMAIL=""
ADMIN_PASS=""

if [ -f /run/secrets/openwebui_admin_email ]; then
    ADMIN_EMAIL=$(cat /run/secrets/openwebui_admin_email)
fi

if [ -f /run/secrets/openwebui_admin_pass ]; then
    ADMIN_PASS=$(cat /run/secrets/openwebui_admin_pass)
fi

# ── Bootstrap admin (first-run only) ────────────────────────────────────────

if [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASS" ]; then
    echo "[entrypoint] Starting temporary server to bootstrap admin account..."

    # Must cd to /app/backend so open_webui module can be imported
    cd /app/backend

    # Start uvicorn with signup enabled (needed to create the first user)
    ENABLE_SIGNUP=true WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" \
        uvicorn open_webui.main:app \
            --host 127.0.0.1 \
            --port 8081 \
            --workers 1 \
            --forwarded-allow-ips '*' &
    BOOTSTRAP_PID=$!

    # Wait for server to be ready (max 90 seconds) — uses curl, wget is not available
    echo "[entrypoint] Waiting for bootstrap server..."
    i=0
    while [ $i -lt 90 ]; do
        if curl -sf http://127.0.0.1:8081/health 2>/dev/null | grep -q "true"; then
            break
        fi
        sleep 1
        i=$((i + 1))
    done

    if [ $i -ge 90 ]; then
        echo "[entrypoint] WARNING: bootstrap server did not become ready, skipping admin creation"
    else
        echo "[entrypoint] Bootstrap server ready. Creating admin account..."
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST http://127.0.0.1:8081/api/v1/auths/signup \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASS}\",\"name\":\"Admin\"}")
        echo "[entrypoint] Signup response status: ${HTTP_CODE} (200=created, 400=already exists, both are OK)"
    fi

    echo "[entrypoint] Stopping bootstrap server..."
    kill "$BOOTSTRAP_PID" 2>/dev/null || true
    wait "$BOOTSTRAP_PID" 2>/dev/null || true
fi

# ── Start the real server ────────────────────────────────────────────────────
echo "[entrypoint] Starting Open WebUI..."
cd /app/backend
exec bash start.sh
