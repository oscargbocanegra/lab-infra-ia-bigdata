#!/usr/bin/env bash
# =============================================================================
# setup-opensearch-logs.sh
# =============================================================================
# Purpose: Configure OpenSearch for centralized Docker log collection.
#
# This script creates:
#   1. ISM Policy    → auto-delete indices older than 7 days
#   2. Index Template → correct mappings for docker-logs-* indices
#
# Run ONCE from the Swarm manager node BEFORE deploying the fluent-bit stack.
# OpenSearch must be running and reachable on port 9200.
#
# Usage:
#   bash scripts/observability/setup-opensearch-logs.sh
#
# Requirements:
#   - curl installed on the Swarm manager
#   - OpenSearch accessible at localhost:9200 (internal overlay port)
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Config — adjust if OpenSearch is on a different host/port
# ---------------------------------------------------------------------------
OS_HOST="${OPENSEARCH_HOST:-localhost}"
OS_PORT="${OPENSEARCH_PORT:-9200}"
OS_URL="http://${OS_HOST}:${OS_PORT}"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${BOLD}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Wait for OpenSearch to be ready
# ---------------------------------------------------------------------------
log "Checking OpenSearch connectivity at ${OS_URL} ..."

MAX_RETRIES=10
for i in $(seq 1 $MAX_RETRIES); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${OS_URL}/_cluster/health" 2>/dev/null || echo "000")
    if [[ "$STATUS" == "200" ]]; then
        ok "OpenSearch is reachable (HTTP 200)"
        break
    fi
    if [[ $i -eq $MAX_RETRIES ]]; then
        err "OpenSearch not reachable after ${MAX_RETRIES} attempts. Is the stack running?"
    fi
    warn "Attempt $i/${MAX_RETRIES} — HTTP ${STATUS}. Retrying in 5s..."
    sleep 5
done

# ---------------------------------------------------------------------------
# 2. Create ISM Policy: docker-logs-retention-7d
# ---------------------------------------------------------------------------
# ISM = Index State Management (OpenSearch's built-in ILM equivalent)
# Policy: indices matching docker-logs-* are automatically deleted after 7 days
# ---------------------------------------------------------------------------
log "Creating ISM policy: docker-logs-retention-7d ..."

ISM_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
    "${OS_URL}/_plugins/_ism/policies/docker-logs-retention-7d" \
    -H 'Content-Type: application/json' \
    -d '{
  "policy": {
    "description": "Delete docker-logs-* indices older than 7 days. Prevents disk exhaustion on master1.",
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
}')

HTTP_CODE=$(echo "$ISM_RESPONSE" | tail -1)
BODY=$(echo "$ISM_RESPONSE" | head -1)

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    ok "ISM policy created successfully (HTTP ${HTTP_CODE})"
elif [[ "$HTTP_CODE" == "409" ]]; then
    warn "ISM policy already exists — skipping (HTTP 409)"
else
    err "Failed to create ISM policy (HTTP ${HTTP_CODE}): ${BODY}"
fi

# ---------------------------------------------------------------------------
# 3. Create Index Template: docker-logs-template
# ---------------------------------------------------------------------------
# Defines field mappings for all docker-logs-YYYY.MM.DD indices.
# Without this, OpenSearch would auto-map everything as text (inefficient).
#
# Key mappings:
#   @timestamp  → date     (the actual log timestamp from Docker)
#   log         → text     (searchable message) + keyword (aggregatable)
#   stream      → keyword  (stdout / stderr — for filtering)
#   node        → keyword  (master1 / master2 — for per-node filtering)
#   container_name → keyword
#   container_id   → keyword
#   image_name     → keyword
#   tag (swarm)    → keyword  (com.docker.stack.namespace, service name)
# ---------------------------------------------------------------------------
log "Creating index template: docker-logs-template ..."

TEMPLATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
    "${OS_URL}/_index_template/docker-logs-template" \
    -H 'Content-Type: application/json' \
    -d '{
  "index_patterns": ["docker-logs-*"],
  "priority": 200,
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "10s",
      "index.lifecycle.name": "docker-logs-retention-7d"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp": {
          "type": "date"
        },
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
        "stream": {
          "type": "keyword"
        },
        "node": {
          "type": "keyword"
        },
        "container_name": {
          "type": "keyword"
        },
        "container_id": {
          "type": "keyword"
        },
        "image_name": {
          "type": "keyword"
        },
        "docker_compose_service": {
          "type": "keyword"
        },
        "com.docker.stack.namespace": {
          "type": "keyword"
        },
        "com.docker.swarm.service.name": {
          "type": "keyword"
        },
        "com.docker.swarm.task.name": {
          "type": "keyword"
        }
      }
    }
  }
}')

HTTP_CODE=$(echo "$TEMPLATE_RESPONSE" | tail -1)
BODY=$(echo "$TEMPLATE_RESPONSE" | head -1)

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    ok "Index template created successfully (HTTP ${HTTP_CODE})"
else
    err "Failed to create index template (HTTP ${HTTP_CODE}): ${BODY}"
fi

# ---------------------------------------------------------------------------
# 4. Verify setup
# ---------------------------------------------------------------------------
log "Verifying ISM policy ..."
ISM_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    "${OS_URL}/_plugins/_ism/policies/docker-logs-retention-7d")
[[ "$ISM_CHECK" == "200" ]] && ok "ISM policy verified ✓" || warn "ISM policy check returned HTTP ${ISM_CHECK}"

log "Verifying index template ..."
TMPL_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    "${OS_URL}/_index_template/docker-logs-template")
[[ "$TMPL_CHECK" == "200" ]] && ok "Index template verified ✓" || warn "Index template check returned HTTP ${TMPL_CHECK}"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD}  OpenSearch log collection configured successfully!${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo ""
echo "  ISM Policy:     docker-logs-retention-7d  (auto-delete after 7 days)"
echo "  Index Pattern:  docker-logs-YYYY.MM.DD    (daily rollover by Fluent Bit)"
echo "  Template:       docker-logs-template       (optimized mappings)"
echo ""
echo "  Next steps:"
echo "  1. Create state dir on BOTH Swarm nodes:"
echo "     manager : mkdir -p /srv/fastdata/fluent-bit"
echo "     worker  : ssh <user>@<worker-ip> 'mkdir -p /srv/fastdata/fluent-bit'"
echo ""
echo "  2. Deploy Fluent Bit:"
echo "     docker stack deploy -c stacks/monitoring/00-fluent-bit/stack.yml fluent-bit"
echo ""
echo "  3. Verify logs arrive in OpenSearch (~30s):"
echo "     curl http://localhost:9200/_cat/indices/docker-logs-* | sort"
echo ""
echo "  4. Configure Dashboards:"
echo "     OpenSearch Dashboards → Management → Index Patterns → docker-logs-*"
echo "     Time field: @timestamp"
echo ""
