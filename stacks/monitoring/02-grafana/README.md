# Grafana Stack — Metrics Dashboards

> Phase 6.2 — Observability | Lab Infra AI + Big Data

## Overview

Grafana provides the visualization layer for all cluster metrics collected by Prometheus.  
It is fully auto-provisioned on startup — no manual UI configuration required.

**Services:**

| Service | Image | Node | Purpose |
|---|---|---|---|
| `grafana` | `grafana/grafana:11.6.14` | control (master1) | Dashboard + visualization |

---

## Auto-Provisioning

Grafana bootstraps itself via Docker Swarm Configs on first start:

| Config file | Target path | Purpose |
|---|---|---|
| `provisioning/datasources/prometheus.yml` | `/etc/grafana/provisioning/datasources/` | Prometheus datasource |
| `provisioning/dashboards/provider.yml` | `/etc/grafana/provisioning/dashboards/` | Dashboard file provider |

The Prometheus datasource points to `http://prometheus:9090` via the Docker overlay DNS.  
No IP addresses, no manual setup in the UI.

---

## Storage

- **Path:** `/srv/fastdata/grafana` on master1
- **Owner:** UID `472` (grafana user inside the container)

---

## Pre-requisites

Run **once** from the Swarm manager node before deploying:

```bash
# 1. Create data directory with correct ownership
mkdir -p /srv/fastdata/grafana
chown 472:472 /srv/fastdata/grafana   # grafana:grafana (Grafana UID)

# 2. Create Swarm Secrets (interactive — use the shared setup script)
bash scripts/observability/setup-prometheus.sh
```

> The setup script handles both Grafana and Prometheus secrets interactively.  
> No passwords are stored in files or environment variables.

### Required Swarm Secrets

| Secret name | Purpose |
|---|---|
| `grafana_admin_user` | Grafana admin username |
| `grafana_admin_password` | Grafana admin password |

---

## Deploy

```bash
# From the Swarm manager node, with the repo cloned/updated:
docker stack deploy -c stacks/monitoring/02-grafana/stack.yml grafana
```

Verify:

```bash
docker stack services grafana
# Expected: 1/1 running

docker service logs -f grafana_grafana
# Look for: "HTTP Server Listen" — confirms startup is complete
```

---

## Access

| Endpoint | URL | Auth |
|---|---|---|
| Grafana UI | `https://grafana.sexydad` | Admin credentials (set via setup script) |

> Requires DNS entry: `grafana.sexydad` → master1 IP  
> See [network setup docs](../../docs/) for Pi-hole / hosts file configuration.

Login with the username and password you entered during `setup-prometheus.sh`.

---

## Adding Dashboards

Dashboards can be added in two ways:

### 1. File-based provisioning (recommended for reproducibility)

Place JSON dashboard files in the provisioning folder **on the host**:

```
/srv/fastdata/grafana/provisioning/dashboards/<dashboard-name>.json
```

Grafana polls this directory and auto-loads new dashboards without restart.

Recommended community dashboards:

| Dashboard | Grafana ID | Description |
|---|---|---|
| Node Exporter Full | `1860` | OS metrics (CPU, RAM, disk, network) |
| cAdvisor | `14282` | Docker container metrics |
| NVIDIA GPU | `14574` | GPU utilization, VRAM, temperature |
| Traefik | `17346` | Request rates, latencies, error rates |

Import via UI: **Dashboards → Import → Enter ID → Load**.

### 2. UI import (ad-hoc)

Use **Dashboards → Import** in the Grafana UI for one-off imports.  
These survive service restarts because they are stored in `/var/lib/grafana` (bind-mounted).

---

## Useful Commands

```bash
# Check service status
docker stack services grafana

# View logs
docker service logs -f grafana_grafana

# Reset admin password (if locked out)
docker exec -it <container_id> grafana-cli admin reset-admin-password <new-password>

# Remove stack
docker stack rm grafana
```

---

## Resource Usage (approximate)

| Service | CPU reservation | RAM reservation |
|---|---|---|
| grafana | 0.1 CPU | 128 MiB |

---

## Configuration Files

- `stack.yml` — service definition, secrets, configs, placement
- `provisioning/datasources/prometheus.yml` — Prometheus datasource (auto-loaded)
- `provisioning/dashboards/provider.yml` — dashboard file provider config

> Swarm Configs are immutable. To update provisioning files, run `docker stack rm grafana` then redeploy.
