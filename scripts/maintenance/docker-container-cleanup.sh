#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/default/lab-docker-container-cleanup}"

if [[ -r "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

: "${APPLY:=false}"
: "${RETENTION:=168h}"
: "${REPORT_DIR:=/var/log/lab-health/docker-cleanup}"

mkdir -p "${REPORT_DIR}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT="${REPORT_DIR}/docker-container-cleanup-$(hostname)-${TIMESTAMP}.txt"

API_JSON="$(mktemp)"
CANDIDATE_IDS_FILE="$(mktemp)"
CURRENT_IDS_FILE="$(mktemp)"

cleanup() {
  rm -f \
    "${API_JSON}" \
    "${CANDIDATE_IDS_FILE}" \
    "${CURRENT_IDS_FILE}"
}
trap cleanup EXIT

exec > >(tee "${REPORT}") 2>&1

exec 9>/run/lab-docker-container-cleanup.lock

if ! flock -n 9; then
  echo "CLEANUP_ALREADY_RUNNING=YES"
  exit 0
fi

echo "HOST=$(hostname)"
echo "DATE=$(date --iso-8601=seconds)"
echo "APPLY=${APPLY}"
echo "RETENTION=${RETENTION}"
echo "REPORT=${REPORT}"

docker info >/dev/null

echo
echo "===== ESTADO ANTES ====="

DEAD_BEFORE="$(
  docker ps -aq --filter status=dead |
  wc -l
)"

EXITED_BEFORE="$(
  docker ps -aq --filter status=exited |
  wc -l
)"

CREATED_BEFORE="$(
  docker ps -aq --filter status=created |
  wc -l
)"

echo "DEAD_BEFORE=${DEAD_BEFORE}"
echo "EXITED_BEFORE=${EXITED_BEFORE}"
echo "CREATED_BEFORE=${CREATED_BEFORE}"

docker system df

echo
echo "===== CANDIDATOS ====="

curl \
  --fail \
  --silent \
  --show-error \
  --unix-socket /var/run/docker.sock \
  'http://localhost/containers/json?all=1' \
  >"${API_JSON}"

python3 - \
  "${API_JSON}" \
  "${RETENTION}" \
  "${CANDIDATE_IDS_FILE}" <<'PY'
import json
import re
import sys
import time
from pathlib import Path

records = json.loads(
    Path(sys.argv[1]).read_text(encoding="utf-8")
)
retention = sys.argv[2]
candidate_ids_path = Path(sys.argv[3])

match = re.fullmatch(r"(\d+)([smhd])", retention)

if not match:
    raise SystemExit(
        "RETENTION debe usar formato como 30m, 24h o 7d"
    )

value = int(match.group(1))
unit = match.group(2)

factor = {
    "s": 1,
    "m": 60,
    "h": 3600,
    "d": 86400,
}[unit]

cutoff = int(time.time()) - (value * factor)
candidates = []

for item in records:
    state = str(item.get("State", ""))

    if state not in {"created", "exited", "dead"}:
        continue

    created = int(item.get("Created", 0))

    if created > cutoff:
        continue

    names = ",".join(item.get("Names") or [])

    candidates.append(
        {
            "id": item.get("Id", ""),
            "state": state,
            "image": item.get("Image", ""),
            "names": names or "NONE",
            "age_hours": round(
                (time.time() - created) / 3600,
                2,
            ),
        }
    )

candidate_ids = sorted(
    {
        item["id"]
        for item in candidates
        if item["id"]
    }
)

candidate_ids_path.write_text(
    "".join(
        f"{candidate_id}\n"
        for candidate_id in candidate_ids
    ),
    encoding="utf-8",
)

print(f"CANDIDATE_COUNT={len(candidate_ids)}")

for item in candidates:
    print(
        "CANDIDATE="
        f"id:{item['id']} "
        f"state:{item['state']} "
        f"age_hours:{item['age_hours']} "
        f"image:{item['image']} "
        f"names:{item['names']}"
    )
PY

if [[ "${APPLY}" != "true" ]]; then
  echo
  echo "CLEANUP_MODE=DRY_RUN"
  echo "CONTAINERS_REMOVED=0"
  echo "IMAGES_REMOVED=0"
  echo "VOLUMES_REMOVED=0"
  echo "NETWORKS_REMOVED=0"
  exit 0
fi

echo
echo "===== ELIMINAR CONTENEDORES DETENIDOS ANTIGUOS ====="

docker container prune \
  --force \
  --filter "until=${RETENTION}"

echo
echo "===== VERIFICAR CANDIDATOS INICIALES ====="

docker ps -aq --no-trunc |
  sort -u >"${CURRENT_IDS_FILE}"

CANDIDATES_INITIAL="$(
  wc -l <"${CANDIDATE_IDS_FILE}"
)"

CANDIDATES_REMOVED=0
CANDIDATES_REMAINING=0

while IFS= read -r candidate_id; do
  [[ -n "${candidate_id}" ]] || continue

  if grep -Fxq \
    "${candidate_id}" \
    "${CURRENT_IDS_FILE}"; then

    echo "CANDIDATE_REMAINING=${candidate_id}"

    CANDIDATES_REMAINING=$(
      (CANDIDATES_REMAINING + 1)
    )
  else
    echo "CANDIDATE_REMOVED=${candidate_id}"

    CANDIDATES_REMOVED=$(
      (CANDIDATES_REMOVED + 1)
    )
  fi
done <"${CANDIDATE_IDS_FILE}"

echo "CANDIDATES_INITIAL=${CANDIDATES_INITIAL}"
echo "CANDIDATES_REMOVED=${CANDIDATES_REMOVED}"
echo "CANDIDATES_REMAINING=${CANDIDATES_REMAINING}"

echo
echo "===== ESTADO DESPUÉS ====="

DEAD_AFTER="$(
  docker ps -aq --filter status=dead |
  wc -l
)"

EXITED_AFTER="$(
  docker ps -aq --filter status=exited |
  wc -l
)"

CREATED_AFTER="$(
  docker ps -aq --filter status=created |
  wc -l
)"

echo "DEAD_AFTER=${DEAD_AFTER}"
echo "EXITED_AFTER=${EXITED_AFTER}"
echo "CREATED_AFTER=${CREATED_AFTER}"

docker system df

if [[ "${CANDIDATES_REMAINING}" -ne 0 ]]; then
  echo "UNRESOLVED_CANDIDATES=YES"
  exit 3
fi

echo "UNRESOLVED_CANDIDATES=NO"

if [[ "${DEAD_AFTER}" -ne 0 ]]; then
  echo "UNRESOLVED_DEAD_METADATA=YES"
  exit 2
fi

echo "UNRESOLVED_DEAD_METADATA=NO"
echo "CLEANUP_MODE=APPLY"
echo "IMAGES_REMOVED=0"
echo "VOLUMES_REMOVED=0"
echo "NETWORKS_REMOVED=0"
echo "DOCKER_CONTAINER_CLEANUP=SUCCESS"
