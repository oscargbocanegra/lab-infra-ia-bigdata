# Prometheus Stack — Metrics Collection

> Phase 6.2 — Observability | Lab Infra AI + Big Data

## Overview

This stack deploys the core metrics collection pipeline for the 2-node Swarm cluster.  
It collects OS-level and container-level metrics from both nodes and exposes them to Grafana.

**Services:**

| Service | Image | Node | Purpose |
|---|---|---|---|
| `prometheus` | `prom/prometheus:v2.53.5` | control (master1) | TSDB + scrape engine |
| `node-exporter` | `prom/node-exporter:v1.10.2` | control (master1) | OS metrics |
| `node-exporter-compute` | `prom/node-exporter:v1.10.2` | compute (master2) | OS metrics |
| `cadvisor` | `ghcr.io/google/cadvisor:v0.56.2` | control (master1) | Container metrics |
| `cadvisor-compute` | `ghcr.io/google/cadvisor:v0.56.2` | compute (master2) | Container metrics |

> NVIDIA GPU metrics are in a separate stack (`03-nvidia-exporter`) — see that README for details.

---

## Metrics Scraped

| Job | Target | Port | Labels |
|---|---|---|---|
| `prometheus` | `localhost` | 9090 | `node=control` |
| `node` | `node-exporter` | 9100 | `node=control` |
| `node` | `node-exporter-compute` | 9100 | `node=compute` |
| `cadvisor` | `cadvisor` | 8080 | `node=control` |
| `cadvisor` | `cadvisor-compute` | 8080 | `node=compute` |
| `nvidia_gpu` | `nvidia-exporter` | 9835 | `node=compute`, `gpu=rtx2080ti` |
| `traefik` | `traefik` | 8082 | `node=control` |

All service names resolve via Docker overlay DNS — no IP addresses needed.

---

## Storage

- **Path:** `/srv/fastdata/prometheus` on master1
- **Retention:** 15 days (`--storage.tsdb.retention.time=15d`)
- **Available space:** ~348 GB on `/srv/fastdata`

---

## Pre-requisites

Run **once** from the Swarm manager node before deploying:

```bash
# 1. Create data directory with correct ownership
mkdir -p /srv/fastdata/prometheus
chown 65534:65534 /srv/fastdata/prometheus   # nobody:nobody (Prometheus UID)

# 2. Create Swarm Secrets (interactive — use the shared setup script)
bash scripts/observability/setup-prometheus.sh
```

> The setup script also creates Grafana secrets and the Prometheus BasicAuth secret for Traefik.

---

## Deploy

```bash
# From the Swarm manager node, with the repo cloned/updated:
docker stack deploy -c stacks/monitoring/01-prometheus/stack.yml prometheus
```

Verify:

```bash
docker stack services prometheus
# Expected: 5/5 services running
```

Check all targets are UP:

```
https://prometheus.sexydad/targets
```

---

## Access

| Endpoint | URL | Auth |
|---|---|---|
| Prometheus UI | `https://prometheus.sexydad` | BasicAuth (`prometheus_basicauth` secret) |

> Requires DNS entry: `prometheus.sexydad` → master1 IP  
> See [network setup docs](../../docs/) for Pi-hole / hosts file configuration.

---

## Resource Usage (approximate)

| Service | CPU reservation | RAM reservation |
|---|---|---|
| prometheus | 0.25 CPU | 512 MiB |
| node-exporter × 2 | 0.05 CPU each | 32 MiB each |
| cadvisor × 2 | 0.05 CPU each | 64 MiB each |

---

## Useful Commands

```bash
# Check service status
docker stack services prometheus

# View Prometheus logs
docker service logs -f prometheus_prometheus

# Force config reload without restart (--web.enable-lifecycle is ON)
curl -X POST http://localhost:9090/-/reload   # run from inside the prometheus container

# Remove stack
docker stack rm prometheus
```

---

## Configuration

- `prometheus.yml` — scrape config (loaded as Docker Swarm Config)
- `stack.yml` — service definitions, placement constraints, resource limits

To update `prometheus.yml` after deployment:

```bash
# Swarm Configs are immutable — must remove and redeploy
docker stack rm prometheus
docker stack deploy -c stacks/monitoring/01-prometheus/stack.yml prometheus
```
