<div align="center">

# 🧠 Lab Infra — AI & Big Data Platform

**Production-grade, self-hosted AI + Big Data laboratory on bare-metal Docker Swarm**

[![Docker Swarm](https://img.shields.io/badge/Docker_Swarm-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docs.docker.com/engine/swarm/)
[![Python](https://img.shields.io/badge/Python_3.11-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Apache Spark](https://img.shields.io/badge/Apache_Spark_3.5-E25A1C?style=for-the-badge&logo=apachespark&logoColor=white)](https://spark.apache.org/)
[![Apache Airflow](https://img.shields.io/badge/Apache_Airflow_2.9-017CEE?style=for-the-badge&logo=apacheairflow&logoColor=white)](https://airflow.apache.org/)
[![Jupyter](https://img.shields.io/badge/JupyterLab-F37626?style=for-the-badge&logo=jupyter&logoColor=white)](https://jupyter.org/)
[![Ollama](https://img.shields.io/badge/Ollama_0.19-000000?style=for-the-badge&logo=ollama&logoColor=white)](https://ollama.com/)
[![Qdrant](https://img.shields.io/badge/Qdrant_v1.13-DC244C?style=for-the-badge&logo=qdrant&logoColor=white)](https://qdrant.tech/)
[![Open WebUI](https://img.shields.io/badge/Open_WebUI_v0.6.5-000000?style=for-the-badge&logo=openai&logoColor=white)](https://github.com/open-webui/open-webui)

[![MinIO](https://img.shields.io/badge/MinIO-C72E49?style=for-the-badge&logo=minio&logoColor=white)](https://min.io/)
[![Delta Lake](https://img.shields.io/badge/Delta_Lake-003366?style=for-the-badge&logo=delta&logoColor=white)](https://delta.io/)
[![OpenSearch](https://img.shields.io/badge/OpenSearch_2.19-005EB8?style=for-the-badge&logo=opensearch&logoColor=white)](https://opensearch.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL_16-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![n8n](https://img.shields.io/badge/n8n-EA4B71?style=for-the-badge&logo=n8n&logoColor=white)](https://n8n.io/)
[![Traefik](https://img.shields.io/badge/Traefik_v2.11-24A1C1?style=for-the-badge&logo=traefikproxy&logoColor=white)](https://traefik.io/)

[![Prometheus](https://img.shields.io/badge/Prometheus_v2.53-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Grafana_11.6-F46800?style=for-the-badge&logo=grafana&logoColor=white)](https://grafana.com/)

[![NVIDIA CUDA](https://img.shields.io/badge/NVIDIA_CUDA_12.2-76B900?style=for-the-badge&logo=nvidia&logoColor=white)](https://developer.nvidia.com/cuda-toolkit)
[![RTX 2080 Ti](https://img.shields.io/badge/RTX_2080_Ti_11GB_VRAM-76B900?style=for-the-badge&logo=nvidia&logoColor=white)](https://www.nvidia.com/)
[![Infrastructure as Code](https://img.shields.io/badge/Infrastructure_as_Code-IaC-success?style=for-the-badge&logo=terraform&logoColor=white)]()
[![Status](https://img.shields.io/badge/Status-100%25_Operational-brightgreen?style=for-the-badge)]()
[![Services](https://img.shields.io/badge/Services-30_Running-brightgreen?style=for-the-badge)]()

</div>

---

## 📌 Overview

This repository is a **fully reproducible Infrastructure-as-Code** definition for a 2-node bare-metal **Docker Swarm** cluster purpose-built for AI, Machine Learning, and Big Data experimentation.

Every component is production-grade: secrets management via Docker Swarm Secrets (zero passwords in code), TLS on all endpoints, LAN whitelist, GPU-accelerated inference, and a complete **Medallion Architecture** data pipeline (Bronze → Silver → Gold) using **Apache Spark + Delta Lake + MinIO**.

> **30 services running — 100% operational.** Deploys from scratch in one sitting.

### What makes this lab special

| Capability | Implementation |
|-----------|---------------|
| 🤖 **Local LLM inference** | Ollama 0.19 on RTX 2080 Ti (11 GB VRAM), no cloud required |
| 💬 **Chat UI + RAG** | Open WebUI v0.6.5 — multi-model chat with document knowledge bases |
| 🔍 **Vector search** | Qdrant v1.13 — semantic embeddings + ANN search for RAG pipelines |
| 🧪 **AI-powered notebooks** | JupyterLab with `%%JARVIS` magic + chat panel via `jupyter-ai` → Ollama |
| ⚡ **Distributed processing** | Apache Spark 3.5 cluster (Master + Worker, 10 CPUs / 14 GB RAM) |
| 🏅 **Medallion data pipeline** | Bronze (raw) → Silver (Delta Lake ACID) → Gold (Delta Lake KPIs) |
| 🔒 **Security by default** | Docker Swarm Secrets + BasicAuth + LAN-only whitelist + TLS |
| 🔄 **Auto-recovery** | All services with `restart_policy: any` — survives full reboot |
| 🧑‍💻 **Multi-user isolation** | Two independent JupyterLab instances (uid-isolated, GPU-shared) |
| 📦 **Pure IaC** | 100% declarative stacks — reproducible deploy from zero |

---

## 📐 Architecture

### Physical Cluster

```
┌─────────────────────────────────────────────────────────────────────┐
│                        LAN  192.168.80.0/24                         │
│                                                                     │
│  ┌──────────────────────────┐    ┌──────────────────────────────┐   │
│  │        master1           │    │          master2             │   │
│  │   (Control Plane)        │    │    (Compute + Data + GPU)    │   │
│  │                          │    │                              │   │
│  │  Intel i7-6700T          │    │  Intel i9-9900K              │   │
│  │  4C/8T  ·  2.8 GHz       │    │  8C/16T  ·  3.6 GHz          │   │
│  │  32 GB RAM               │    │  32 GB RAM                   │   │
│  │  HDD 500 GB              │    │  NVMe 1 TB + HDD 2 TB        │   │
│  │                          │    │  NVIDIA RTX 2080 Ti          │   │
│  │  Swarm: MANAGER          │    │  11 GB VRAM · CUDA 12.2      │   │
│  │  tier=control            │    │  Swarm: WORKER               │   │
│  │  192.168.80.100          │    │  tier=compute · gpu=nvidia   │   │
│  │                          │    │  192.168.80.200              │   │
│  └──────────┬───────────────┘    └──────────────┬───────────────┘   │
│             └──────────── Overlay Networks ─────┘                   │
│                    (public + internal)                               │
└─────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow

All external traffic enters through **Traefik** (master1) over HTTPS with TLS + LAN whitelist:

```
LAN User (browser)
       │  HTTPS :443
       ▼
┌──────────────┐
│  Traefik     │  ── lan-whitelist ── basicauth ── TLS termination
│  master1     │
└──────┬───────┘
       │
       ├──► portainer.sexydad        → Portainer CE        (master1)
       ├──► traefik.sexydad          → Traefik Dashboard   (master1)
       ├──► airflow.sexydad          → Airflow Webserver   (master1)
       ├──► airflow-flower.sexydad   → Celery Flower       (master1)
       ├──► opensearch.sexydad       → OpenSearch API      (master1)
       ├──► dashboards.sexydad       → OpenSearch Dashboards (master1)
       ├──► spark-master.sexydad     → Spark Master UI     (master1)
       ├──► spark-history.sexydad    → Spark History       (master1)
       ├──► n8n.sexydad              → n8n Automation      (master2)
       ├──► jupyter-ogiovanni.sexydad→ JupyterLab + GPU    (master2)
       ├──► jupyter-odavid.sexydad   → JupyterLab + GPU    (master2)
        ├──► ollama.sexydad           → Ollama LLM API      (master2)
        ├──► chat.sexydad             → Open WebUI Chat     (master1)
        ├──► qdrant.sexydad           → Qdrant Web UI       (master1)
        ├──► rag-api.sexydad          → RAG API + Swagger   (master1)
        ├──► minio.sexydad            → MinIO Console       (master2)
       ├──► minio-api.sexydad        → MinIO S3 API        (master2)
        ├──► spark-worker.sexydad     → Spark Worker UI     (master2)
        ├──► fluent-bit               → Log Collector (global, no UI)
        ├──► prometheus.sexydad       → Prometheus UI       (master1)
        └──► grafana.sexydad          → Grafana Dashboards  (master1)
```

### Service Placement Strategy

| Node | Services | Rationale |
|------|----------|-----------|
| **master1** | Traefik, Portainer, OpenSearch, Airflow (web/scheduler/flower), Redis, Spark (master/history), Qdrant, RAG API, Open WebUI | Lightweight control-plane services — HDD sufficient |
| **master2** | PostgreSQL, n8n, JupyterLab ×2, Ollama, MinIO, Spark Worker, Airflow Worker | Heavy I/O + GPU workloads on NVMe + RTX 2080 Ti |
| **global** | Portainer Agent, Fluent Bit | Required on all nodes for Swarm management and log collection |

---

## 🏅 Medallion Architecture (Bronze → Silver → Gold)

Data flows through three progressive quality layers, all stored in **MinIO (S3-compatible)** and processed by **Apache Spark**:

```
Data Sources (CSV, JSON, APIs, DB exports)
    │
    ▼
┌─────────────────────────────────────────┐
│  BRONZE  —  Raw Zone                    │
│  "Data exactly as it arrived"           │
│  s3a://bronze/                          │
│  Format: CSV / JSON / Parquet           │
│  Policy: append-only, never modify      │
└───────────────┬─────────────────────────┘
                │  Spark job: clean + validate + deduplicate
                ▼
┌─────────────────────────────────────────┐
│  SILVER  —  Curated Zone                │
│  "Clean, typed, deduplicated"           │
│  s3a://silver/                          │
│  Format: Delta Lake (ACID + time travel)│
│  Policy: upsert / SCD merge             │
└───────────────┬─────────────────────────┘
                │  Spark job: aggregate + business rules
                ▼
┌─────────────────────────────────────────┐
│  GOLD  —  Business Zone                 │
│  "Ready to consume: KPIs, ML features"  │
│  s3a://gold/                            │
│  Format: Delta Lake (partitioned)       │
│  Policy: periodic overwrite             │
└─────────────────────────────────────────┘
```

| Bucket | Layer | Format | Written by | Read by |
|--------|-------|--------|-----------|---------|
| `bronze` | Raw | CSV / JSON / Parquet | Airflow DAGs, n8n, notebooks | Spark (→ silver) |
| `silver` | Curated | **Delta Lake** | Spark | Spark (→ gold), Jupyter |
| `gold` | Business | **Delta Lake** | Spark | Jupyter, n8n, Airflow |
| `airflow-logs` | Infra | Plain text | Airflow worker | Airflow UI |
| `spark-warehouse` | Infra | Delta catalog | Spark | Spark History Server |
| `lab-notebooks` | Dev | `.ipynb` | Jupyter | Jupyter |

**Why Delta Lake on Silver and Gold?** ACID transactions (no corrupt tables on job failure), time travel (`VERSION AS OF N`), schema evolution, upserts via `MERGE`, and compaction (`OPTIMIZE`).

---

## 🧩 Service Inventory

### Core Infrastructure

| Service | Version | Node | URL | Status |
|---------|---------|------|-----|--------|
| **Traefik** — Reverse Proxy + TLS | v2.11 | master1 | `https://traefik.sexydad/dashboard/` | ✅ |
| **Portainer CE** — Swarm UI | 2.39.1 | master1 | `https://portainer.sexydad` | ✅ |
| **PostgreSQL** — Central DB | 16 | master2 | `192.168.80.200:5432` | ✅ |

### Automation

| Service | Version | Node | URL | Status |
|---------|---------|------|-----|--------|
| **n8n** — Workflow automation | 2.4.7 | master2 | `https://n8n.sexydad` | ✅ |
| **Airflow Webserver** | 2.9.3 | master1 | `https://airflow.sexydad` | ✅ |
| **Airflow Scheduler** | 2.9.3 | master1 | — (internal) | ✅ |
| **Airflow Worker** (Celery) | 2.9.3 | master2 | — (internal) | ✅ |
| **Airflow Flower** — Celery monitor | 2.9.3 | master1 | `https://airflow-flower.sexydad` | ✅ |
| **Redis** — Celery broker | 7.2 | master1 | — (internal) | ✅ |

### AI / ML

| Service | Version | Node | URL | Status |
|---------|---------|------|-----|--------|
| **JupyterLab** (ogiovanni) | Python 3.11 + GPU | master2 | `https://jupyter-ogiovanni.sexydad` | ✅ |
| **JupyterLab** (odavid) | Python 3.11 + GPU | master2 | `https://jupyter-odavid.sexydad` | ✅ |
| **Ollama** — LLM inference | 0.19 + RTX 2080 Ti | master2 | `https://ollama.sexydad` | ✅ |
| **Qdrant** — Vector DB | v1.13.4 | master1 | `https://qdrant.sexydad` | ✅ |
| **RAG API** — FastAPI RAG orchestration | latest | master1 | `https://rag-api.sexydad` | ✅ |
| **Open WebUI** — Chat UI | v0.6.5 | master1 | `https://chat.sexydad` | ✅ |

### Data / Big Data

| Service | Version | Node | URL | Status |
|---------|---------|------|-----|--------|
| **OpenSearch** — Search & Analytics | 2.19.4 | master1 | `https://opensearch.sexydad` | ✅ |
| **OpenSearch Dashboards** | 2.19.4 | master1 | `https://dashboards.sexydad` | ✅ |
| **MinIO** — S3-compatible object store | 2024-11-07 | master2 | `https://minio.sexydad` | ✅ |
| **Spark Master** — Distributed processing | 3.5.3 | master1 | `https://spark-master.sexydad` | ✅ |
| **Spark Worker** | 3.5.3 | master2 | `https://spark-worker.sexydad` | ✅ |
| **Spark History Server** | 3.5.3 | master1 | `https://spark-history.sexydad` | ✅ |

> **Total: 23 services — all 1/1 (or N/N) ✅**

---

## 📊 Observability

| Service | Version | Node | URL | Status |
|---------|---------|------|-----|--------|
| **Fluent Bit** — Log collector | 3.2 | global (both) | — (internal) | ✅ |
| **Prometheus** — Metrics TSDB | v2.53.5 | master1 | `https://prometheus.sexydad` | ✅ |
| **node-exporter** (master1) | v1.10.2 | master1 | — (internal :9100) | ✅ |
| **node-exporter** (master2) | v1.10.2 | master2 | — (internal :9100) | ✅ |
| **cAdvisor** (master1) | 0.56.2 | master1 | — (internal :8080) | ✅ |
| **cAdvisor** (master2) | 0.56.2 | master2 | — (internal :8080) | ✅ |
| **NVIDIA GPU Exporter** | 1.4.1 | master2 | — (internal :9835) | ✅ |
| **Grafana** — Dashboards | 11.6.14 | master1 | `https://grafana.sexydad` | ✅ |

> **Total: 30 services — all 1/1 (or N/N) ✅**

---

## 🤖 AI Features in JupyterLab

Each JupyterLab instance ships with three specialized kernels and full AI integration:

### Kernels

| Kernel | Purpose | Key Libraries |
|--------|---------|--------------|
| **Python — LLM** | LLM experiments, RAG, embeddings | `langchain`, `transformers`, `openai`, `boto3` |
| **Python — AI/ML** | ML training, computer vision, CUDA | `torch`, `torchvision`, `scikit-learn`, `tensorflow` |
| **Python — BigData** | Pipeline development, Delta Lake | `pyspark`, `delta-spark`, `s3fs`, `pyarrow` |

### `%%JARVIS` Magic — AI in any cell

Run natural language prompts directly inside notebooks using the local Ollama LLM (no cloud, no API key):

```python
# Load the extension once per session (or auto-loaded via startup)
%load_ext jupyter_ai_magics

# Ask Ollama directly from any cell
%%JARVIS
Write a PySpark function to read a Delta Lake table from MinIO and
calculate the daily sales total, partitioned by product category.
```

### Chat Panel

A persistent sidebar chat powered by `jupyter-ai` connects to Ollama (`qwen2.5-coder:7b`) for real-time code assistance — 100% local, 100% LAN, zero data leaves the cluster.

---

## 🔒 Security Model

```
Layer 1 — Perimeter:   LAN-only whitelist (192.168.80.0/24) via Traefik middleware
Layer 2 — Auth:        BasicAuth per service + native auth (Portainer, Airflow, MinIO, n8n)
Layer 3 — Transport:   TLS self-signed on all 15+ HTTPS endpoints
Layer 4 — Secrets:     Docker Swarm Secrets — zero passwords in repository
Layer 5 — Network:     Overlay networks (public + internal) — internal services never exposed
```

> **Zero secrets in this repository.** All passwords, keys, and certificates are stored exclusively as Docker Swarm Secrets, created manually on the cluster.

---

## 📁 Repository Structure

```
lab-infra-ia-bigdata/
│
├── stacks/                         # All Docker Compose stacks (IaC)
│   ├── core/
│   │   ├── 00-traefik/             # Reverse proxy + TLS gateway
│   │   ├── 01-portainer/           # Docker Swarm management UI
│   │   └── 02-postgres/            # Central relational database
│   ├── automation/
│   │   ├── 02-n8n/                 # Workflow automation
│   │   └── 03-airflow/             # Pipeline orchestration (CeleryExecutor)
│   ├── data/
│   │   ├── 11-opensearch/          # Search engine + dashboards
│   │   ├── 12-minio/               # S3-compatible object storage
│   │   └── 98-spark/               # Distributed processing cluster
│   ├── ai-ml/
│       ├── 01-jupyter/             # Multi-user JupyterLab + GPU + AI
│       ├── 02-ollama/              # Local LLM inference engine
│       ├── 03-qdrant/              # Vector DB for RAG pipelines
│       ├── 04-rag-api/             # FastAPI RAG orchestration service
│       └── 05-open-webui/          # ChatGPT-like UI + multi-model chat + RAG
│   └── monitoring/
│       ├── 00-fluent-bit/          # Centralized log collection → OpenSearch
│       ├── 01-prometheus/          # Prometheus TSDB + node/container exporters
│       ├── 02-grafana/             # Grafana dashboards (auto-provisioned)
│       └── 03-nvidia-exporter/     # NVIDIA GPU metrics exporter
│
├── docs/
│   ├── architecture/               # System design documentation
│   │   ├── ARCHITECTURE.md         # Full architecture + diagrams
│   │   ├── SERVICES.md             # Complete service inventory
│   │   ├── DATABASES.md            # DB schemas, users, secrets mapping
│   │   ├── NODES.md                # Physical node specs
│   │   ├── STORAGE.md              # Disk layout, LVM, mount points
│   │   ├── NETWORKING.md           # Overlay networks, domains, ports
│   │   └── MEDALLION.md            # Medallion architecture deep-dive
│   ├── adrs/                       # Architecture Decision Records (6 ADRs)
│   ├── runbooks/                   # Day-2 operations per service (12 runbooks)
│   └── ROADMAP.md                  # Next phases and planned improvements
│
├── scripts/
│   ├── bootstrap/                  # Initial node setup
│   ├── verify/                     # post-reboot-check.sh — full health check
│   ├── backup/                     # Backup scripts
│   └── diagnostics/                # Service diagnostics
│
├── envs/
│   └── examples/                   # .env.example per stack (no secrets)
│
└── secrets/                        # NOT versioned (.gitignore)
```

---

## 🚀 Deployment

All commands run from **master1** (Swarm manager):

### Prerequisites

```bash
# 1. Create required directories on master1
mkdir -p /srv/fastdata/{portainer,opensearch,airflow/{dags,logs,plugins,redis},spark-history}

# 2. Create required directories on master2
# (via SSH)
mkdir -p /srv/fastdata/{postgres,n8n,jupyter/{ogiovanni,odavid}/work,spark-tmp,airflow/{dags,logs,plugins}}
mkdir -p /srv/datalake/{minio,models/ollama,datasets,artifacts}

# 3. Create Docker Swarm Secrets
# See: docs/runbooks/runbook_deploy_fase5.md for the full list
```

### Deploy Order

```bash
# === PHASE 1: Core ===
docker stack deploy -c stacks/core/00-traefik/stack.yml    traefik
docker stack deploy -c stacks/core/01-portainer/stack.yml  portainer
docker stack deploy -c stacks/core/02-postgres/stack.yml   postgres

# === PHASE 2: Storage (must be first — Airflow and Spark depend on it) ===
docker stack deploy -c stacks/data/12-minio/stack.yml      minio
# → Create buckets: bronze, silver, gold, airflow-logs, spark-warehouse, lab-notebooks

# === PHASE 3: Automation ===
docker stack deploy -c stacks/automation/02-n8n/stack.yml     n8n
docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow

# === PHASE 4: AI / ML ===
docker stack deploy -c stacks/ai-ml/01-jupyter/stack.yml  jupyter
docker stack deploy -c stacks/ai-ml/02-ollama/stack.yml   ollama

# === PHASE 5: Data Processing ===
docker stack deploy -c stacks/data/11-opensearch/stack.yml opensearch
docker stack deploy -c stacks/data/98-spark/stack.yml      spark

# === PHASE 6: Observability ===
# Run setup script first (creates dirs + Swarm Secrets interactively):
bash scripts/observability/setup-prometheus.sh
# Then update Traefik (adds metrics endpoint + new secrets):
docker stack deploy -c stacks/core/00-traefik/stack.yml    traefik
# Deploy monitoring stacks:
docker stack deploy -c stacks/monitoring/00-fluent-bit/stack.yml    fluent-bit
docker stack deploy -c stacks/monitoring/01-prometheus/stack.yml    prometheus
docker stack deploy -c stacks/monitoring/03-nvidia-exporter/stack.yml nvidia-exporter
docker stack deploy -c stacks/monitoring/02-grafana/stack.yml       grafana

# === PHASE 8: Vector DB + RAG + Chat UI ===
# Prerequisites: PostgreSQL must be running (openwebui DB + user)
# Create Swarm Secrets: qdrant_api_key, pg_openwebui_pass,
#   openwebui_secret_key, openwebui_admin_email, openwebui_admin_pass
docker stack deploy -c stacks/ai-ml/03-qdrant/stack.yml      qdrant
docker stack deploy -c stacks/ai-ml/04-rag-api/stack.yml     rag-api
docker stack deploy -c stacks/ai-ml/05-open-webui/stack.yml  open-webui
```

### LAN DNS Setup

Add to `/etc/hosts` on each LAN client (or configure a local DNS wildcard):

```
192.168.80.100  traefik.sexydad portainer.sexydad
192.168.80.100  airflow.sexydad airflow-flower.sexydad
192.168.80.100  opensearch.sexydad dashboards.sexydad
192.168.80.100  spark-master.sexydad spark-worker.sexydad spark-history.sexydad
192.168.80.100  ollama.sexydad jupyter-ogiovanni.sexydad jupyter-odavid.sexydad
192.168.80.100  minio.sexydad minio-api.sexydad n8n.sexydad
192.168.80.100  prometheus.sexydad grafana.sexydad
192.168.80.100  chat.sexydad qdrant.sexydad rag-api.sexydad
```

> All endpoints use self-signed TLS. Accept the browser security exception on first visit.

---

## ✅ Post-Reboot Health Check

After any node reboot, run from master1:

```bash
bash ~/lab-infra-ia-bigdata/scripts/verify/post-reboot-check.sh
```

The script verifies:
- Both Swarm nodes are `Ready` + `Active`
- All 30 services are at their expected replica count (N/N)
- Internal connectivity: PostgreSQL, Redis, MinIO, OpenSearch, Ollama, Spark, Qdrant
- All HTTPS endpoints reachable through Traefik

---

## 📊 Resource Utilization

### master1 — Control Plane

| Service | CPU (reserved) | RAM (reserved) |
|---------|---------------|----------------|
| Traefik | 0.1 | 128 MB |
| Portainer | 0.1 | 128 MB |
| OpenSearch | 1.0 | 2 GB |
| OpenSearch Dashboards | 0.5 | 1 GB |
| Airflow (web + sched + flower) | 1.1 | 1.6 GB |
| Redis | 0.1 | 128 MB |
| Spark (master + history) | 0.75 | 1.5 GB |
| **TOTAL** | **~3.75 / 8 threads** | **~6.6 / 32 GB** ✅ |

### master2 — Compute Node

| Service | CPU (reserved) | RAM (reserved) |
|---------|---------------|----------------|
| PostgreSQL | 0.5 | 512 MB |
| n8n | 0.2 | 256 MB |
| JupyterLab × 2 | 4.0 | 8 GB |
| Ollama (GPU) | 6.0 | 12 GB |
| MinIO | 0.5 | 512 MB |
| Spark Worker | 2.0 | 2 GB |
| Airflow Worker | 1.0 | 1 GB |
| **TOTAL** | **~14.3 / 16 threads** | **~24.3 / 32 GB** ✅ |

---

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [`docs/architecture/ARCHITECTURE.md`](docs/architecture/ARCHITECTURE.md) | Full system design: physical + logical diagrams, traffic flows, security model |
| [`docs/architecture/SERVICES.md`](docs/architecture/SERVICES.md) | Complete service inventory with versions, ports, secrets, and constraints |
| [`docs/architecture/DATABASES.md`](docs/architecture/DATABASES.md) | Database schemas, users, roles, and secrets mapping |
| [`docs/architecture/NODES.md`](docs/architecture/NODES.md) | Physical specs for master1 and master2 |
| [`docs/architecture/STORAGE.md`](docs/architecture/STORAGE.md) | Disk layout, LVM configuration, and mount points |
| [`docs/architecture/NETWORKING.md`](docs/architecture/NETWORKING.md) | Overlay networks, domain map, and traffic flow |
| [`docs/architecture/MEDALLION.md`](docs/architecture/MEDALLION.md) | Deep-dive: Medallion architecture, Delta Lake patterns, code examples |
| [`docs/adrs/`](docs/adrs/) | Architecture Decision Records (6 ADRs) |
| [`docs/runbooks/`](docs/runbooks/) | Day-2 operations: deploy, troubleshoot, and maintain each service |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Planned phases: Observability (Prometheus + Grafana), backups, hardening |

---

## 🗺️ Roadmap

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 — Cluster base | ✅ Done | Docker Swarm, overlay networks, GPU, node labels |
| Phase 2 — Storage | ✅ Done | LVM on NVMe, datalake HDD, mount points |
| Phase 3 — IaC structure | ✅ Done | Repo structure, stack conventions, secrets pattern |
| Phase 4 — Core services | ✅ Done | Traefik, Portainer, PostgreSQL, n8n, JupyterLab, Ollama, OpenSearch |
| Phase 5 — Big Data | ✅ Done | MinIO, Apache Spark, Apache Airflow, Medallion pipeline |
| Phase 6.1 — Log Collection | ✅ Done | Fluent Bit (global) → OpenSearch · daily index rollover · 7-day ISM auto-delete |
| Phase 6.2 — Metrics | ✅ Done | Prometheus + Grafana + node_exporter + cAdvisor + NVIDIA GPU exporter |
| Phase 7 — Hardening | ⏳ Planned | UFW, SSH hardening, backup automation (restic), cert rotation |
| Phase 8 — Vector DB + RAG | ✅ Done | Qdrant v1.13 + RAG API (FastAPI) + Open WebUI v0.6.5 |
| Phase 9 — Agents & Evals | ⏳ Planned | LangGraph agents, batch evaluation pipelines, model benchmarks |

---

## ⚙️ Architecture Decisions

> Full ADRs available in [`docs/adrs/`](docs/adrs/)

| ADR | Decision | Rationale |
|-----|----------|-----------|
| ADR-001 | **Docker Swarm** over Kubernetes | 2 nodes don't justify K8s complexity. Swarm is sufficient, simpler, declarative |
| ADR-002 | **master1 as exclusive gateway** | Single TLS entry point, clean whitelist, master2 free for GPU workloads |
| ADR-003 | **Separate fastdata/datalake mounts** | NVMe for I/O-intensive DBs, HDD 2TB for bulk data — maximize performance |
| ADR-004 | **OpenSearch security plugin disabled** | LAN-only lab — Traefik BasicAuth + whitelist is sufficient |
| ADR-005 | **GPU via Generic Resources** | Swarm has no native `--gpus`. Generic Resources (`nvidia.com/gpu=1`) enables proper placement |
| ADR-006 | **OpenSearch on master1** | At deploy time, master2 had 14/16 CPUs committed. OpenSearch is observability support, HDD sufficient |

---

## 🧱 Operational Principles

- **All stateful workloads → master2** (NVMe + GPU): PostgreSQL, MinIO, Ollama, JupyterLab, Spark Worker, Airflow Worker
- **All control workloads → master1** (lightweight): Traefik, Portainer, Airflow orchestration, Spark master
- **Placement via Swarm labels**: `tier=control` / `tier=compute` / `gpu=nvidia`
- **Zero passwords in repo**: all credentials exclusively via Docker Swarm Secrets
- **Internal domain**: `*.sexydad` resolved via `/etc/hosts` on LAN clients
- **Auto-restart on reboot**: every service uses `restart_policy: condition: any`
- **Medallion Architecture**: Bronze (raw) → Silver (Delta Lake ACID) → Gold (Delta Lake aggregated)

---

<div align="center">

Built with ❤️ on bare metal · Docker Swarm · No cloud required

</div>
