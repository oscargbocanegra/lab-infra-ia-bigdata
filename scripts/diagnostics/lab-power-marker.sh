#!/usr/bin/env bash
set -Eeuo pipefail

umask 0027

STATE_DIR="${LAB_HEALTH_STATE_DIR:-/var/lib/lab-health}"
REPORT_DIR="${LAB_HEALTH_REPORT_DIR:-/var/log/lab-health/reboot}"

HOST="$(hostname -s)"
MARKER="${STATE_DIR}/clean-shutdown.marker"
INITIALIZED="${STATE_DIR}/initialized"

install -d -m 0750 "${STATE_DIR}" "${REPORT_DIR}"

case "${1:-}" in
  boot)
    TS="$(date +%Y%m%d_%H%M%S)"
    REPORT="${REPORT_DIR}/power-event-${HOST}-${TS}.txt"

    if [[ ! -f "${INITIALIZED}" ]]; then
      RESULT="INITIALIZED"
    elif [[ -f "${MARKER}" ]]; then
      RESULT="CLEAN_SHUTDOWN"
    else
      RESULT="UNCLEAN_SHUTDOWN"
    fi

    {
      echo "DATE=$(date --iso-8601=seconds)"
      echo "HOST=${HOST}"
      echo "BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)"
      echo "PREVIOUS_POWER_EVENT=${RESULT}"
      echo "UPTIME=$(uptime -p)"
    } > "${REPORT}"

    chmod 0640 "${REPORT}"
    touch "${INITIALIZED}"

    if [[ -f "${MARKER}" ]]; then
      rm -f "${MARKER}"
    fi
    ;;

  shutdown)
    TMP_MARKER="$(mktemp "${STATE_DIR}/clean-shutdown.marker.XXXXXX")"

    {
      echo "DATE=$(date --iso-8601=seconds)"
      echo "HOST=${HOST}"
      echo "BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)"
    } > "${TMP_MARKER}"

    chmod 0640 "${TMP_MARKER}"
    mv -f "${TMP_MARKER}" "${MARKER}"
    sync
    ;;

  *)
    echo "Uso: $0 {boot|shutdown}" >&2
    exit 2
    ;;
esac
