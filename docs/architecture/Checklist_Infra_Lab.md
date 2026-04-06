# Infrastructure Checklist — lab-infra-ia-bigdata

Last updated: 2026-03-30 — Phase 5: MinIO + Spark + Airflow implemented

This document centralizes the **real state** (OK / Pending) to bring up the complete lab infrastructure, with **recommended order**, **dependencies** and **minimum verification steps**.

---

## Legend

- ✅ **OK**: implemented, verified and persistent.
- ⏳ **PEND / IN PROGRESS**: not yet implemented or in optimization.
- [~] **PEND (non-blocking)**: pending, but does not block the next block.
- **NEXT**: next suggested work block.

---

## General prerequisites (before any stack)

Access and system base:

- ✅ SSH access between nodes (master1 ↔ master2) operational
- ✅ Docker Engine installed and running on both nodes
- ✅ Operational users with permissions (ideally: members of `docker` group)
- ✅ **GPU NVIDIA RTX 2080 Ti** registered as Generic Resource in Swarm (master2)
- ✅ **`default-runtime: nvidia`** in `/etc/docker/daemon.json` on master2 (required for Jupyter + Ollama GPU)

Network / naming:

- ✅ Internal hostnames with `<INTERNAL_DOMAIN>` suffix defined
- ✅ LAN resolution validated (includes tests with `--resolve` from master2)
- ⏳ (Optional) Formal internal DNS for `*.<INTERNAL_DOMAIN>` (router/local DNS) [~]

Minimum recommended hardening (non-blocking, but advisable):

- ⏳ Security updates applied (apt/yum) [~]
- ⏳ Time synchronization (NTP/chrony) verified [~]
- ⏳ Firewall reviewed (Swarm ports + 80/443 on master1) [~]

---

## Executive summary (Deployment State)

| # | Stack | State | Version/Detail |
|---|-------|-------|----------------|
| 1 | **Traefik** | ✅ | Reverse Proxy + TLS + BasicAuth |
| 2 | **Portainer** | ✅ | v2.39.1 - Web UI for Swarm |
| 3 | **Postgres** | ✅ | v16 - Multi-DB: postgres, n8n, airflow |
| 4 | **n8n** | ✅ | Automation Core + Postgres Backend |
| 5 | **Jupyter Lab** | ✅ | Multi-user + GPU + AI/LLM/BigData Kernels |
| 6 | **Ollama** | ✅ | v0.6.1 LLM API + GPU (RTX 2080 Ti) - OPERATIONAL |
| 7 | **OpenSearch** | ✅ | v2.19.4 - Search & Analytics + Dashboards UI - OPERATIONAL |
| 8 | **MinIO** | ⏳ | Stack ready — pending deploy + create buckets |
| 9 | **Spark** | ⏳ | Stack ready — pending deploy + create spark-warehouse/history bucket |
| 10 | **Airflow** | ⏳ | Stack ready — pending deploy + secrets + db init |
| 11 | **Backups/Hardening** | ⏳ | Pending planning |

---

## Repo map (Where each stack lives)

Implemented and functional stacks (operational in cluster):

- **Traefik**: [stacks/core/00-traefik/stack.yml](stacks/core/00-traefik/stack.yml)
- **Portainer**: [stacks/core/01-portainer/stack.yml](stacks/core/01-portainer/stack.yml)
- **Postgres**: [stacks/core/02-postgres/stack.yml](stacks/core/02-postgres/stack.yml)
- **n8n**: [stacks/automation/02-n8n/stack.yml](stacks/automation/02-n8n/stack.yml)
- **Jupyter**: [stacks/ai-ml/01-jupyter/stack.yml](stacks/ai-ml/01-jupyter/stack.yml)
- **Ollama**: [stacks/ai-ml/02-ollama/stack.yml](stacks/ai-ml/02-ollama/stack.yml) ✅ OPERATIONAL
- **OpenSearch**: [stacks/data/11-opensearch/stack.yml](stacks/data/11-opensearch/stack.yml) ✅ OPERATIONAL

Stacks ready to deploy (code complete, pending execution):

- **MinIO**: [stacks/data/12-minio/stack.yml](stacks/data/12-minio/stack.yml)
- **Spark**: [stacks/data/98-spark/stack.yml](stacks/data/98-spark/stack.yml)
- **Airflow**: [stacks/automation/03-airflow/stack.yml](stacks/automation/03-airflow/stack.yml)

Available runbooks:

- [docs/runbooks/runbook_traefik.md](docs/runbooks/runbook_traefik.md)
- [docs/runbooks/runbook_postgres.md](docs/runbooks/runbook_postgres.md)
- [docs/runbooks/runbook_n8n.md](docs/runbooks/runbook_n8n.md)
- [docs/runbooks/runbook_jupyter.md](docs/runbooks/runbook_jupyter.md)
- [docs/runbooks/runbook_ollama.md](docs/runbooks/runbook_ollama.md)
- [docs/runbooks/runbook_opensearch.md](docs/runbooks/runbook_opensearch.md)
- [docs/runbooks/runbook_portainer.md](docs/runbooks/runbook_portainer.md)
- [docs/runbooks/runbook_minio.md](docs/runbooks/runbook_minio.md)
- [docs/runbooks/runbook_spark.md](docs/runbooks/runbook_spark.md)
- [docs/runbooks/runbook_airflow.md](docs/runbooks/runbook_airflow.md)

---

## Secrets and certificate management (Swarm)

Principles:

- ✅ Do not version secrets in Git (covered by `.gitignore`)
- ✅ Use Docker Swarm secrets for sensitive values
- ✅ Names in `snake_case`, with stack prefix (e.g.: `postgres_*`, `n8n_*`, `airflow_*`)

### Secrets inventory

| Secret | Stack | State |
|--------|-------|-------|
| `traefik_basic_auth` | Traefik | ✅ Created |
| `traefik_tls_cert` | Traefik | ✅ Created |
| `traefik_tls_key` | Traefik | ✅ Created |
| `jupyter_basicauth_v2` | Traefik/Jupyter | ✅ Created |
| `ollama_basicauth` | Traefik/Ollama | ✅ Created |
| `opensearch_basicauth` | Traefik/OpenSearch | ✅ Created |
| `dashboards_basicauth` | Traefik/Dashboards | ✅ Created |
| `pg_super_pass` | Postgres | ✅ Created |
| `pg_n8n_pass` | Postgres, n8n | ✅ Created |
| `pg_airflow_pass` | Postgres, Airflow | ⏳ **Create before deploy** |
| `minio_access_key` | MinIO, Spark, Jupyter, Airflow | ⏳ **Create before deploy** |
| `minio_secret_key` | MinIO, Spark, Jupyter, Airflow | ⏳ **Create before deploy** |
| `airflow_fernet_key` | Airflow | ⏳ **Create before deploy** |
| `airflow_webserver_secret` | Airflow | ⏳ **Create before deploy** |

### Commands to create new secrets

```bash
# On master1 (Swarm manager):

# pg_airflow_pass
echo "$(openssl rand -base64 32)" | docker secret create pg_airflow_pass -

# MinIO credentials (access key: min 3 chars, secret key: min 8 chars)
echo "<minio-admin-user>" | docker secret create minio_access_key -
echo "$(openssl rand -base64 32)" | docker secret create minio_secret_key -

# Airflow Fernet key (MUST be a valid Fernet key of 32 bytes base64url)
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" | docker secret create airflow_fernet_key -

# Airflow webserver secret key (Flask)
echo "$(openssl rand -hex 32)" | docker secret create airflow_webserver_secret -
```

---

## Endpoint inventory (LAN)

| Service | URL | State |
|---------|-----|-------|
| **Traefik Dashboard** | `https://traefik.sexydad` | ✅ |
| **Portainer** | `https://portainer.sexydad` | ✅ |
| **n8n** | `https://n8n.sexydad` | ✅ |
| **Jupyter (<admin-user>)** | `https://jupyter-<admin-user>.sexydad` | ✅ |
| **Jupyter (<second-user>)** | `https://jupyter-<second-user>.sexydad` | ✅ |
| **Ollama** | `https://ollama.sexydad` | ✅ OPERATIONAL |
| **OpenSearch API** | `https://opensearch.sexydad` | ✅ OPERATIONAL |
| **OpenSearch Dashboards** | `https://dashboards.sexydad` | ✅ OPERATIONAL |
| **MinIO Console** | `https://minio.sexydad` | ⏳ Pending deploy |
| **MinIO S3 API** | `https://minio-api.sexydad` | ⏳ Pending deploy |
| **Spark Master UI** | `https://spark-master.sexydad` | ⏳ Pending deploy |
| **Spark History Server** | `https://spark-history.sexydad` | ⏳ Pending deploy |
| **Airflow** | `https://airflow.sexydad` | ⏳ Pending deploy |
| **Airflow Flower** | `https://airflow-flower.sexydad` | ⏳ Pending deploy |

### /etc/hosts to configure on LAN clients

```
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

---

## Phase 1 — Cluster base (Swarm / network / labels)

### Docker + Swarm
- ✅ Docker installed on master1
- ✅ Docker installed on master2
- ✅ Swarm initialized on master1 (manager/leader)
- ✅ master2 joined Swarm as worker

Verifications:

- ✅ `docker node ls` shows master1 (Leader) + master2 (Ready)
- ✅ `docker info` indicates Swarm: active

### Networking (overlay)
- ✅ `public` overlay network created (attachable)
- ✅ `internal` overlay network created (attachable)

### Node labels & Resources
- ✅ Labels on master1 applied and verified (e.g.: `tier=control`, `node_role=manager`)
- ✅ Labels on master2 applied and verified (e.g.: `tier=compute`, `storage=primary`, `gpu=nvidia`)
- ✅ **Generic Resource GPU**: Registered on `master2` (`nvidia.com/gpu=1`) to allow `reservations` in Swarm mode.

Verifications:

- ✅ `docker node inspect master2 --format '{{ json .Description.Resources.GenericResources }}'` shows the GPU.

**Result:** control-plane ready and Swarm network operational with GPU support.

---

## Phase 2 — Storage on master2 (HDD datalake)

- ✅ `/srv/datalake` mount confirmed (HDD ~1.8T)
- ✅ Persistence in `/etc/fstab` confirmed (LABEL/UUID) and mounting

Verifications:

- ✅ `df -h | grep /srv/datalake` shows expected size
- ✅ Reboot and remount validated

---

## Phase 3 — Volumes and structure on master2 (NVMe fastdata + directories)

### LVM + mount
- ✅ LVM created: LV `fastdata` = 600G
- ✅ Formatted ext4 and mounted at `/srv/fastdata`
- ✅ Persistence via `/etc/fstab` (UUID)
- ✅ Real reboot validated

### Existing directory structure

NVMe (fast):
- ✅ `/srv/fastdata/postgres`
- ✅ `/srv/fastdata/n8n`
- ✅ `/srv/fastdata/opensearch`
- ✅ `/srv/fastdata/airflow`
- ✅ `/srv/fastdata/jupyter/{<admin-user>,<second-user>}`
- ✅ `/srv/fastdata/jupyter/{user}/.venv`
- ✅ `/srv/fastdata/jupyter/{user}/.local`

New directories to create (Phase 5 — before deploy):
- ⏳ `/srv/fastdata/airflow/dags` — DAGs on master1 **and** master2
- ⏳ `/srv/fastdata/airflow/logs` — on master1
- ⏳ `/srv/fastdata/airflow/plugins` — on master1
- ⏳ `/srv/fastdata/airflow/redis` — on master1
- ⏳ `/srv/fastdata/spark-tmp` — on master2 (Spark Worker shuffle/spill)

HDD (datalake):
- ✅ `/srv/datalake/datasets`
- ✅ `/srv/datalake/models`
- ✅ `/srv/datalake/notebooks`
- ✅ `/srv/datalake/artifacts`
- ✅ `/srv/datalake/backups`
- ⏳ `/srv/datalake/minio` — on master2 (MinIO main volume)

### Permissions for new directories

```bash
# On master1:
sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins,redis}
sudo chown root:docker /srv/fastdata/airflow/{dags,logs,plugins,redis}
sudo chmod 2775 /srv/fastdata/airflow/{dags,logs,plugins,redis}
# Airflow runs as UID 50000:
sudo chown 50000:50000 /srv/fastdata/airflow/{dags,logs,plugins}

# On master2:
sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins}
sudo chown 50000:50000 /srv/fastdata/airflow/{dags,logs,plugins}

sudo mkdir -p /srv/fastdata/spark-tmp
sudo chown root:docker /srv/fastdata/spark-tmp
sudo chmod 2775 /srv/fastdata/spark-tmp

sudo mkdir -p /srv/datalake/minio
sudo chown root:docker /srv/datalake/minio
sudo chmod 2775 /srv/datalake/minio
```

**Result:** persistence aligned to deploy stateful services without surprises.

---

## Phase 4 — Infrastructure as code (repo)

- ✅ Repo created: `lab-infra-ia-bigdata`
- ✅ Base structure applied (`docs/`, `envs/`, `scripts/`, `stacks/`, etc.)
- ✅ `.gitignore` covers `.env`, `secrets/`, keys, passwords, etc.

---

## Block — Postgres (master2) ✅

Objective: Stateful Postgres in Swarm, persisting to `/srv/fastdata/postgres`, accessible via `internal` network.

Secrets:
- ✅ `pg_super_pass`
- ✅ `pg_n8n_pass`
- ⏳ `pg_airflow_pass` — create before redeploy

**IMPORTANT on redeploy**: PostgreSQL init scripts only run on an empty volume.
If the volume already has data, you must:
1. Bring down all services using Postgres (n8n, airflow)
2. `docker service rm postgres_postgres`
3. Delete the volume: `sudo rm -rf /srv/fastdata/postgres`
4. Redeploy Postgres — init scripts will automatically create n8n and airflow.

Done criteria:
- ✅ Service stable.
- ⏳ DB `airflow` and role `airflow` created by initdb.
- ✅ Persistence verified after reboot.

---

## Block — n8n (master2) ✅

Objective: n8n connected to Postgres for workflow automation with secure access via Traefik.

Done criteria:
- ✅ Service stays `running` and stable.
- ✅ Postgres connection validated.
- ✅ URL responds: `https://n8n.sexydad`

---

## Block — Jupyter Lab (master2) ✅

Objective: Multi-user environment (<admin-user>, <second-user>) optimized for AI/LLM/BigData with GPU.

Checklist:
- ✅ (Repo) Stack updated with AI, LLM, BigData kernels (PySpark + Delta + boto3)
- ✅ Reservations adjusted (2 CPUs / 4GB) to leave headroom for Spark + Airflow
- ✅ MinIO secrets mounted (`minio_access_key`, `minio_secret_key`)
- ✅ entrypoint.sh exports `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL`
- ✅ GPU reservation enabled

Done criteria:
- ✅ Jupyter responds at: `https://jupyter-{user}.sexydad`
- ✅ `torch.cuda.is_available()` is `True`
- ✅ BigData kernel can connect to `spark://spark_master:7077`
- ✅ `boto3.client('s3', endpoint_url='http://minio:9000')` works

---

## Block — Ollama (master2) ✅ OPERATIONAL

Current state:
- ✅ **OPERATIONAL** - Service deployed and running on master2.
- ✅ GPU detected and available (11GB VRAM). Version: 0.6.1
- ✅ REST API responding correctly.
- ⏳ Pending: Download LLM models (on demand).

---

## Block — OpenSearch (master1) ✅ OPERATIONAL

Current state:
- ✅ **OPERATIONAL** - Cluster status GREEN, version 2.19.4
- ✅ OpenSearch Dashboards UI operational.

---

## Block — MinIO (master2) ⏳ NEXT

Prerequisites:
- ⏳ Secret `minio_access_key` created in Swarm
- ⏳ Secret `minio_secret_key` created in Swarm
- ⏳ Directory `/srv/datalake/minio` created on master2 with correct permissions

Checklist:
- ✅ (Repo) Stack created: [stacks/data/12-minio/stack.yml](stacks/data/12-minio/stack.yml)
- ✅ (Repo) Runbook: [docs/runbooks/runbook_minio.md](docs/runbooks/runbook_minio.md)
- ⏳ Deploy: `docker stack deploy -c stacks/data/12-minio/stack.yml minio`
- ⏳ Create Medallion Architecture buckets via MinIO Console or `mc`:
  - `bronze`          → raw layer (CSV/JSON/Parquet, append-only)
  - `silver`          → curated layer (Delta Lake, ACID)
  - `gold`            → business layer (Delta Lake, KPIs/ML features)
  - `lab-notebooks`   → notebook exports
  - `airflow-logs`    → Airflow task logs
  - `spark-warehouse` (and inside: `spark-warehouse/history/`)

Done criteria:
- ⏳ `https://minio.sexydad` responds with MinIO UI
- ⏳ `https://minio-api.sexydad/minio/health/live` → HTTP 200
- ⏳ Bucket `spark-warehouse` exists (required by Spark History Server)

---

## Block — Spark (master1 + master2) ⏳

Prerequisites:
- ⏳ **MinIO operational** and bucket `spark-warehouse/history` created
- ⏳ Directory `/srv/fastdata/spark-tmp` created on master2
- ⏳ Secrets `minio_access_key` and `minio_secret_key` existing

Checklist:
- ✅ (Repo) Stack created: [stacks/data/98-spark/stack.yml](stacks/data/98-spark/stack.yml)
- ✅ (Repo) Runbook: [docs/runbooks/runbook_spark.md](docs/runbooks/runbook_spark.md)
- ⏳ Deploy: `docker stack deploy -c stacks/data/98-spark/stack.yml spark`

Done criteria:
- ⏳ `https://spark-master.sexydad` shows Master UI with 1 alive worker
- ⏳ Worker registered with 10 CPUs / 14 GB
- ⏳ PySpark from Jupyter can connect: `spark://spark_master:7077`

---

## Block — Airflow (master1 + master2) ⏳

Prerequisites:
- ⏳ **Postgres redeploy** (so init script creates DB airflow)
- ⏳ Secret `pg_airflow_pass` created
- ⏳ Secret `airflow_fernet_key` created
- ⏳ Secret `airflow_webserver_secret` created
- ⏳ Secrets `minio_access_key`, `minio_secret_key` existing
- ⏳ Directories on master1 and master2 created (see Phase 3)

Checklist:
- ✅ (Repo) Stack created: [stacks/automation/03-airflow/stack.yml](stacks/automation/03-airflow/stack.yml)
- ✅ (Repo) DB init script: [stacks/core/02-postgres/initdb/02-init-airflow.sh](stacks/core/02-postgres/initdb/02-init-airflow.sh)
- ✅ (Repo) Runbook: [docs/runbooks/runbook_airflow.md](docs/runbooks/runbook_airflow.md)
- ⏳ Redeploy Postgres (clean volume → init scripts run)
- ⏳ Deploy Redis + Airflow:
  ```bash
  docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow
  ```
- ⏳ Initialize Airflow DB (once only):
  ```bash
  docker service scale airflow_airflow_init=1
  # Check logs until "DB migrations done" appears
  docker service scale airflow_airflow_init=0
  ```
- ⏳ Create admin user in Airflow UI

Done criteria:
- ⏳ `https://airflow.sexydad` shows Airflow UI
- ⏳ `https://airflow-flower.sexydad` shows Flower with 1 worker online
- ⏳ Scheduler and Worker in `running` state
- ⏳ Test DAG executes with `success` status

Note on Remote Logging:
- Remote logging to MinIO is **disabled** by default.
- Enable it later (Phase 6): create `minio_s3` connection in UI, then change `REMOTE_LOGGING: "true"`.

---

## Backups, hardening and operations ⏳

### Backups ⏳
- ⏳ Backup master2 → master1 (rsync/restic).
- ⏳ Retention policy.
- ⏳ Restore test (Critical).

### Observability / Hardening ⏳
- ⏳ Firewall hardening (master1).
- ⏳ Logs/Metrics (optional).

---

## Notes / decisions

- ✅ Priority order is: **MinIO** → **Spark** → **Airflow** (Airflow depends on both)
- ✅ GPU is reserved for stacks on `master2`: Jupyter, Ollama (generic), not Spark/Airflow.
- ✅ Airflow remote logging disabled for first deploy — enable in Phase 6.
- ✅ `dag_airflow_dags` is mounted on master1 (webserver/scheduler) AND on master2 (worker).
  - Option A (current): same directory structure; user copies/syncs DAGs manually.
  - Option B (future): NFS share or git-sync sidecar.
- ✅ HDFS discarded: MinIO as object storage is sufficient for lab (512MB vs 3+ GB).
- ✅ CeleryExecutor chosen over LocalExecutor: production realism + distributed worker on master2.

---

## Recent Changelog

### 2026-03-30: Phase 5 — MinIO + Spark + Airflow (stacks ready) ⏳ Pending deploy
- ✅ `stacks/data/12-minio/stack.yml` — MinIO RELEASE.2024-11-07, storage at /srv/datalake/minio
- ✅ `stacks/data/98-spark/stack.yml` — bitnami/spark:3.5.3, master on master1, worker on master2
- ✅ `stacks/automation/03-airflow/stack.yml` — apache/airflow:2.9.3, CeleryExecutor + Redis
- ✅ `stacks/core/02-postgres/initdb/02-init-airflow.sh` — creates airflow DB + role
- ✅ `stacks/core/02-postgres/stack.yml` — POSTGRES_DB changed to 'postgres' (neutral), adds pg_airflow_pass
- ✅ `stacks/ai-ml/01-jupyter/stack.yml` — optimized reservations, MinIO secrets, datalake mounts
- ✅ `stacks/ai-ml/01-jupyter/init-kernels.sh` — BigData kernel (pyspark + delta-spark + boto3 + s3fs)
- ✅ `stacks/ai-ml/01-jupyter/entrypoint.sh` — exports AWS_ACCESS_KEY_ID/SECRET from secrets
- ✅ `stacks/ai-ml/02-ollama/stack.yml` — image pinned to 0.6.1
- ✅ `docs/hosts/master2/etc/docker/daemon.json` — added default-runtime: nvidia + runtimes block
- ✅ `docs/architecture/NODES.md` — services updated for Phase 5
- ✅ `docs/architecture/NETWORKING.md` — domains and ports Phase 5
- ✅ `docs/architecture/STORAGE.md` — new paths: minio, spark-tmp, airflow subdirs
- ✅ `docs/runbooks/runbook_minio.md` — new
- ✅ `docs/runbooks/runbook_spark.md` — new
- ✅ `docs/runbooks/runbook_airflow.md` — new

### 2026-03-30: Portainer Upgrade + Docs restructuring ✅
- ✅ Portainer CE + Agent updated: **2.21.0 → 2.39.1**
- ✅ Root README rewritten with complete architecture
- ✅ 6 ADRs documented in `docs/adrs/`
- ✅ Runbooks for OpenSearch, Ollama, Jupyter, Portainer

### 2026-02-04: OpenSearch Stack DEPLOYED ✅
- ✅ Cluster status: **GREEN**, version 2.19.4, Dashboards UI operational

### 2026-02-03: Ollama Stack DEPLOYED ✅
- ✅ GPU RTX 2080 Ti detected (11GB VRAM), REST API functional

### Previous state:
- ✅ Jupyter multi-user operational (<admin-user>, <second-user>) with GPU
- ✅ n8n + Postgres + Portainer + Traefik operational
