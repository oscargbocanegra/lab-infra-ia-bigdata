#!/usr/bin/env bash
# =============================================================================
# setup-prometheus.sh
# =============================================================================
# Purpose: Bootstrap all prerequisites for the Prometheus + Grafana stacks.
#
# This script:
#   1. Creates required host directories on both Swarm nodes
#   2. Sets correct ownership (Prometheus: nobody/65534, Grafana: 472)
#   3. Creates Swarm Secrets for Grafana admin credentials
#   4. Creates Swarm Secret for Prometheus BasicAuth (via Traefik)
#
# Run ONCE from the Swarm manager node before deploying the stacks.
#
# Usage:
#   bash scripts/observability/setup-prometheus.sh
#
# Requirements:
#   - Docker Swarm manager access
#   - SSH access to the compute node
#   - htpasswd (apache2-utils) for BasicAuth hash generation
#     Install: sudo apt-get install -y apache2-utils
# =============================================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${BOLD}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# =============================================================================
# 1. Create directories on manager node
# =============================================================================
log "Creating directories on manager node..."

mkdir -p /srv/fastdata/prometheus
chown 65534:65534 /srv/fastdata/prometheus   # nobody:nobody (Prometheus UID)
ok "  /srv/fastdata/prometheus  → owner: 65534 (nobody)"

mkdir -p /srv/fastdata/grafana
chown 472:472 /srv/fastdata/grafana          # grafana:grafana (Grafana UID)
ok "  /srv/fastdata/grafana     → owner: 472 (grafana)"

# =============================================================================
# 2. Create Swarm Secrets
# =============================================================================
log "Creating Swarm Secrets..."

# Helper: create secret only if it doesn't already exist
create_secret() {
    local name="$1"
    local value="$2"
    if docker secret inspect "$name" &>/dev/null 2>&1; then
        warn "Secret '$name' already exists — skipping"
    else
        echo "$value" | docker secret create "$name" -
        ok "Secret '$name' created"
    fi
}

# --- Grafana admin credentials ---
# Prompt for secure password instead of hardcoding
echo ""
echo -e "${BOLD}Grafana admin credentials${NC}"
read -r -p "  Enter Grafana admin username [admin]: " GRAFANA_USER
GRAFANA_USER="${GRAFANA_USER:-admin}"

read -r -s -p "  Enter Grafana admin password: " GRAFANA_PASS
echo ""
if [[ -z "$GRAFANA_PASS" ]]; then
    err "Grafana password cannot be empty"
fi

create_secret "grafana_admin_user"     "$GRAFANA_USER"
create_secret "grafana_admin_password" "$GRAFANA_PASS"

# --- Prometheus BasicAuth (for Traefik) ---
echo ""
echo -e "${BOLD}Prometheus BasicAuth (for Traefik)${NC}"
echo "  This protects the Prometheus UI endpoint."
read -r -p "  Enter Prometheus username [prometheus]: " PROM_USER
PROM_USER="${PROM_USER:-prometheus}"

read -r -s -p "  Enter Prometheus password: " PROM_PASS
echo ""
if [[ -z "$PROM_PASS" ]]; then
    err "Prometheus password cannot be empty"
fi

# Generate htpasswd hash (bcrypt)
if ! command -v htpasswd &>/dev/null; then
    err "htpasswd not found. Install with: sudo apt-get install -y apache2-utils"
fi

PROM_HASH=$(htpasswd -nbB "$PROM_USER" "$PROM_PASS")
create_secret "prometheus_basicauth" "$PROM_HASH"

# =============================================================================
# 3. Summary
# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD}  Prometheus + Grafana prerequisites configured!${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo ""
echo "  Directories:"
echo "    /srv/fastdata/prometheus  (owner: nobody/65534)"
echo "    /srv/fastdata/grafana     (owner: grafana/472)"
echo ""
echo "  Secrets created:"
echo "    grafana_admin_user"
echo "    grafana_admin_password"
echo "    prometheus_basicauth"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Update Traefik stack with metrics endpoint + new secrets:"
echo "     docker stack deploy -c stacks/core/00-traefik/stack.yml traefik"
echo ""
echo "  2. Deploy Prometheus stack:"
echo "     docker stack deploy -c stacks/monitoring/01-prometheus/stack.yml prometheus"
echo ""
echo "  3. Deploy NVIDIA GPU exporter:"
echo "     docker stack deploy -c stacks/monitoring/03-nvidia-exporter/stack.yml nvidia-exporter"
echo ""
echo "  4. Deploy Grafana stack:"
echo "     docker stack deploy -c stacks/monitoring/02-grafana/stack.yml grafana"
echo ""
echo "  5. Add DNS entry for new endpoints:"
echo "     prometheus.sexydad  → manager node IP"
echo "     grafana.sexydad     → manager node IP"
echo ""
