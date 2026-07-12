#!/usr/bin/env bash
set -u

TS="$(date +%Y%m%d_%H%M%S)"
HOST="$(hostname -s)"
REPORT_DIR="${LAB_REPORT_DIR:-${HOME}/lab-reports}"
REPORT="${REPORT_DIR}/host-report-${HOST}-${TS}.txt"

mkdir -p "${REPORT_DIR}"
exec > >(tee "${REPORT}") 2>&1

section() {
  echo
  echo "===== $1 ====="
}

run() {
  local title="$1"
  shift

  section "${title}"
  timeout 30s "$@" || true
}

echo "HOST_REPORT_START=$(date --iso-8601=seconds)"
echo "HOST=${HOST}"

run "OS" hostnamectl
run "KERNEL" uname -a
run "UPTIME" uptime
run "CPU" lscpu
run "RAM" free -h
run "SWAP" swapon --show
run "DISKS" lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,MODEL,ROTA
run "FILESYSTEM" df -hT
run "NETWORK" ip -br address
run "ROUTES" ip route
run "FAILED_SYSTEMD" systemctl --failed --no-pager
run "DOCKER_VERSION" docker version
run "DOCKER_INFO" docker info
run "DOCKER_CONTAINERS" docker ps -a
run "DOCKER_SYSTEM_DF" docker system df

if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null |
  grep -qx active
then
  section "SWARM"

  if docker node ls >/dev/null 2>&1; then
    docker node ls
    docker service ls
  else
    echo "Nodo worker: inventario Swarm disponible desde master1."
  fi
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  run "GPU" nvidia-smi
fi

echo
echo "HOST_REPORT_STATUS=COMPLETE"
echo "REPORT=${REPORT}"
