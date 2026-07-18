#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" &&
  pwd
)"

sudo install \
  -m 0755 \
  "${SCRIPT_DIR}/docker-container-cleanup.sh" \
  /usr/local/sbin/lab-docker-container-cleanup

sudo install \
  -m 0644 \
  "${SCRIPT_DIR}/systemd/lab-docker-container-cleanup.service" \
  /etc/systemd/system/lab-docker-container-cleanup.service

sudo install \
  -m 0644 \
  "${SCRIPT_DIR}/systemd/lab-docker-container-cleanup.timer" \
  /etc/systemd/system/lab-docker-container-cleanup.timer

if [[ ! -f /etc/default/lab-docker-container-cleanup ]]; then
  sudo tee \
    /etc/default/lab-docker-container-cleanup \
    >/dev/null <<'CONFIG'
APPLY=true
RETENTION=24h
IMAGE_PRUNE_DANGLING=true
IMAGE_RETENTION=72h
REPORT_DIR=/var/log/lab-health/docker-cleanup
CONFIG
fi

sudo install \
  -d \
  -m 0755 \
  /var/log/lab-health/docker-cleanup

sudo systemctl daemon-reload
sudo systemctl enable \
  --now \
  lab-docker-container-cleanup.timer

echo "DOCKER_CONTAINER_CLEANUP_INSTALL=SUCCESS"
echo "APPLY_MODE=$(
  sudo awk -F= \
    '$1 == "APPLY" {print $2}' \
    /etc/default/lab-docker-container-cleanup
)"
