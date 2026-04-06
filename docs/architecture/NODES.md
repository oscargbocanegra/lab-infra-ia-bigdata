# Cluster Nodes

> Updated: 2026-03-30 — Phase 5: MinIO, Spark, Airflow

---

## master1 — Control Plane

| Attribute | Detail |
|-----------|--------|
| **Hostname** | `master1` |
| **Swarm role** | Manager / Leader |
| **CPU** | Intel Core i7-6700T @ 2.80 GHz |
| **Cores / Threads** | 4C / 8T |
| **Total RAM** | 32 GB |
| **Available RAM (typical)** | ~25 GB |
| **Swap** | 2 GB |
| **Disk** | WDC WD5000LPLX-0 — 500 GB HDD (ROTA=1) |
| **GPU** | None |
| **OS** | Ubuntu (Debian family) |
| **LAN IP** | `<IP_MASTER1>` (static, <lan-cidr> network) |

### Swarm Labels (master1)

```bash
docker node update --label-add tier=control master1
docker node update --label-add node_role=manager master1
docker node update --label-add storage=backup master1
docker node update --label-add net=lan master1
```

### Services running on master1

| Service | Stack | Constraint |
|---------|-------|------------|
| Traefik | core/00-traefik | `tier=control` |
| Portainer | core/01-portainer | `tier=control` |
| Portainer Agent | core/01-portainer | global |
| OpenSearch | data/11-opensearch | `tier=control` |
| OpenSearch Dashboards | data/11-opensearch | `tier=control` |
| Spark Master | data/98-spark | `tier=control` |
| Spark History Server | data/98-spark | `tier=control` |
| Airflow Webserver | automation/03-airflow | `tier=control` |
| Airflow Scheduler | automation/03-airflow | `tier=control` |
| Airflow Flower | automation/03-airflow | `tier=control` |
| Redis (Airflow broker) | automation/03-airflow | `tier=control` |

### Mounts on master1

```
/srv/fastdata/        → local HDD (no LVM) — Portainer data, OpenSearch data
/srv/fastdata/portainer
/srv/fastdata/opensearch
/srv/fastdata/airflow/dags     → shared DAGs (accessed by webserver + scheduler)
/srv/fastdata/airflow/logs     → local task logs (before remote logging)
/srv/fastdata/airflow/plugins  → Airflow plugins
/srv/fastdata/airflow/redis    → Redis persistence (Celery broker)
/srv/backups/master2  → (planned) backups received from master2 via rsync
```

### Relevant system configuration

- **systemd override**: `RequiresMountsFor=/srv/fastdata` before starting Docker
- **Docker daemon.json**: log driver `json-file`, standard default runtime

---

## master2 — Compute + Data + GPU

| Attribute | Detail |
|-----------|--------|
| **Hostname** | `master2` |
| **Swarm role** | Worker |
| **CPU** | Intel Core i9-9900K @ 3.60 GHz |
| **Cores / Threads** | 8C / 16T |
| **Total RAM** | 32 GB |
| **Available RAM (typical)** | ~4–8 GB (Jupyter + Ollama active) |
| **Swap** | 8 GB |
| **Disk 1** | Samsung SSD 970 EVO — 931.5 GB NVMe (ROTA=0) |
| **Disk 2** | Seagate ST2000LM015 — 1.8 TB HDD (ROTA=1) |
| **GPU** | NVIDIA GeForce RTX 2080 Ti |
| **VRAM** | 11 GB |
| **NVIDIA Driver** | 535.288.01 |
| **CUDA Version** | 12.2 |
| **OS** | Ubuntu (Debian family) |
| **LAN IP** | `<IP_MASTER2>` (static, <lan-cidr> network) |

### Swarm Labels (master2)

```bash
docker node update --label-add tier=compute master2
docker node update --label-add node_role=worker master2
docker node update --label-add storage=primary master2
docker node update --label-add gpu=nvidia master2
docker node update --label-add net=lan master2
```

### GPU: Registered Generic Resource

```bash
# In /etc/docker/daemon.json on master2:
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "node-generic-resources": ["nvidia.com/gpu=1"]
}

# Verify:
docker node inspect master2 --format '{{ json .Description.Resources.GenericResources }}'
# Should show: [{"DiscreteResourceSpec":{"Kind":"nvidia.com/gpu","Value":1}}]
```

### Services running on master2

| Service | Stack | Constraint | Storage |
|---------|-------|------------|---------|
| PostgreSQL 16 | core/02-postgres | `hostname=master2` | `/srv/fastdata/postgres` (NVMe) |
| n8n | automation/02-n8n | `tier=compute` | `/srv/fastdata/n8n` (NVMe) |
| JupyterLab (<admin-user>) | ai-ml/01-jupyter | `tier=compute` + hostname | `/srv/fastdata/jupyter/<admin-user>` (NVMe) |
| JupyterLab (<second-user>) | ai-ml/01-jupyter | `tier=compute` + hostname | `/srv/fastdata/jupyter/<second-user>` (NVMe) |
| Ollama | ai-ml/02-ollama | `tier=compute` + `gpu=nvidia` | `/srv/datalake/models/ollama` (HDD) |
| MinIO | data/12-minio | `tier=compute` + hostname | `/srv/datalake/minio` (HDD) |
| Spark Worker | data/98-spark | `tier=compute` + hostname | `/srv/fastdata/spark-tmp` (NVMe) |
| Airflow Worker (Celery) | automation/03-airflow | `tier=compute` + hostname | `/srv/fastdata/airflow/dags` (shared) |
| Portainer Agent | core/01-portainer | global | — |

### Mounts on master2

```
/srv/fastdata/        → LVM on NVMe (600 GB, ext4)
│   ├── postgres/     → PostgreSQL data
│   ├── n8n/          → n8n config/data
│   ├── airflow/      → DAGs, logs, plugins (shared with master1 via volume/sync)
│   │   ├── dags/
│   │   ├── logs/
│   │   └── plugins/
│   ├── spark-tmp/    → Spark scratch: shuffle, spill (NVMe for maximum speed)
│   └── jupyter/
│       ├── <admin-user>/
│       │   ├── .venv/   → virtualenv AI/LLM/BigData kernels (persistent)
│       │   └── .local/  → kernelspecs (persistent)
│       └── <second-user>/
│           ├── .venv/
│           └── .local/

/srv/datalake/        → HDD 2TB (mounted via fstab, UUID)
    ├── minio/        → MinIO object storage (data buckets)
    ├── datasets/     → raw datasets (CSV, Parquet, JSON)
    ├── models/
    │   └── ollama/   → Ollama .gguf models
    ├── notebooks/    → exported / shared notebooks
    ├── artifacts/    → training results, experiments
    └── backups/      → local cold storage backups
```

### Critical system configuration (master2)

```ini
# /etc/systemd/system/docker.service.d/override.conf
# Docker does NOT start until disks are mounted
[Unit]
After=network-online.target srv-fastdata.mount srv-datalake.mount
Wants=network-online.target
RequiresMountsFor=/srv/fastdata /srv/datalake
```

> **Without this override**: Docker starts before `/srv/fastdata` is available → Postgres/n8n fail when trying to open volumes → restart loop.

---

## Resource comparison

```
Resource        master1 (Control)    master2 (Compute)
─────────────── ──────────────────   ──────────────────────
CPU             i7-6700T 4C/8T       i9-9900K 8C/16T       ← 2x more cores
RAM             32 GB                32 GB
Fast disk       HDD 500 GB           NVMe 1TB              ← 10-20x more IOPS
Mass storage    —                    HDD 2TB               ← 4x capacity
GPU             —                    RTX 2080 Ti 11GB VRAM ← only GPU node
Role            Control/Gateway      Compute/Data/AI
```
