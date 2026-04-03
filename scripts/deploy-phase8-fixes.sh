#!/bin/bash
# =============================================================================
# Phase 8 Fix: Open WebUI admin bootstrap + Qdrant Web UI redirect
# Run from: master1 (ssh ogiovanni@192.168.80.100)
# Assumes: git pull already done, repo at ~/lab-infra-ia-bigdata
# =============================================================================
set -euo pipefail

REPO=~/lab-infra-ia-bigdata
ADMIN_EMAIL="ogiovanni@lab.local"
ADMIN_PASS="jupyter2024"

echo "==> [1/7] Creating new Docker secrets for Open WebUI admin bootstrap..."

# Create admin email secret (idempotent: skip if already exists)
if ! docker secret inspect openwebui_admin_email &>/dev/null; then
    echo -n "${ADMIN_EMAIL}" | docker secret create openwebui_admin_email -
    echo "    openwebui_admin_email created."
else
    echo "    openwebui_admin_email already exists — skipping."
fi

# Create admin password secret (idempotent: skip if already exists)
if ! docker secret inspect openwebui_admin_pass &>/dev/null; then
    echo -n "${ADMIN_PASS}" | docker secret create openwebui_admin_pass -
    echo "    openwebui_admin_pass created."
else
    echo "    openwebui_admin_pass already exists — skipping."
fi

echo ""
echo "==> [2/7] Recreating Docker config openwebui_entrypoint (configs are immutable)..."

# Scale down Open WebUI to 0 replicas before removing the config
docker service scale open-webui_open-webui=0 || true
sleep 5

# Remove old config if it exists
if docker config inspect openwebui_entrypoint &>/dev/null; then
    docker config rm openwebui_entrypoint
    echo "    Old config removed."
fi

# Create new config from updated entrypoint.sh
docker config create openwebui_entrypoint "${REPO}/stacks/ai-ml/05-open-webui/entrypoint.sh"
echo "    openwebui_entrypoint config created."

echo ""
echo "==> [3/7] Deploying Open WebUI stack..."
docker stack deploy \
    --with-registry-auth \
    --prune \
    -c "${REPO}/stacks/ai-ml/05-open-webui/stack.yml" \
    open-webui

echo ""
echo "==> [4/7] Redeploying Qdrant stack (pick up new Traefik redirect middleware)..."
docker stack deploy \
    --with-registry-auth \
    --prune \
    -c "${REPO}/stacks/ai-ml/03-qdrant/stack.yml" \
    qdrant

echo ""
echo "==> [5/7] Building RAG API Docker image on master1..."
cd "${REPO}/stacks/ai-ml/04-rag-api"
docker build -t lab-rag-api:latest .
echo "    lab-rag-api:latest built."

echo ""
echo "==> [6/7] Deploying RAG API stack..."
docker stack deploy \
    --with-registry-auth \
    --prune \
    -c "${REPO}/stacks/ai-ml/04-rag-api/stack.yml" \
    rag-api

echo ""
echo "==> [7/7] Waiting for all services to stabilize (40s)..."
sleep 40

echo ""
echo "==> Service status:"
docker service ls | grep -E "qdrant|open-webui|rag-api"

echo ""
echo "==> Open WebUI logs (last 20 lines):"
docker service logs --tail 20 open-webui_open-webui 2>&1 || true

echo ""
echo "==> RAG API logs (last 20 lines):"
docker service logs --tail 20 rag-api_rag-api 2>&1 || true

echo ""
echo "==> Done!"
echo "    Open WebUI: https://chat.sexydad  (admin: ${ADMIN_EMAIL} / ${ADMIN_PASS})"
echo "    Qdrant UI:  https://qdrant.sexydad  (redirects to /dashboard)"
echo "    RAG API:    https://rag-api.sexydad/docs"
