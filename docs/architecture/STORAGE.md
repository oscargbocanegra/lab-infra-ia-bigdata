# Storage — Disk Map and Paths

> Updated: 2026-03-30 — Phase 5: MinIO, Spark, Airflow

---

## master1: Storage layout

```
Single disk: WDC WD5000LPLX — 500 GB HDD (ROTA)
│
├── / (root filesystem)
├── /srv/fastdata/           → local HDD (NOT NVMe, name is inherited)
│   ├── portainer/           → Portainer CE data
│   ├── opensearch/          → OpenSearch data (index, translog)
│   └── traefik/             → (prep) Traefik configs if needed
└── /srv/backups/
    └── master2/             → (planned) backups received via rsync/restic
```

**Note**: On master1 the `/srv/fastdata` directory exists but sits on a rotational HDD, NOT NVMe. The name is consistent with master2 to simplify runbooks, but performance differs.

---

## master2: Storage layout

### Physical disks

| Disk | Model | Size | Type | Mount |
|------|-------|------|------|-------|
| nvme0n1 | Samsung SSD 970 EVO 1TB | 931.5 GB | NVMe (ROTA=0) | LVM → `/srv/fastdata` |
| sda | Seagate ST2000LM015 | 1.8 TB | HDD (ROTA=1) | `/srv/datalake` |

### LVM on NVMe

```
NVMe (nvme0n1)
└── PV → VG (vg0)
    └── LV: fastdata → 600 GB (ext4)
        └── mounted at /srv/fastdata
            (remaining NVMe available for LVM expansion)
```

**Verification commands**:
```bash
# Check LVM
sudo pvs && sudo vgs && sudo lvs

# Check active mount
findmnt /srv/fastdata
df -h /srv/fastdata
```

### /etc/fstab (master2) — key lines

```
# NVMe fastdata (LVM)
/dev/vg0/fastdata   /srv/fastdata   ext4   defaults,nofail   0 2

# HDD datalake (by UUID — see blkid for the actual UUID)
UUID=<UUID_HDD_DATALAKE>   /srv/datalake   ext4   defaults,nofail   0 2
```

> Versioned file at: `docs/hosts/master2/etc/fstab`

### Full directory structure on master2

```
/srv/fastdata/                    (NVMe — I/O intensive, active workloads)
├── postgres/                     PostgreSQL 16 data directory
│   └── [PG internal files]       owner: 999:999, mode: 700
├── n8n/                          n8n config, workflows, credentials
├── airflow/                      Airflow DAGs, logs, plugins, Redis data
│   ├── dags/                     Python DAGs (mounted on master1 and master2)
│   ├── logs/                     Local task logs (before enabling MinIO)
│   ├── plugins/                  Custom Airflow plugins
│   └── redis/                    Redis persistence (Celery broker — 60s/1 key)
├── spark-tmp/                    Spark scratch: shuffle/spill (NVMe max speed)
└── jupyter/
    ├── <admin-user>/
    │   ├── work/                 JupyterLab home (notebooks, scripts)
    │   ├── .venv/                virtualenv AI/LLM/BigData kernels (persistent)
    │   └── .local/               JupyterLab kernelspecs
    └── <second-user>/
        ├── work/
        ├── .venv/
        └── .local/

/srv/datalake/                    (HDD 2TB — bulk storage)
├── minio/                        MinIO object storage (all buckets)
│   ├── bronze/                   → Medallion Bronze: raw data (CSV/JSON/Parquet, append-only)
│   ├── silver/                   → Medallion Silver: Delta Lake ACID (clean, typed, deduplicated)
│   ├── gold/                     → Medallion Gold: Delta Lake (KPIs, ML features, reports)
│   ├── lab-notebooks/            → notebook exports (.ipynb)
│   ├── airflow-logs/             → Airflow task logs (remote logging)
│   └── spark-warehouse/          → Delta catalog + Spark SQL warehouse
│       └── history/              → Spark History Server event logs
├── datasets/                     Local datasets (direct access without MinIO)
├── models/
│   └── ollama/                   LLM models in .gguf format
│       └── [llama3/, mistral/]   Downloaded by Ollama on pull
├── notebooks/                    Exported or shared notebooks
├── artifacts/                    Experiment results, ML outputs
└── backups/                      Local cold storage backups
```

---

## Storage usage policy

| Data type | Location | Reason |
|-----------|----------|--------|
| PostgreSQL data | `/srv/fastdata/postgres` | Critical IOPS — NVMe avoids I/O wait |
| n8n state | `/srv/fastdata/n8n` | Metadata + credentials — NVMe |
| Airflow DAGs/logs/plugins | `/srv/fastdata/airflow` | Frequent access — NVMe |
| Spark shuffle/spill | `/srv/fastdata/spark-tmp` | Massive I/O on joins — NVMe mandatory |
| OpenSearch index | `/srv/fastdata/opensearch` | Query latency — HDD on master1 (sufficient for lab) |
| Jupyter home | `/srv/fastdata/jupyter/{user}` | .venv and kernels — NVMe for fast pip install |
| MinIO buckets | `/srv/datalake/minio` | Bulk object storage — HDD sufficient (cold data) |
| LLM models (.gguf) | `/srv/datalake/models/ollama` | Large files (4–30 GB) — HDD sufficient |
| ML datasets | `/srv/datalake/datasets` | Bulk data — HDD sufficient for sequential read |
| Artifacts/experiments | `/srv/datalake/artifacts` | Outputs — HDD sufficient |
| Local backups | `/srv/datalake/backups` | Cold storage — HDD sufficient |

---

## Standard permissions

```bash
# Service directories (Docker bind mounts)
sudo chown root:docker /srv/fastdata/<dir>
sudo chmod 2775 /srv/fastdata/<dir>   # SGID for docker group

# Postgres (runs as UID 999)
sudo chown -R 999:999 /srv/fastdata/postgres
sudo chmod 700 /srv/fastdata/postgres

# Jupyter users (known UIDs)
sudo chown -R 1000:1000 /srv/fastdata/jupyter/<admin-user>
sudo chown -R 1001:1001 /srv/fastdata/jupyter/<second-user>
sudo chmod 2770 /srv/fastdata/jupyter/<admin-user>
sudo chmod 2770 /srv/fastdata/jupyter/<second-user>
```

---

## Current capacity (estimated)

| Mount | Total | Used | Free | Notes |
|-------|-------|------|------|-------|
| `/srv/fastdata` | 600 GB | ~20 GB | ~580 GB | NVMe — high headroom |
| `/srv/datalake` | 1.8 TB | ~50 GB | ~1.75 TB | HDD — space for datasets |

> Update with `df -h /srv/fastdata /srv/datalake` on master2.
