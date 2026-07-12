#!/usr/bin/env bash
set -Eeuo pipefail

umask 0027

OUTPUT_DIR="${LAB_HEALTH_REPORT_DIR:-/var/log/lab-health/reboot}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="${2:?Falta valor para --output-dir}"
      shift 2
      ;;
    *)
      echo "Argumento no reconocido: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Este script debe ejecutarse como root." >&2
  exit 1
fi

HOST="$(hostname -s)"
TS="$(date +%Y%m%d_%H%M%S)"
REPORT="${OUTPUT_DIR}/reboot-analysis-${HOST}-${TS}.txt"
LATEST="${OUTPUT_DIR}/reboot-analysis-${HOST}-latest.txt"

install -d -m 0750 "${OUTPUT_DIR}"
touch "${REPORT}"
chmod 0640 "${REPORT}"

run_section() {
  local title="$1"
  shift

  {
    echo
    echo "===== ${title} ====="

    if ! timeout 45s "$@"; then
      echo "COMMAND_STATUS=NONZERO"
    fi
  } >> "${REPORT}" 2>&1
}

{
  echo "REBOOT_ANALYSIS_START=$(date --iso-8601=seconds)"
  echo "HOST=${HOST}"
  echo "CURRENT_BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)"
  echo "KERNEL=$(uname -r)"
} > "${REPORT}"

run_section "POWER_EVENT_REPORTS" \
  bash -c "find '${OUTPUT_DIR}' -maxdepth 1 -type f -name 'power-event-${HOST}-*.txt' -printf '%T@ %p\n' | sort -nr | head -5"

run_section "BOOT_HISTORY" \
  journalctl --list-boots --no-pager

run_section "LAST_REBOOTS_AND_SHUTDOWNS" \
  last -x -n 30

run_section "PREVIOUS_BOOT_WARNINGS" \
  journalctl -b -1 -p warning..alert --no-pager -n 400

run_section "PREVIOUS_BOOT_KERNEL" \
  journalctl -k -b -1 --no-pager -n 400

run_section "PREVIOUS_BOOT_SYSTEMD" \
  journalctl -b -1 -u systemd-logind \
  -u systemd-poweroff.service \
  -u systemd-reboot.service \
  -u systemd-shutdown.service \
  --no-pager -n 300

run_section "CURRENT_FAILED_UNITS" \
  systemctl --failed --no-pager

run_section "DISK_AND_FILESYSTEM" \
  df -hT

run_section "MEMORY" \
  free -h

run_section "DOCKER_STATUS" \
  systemctl status docker --no-pager

run_section "DOCKER_EVENTS_PREVIOUS_BOOT" \
  journalctl -b -1 -u docker --no-pager -n 300

{
  echo
  echo "REBOOT_ANALYSIS_STATUS=COMPLETE"
  echo "REPORT=${REPORT}"
} >> "${REPORT}"

cp -f "${REPORT}" "${LATEST}"
chmod 0640 "${LATEST}"

echo "REBOOT_ANALYSIS_REPORT=${REPORT}"
echo "REBOOT_ANALYSIS_STATUS=COMPLETE"
