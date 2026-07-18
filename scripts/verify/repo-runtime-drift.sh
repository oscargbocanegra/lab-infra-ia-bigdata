#!/usr/bin/env bash
# Lightweight repo/runtime drift snapshot for the lab (non-destructive).

set -euo pipefail

REPORT_DIR="${LAB_REPORT_DIR:-${HOME}/lab-reports}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_PATH="${REPORT_DIR}/repo-runtime-drift-${TIMESTAMP}.txt"
mkdir -p "${REPORT_DIR}"
exec > >(tee "${REPORT_PATH}") 2>&1

echo "REPO_RUNTIME_DRIFT_REPORT_START=$(date --iso-8601=seconds)"
echo "HOST=$(hostname)"
echo

echo "== GIT STATUS =="
echo "BRANCH=$(git branch --show-current)"
echo "HEAD=$(git rev-parse --short HEAD)"
echo "ORIGIN_MAIN=$(git rev-parse --short origin/main 2>/dev/null || echo 'n/a')"
echo

echo "== STACK SERVICES =="
for stack in traefik portainer postgres n8n ollama opensearch minio spark airflow rag-api agent fluent-bit prometheus grafana; do
  echo "-- stack=${stack}"
  docker stack services "${stack}" 2>/dev/null || echo "stack-not-found"
done
echo

echo "== SWARM NODES =="
docker node ls || true
echo

echo "REPO_RUNTIME_DRIFT_REPORT_END=$(date --iso-8601=seconds)"
echo "REPORT=${REPORT_PATH}"
