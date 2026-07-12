#!/usr/bin/env bash
# Configure OpenSearch for centralized Docker logs.
#
# Execute from master1. The script reaches the active OpenSearch container
# on master2 through SSH and Docker exec, avoiding exposed credentials.
#
# Optional environment variables:
#   OPENSEARCH_NODE=master2
#   OPENSEARCH_SERVICE_FILTER=opensearch_opensearch
#   REPORT_DIR=$HOME/lab-reports

set -Eeuo pipefail

OPENSEARCH_NODE="${OPENSEARCH_NODE:-master2}"
OPENSEARCH_SERVICE_FILTER="${OPENSEARCH_SERVICE_FILTER:-opensearch_opensearch}"
OPENSEARCH_SSH_IDENTITY="${OPENSEARCH_SSH_IDENTITY:-${HOME}/.ssh/id_ed25519_master2}"
REPORT_DIR="${REPORT_DIR:-${HOME}/lab-reports}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT="${REPORT_DIR}/setup-opensearch-logs-${TIMESTAMP}.txt"

mkdir -p "${REPORT_DIR}"
exec > >(tee "${REPORT}") 2>&1

log() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ "$(hostname)" == "master1" ]] || die "Run this script from master1"

command -v ssh >/dev/null 2>&1 || die "ssh is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
[[ -r "${OPENSEARCH_SSH_IDENTITY}" ]] || die "SSH identity not readable: ${OPENSEARCH_SSH_IDENTITY}"

log "Resolving OpenSearch container on ${OPENSEARCH_NODE}"

OS_CONTAINER="$(
  ssh -i "${OPENSEARCH_SSH_IDENTITY}" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 "${OPENSEARCH_NODE}" \
    "docker ps -q --filter name=${OPENSEARCH_SERVICE_FILTER} | head -1"
)"

[[ -n "${OS_CONTAINER}" ]] || \
  die "OpenSearch container not found on ${OPENSEARCH_NODE}"

ok "Container resolved: ${OS_CONTAINER}"

os_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  if [[ -n "${body}" ]]; then
    printf '%s' "${body}" |
      ssh -i "${OPENSEARCH_SSH_IDENTITY}" -o IdentitiesOnly=yes -o BatchMode=yes "${OPENSEARCH_NODE}" \
        "docker exec -i ${OS_CONTAINER} curl -sS -w '\n%{http_code}' \
        -X ${method} 'http://127.0.0.1:9200${path}' \
        -H 'Content-Type: application/json' --data-binary @-"
  else
    ssh -i "${OPENSEARCH_SSH_IDENTITY}" -o IdentitiesOnly=yes -o BatchMode=yes "${OPENSEARCH_NODE}" \
      "docker exec ${OS_CONTAINER} curl -sS -w '\n%{http_code}' \
      -X ${method} 'http://127.0.0.1:9200${path}'"
  fi
}

split_response() {
  local response="$1"
  RESPONSE_CODE="$(printf '%s\n' "${response}" | tail -n 1)"
  RESPONSE_BODY="$(printf '%s\n' "${response}" | sed '$d')"
}

expect_code() {
  local actual="$1"
  local operation="$2"
  shift 2

  local expected
  for expected in "$@"; do
    if [[ "${actual}" == "${expected}" ]]; then
      ok "${operation} (HTTP ${actual})"
      return 0
    fi
  done

  printf '%s\n' "${RESPONSE_BODY}" >&2
  die "${operation} failed with HTTP ${actual}"
}

log "Checking cluster health"
response="$(os_request GET '/_cluster/health')"
split_response "${response}"
expect_code "${RESPONSE_CODE}" "Cluster health" 200

log "Applying single-node persistent settings"
cluster_settings='{
  "persistent": {
    "cluster.default_number_of_replicas": "0",
    "plugins.index_state_management.history.number_of_replicas": "0"
  }
}'
response="$(os_request PUT '/_cluster/settings' "${cluster_settings}")"
split_response "${response}"
expect_code "${RESPONSE_CODE}" "Single-node settings" 200

policy_path='/_plugins/_ism/policies/docker-logs-retention-7d'
policy_body='{
  "policy": {
    "description": "Delete docker-logs-* indices older than 7 days on the single-node lab cluster.",
    "default_state": "active",
    "states": [
      {
        "name": "active",
        "actions": [],
        "transitions": [
          {
            "state_name": "delete",
            "conditions": {
              "min_index_age": "7d"
            }
          }
        ]
      },
      {
        "name": "delete",
        "actions": [
          {
            "delete": {}
          }
        ],
        "transitions": []
      }
    ],
    "ism_template": [
      {
        "index_patterns": ["docker-logs-*"],
        "priority": 100
      }
    ]
  }
}'

log "Reading ISM policy"
response="$(os_request GET "${policy_path}")"
split_response "${response}"

if [[ "${RESPONSE_CODE}" == "200" ]]; then
  read -r seq_no primary_term < <(
    printf '%s' "${RESPONSE_BODY}" |
      python3 -c '
import json, sys
data = json.load(sys.stdin)
print(data["_seq_no"], data["_primary_term"])
'
  )
  update_path="${policy_path}?if_seq_no=${seq_no}&if_primary_term=${primary_term}"
  log "Updating existing ISM policy"
  response="$(os_request PUT "${update_path}" "${policy_body}")"
  split_response "${response}"
  expect_code "${RESPONSE_CODE}" "ISM policy update" 200
elif [[ "${RESPONSE_CODE}" == "404" ]]; then
  log "Creating ISM policy"
  response="$(os_request PUT "${policy_path}" "${policy_body}")"
  split_response "${response}"
  expect_code "${RESPONSE_CODE}" "ISM policy creation" 200 201
else
  printf '%s\n' "${RESPONSE_BODY}" >&2
  die "Unable to read ISM policy (HTTP ${RESPONSE_CODE})"
fi

template_body='{
  "index_patterns": ["docker-logs-*"],
  "priority": 200,
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "10s"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "@timestamp": {"type": "date"},
        "log": {
          "type": "text",
          "analyzer": "standard",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 512
            }
          }
        },
        "stream": {"type": "keyword"},
        "node": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "container_name": {"type": "keyword"},
        "container_id": {"type": "keyword"},
        "image_name": {"type": "keyword"},
        "docker_compose_service": {"type": "keyword"},
        "com.docker.stack.namespace": {"type": "keyword"},
        "com.docker.swarm.service.name": {"type": "keyword"},
        "com.docker.swarm.task.name": {"type": "keyword"}
      }
    }
  }
}'

log "Creating or updating index template"
response="$(
  os_request PUT '/_index_template/docker-logs-template' "${template_body}"
)"
split_response "${response}"
expect_code "${RESPONSE_CODE}" "Index template" 200 201

log "Applying zero replicas to existing docker log indices"
replica_body='{"index":{"number_of_replicas":0}}'
response="$(
  os_request PUT \
    '/docker-logs-*/_settings?allow_no_indices=true&expand_wildcards=all' \
    "${replica_body}"
)"
split_response "${response}"
expect_code "${RESPONSE_CODE}" "Existing index replicas" 200

log "Verifying resources"

for resource in \
  '/_cluster/settings?include_defaults=true&flat_settings=true' \
  "${policy_path}" \
  '/_index_template/docker-logs-template' \
  '/_cluster/health'
do
  response="$(os_request GET "${resource}")"
  split_response "${response}"
  expect_code "${RESPONSE_CODE}" "Verify ${resource}" 200
done

health_response="$(os_request GET '/_cluster/health')"
split_response "${health_response}"

cluster_status="$(
  printf '%s' "${RESPONSE_BODY}" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])'
)"
unassigned="$(
  printf '%s' "${RESPONSE_BODY}" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["unassigned_shards"])'
)"

[[ "${cluster_status}" == "green" ]] || \
  die "Cluster status is ${cluster_status}, expected green"
[[ "${unassigned}" == "0" ]] || \
  die "Unassigned shards=${unassigned}, expected 0"

ok "Cluster remains green with zero unassigned shards"

echo
echo "VALIDATION_RESULT=SUCCESS"
echo "OPENSEARCH_NODE=${OPENSEARCH_NODE}"
echo "OPENSEARCH_CONTAINER=${OS_CONTAINER}"
echo "CLUSTER_STATUS=${cluster_status}"
echo "UNASSIGNED_SHARDS=${unassigned}"
echo "REPORT=${REPORT}"
