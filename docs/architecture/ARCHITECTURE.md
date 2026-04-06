# Lab Architecture — lab-infra-ia-bigdata

> Last updated: 2026-03-31 — Lab 100% operational (20 services)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Physical cluster diagram](#2-physical-cluster-diagram)
3. [Logical services diagram](#3-logical-services-diagram)
4. [LAN traffic flow](#4-lan-traffic-flow)
5. [Data flow in AI/Data pipelines](#5-data-flow-in-aidata-pipelines)
6. [Placement strategy](#6-placement-strategy)
7. [Docker Swarm networks](#7-docker-swarm-networks)
8. [Security model](#8-security-model)
9. [Key architectural decisions](#9-key-architectural-decisions)

---

## 1. Overview

The lab is a **2-node Docker Swarm cluster** oriented toward experimentation with **AI, Big Data, and automation**. The design follows a **separation of concerns** principle:

- **master1** (Control Plane): gateway, orchestration, lightweight services
- **master2** (Compute + Data): GPU workloads, databases, primary storage

All external traffic enters through **Traefik** (on master1) via HTTPS with self-signed TLS, accessible only from the LAN `<lan-cidr>`.

---

## 2. Physical cluster diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        LAN <lan-cidr>                               │
│                                                                     │
│  ┌──────────────────────────┐    ┌──────────────────────────────┐   │
│  │        master1           │    │          master2             │   │
│  │   (Control Plane)        │    │    (Compute + Data + GPU)    │   │
│  │                          │    │                              │   │
│  │  Intel i7-6700T          │    │  Intel i9-9900K              │   │
│  │  4C/8T @ 2.8 GHz         │    │  8C/16T @ 3.6 GHz            │   │
│  │  32 GB RAM               │    │  32 GB RAM                   │   │
│  │                          │    │                              │   │
│  │  💾 HDD 500 GB (ROTA)    │    │  💾 NVMe 1TB (970 EVO)       │   │
│  │  └─ /srv/fastdata        │    │  └─ /srv/fastdata (LVM 600G) │   │
│  │     (local HDD)          │    │     postgres/ opensearch/    │   │
│  │                          │    │     airflow/ jupyter/        │   │
│  │  Swarm: MANAGER/LEADER   │    │  💾 HDD 2TB (ST2000LM015)   │   │
│  │  Labels:                 │    │  └─ /srv/datalake            │   │
│  │   tier=control           │    │     datasets/ models/        │   │
│  │   node_role=manager      │    │     notebooks/ artifacts/    │   │
│  │   storage=backup         │    │     backups/                 │   │
│  │   net=lan                │    │                              │   │
│  │                          │    │  🎮 NVIDIA RTX 2080 Ti       │   │
│  │                          │    │     11 GB VRAM               │   │
│  │                          │    │     CUDA 12.2                │   │
│  │                          │    │     Driver 535.288.01        │   │
│  │                          │    │                              │   │
│  │                          │    │  Swarm: WORKER               │   │
│  │                          │    │  Labels:                     │   │
│  │                          │    │   tier=compute               │   │
│  │                          │    │   node_role=worker           │   │
│  │                          │    │   storage=primary            │   │
│  │                          │    │   gpu=nvidia                 │   │
│  │                          │    │   net=lan                    │   │
│  └──────────┬───────────────┘    └──────────────┬───────────────┘   │
│             │                                   │                   │
│             └──────────── Overlay Networks ─────┘                   │
│                    (public + internal)                               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Logical services diagram

```
╔══════════════════════════════════════╗  ╔═══════════════════════════════════════════╗
║         master1  (tier=control)      ║  ║         master2  (tier=compute)           ║
╠══════════════════════════════════════╣  ╠═══════════════════════════════════════════╣
║                                      ║  ║                                           ║
║  ┌──────────────────────────────┐    ║  ║  ┌──────────────────────────────────┐    ║
║  │  Traefik v2.11               │    ║  ║  │  PostgreSQL 16                   │    ║
║  │  :80 :443 (host mode)        │    ║  ║  │  /srv/fastdata/postgres (NVMe)   │    ║
║  │  Reverse Proxy + TLS + LAN   │    ║  ║  │  :5432 (host mode)               │    ║
║  └──────────────────────────────┘    ║  ║  │  databases: postgres / n8n / airflow│  ║
║                                      ║  ║  └──────────────────────────────────┘    ║
║  ┌──────────────────────────────┐    ║  ║                                           ║
║  │  Portainer CE 2.39.1         │    ║  ║  ┌──────────────────────────────────┐    ║
║  │  /srv/fastdata/portainer     │    ║  ║  │  n8n 2.4.7                       │    ║
║  │  → tcp://tasks.agent:9001    │    ║  ║  │  /srv/fastdata/n8n (NVMe)        │    ║
║  └──────────────────────────────┘    ║  ║  │  → postgres:5432 (n8n DB)        │    ║
║                                      ║  ║  └──────────────────────────────────┘    ║
║  ┌──────────────────────────────┐    ║  ║                                           ║
║  │  OpenSearch 2.19.4           │    ║  ║  ┌──────────────────────────────────┐    ║
║  │  /srv/fastdata/opensearch    │    ║  ║  │  JupyterLab (<admin-user>)       │    ║
║  │  :9200 (internal)            │    ║  ║  │  /srv/fastdata/jupyter/<admin-user>│   ║
║  └──────────────────────────────┘    ║  ║  │  GPU + 8CPU + 12GB — uid 1000    │    ║
║                                      ║  ║  └──────────────────────────────────┘    ║
║  ┌──────────────────────────────┐    ║  ║                                           ║
║  │  OpenSearch Dashboards       │    ║  ║  ┌──────────────────────────────────┐    ║
║  │  2.19.4  :5601               │    ║  ║  │  JupyterLab (<second-user>)      │    ║
║  └──────────────────────────────┘    ║  ║  │  /srv/fastdata/jupyter/<second-user>│  ║
║                                      ║  ║  │  GPU + 8CPU + 12GB — uid 1001    │    ║
║  ┌──────────────────────────────┐    ║  ║  └──────────────────────────────────┘    ║
║  │  Redis 7.2 (Celery broker)   │    ║  ║                                           ║
║  │  /srv/fastdata/airflow/redis │    ║  ║  ┌──────────────────────────────────┐    ║
║  └──────────────────────────────┘    ║  ║  │  Ollama 0.19.0                   │    ║
║                                      ║  ║  │  /srv/datalake/models/ollama     │    ║
║  ┌──────────────────────────────┐    ║  ║  │  GPU RTX 2080 Ti (11 GB VRAM)    │    ║
║  │  Airflow Webserver 2.9.3     │    ║  ║  │  :11434 (internal)               │    ║
║  │  /srv/fastdata/airflow/dags  │    ║  ║  └──────────────────────────────────┘    ║
║  │  :8080 (internal)            │    ║  ║                                           ║
║  └──────────────────────────────┘    ║  ║  ┌──────────────────────────────────┐    ║
║                                      ║  ║  │  MinIO RELEASE.2024-11-07        │    ║
║  ┌──────────────────────────────┐    ║  ║  │  /srv/datalake/minio (HDD 2TB)   │    ║
║  │  Airflow Scheduler           │    ║  ║  │  :9000 S3 API / :9001 Console    │    ║
║  │  /srv/fastdata/airflow/dags  │    ║  ║  └──────────────────────────────────┘    ║
║  └──────────────────────────────┘    ║  ║                                           ║
║                                      ║  ║  ┌──────────────────────────────────┐    ║
║  ┌──────────────────────────────┐    ║  ║  │  Spark Worker 3.5.3              │    ║
║  │  Airflow Flower              │    ║  ║  │  /srv/fastdata/spark-tmp (NVMe)  │    ║
║  │  :5555 (internal)            │    ║  ║  │  10 CPUs / 14 GB offered         │    ║
║  └──────────────────────────────┘    ║  ║  │  → spark-master:7077             │    ║
║                                      ║  ║  └──────────────────────────────────┘    ║
║  ┌──────────────────────────────┐    ║  ║                                           ║
║  │  Spark Master 3.5.3          │    ║  ║  ┌──────────────────────────────────┐    ║
║  │  /srv/fastdata/spark-history │    ║  ║  │  Airflow Worker (Celery)         │    ║
║  │  :7077 (internal)            │    ║  ║  │  /srv/fastdata/airflow/dags      │    ║
║  └──────────────────────────────┘    ║  ║  │  /srv/datalake/datasets (ro)     │    ║
║                                      ║  ║  └──────────────────────────────────┘    ║
║  ┌──────────────────────────────┐    ║  ║                                           ║
║  │  Spark History Server        │    ║  ║  ┌──────────────────────────────────┐    ║
║  │  /srv/fastdata/spark-history │    ║  ║  │  Portainer Agent                 │    ║
║  │  :18080 (internal)           │    ║  ║  │  (global: both nodes)            │    ║
║  └──────────────────────────────┘    ║  ║  └──────────────────────────────────┘    ║
║                                      ║  ║                                           ║
║  ┌──────────────────────────────┐    ║  ╚═══════════════════════════════════════════╝
║  │  Portainer Agent             ║    ║
║  │  (global: both nodes)        ║    ║
║  └──────────────────────────────┘    ║
╚══════════════════════════════════════╝
```

---

## 4. LAN traffic flow

```
LAN User (PC)
       │
       │  HTTPS :443
       ▼
┌──────────────────┐
│  Traefik v2.11   │  master1:443 (mode: host)
│  <master1-ip>    │  HTTP→HTTPS redirect on :80
└────────┬─────────┘
         │
         │  Middleware chain per route:
         │  1. lan-whitelist (<lan-cidr>)
         │  2. basicauth (per service)
         │  3. TLS termination (self-signed cert)
         │
         ├──[portainer.sexydad]──────────────► Portainer :9000 (master1)
         ├──[traefik.sexydad]────────────────► Traefik Dashboard :8080 (master1)
         ├──[n8n.sexydad]────────────────────► n8n :5678 (master2)
         ├──[opensearch.sexydad]─────────────► OpenSearch :9200 (master1)
         ├──[dashboards.sexydad]─────────────► OpenSearch Dashboards :5601 (master1)
         ├──[ollama.sexydad]─────────────────► Ollama :11434 (master2)
         ├──[jupyter-<admin-user>.sexydad]───► JupyterLab :8888 (master2)
         ├──[jupyter-<second-user>.sexydad]──► JupyterLab :8888 (master2)
         ├──[minio.sexydad]──────────────────► MinIO Console :9001 (master2)
         ├──[minio-api.sexydad]──────────────► MinIO S3 API :9000 (master2)
         ├──[spark-master.sexydad]───────────► Spark Master UI :8080 (master1)
         ├──[spark-worker.sexydad]───────────► Spark Worker UI :8081 (master2)
         ├──[spark-history.sexydad]──────────► Spark History :18080 (master1)
         ├──[airflow.sexydad]────────────────► Airflow Webserver :8080 (master1)
         └──[airflow-flower.sexydad]──────────► Celery Flower :5555 (master1)


Internal communication (service-to-service via "internal" overlay):
  n8n              ──► postgres:5432
  airflow_*        ──► postgres:5432  (DAG metadata)
  airflow_*        ──► redis:6379     (Celery broker)
  airflow_*        ──► minio:9000     (remote logs — disabled by default)
  airflow_worker   ──► ollama:11434   (inference from DAGs)
  opensearch-dashboards ──► opensearch:9200
  jupyter          ──► ollama:11434   (no auth, internal network)
  jupyter          ──► opensearch:9200
  jupyter          ──► minio:9000     (S3 API for datasets)
  jupyter          ──► spark-master:7077 (submit jobs)
  spark_worker     ──► spark-master:7077
  spark_history    ──► /opt/spark/history (shared filesystem)
```

---

## 5. Data flow in AI/Data pipelines

```
┌─────────────────────────────────────────────────────────────────────┐
│                   Data flow — Medallion Architecture                 │
└─────────────────────────────────────────────────────────────────────┘

INGESTION (Bronze):
  Airflow DAGs / n8n / manual scripts
       │
       ▼
  s3a://bronze/  (MinIO — HDD 2TB, CSV/JSON/Parquet raw, append-only)

PROCESSING (Silver):
  Airflow → SparkSubmitOperator
       │
       ▼
  Spark Job (master1:7077 → worker master2)
       │   reads  s3a://bronze/
       │   writes → s3a://silver/  (Delta Lake ACID: clean, typed, deduplicated)
       └── event logs → /srv/fastdata/spark-history

AGGREGATION (Gold):
  Airflow → SparkSubmitOperator
       │
       ▼
  Spark Job
       │   reads  s3a://silver/
       └── writes → s3a://gold/  (Delta Lake: KPIs, ML features, reports)

ANALYSIS / ML:
  JupyterLab (PySpark + Delta + boto3)
       │   reads  s3a://bronze/ | silver/ | gold/
       │   accesses GPU ◄── RTX 2080 Ti (CUDA)
       │   uses Ollama ◄── http://ollama:11434 (LLM inference)
       │   indexes in OpenSearch ──► http://opensearch:9200
       └── saves results ──► /srv/datalake/artifacts

VISUALIZATION:
  OpenSearch Dashboards ◄──── Indices + Aggregations
  (https://dashboards.sexydad)

AUTOMATION:
  n8n (https://n8n.sexydad) ──► webhooks, external integrations, notifications
  Airflow (https://airflow.sexydad) ──► orchestrates the ENTIRE pipeline

LLM MODELS:
  Ollama ──► /srv/datalake/models/ollama (HDD 2TB, persistent)
  Jupyter ──► access via http://ollama:11434/api/generate
  Airflow ──► access via http://ollama:11434 from worker
```

---

## 6. Placement strategy

Docker Swarm distributes containers using **node labels + constraints in the stack**:

```yaml
# Constraint example (in each service's stack.yml):
deploy:
  placement:
    constraints:
      - node.labels.tier == control    # → master1
      - node.labels.tier == compute    # → master2
      - node.labels.gpu == nvidia      # → master2 (GPU only)
```

| Service | Node | Label used | Reason |
|---------|------|------------|--------|
| Traefik | master1 | `tier=control` | Ports :80/:443 on control plane |
| Portainer | master1 | `tier=control` | Admin UI |
| OpenSearch | master1 | `tier=control` | master2 saturated with GPU workloads |
| OpenSearch Dashboards | master1 | `tier=control` | Lightweight frontend |
| Redis (Celery) | master1 | `tier=control` | Lightweight broker, alongside scheduler |
| Airflow Webserver | master1 | `tier=control` | UI + REST API |
| Airflow Scheduler | master1 | `tier=control` | Lightweight planner |
| Airflow Flower | master1 | `tier=control` | Lightweight monitor |
| Spark Master | master1 | `tier=control` | Lightweight coordinator |
| Spark History | master1 | `tier=control` | Reads logs from filesystem |
| PostgreSQL | master2 | `hostname=master2` | NVMe for I/O-intensive workloads |
| n8n | master2 | `tier=compute` | Co-located with Postgres (same network) |
| **JupyterLab** | master2 | `tier=compute` + `hostname=master2` | GPU + NVMe for notebooks |
| **Ollama** | master2 | `tier=compute` + `gpu=nvidia` | GPU required |
| MinIO | master2 | `tier=compute` + `hostname=master2` | HDD 2TB datalake |
| Spark Worker | master2 | `tier=compute` + `hostname=master2` | NVMe for shuffle/spill |
| Airflow Worker | master2 | `tier=compute` + `hostname=master2` | GPU, NVMe, HDD datalake access |
| Portainer Agent | GLOBAL | — | Runs on ALL nodes |

---

## 7. Docker Swarm networks

```
┌─────────────────────────────────────────────────────────────┐
│                    Overlay Networks                          │
├────────────┬───────────────────────────────────────────────┤
│  public    │  attachable, overlay                           │
│            │  Used for: Traefik ↔ backends                  │
│            │  Services: traefik, portainer, n8n,            │
│            │             jupyter, ollama,                   │
│            │             opensearch, dashboards,            │
│            │             minio, spark_*, airflow_webserver, │
│            │             airflow_flower                     │
├────────────┼───────────────────────────────────────────────┤
│  internal  │  attachable, overlay                           │
│            │  Used for: service-to-service                  │
│            │  Services: postgres, n8n, traefik,             │
│            │             jupyter, ollama,                   │
│            │             opensearch, portainer-agent,       │
│            │             minio, spark_*, redis,             │
│            │             airflow_* (all)                    │
└────────────┴───────────────────────────────────────────────┘
```

**Access rules**:
- A service on `public` can be reached by Traefik
- A service on `internal` can communicate with other services without exposing ports
- Services that need BOTH (externally reachable AND talking to other services) join both networks

---

## 8. Security model

```
┌─────────────────────────────────────────────────────────────────┐
│                    Security layers                               │
│                                                                  │
│  1. Perimeter: LAN only (<lan-cidr>)                             │
│     └─ Traefik middleware: lan-whitelist / lan-allow             │
│                                                                  │
│  2. Authentication: BasicAuth per service (where applicable)     │
│     └─ Secrets: traefik_basic_auth, jupyter_basicauth_v2,        │
│                 ollama_basicauth, opensearch_basicauth,           │
│                 dashboards_basicauth                              │
│     └─ Native auth: Portainer, Airflow, MinIO, n8n               │
│                                                                  │
│  3. Transport: Self-signed TLS on all endpoints                  │
│     └─ Secrets: traefik_tls_cert, traefik_tls_key               │
│                                                                  │
│  4. DB/App credentials: Docker Swarm Secrets                     │
│     └─ Secrets: pg_super_pass, pg_n8n_pass, pg_airflow_pass      │
│                 minio_access_key, minio_secret_key               │
│                 n8n_encryption_key, n8n_user_mgmt_jwt_secret     │
│                 airflow_fernet_key, airflow_webserver_secret      │
│                                                                  │
│  5. Internal network: Encrypted overlay (not exposed to LAN)     │
│     └─ Internal services: have NO published ports               │
└─────────────────────────────────────────────────────────────────┘
```

**What is NOT yet implemented** (backlog):
- [ ] Hardened firewall (UFW/iptables) on both nodes
- [ ] Automatic secret rotation
- [ ] Certificates from a real internal CA (instead of self-signed)
- [ ] OpenID/OAuth authentication (for Jupyter/Airflow)

---

## 9. Key architectural decisions

> See full ADRs in [`docs/adrs/`](../adrs/)

### ADR-001: Docker Swarm over Kubernetes
**Decision**: Use Docker Swarm for orchestration.  
**Reason**: 2 nodes don't justify K8s operational complexity. Swarm is sufficient for a lab, simpler to maintain, and supports declarative stack-based deployments.

### ADR-002: master1 as exclusive gateway
**Decision**: Traefik runs only on master1 (mode: host on ports :80/:443).  
**Reason**: A single entry point simplifies certificates, whitelisting, and logging. master2 is free for GPU/data workloads.

### ADR-003: fastdata/datalake separation
**Decision**: Two distinct mount points on master2.  
**Reason**: `/srv/fastdata` (NVMe) for I/O-intensive workloads (DBs, metadata). `/srv/datalake` (HDD 2TB) for bulk data (models, datasets, artifacts). Maximizes performance without wasting NVMe capacity.

### ADR-004: OpenSearch security plugin disabled
**Decision**: `DISABLE_SECURITY_PLUGIN=true` in OpenSearch.  
**Reason**: In a LAN-only lab with BasicAuth+Whitelist in Traefik, this is sufficient. The security plugin adds internal certificate complexity that provides no benefit in this context.

### ADR-005: GPU Generic Resources in Swarm
**Decision**: Register GPU as Generic Resource (`nvidia.com/gpu=1`) instead of using the runtime driver directly.  
**Reason**: Swarm has no native `--gpus` support. Generic Resources enable proper reservation and placement. `default-runtime: nvidia` in master2's `daemon.json` activates the runtime.

### ADR-006: OpenSearch on master1 (not master2)
**Decision**: OpenSearch runs on master1 despite having HDD instead of NVMe.  
**Reason**: At deployment time, master2 had 14/16 CPUs and 28/31 GB RAM committed by Jupyter x2 + Ollama. OpenSearch is a support/observability service; HDD is sufficient for lab workloads.
