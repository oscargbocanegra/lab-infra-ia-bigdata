#!/usr/bin/env bash
# ufw-master2.sh — Configure UFW firewall rules for master2 (compute node)
# Run as: sudo bash scripts/hardening/ufw-master2.sh
# Node: master2 (192.168.80.200) — Swarm worker, PostgreSQL, GPU workloads
set -euo pipefail

echo "=== UFW hardening for master2 ==="

# CRITICAL: UFW's DEFAULT_FORWARD_POLICY must be ACCEPT for Docker to forward
# traffic to containers. Without this, UFW drops all forwarded packets before
# they reach the DOCKER-USER chain — breaking all Docker-published ports.
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

# Reset to clean state
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing
# Note: forward policy is controlled by /etc/default/ufw DEFAULT_FORWARD_POLICY=ACCEPT above.
# 'ufw default deny forward' would override it back to DROP — intentionally omitted.

# SSH (must come FIRST — never lock yourself out)
ufw allow 22/tcp comment 'SSH'

# Docker Swarm cluster traffic (only from master1)
ufw allow from 192.168.80.100 to any port 2377 proto tcp comment 'Swarm management'
ufw allow from 192.168.80.100 to any port 7946 proto tcp comment 'Swarm node communication TCP'
ufw allow from 192.168.80.100 to any port 7946 proto udp comment 'Swarm node communication UDP'
ufw allow from 192.168.80.100 to any port 4789 proto udp comment 'Swarm overlay network'

# PostgreSQL — only accessible from master1 (for Docker Swarm overlay + DBeaver SSH tunnel)
ufw allow from 192.168.80.100 to any port 5432 proto tcp comment 'PostgreSQL from master1'

# ── DOCKER-USER rules via /etc/ufw/after.rules ────────────────────────────
# Docker bypasses UFW by inserting rules before the UFW chains in iptables.
# The DOCKER-USER chain is the official hook for adding restrictions to Docker traffic.
# We append these rules to after.rules so UFW persists them across reboots.
#
# NOTE: ufw and iptables-persistent conflict on this system — do NOT install
# iptables-persistent. UFW persists its own rules natively.
AFTER_RULES="/etc/ufw/after.rules"

# Remove any existing DOCKER-USER block we may have added previously
if grep -q "# DOCKER-USER" "${AFTER_RULES}"; then
  sed -i '/# DOCKER-USER/,/# END DOCKER-USER/d' "${AFTER_RULES}"
fi

# Append DOCKER-USER block
cat >> "${AFTER_RULES}" << 'DOCKER_RULES'

# DOCKER-USER — restrict Docker-published ports to LAN only
*filter
:DOCKER-USER - [0:0]
# Allow traffic from Docker overlay/bridge subnets (172.16.0.0/12)
# Without these rules, inter-container traffic and container→internet is dropped
# because containers use 172.x.x.x IPs, not 192.168.80.x
-A DOCKER-USER -s 172.16.0.0/12 -j RETURN
-A DOCKER-USER -d 172.16.0.0/12 -j RETURN
# Allow traffic from private LAN
-A DOCKER-USER -d 192.168.80.0/24 -j RETURN
-A DOCKER-USER -s 192.168.80.0/24 -j RETURN
# Drop everything else (non-LAN traffic hitting Docker-published ports)
-A DOCKER-USER -j DROP
COMMIT
# END DOCKER-USER
DOCKER_RULES

echo "=== Enabling UFW ==="
ufw --force enable
ufw status verbose

echo "=== DOCKER-USER rules added to after.rules ==="

echo "=== UFW master2 hardening complete ==="
