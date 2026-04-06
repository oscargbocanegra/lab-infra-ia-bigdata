# Networking — Networks, Domains and Traffic Flow

> Updated: 2026-03-30 — Phase 5: MinIO, Spark, Airflow

---

## Network Topology

```
                         INTERNET
                            ✗  (no public exposure)
                            │
                   ┌────────┴────────┐
                   │   LAN Router    │
                   │ <router-ip>     │
                   └────────┬────────┘
                            │ Ethernet (wired)
              ┌─────────────┴──────────────┐
              │                            │
    ┌─────────▼──────────┐      ┌──────────▼──────────┐
    │    master1         │      │    master2          │
    │ <master1-ip>       │      │ <master2-ip>        │
    │ Swarm Manager      │      │ Swarm Worker        │
    └─────────┬──────────┘      └──────────┬──────────┘
              │                            │
              └──────────┬─────────────────┘
                         │
              Docker Swarm Overlay Networks
              ┌──────────┴──────────────┐
              │                         │
         ┌────▼─────┐           ┌───────▼──────┐
         │  public  │           │   internal   │
         │ overlay  │           │   overlay    │
         │ (ingress)│           │  (backend)   │
         └──────────┘           └──────────────┘
```

---

## Docker Swarm Networks

### `public` network (overlay, attachable)

**Purpose**: Communication between Traefik and each service's backends.

```bash
# Initial creation
docker network create --driver overlay --attachable public
```

| Parameter | Value |
|-----------|-------|
| Driver | overlay |
| Scope | swarm |
| Attachable | yes |
| Encryption | yes (automatic overlay) |

**Connected services**:
- traefik (bidirectional: receives LAN requests, routes to backends)
- portainer
- n8n
- jupyter-<admin-user> / jupyter-<second-user>
- ollama
- opensearch / dashboards
- minio (console + API)
- spark-master / spark-worker / spark-history
- airflow-webserver / airflow-flower

### `internal` network (overlay, attachable)

**Purpose**: Private service-to-service communication. Not exposed to Traefik or LAN directly.

```bash
# Initial creation
docker network create --driver overlay --attachable internal
```

| Parameter | Value |
|-----------|-------|
| Driver | overlay |
| Scope | swarm |
| Attachable | yes |
| Encryption | yes |

**Connected services**:
- postgres (accessed by n8n, airflow)
- n8n (accesses postgres, opensearch)
- traefik (needs to know backends' IPs)
- ollama (accessed by jupyter internally)
- opensearch (accessed by dashboards, jupyter, n8n)
- portainer-agent
- minio (accessed by spark, jupyter, airflow via s3a/boto3)
- redis (accessed by airflow scheduler + worker)
- spark-master (accessed by jupyter via spark://)
- airflow-scheduler / airflow-worker / airflow-flower

---

## Internal domain: `*.sexydad`

All services are published under the `.sexydad` domain (internal LAN domain).

**Resolution**: No formal DNS. Configured via `/etc/hosts` on each client:

```
# /etc/hosts (Windows/Linux/Mac client)
<master1-ip>  traefik.sexydad
<master1-ip>  portainer.sexydad
<master1-ip>  n8n.sexydad
<master1-ip>  opensearch.sexydad
<master1-ip>  dashboards.sexydad
<master1-ip>  ollama.sexydad
<master1-ip>  jupyter-<admin-user>.sexydad
<master1-ip>  jupyter-<second-user>.sexydad
<master1-ip>  minio.sexydad
<master1-ip>  minio-api.sexydad
<master1-ip>  spark-master.sexydad
<master1-ip>  spark-worker.sexydad
<master1-ip>  spark-history.sexydad
<master1-ip>  airflow.sexydad
<master1-ip>  airflow-flower.sexydad
```

> All entries point to `<master1-ip>` (master1) because **Traefik acts as the sole ingress**.

**Recommended next step (improvement)**: Configure a local DNS on the router for wildcard `*.sexydad → <master1-ip>` to eliminate the need to edit `/etc/hosts` on every client.

---

## Port Map

### master1 — Published ports

| Port | Protocol | Service | Mode |
|------|----------|---------|------|
| 80 | TCP | Traefik (→ redirect HTTPS) | host |
| 443 | TCP | Traefik (HTTPS/TLS) | host |

> Traefik uses `mode: host` to ensure ports are opened directly on master1, NOT through Swarm's routing mesh.

### master2 — Published ports

| Port | Protocol | Service | Mode |
|------|----------|---------|------|
| 5432 | TCP | PostgreSQL | host |

> Postgres uses `mode: host` for direct access from DBeaver/SQL clients on the LAN.

### Internal ports (overlay `internal` only)

| Port | Service | Accessed by |
|------|---------|-------------|
| 5678 | n8n | Traefik (via public) |
| 9200 | OpenSearch | Traefik, Jupyter, n8n, Airflow |
| 5601 | OpenSearch Dashboards | Traefik |
| 11434 | Ollama | Traefik, Jupyter |
| 8888 | JupyterLab (per user) | Traefik |
| 9000 | Portainer | Traefik |
| 9001 | Portainer Agent | Portainer server |
| 9000 | MinIO API (S3) | Spark (s3a), Jupyter (boto3/s3fs), Airflow |
| 9001 | MinIO Console | Traefik |
| 7077 | Spark Master (Spark protocol) | Jupyter (SparkSession), Airflow |
| 8080 | Spark Master WebUI | Traefik |
| 8081 | Spark Worker WebUI | Traefik |
| 18080 | Spark History Server | Traefik |
| 8080 | Airflow Webserver | Traefik |
| 5555 | Airflow Flower | Traefik |
| 6379 | Redis | Airflow scheduler + worker (Celery) |

---

## HTTP Request Flow (example: n8n)

```
LAN Client (<client-ip>)
  │
  │  GET https://n8n.sexydad
  │  → DNS lookup: n8n.sexydad → <master1-ip> (via /etc/hosts)
  │  → TCP connect to <master1-ip>:443
  ▼
Traefik (master1:443, mode: host)
  │
  │  1. TLS handshake (self-signed cert from secret traefik_tls_cert)
  │  2. Middleware: lan-whitelist.check(<client-ip>) → ✅ in <lan-cidr>
  │  3. Router match: Host(`n8n.sexydad`) → service n8n
  │  4. Load balance to n8n container (via overlay public)
  ▼
n8n container (master2, overlay public)
  │
  │  Response HTTP 200
  ▼
LAN Client
```

---

## Internal Communication (service-to-service)

```
n8n → postgres (overlay internal)
  Service DNS: postgres_postgres → Container IP of Postgres
  Port: 5432
  No network authentication (password via secret)

opensearch-dashboards → opensearch (overlay internal)
  Service DNS: opensearch_opensearch (or hostname "opensearch")
  Port: 9200
  No auth (security plugin disabled)

jupyter → ollama (overlay internal)
  URL: http://ollama:11434
  No auth (internal network only — not exposed to LAN without Traefik)
  
jupyter → opensearch (overlay internal)  
  URL: http://opensearch:9200
  No auth (internal network only)
```

---

## Firewall Considerations

**Current state**: UFW is active on both nodes (Phase 7 — DOCKER-USER chain configured).

```bash
# master1: allow ingress on :80, :443 and SSH
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from <lan-cidr>   # Full LAN for Swarm internals
ufw enable

# master2: SSH + Swarm + postgres LAN only
ufw allow 22/tcp
ufw allow from <lan-cidr>   # LAN for Swarm + Postgres :5432
ufw enable
```
