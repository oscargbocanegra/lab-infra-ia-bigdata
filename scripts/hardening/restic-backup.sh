#!/usr/bin/env bash
# restic-backup.sh — Daily backup automation using restic → MinIO
# Schedule: cron daily at 02:00 on both nodes
# Retention: 7 daily, 4 weekly, 3 monthly
#
# Install on each node:
#   sudo cp scripts/hardening/restic-backup.sh /usr/local/bin/restic-backup.sh
#   sudo chmod +x /usr/local/bin/restic-backup.sh
#   echo "0 2 * * * root /usr/local/bin/restic-backup.sh >> /var/log/restic-backup.log 2>&1" \
#     | sudo tee /etc/cron.d/restic-backup
#
# First-time init on each node:
#   sudo RESTIC_PASSWORD=<your-password> /usr/local/bin/restic-backup.sh --init
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
# MinIO runs on master2 and is only accessible from within that host (Docker overlay).
# This script must run locally on each node:
#   - master2: connects to localhost:9000 (MinIO direct)
#   - master1: connects to localhost:9000 if MinIO is also present, otherwise skip
# The S3 endpoint is always localhost:9000 from each node's perspective.
MINIO_ENDPOINT="http://localhost:9000"
MINIO_BUCKET="backups"
AWS_ACCESS_KEY_ID="minioadmin"
# NOTE: Set AWS_SECRET_ACCESS_KEY in /etc/restic/env or pass via environment
# Real value from MinIO secrets — do not hardcode in this file
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-minioadmin}"
RESTIC_REPOSITORY="s3:${MINIO_ENDPOINT}/${MINIO_BUCKET}/$(hostname)"
RESTIC_PASSWORD_FILE="/etc/restic/password"
LOG_TAG="restic-backup"

# Paths to back up — adjust per node
if [[ "$(hostname)" == "master1" ]]; then
  BACKUP_PATHS=(
    /srv/fastdata/traefik
    /srv/fastdata/prometheus
    /srv/fastdata/grafana
  )
else
  BACKUP_PATHS=(
    /srv/fastdata/postgres
    /srv/fastdata/qdrant
    /srv/fastdata/open-webui
    /srv/fastdata/n8n
  )
fi

# ── Exports ──────────────────────────────────────────────────────────────────
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export RESTIC_REPOSITORY
export RESTIC_PASSWORD_FILE

# ── Init mode ────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--init" ]]; then
  echo "[${LOG_TAG}] Initializing restic repository at ${RESTIC_REPOSITORY}"
  mkdir -p /etc/restic
  if [[ -n "${RESTIC_PASSWORD:-}" ]]; then
    echo "${RESTIC_PASSWORD}" > "${RESTIC_PASSWORD_FILE}"
    chmod 600 "${RESTIC_PASSWORD_FILE}"
    echo "[${LOG_TAG}] Password saved to ${RESTIC_PASSWORD_FILE}"
  fi
  restic init
  echo "[${LOG_TAG}] Repository initialized"
  exit 0
fi

# ── Backup ───────────────────────────────────────────────────────────────────
echo "[${LOG_TAG}] $(date -Iseconds) — Starting backup on $(hostname)"

restic backup \
  --verbose \
  --tag "$(hostname)" \
  --tag "$(date +%Y-%m-%d)" \
  "${BACKUP_PATHS[@]}"

echo "[${LOG_TAG}] $(date -Iseconds) — Backup complete. Applying retention policy..."

# ── Retention ────────────────────────────────────────────────────────────────
restic forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 3 \
  --prune \
  --verbose

echo "[${LOG_TAG}] $(date -Iseconds) — Retention applied"

# ── Health check ─────────────────────────────────────────────────────────────
restic check --no-lock

echo "[${LOG_TAG}] $(date -Iseconds) — All done"
