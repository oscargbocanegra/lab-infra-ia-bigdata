# Runbook: UFW Firewall + Docker Swarm

> **Last updated:** 2026-04-06  
> **Applies to:** master1 (`<master1-ip>`) and master2 (`<master2-ip>`)

---

## Overview

Both nodes run **UFW** (Uncomplicated Firewall) as the host-level firewall. Docker Swarm interacts with `iptables` in non-obvious ways that require careful configuration to avoid breaking container traffic while maintaining security.

This runbook documents the architecture, known gotchas, and troubleshooting procedures.

---

## Architecture

### How Docker and UFW interact with iptables

```
Incoming packet (from LAN client → host:443)
         │
         ▼
   PREROUTING (nat)
         │  DNAT: <master1-ip>:443 → 172.19.0.16:443  (docker-proxy)
         ▼
   FORWARD chain
         │
         ├─► DOCKER-USER          ← OUR custom rules (LAN allowlist)
         ├─► DOCKER-FORWARD       ← Docker's own rules
         └─► ufw-before-forward   ← UFW forward rules
                                     (requires DEFAULT_FORWARD_POLICY=ACCEPT)
```

**Key insight:** Docker-published ports use DNAT + FORWARD — NOT the INPUT chain. UFW's `allow 443/tcp` rules live in the INPUT chain and have NO effect on Docker container traffic. Security for Docker ports must be implemented in the **DOCKER-USER** chain.

### UFW configuration files

| File | Purpose |
|------|---------|
| `/etc/default/ufw` | Master config — must set `DEFAULT_FORWARD_POLICY=ACCEPT` |
| `/etc/ufw/after.rules` | Persists DOCKER-USER chain rules across reboots |
| `/etc/ufw/ufw.conf` | Enable/disable, logging level |

---

## Critical Rules

### `/etc/default/ufw`

```
DEFAULT_FORWARD_POLICY="ACCEPT"
```

**WHY this must be ACCEPT:** UFW's forward chain (`ufw-before-forward`) requires forwarding to be allowed at the kernel level. With `DROP`, all forwarded packets are blocked before they can reach the DOCKER-USER chain — even if UFW INPUT rules allow the ports. This silently breaks all Docker-published ports.

> **Warning:** Running `ufw default deny forward` in a script OVERRIDES this setting back to DROP. Never use that command on these nodes.

---

### DOCKER-USER chain (in `/etc/ufw/after.rules`)

```iptables
# DOCKER-USER — restrict Docker-published ports to LAN only
*filter
:DOCKER-USER - [0:0]
# Allow traffic from Docker overlay/bridge subnets (172.16.0.0/12)
# Without these rules, inter-container traffic and container→internet is dropped
# because containers use 172.x.x.x IPs which don't match the LAN RETURN rules below.
-A DOCKER-USER -s 172.16.0.0/12 -j RETURN
-A DOCKER-USER -d 172.16.0.0/12 -j RETURN
# Allow traffic from private LAN
-A DOCKER-USER -d <lan-cidr> -j RETURN
-A DOCKER-USER -s <lan-cidr> -j RETURN
# Drop everything else (non-LAN traffic hitting Docker-published ports)
-A DOCKER-USER -j DROP
COMMIT
# END DOCKER-USER
```

**WHY four RETURN rules are required:**

1. `-s 172.16.0.0/12 RETURN` — allows container→internet and container→container traffic (source is 172.x.x.x)
2. `-d 172.16.0.0/12 RETURN` — allows internet→container replies (destination is 172.x.x.x)
3. `-s <lan-cidr> RETURN` — allows LAN client requests to reach containers
4. `-d <lan-cidr> RETURN` — allows container SYN-ACK replies back to LAN clients

Without rules 1 and 2, containers have no internet access and cannot communicate with each other through the overlay network. This causes service crashes on startup (e.g. `pip install` in entrypoint scripts failing with `Network is unreachable`).

---

## Current Firewall Rules

### master1 (control node — Traefik gateway)

```
Port      Protocol  From                  Purpose
────────  ────────  ──────────────────    ─────────────────────────
22/tcp    TCP       Anywhere              SSH
80/tcp    TCP       Anywhere              HTTP (Traefik redirect)
443/tcp   TCP       Anywhere              HTTPS (Traefik + all services)
2377/tcp  TCP       <master2-ip> only     Docker Swarm management
7946/tcp  TCP       <master2-ip> only     Swarm node communication
7946/udp  UDP       <master2-ip> only     Swarm node communication
4789/udp  UDP       <master2-ip> only     Swarm overlay network (VXLAN)
```

> Port 80 and 443 accept from Anywhere because they pass through DOCKER-USER which enforces the LAN allowlist at the container level.

### master2 (compute node — no public services)

```
Port      Protocol  From                  Purpose
────────  ────────  ──────────────────    ─────────────────────────
22/tcp    TCP       Anywhere              SSH
2377/tcp  TCP       <master1-ip> only     Docker Swarm management
7946/tcp  TCP       <master1-ip> only     Swarm node communication
7946/udp  UDP       <master1-ip> only     Swarm node communication
4789/udp  UDP       <master1-ip> only     Swarm overlay network (VXLAN)
5432/tcp  TCP       <master1-ip> only     PostgreSQL (for DBeaver SSH tunnel)
9000/tcp  TCP       <master1-ip> only     MinIO API (restic backups)
```

---

## Applying the Firewall (fresh setup)

```bash
# On master1
sudo bash scripts/hardening/ufw-master1.sh

# On master2 (run from master1 via scp + ssh)
scp scripts/hardening/ufw-master2.sh '<admin-user>@<master2-ip>:/tmp/'
ssh '<admin-user>@<master2-ip>' 'sudo bash /tmp/ufw-master2.sh'
```

---

## Verifying the firewall is correct

### Check UFW status

```bash
sudo ufw status verbose
```

Expected output includes `Default: allow (forward)` or `deny (forward)` — confirm `/etc/default/ufw` has `ACCEPT`.

### Check DOCKER-USER chain

```bash
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Expected output:
```
num  pkts bytes target  prot opt in  out  source           destination
1       X     X RETURN   0   --  *   *    0.0.0.0/0        <lan-cidr>
2       X     X RETURN   0   --  *   *    <lan-cidr>       0.0.0.0/0
3       X     X DROP     0   --  *   *    0.0.0.0/0        0.0.0.0/0
```

### Test Traefik is accessible

```bash
# From master1 itself
curl -sk -o /dev/null -w "%{http_code}" https://localhost
# Expected: 404 (Traefik default, no host matched)

curl -sk -o /dev/null -w "%{http_code}" --resolve portainer.sexydad:443:127.0.0.1 https://portainer.sexydad
# Expected: 200 or 401
```

---

## Troubleshooting

### Symptom: `ERR_CONNECTION_TIMED_OUT` on all services

The TCP handshake is failing. The three most common causes:

#### Cause 1: `DEFAULT_FORWARD_POLICY=DROP`

Check:
```bash
grep DEFAULT_FORWARD /etc/default/ufw
```

Fix:
```bash
sudo sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
sudo ufw reload
```

#### Cause 2: Missing `-d <lan-cidr> RETURN` in DOCKER-USER

Check:
```bash
sudo iptables -L DOCKER-USER -n -v
```
If you only see `-s <lan-cidr> RETURN` (no `-d` rule), container replies are being dropped.

Fix (live — survives until next ufw reload):
```bash
sudo iptables -I DOCKER-USER 1 -d <lan-cidr> -j RETURN
```

Fix (persistent — add to `/etc/ufw/after.rules` before the `-s` rule):
```bash
sudo sed -i 's/-A DOCKER-USER -s <lan-cidr> -j RETURN/-A DOCKER-USER -d <lan-cidr> -j RETURN\n-A DOCKER-USER -s <lan-cidr> -j RETURN/' /etc/ufw/after.rules
sudo ufw reload
```

#### Cause 3: Traefik service is down

```bash
docker service ls | grep traefik
# Expected: traefik_traefik   1/1
```

If 0/1, redeploy:
```bash
docker stack deploy -c stacks/core/00-traefik/stack.yml traefik
```

---

### Debugging traffic with iptables LOG

To see exactly which source IPs are hitting DOCKER-USER:

```bash
# Insert LOG rule at position 1 (before any RETURN/DROP)
sudo iptables -I DOCKER-USER 1 -j LOG --log-prefix "DU: " --log-level 4

# Trigger traffic (open browser, curl, etc.)

# Read the log
sudo dmesg | grep "DU: " | tail -20

# Remove LOG rule when done (always clean up)
sudo iptables -D DOCKER-USER 1
```

Sample output showing the bidirectional flow:
```
DU: IN=<host-nic> OUT=docker_gwbridge SRC=<client-ip> DST=172.19.0.16 DPT=443  ← client SYN
DU: IN=docker_gwbridge OUT=<host-nic> SRC=172.19.0.16 DST=<client-ip> SPT=443  ← container SYN-ACK
```

---

## Docker container cleanup

Docker Swarm accumulates stopped containers from service restarts. These are safe to remove periodically:

```bash
# Preview what will be removed
docker ps -a --filter status=exited --filter status=dead

# Remove stopped containers (safe — running containers are untouched)
docker container prune -f

# Remove dangling images (untagged, not referenced by any container)
docker image prune -f

# Full summary of disk usage
docker system df
```

> **Do NOT run `docker image prune -a`** unless you intend to remove all images not currently used by a running container. On Swarm nodes, some images are kept for fast redeployment.

### Typical disk state after cleanup

| Node | Images | Containers |
|------|--------|-----------|
| master1 | ~18 GB (19 images) | ~19 active |
| master2 | ~25 GB (15 images, includes Ollama 9.7 GB + Jupyter 8.3 GB) | ~78 Swarm-managed |

The apparent high "reclaimable" percentage reported by `docker system df` on master2 is a cosmetic artifact — Swarm-managed containers hold image references even when stopped between task cycles.

---

## Notes

- `ufw` and `iptables-persistent` **conflict** on this Ubuntu 24.04 system. Do NOT install `iptables-persistent` — it will remove `ufw` and break the firewall setup.
- Docker Swarm overlay network (`4789/udp`) must be open between nodes or the overlay will fail silently and containers on different nodes won't communicate.
- The DOCKER-USER chain rules are stored in `/etc/ufw/after.rules` and survive `ufw reload`. They do NOT survive a fresh `ufw --force reset` — always re-run the hardening script after a reset.
