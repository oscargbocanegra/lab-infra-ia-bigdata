#!/usr/bin/env bash
# cert-rotate.sh — TLS certificate rotation check and renewal
# Checks expiry of self-signed certs. If < 30 days remaining, regenerates
# and triggers a Traefik service update to pick up the new cert.
#
# Schedule: cron weekly (Sunday 03:00) on master1
#   echo "0 3 * * 0 root /usr/local/bin/cert-rotate.sh >> /var/log/cert-rotate.log 2>&1" \
#     | sudo tee /etc/cron.d/cert-rotate
#
# Run manually: sudo bash scripts/hardening/cert-rotate.sh
set -euo pipefail

CERT_DIR="/srv/fastdata/traefik/certs"
CERT_FILE="${CERT_DIR}/local.crt"
KEY_FILE="${CERT_DIR}/local.key"
DAYS_THRESHOLD=30
LOG_TAG="cert-rotate"
TRAEFIK_SERVICE="core_traefik"

echo "[${LOG_TAG}] $(date -Iseconds) — Checking TLS certificate expiry"

if [[ ! -f "${CERT_FILE}" ]]; then
  echo "[${LOG_TAG}] Certificate not found at ${CERT_FILE} — will generate"
  NEEDS_ROTATE=true
else
  # Get expiry date in epoch seconds
  EXPIRY_EPOCH=$(openssl x509 -in "${CERT_FILE}" -noout -enddate \
    | sed 's/notAfter=//' \
    | xargs -I{} date -d "{}" +%s)
  NOW_EPOCH=$(date +%s)
  DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

  echo "[${LOG_TAG}] Certificate expires in ${DAYS_LEFT} days (threshold: ${DAYS_THRESHOLD})"

  if (( DAYS_LEFT < DAYS_THRESHOLD )); then
    echo "[${LOG_TAG}] Certificate expiring soon — rotating"
    NEEDS_ROTATE=true
  else
    echo "[${LOG_TAG}] Certificate is valid — no rotation needed"
    NEEDS_ROTATE=false
  fi
fi

if [[ "${NEEDS_ROTATE}" == "true" ]]; then
  echo "[${LOG_TAG}] Generating new self-signed certificate (825 days)"
  mkdir -p "${CERT_DIR}"

  openssl req -x509 -newkey rsa:4096 -sha256 -days 825 \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -nodes \
    -subj "/C=AR/ST=Buenos Aires/O=Lab/CN=*.sexydad" \
    -addext "subjectAltName=DNS:*.sexydad,DNS:sexydad,IP:192.168.80.100"

  chmod 600 "${KEY_FILE}"
  chmod 644 "${CERT_FILE}"

  echo "[${LOG_TAG}] Certificate generated. Updating Traefik service to reload certs..."

  docker service update --force "${TRAEFIK_SERVICE}"

  echo "[${LOG_TAG}] Traefik restarted. New certificate active."

  # Verify new cert
  EXPIRY=$(openssl x509 -in "${CERT_FILE}" -noout -enddate | sed 's/notAfter=//')
  echo "[${LOG_TAG}] New certificate expires: ${EXPIRY}"
fi

echo "[${LOG_TAG}] $(date -Iseconds) — Done"
