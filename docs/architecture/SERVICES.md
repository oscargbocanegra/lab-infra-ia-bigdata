# Service Inventory

> Updated: 2026-03-31 — Lab 100% operational (20 services)

---

## Overall status

```
✅ OPERATIONAL  — Deployed, running, persistent after reboot
🔧 IN PROGRESS  — Under configuration/optimization
```

---

## Cluster summary

```
master1 (Control/Gateway)         master2 (Compute/Data/GPU)
──────────────────────────────    ──────────────────────────────────────
Traefik          ✅               PostgreSQL        ✅
Portainer        ✅               n8n               ✅
OpenSearch       ✅               JupyterLab x2     ✅
Dashboards       ✅               Ollama (GPU)      ✅
Airflow Web      ✅               MinIO             ✅
Airflow Sched.   ✅               Spark Worker      ✅
Airflow Flower   ✅               Airflow Worker    ✅
Redis (Celery)   ✅               Portainer Agent   ✅
Spark Master     ✅
Spark History    ✅
Portainer Agent  ✅
```

**Total: 20 services / 20 operational ✅**

---

## Operational services

### 1. Traefik — Reverse Proxy + TLS

| Parameter | Value |
|-----------|-------|
| **Stack** | `traefik` |
| **File** | `stacks/core/00-traefik/stack.yml` |
| **Image** | `traefik:v2.11` |
| **Node** | master1 (`tier=control`) |
| **Ports** | `:80` (redirect→HTTPS) `:443` (TLS) — `mode: host` |
| **Status** | ✅ OPERATIONAL |
| **URL** | `https://traefik.sexydad/dashboard/` |
| **Auth** | BasicAuth (`traefik_basic_auth`) + LAN whitelist |
| **Secrets** | `traefik_basic_auth` `traefik_tls_cert` `traefik_tls_key` + auth secrets from other services |
| **Restart** | `condition: any` |
| **Runbook** | [`runbook_traefik.md`](../runbooks/runbook_traefik.md) |

---

### 2. Portainer CE — Swarm cluster management

| Parameter | Value |
|-----------|-------|
| **Stack** | `portainer` |
| **File** | `stacks/core/01-portainer/stack.yml` |
| **Image (server)** | `portainer/portainer-ce:2.39.1` |
| **Image (agent)** | `portainer/agent:2.39.1` |
| **Server node** | master1 (`tier=control`) |
| **Agent node** | global (master1 + master2) |
| **Persistence** | `/srv/fastdata/portainer:/data` (HDD master1) |
| **Status** | ✅ OPERATIONAL |
| **URL** | `https://portainer.sexydad` |
| **Auth** | Portainer internal users |
| **Restart** | `condition: any` |
| **Runbook** | [`runbook_portainer.md`](../runbooks/runbook_portainer.md) |

> **Operational note**: Portainer has a ~5 min timeout on first install to create the admin user. If it expires: `docker service update --force portainer_portainer` and create admin immediately.

---

### 3. PostgreSQL 16 — Central database

| Parameter | Value |
|-----------|-------|
| **Stack** | `postgres` |
| **File** | `stacks/core/02-postgres/stack.yml` |
| **Image** | `postgres:16` |
| **Node** | master2 (`hostname=master2`) |
| **Persistence** | `/srv/fastdata/postgres` (NVMe LVM) |
| **Port** | `5432` (`mode: host`) — accessible from master2 only |
| **Databases** | `postgres` (default/admin), `n8n`, `airflow` |
| **Users** | `postgres` (superuser), `n8n`, `airflow` |
| **Secrets** | `pg_super_pass` `pg_n8n_pass` `pg_airflow_pass` |
| **Status** | ✅ OPERATIONAL |
| **Internal access** | `postgres_postgres:5432` (overlay internal) |
| **LAN direct access** | `<master2-ip>:5432` (DBeaver, psql) |
| **Restart** | `condition: any`, `max_attempts: 0` (infinite — critical) |
| **Runbook** | [`runbook_postgres.md`](../runbooks/runbook_postgres.md) |

> See full database and user details: [`DATABASES.md`](DATABASES.md)

---

### 4. n8n — Workflow automation

| Parameter | Value |
|-----------|-------|
| **Stack** | `n8n` |
| **File** | `stacks/automation/02-n8n/stack.yml` |
| **Image** | `n8nio/n8n:2.4.7` |
| **Node** | master2 (`tier=compute`) |
| **Persistence** | `/srv/fastdata/n8n` (NVMe) |
| **DB Backend** | PostgreSQL (`n8n` database on master2) |
| **Status** | ✅ OPERATIONAL |
| **URL** | `https://n8n.sexydad` |
| **Auth** | n8n internal users |
| **Secrets** | `pg_n8n_pass` `n8n_encryption_key` `n8n_user_mgmt_jwt_secret` |
| **Restart** | `condition: any`, `max_attempts: 0` |
| **Runbook** | [`runbook_n8n.md`](../runbooks/runbook_n8n.md) |

---

### 5–6. JupyterLab — Multi-user AI/ML/BigData environment

| Parameter | Value |
|-----------|-------|
| **Stack** | `jupyter` |
| **File** | `stacks/ai-ml/01-jupyter/stack.yml` |
| **Image** | `jupyter/datascience-notebook:python-3.11` |
| **Node** | master2 (`tier=compute` + `hostname=master2`) |
| **Users** | `<admin-user>` (uid 1000) + `<second-user>` (uid 1001) |
| **Persistence** | `/srv/fastdata/jupyter/{user}/work` (NVMe) |
| **Extra volumes** | `/srv/datalake/datasets` (ro), `shared-notebooks`, `artifacts` |
| **GPU** | RTX 2080 Ti (shared between users + Ollama) |
| **Resources (each)** | limit: 8 CPUs / 12 GB — reserve: 2 CPUs / 4 GB |
| **Kernels** | Python LLM · Python AI · Python BigData (PySpark + Delta) |
| **Status** | ✅ OPERATIONAL |
| **URLs** | `https://jupyter-<admin-user>.sexydad` / `https://jupyter-<second-user>.sexydad` |
| **Auth** | BasicAuth (`jupyter_basicauth_v2`) via Traefik |
| **Secrets** | `minio_access_key` `minio_secret_key` |
| **Restart** | `condition: any` |
| **Jupyter token** | `docker service logs jupyter_jupyter_{user} 2>&1 \| grep token` |
| **Runbook** | [`runbook_jupyter.md`](../runbooks/runbook_jupyter.md) |

---

### 7. Ollama — LLM Inference Engine

| Parameter | Value |
|-----------|-------|
| **Stack** | `ollama` |
| **File** | `stacks/ai-ml/02-ollama/stack.yml` |
| **Image** | `ollama/ollama:0.19.0` (pinned version) |
| **Node** | master2 (`tier=compute` + `gpu=nvidia`) |
| **Persistence** | `/srv/datalake/models/ollama` (HDD 2TB) |
| **GPU** | RTX 2080 Ti — 11 GB VRAM — CUDA 12.2 |
| **Reserved VRAM** | 10 GB for models (1 GB overhead) |
| **Status** | ✅ OPERATIONAL |
| **External URL** | `https://ollama.sexydad` (BasicAuth + LAN whitelist) |
| **Internal URL** | `http://ollama:11434` |
| **Auth** | BasicAuth (`ollama_basicauth`) |
| **Secrets** | `ollama_basicauth` |
| **Restart** | `condition: any` |
| **Download model** | `docker exec -it <container_id> ollama pull llama3` |
| **Runbook** | [`runbook_ollama.md`](../runbooks/runbook_ollama.md) |

---

### 8–9. OpenSearch + Dashboards

| Parameter | Value |
|-----------|-------|
| **Stack** | `opensearch` |
| **File** | `stacks/data/11-opensearch/stack.yml` |
| **OpenSearch image** | `opensearchproject/opensearch:2.19.4` |
| **Dashboards image** | `opensearchproject/opensearch-dashboards:2.19.4` |
| **Node** | master1 (`tier=control`) |
| **Persistence** | `/srv/fastdata/opensearch` (HDD master1) |
| **Mode** | `single-node`, security plugin DISABLED |
| **JVM memory** | `-Xms1g -Xmx1g` |
| **Status** | ✅ OPERATIONAL |
| **API URL** | `https://opensearch.sexydad` |
| **UI URL** | `https://dashboards.sexydad` |
| **Internal URL** | `http://opensearch:9200` |
| **Auth** | BasicAuth (`opensearch_basicauth` / `dashboards_basicauth`) |
| **Restart** | `condition: any` |
| **Runbook** | [`runbook_opensearch.md`](../runbooks/runbook_opensearch.md) |

> **ADR-004**: Security plugin disabled. In a LAN-only lab with BasicAuth+Whitelist in Traefik this is sufficient.

---

### 10. MinIO — S3-compatible Object Storage

| Parameter | Value |
|-----------|-------|
| **Stack** | `minio` |
| **File** | `stacks/data/12-minio/stack.yml` |
| **Image** | `minio/minio:RELEASE.2024-11-07T00-52-20Z` |
| **Node** | master2 (`tier=compute`) |
| **Persistence** | `/srv/datalake/minio` (HDD 2TB) |
| **Resources** | limit: 4 CPUs / 2 GB — reserve: 0.5 CPU / 512 MB |
| **Status** | ✅ OPERATIONAL |
| **Console URL** | `https://minio.sexydad` |
| **S3 API URL** | `https://minio-api.sexydad` |
| **Internal URL** | `http://minio:9000` (Spark/Airflow/Jupyter) |
| **Secrets** | `minio_access_key` `minio_secret_key` |
| **Restart** | `condition: any` |
| **Medallion buckets** | `bronze` · `silver` · `gold` · `airflow-logs` · `spark-warehouse` · `lab-notebooks` |
| **Region** | `us-east-1` (for boto3/s3fs compatibility) |
| **Runbook** | [`runbook_minio.md`](../runbooks/runbook_minio.md) |

---

### 11. Apache Spark 3.5 — Distributed Processing

| Parameter | Value |
|-----------|-------|
| **Stack** | `spark` |
| **File** | `stacks/data/98-spark/stack.yml` |
| **Image** | `apache/spark:3.5.3` (official ASF image) |
| **Master node** | master1 (`tier=control`) |
| **Worker node** | master2 (`tier=compute`) |
| **Worker resources** | limit: 12 CPUs / 16 GB — offered to cluster: 10 CPUs / 14 GB |
| **Master resources** | limit: 2 CPUs / 2 GB |
| **Status** | ✅ OPERATIONAL |
| **Master UI URL** | `https://spark-master.sexydad` |
| **Worker UI URL** | `https://spark-worker.sexydad` |
| **History URL** | `https://spark-history.sexydad` |
| **Internal URL** | `spark://spark-master:7077` |
| **Event logs** | `/srv/fastdata/spark-history` (local filesystem — implicit NFS between master/worker/history) |
| **Restart** | `condition: any` |
| **Runbook** | [`runbook_spark.md`](../runbooks/runbook_spark.md) |

> **Note**: `apache/spark:3.5.3` does NOT include `hadoop-aws.jar`. Event logs use local filesystem. Hostnames with **hyphens** (spark-master, not spark_master) — Spark validates these as Java URLs.

---

### 12–16. Apache Airflow 2.9 — Pipeline Orchestration

| Component | Node | Resources (reserve) | Status |
|-----------|------|---------------------|--------|
| `airflow_redis` | master1 | 0.1 CPU / 128 MB | ✅ |
| `airflow_webserver` | master1 | 0.5 CPU / 1 GB | ✅ |
| `airflow_scheduler` | master1 | 0.5 CPU / 512 MB | ✅ |
| `airflow_flower` | master1 | 0.1 CPU / 128 MB | ✅ |
| `airflow_worker` | master2 | 1 CPU / 1 GB | ✅ |

| Parameter | Value |
|-----------|-------|
| **Stack** | `airflow` |
| **File** | `stacks/automation/03-airflow/stack.yml` |
| **Image** | `apache/airflow:2.9.3` |
| **Executor** | `CeleryExecutor` + Redis 7 as broker |
| **DB Backend** | PostgreSQL `airflow` on master2 |
| **DAGs path** | `/srv/fastdata/airflow/dags` (master1 + master2, same path) |
| **Logs** | `/srv/fastdata/airflow/logs` (local — remote logging to MinIO disabled by default) |
| **Secrets** | `pg_airflow_pass` `airflow_fernet_key` `airflow_webserver_secret` `minio_access_key` `minio_secret_key` |
| **Docker config** | `airflow_entrypoint_v4` — URL-encodes the Postgres password before building the SQLAlchemy URL |
| **Webserver URL** | `https://airflow.sexydad` |
| **Flower URL** | `https://airflow-flower.sexydad` |
| **Restart** | `condition: any` |
| **Runbook** | [`runbook_airflow.md`](../runbooks/runbook_airflow.md) |

> **Critical bug resolved**: The Postgres password contains special characters (`/`, `=`). The `airflow-entrypoint.sh` entrypoint uses `urllib.parse.quote()` to URL-encode the password before building the SQLAlchemy and Celery URLs. Without this: `ValueError: Port could not be cast to integer value`.

---

## Resource commitment map (current state)

### master1 — Control Plane (32 GB RAM / 8 threads)

```
Service                CPU reserve   RAM reserve
────────────────────── ─────────── ──────────────
Traefik                ~0.1        ~128 MB
Portainer              ~0.1        ~128 MB
Portainer Agent        ~0.1        ~64 MB
OpenSearch             1.0         2 GB
Dashboards             0.5         1 GB
Airflow Webserver      0.5         1 GB
Airflow Scheduler      0.5         512 MB
Airflow Flower         0.1         128 MB
Redis (Celery)         0.1         128 MB
Spark Master           0.5         1 GB
Spark History          0.25        512 MB
────────────────────── ─────────── ──────────────
TOTAL                  ~3.75 CPU   ~6.6 GB / 32 GB  ✅ VERY COMFORTABLE
```

### master2 — Compute Node (32 GB RAM / 16 threads)

```
Service                CPU reserve   RAM reserve
────────────────────── ─────────── ──────────────
PostgreSQL             0.5         512 MB
n8n                    ~0.2        ~256 MB
Jupyter <admin-user>   2.0         4 GB
Jupyter <second-user>  2.0         4 GB
Ollama (GPU)           6.0         12 GB
MinIO                  0.5         512 MB
Spark Worker           2.0         2 GB
Airflow Worker         1.0         1 GB
Portainer Agent        ~0.1        ~64 MB
────────────────────── ─────────── ──────────────
TOTAL                  ~14.3 CPU   ~24.3 GB / 32 GB  ✅ BREATHING ROOM
```
