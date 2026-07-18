#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecutar con sudo." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

install -d -m 0750 \
  /var/lib/lab-health \
  /var/log/lab-health/reboot

install -d -m 0755 \
  /usr/local/share/lab-infra/docs/runbooks

install -m 0755 \
  "${SCRIPT_DIR}/lab-power-marker.sh" \
  /usr/local/sbin/lab-power-marker.sh

install -m 0755 \
  "${SCRIPT_DIR}/analyze-reboot.sh" \
  /usr/local/sbin/analyze-reboot.sh

install -m 0755 \
  "${SCRIPT_DIR}/lab-report.sh" \
  /usr/local/sbin/lab-report.sh

install -m 0644 \
  "${SCRIPT_DIR}/systemd/lab-power-marker.service" \
  /etc/systemd/system/lab-power-marker.service

install -m 0644 \
  "${SCRIPT_DIR}/systemd/lab-report-boot.service" \
  /etc/systemd/system/lab-report-boot.service

install -m 0644 \
  "${SCRIPT_DIR}/systemd/lab-report-boot.timer" \
  /etc/systemd/system/lab-report-boot.timer

install -m 0644 \
  "${SCRIPT_DIR}/systemd/lab-reboot-analysis.service" \
  /etc/systemd/system/lab-reboot-analysis.service

install -m 0644 \
  "${SCRIPT_DIR}/systemd/lab-reboot-analysis.timer" \
  /etc/systemd/system/lab-reboot-analysis.timer

install -m 0644 \
  "${REPO_ROOT}/docs/runbooks/REBOOT_DIAGNOSTICS.md" \
  /usr/local/share/lab-infra/docs/runbooks/REBOOT_DIAGNOSTICS.md

systemd-analyze verify \
  /etc/systemd/system/lab-power-marker.service \
  /etc/systemd/system/lab-report-boot.service \
  /etc/systemd/system/lab-report-boot.timer \
  /etc/systemd/system/lab-reboot-analysis.service \
  /etc/systemd/system/lab-reboot-analysis.timer

LEGACY_BOOT_UNIT="/etc/systemd/system/lab-report-boot.service"
LEGACY_UNIT="/etc/systemd/system/analyze-reboot.service"
LEGACY_SCRIPT="/opt/node_maintenance/analyze_reboot.sh"
LEGACY_BACKUP_ROOT="/var/lib/lab-health/legacy-backup"

if [[ -e "${LEGACY_BOOT_UNIT}" ]]; then
  systemctl disable --now lab-report-boot.service 2>/dev/null || true
fi

if [[ -e "${LEGACY_UNIT}" || -e "${LEGACY_SCRIPT}" ]]; then
  LEGACY_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
  LEGACY_BACKUP_DIR="${LEGACY_BACKUP_ROOT}/${LEGACY_TIMESTAMP}"

  install -d -m 0750 "${LEGACY_BACKUP_DIR}"

  systemctl disable --now analyze-reboot.service 2>/dev/null || true

  if [[ -e "${LEGACY_UNIT}" ]]; then
    mv "${LEGACY_UNIT}" "${LEGACY_BACKUP_DIR}/"
  fi

  if [[ -e "${LEGACY_SCRIPT}" ]]; then
    mv "${LEGACY_SCRIPT}" "${LEGACY_BACKUP_DIR}/"
  fi

  echo "LEGACY_BACKUP_DIR=${LEGACY_BACKUP_DIR}"
fi

systemctl daemon-reload
systemctl reset-failed lab-report-boot.service 2>/dev/null || true
systemctl reset-failed analyze-reboot.service 2>/dev/null || true

systemctl enable --now lab-power-marker.service
systemctl enable --now lab-report-boot.timer
systemctl enable --now lab-reboot-analysis.timer

echo "REBOOT_DIAGNOSTICS_INSTALL=SUCCESS"
