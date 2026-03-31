# Storage — Mapa de Discos y Paths

> Actualizado: 2026-03-30 — Fase 5: MinIO, Spark, Airflow

---

## master1: Storage layout

```
Disco único: WDC WD5000LPLX — 500 GB HDD (ROTA)
│
├── / (root filesystem)
├── /srv/fastdata/           → HDD local (NO es NVMe, nombre es heredado)
│   ├── portainer/           → Portainer CE data
│   ├── opensearch/          → OpenSearch data (index, translog)
│   └── traefik/             → (prep) configs Traefik si se necesita
└── /srv/backups/
    └── master2/             → (planeado) backups recibidos por rsync/restic
```

**Nota**: En master1 el directorio `/srv/fastdata` existe pero está sobre HDD rotativo, NO NVMe. El nombre es consistente con master2 para simplificar runbooks, pero el rendimiento es diferente.

---

## master2: Storage layout

### Discos físicos

| Disco | Modelo | Tamaño | Tipo | Montaje |
|-------|--------|--------|------|---------|
| nvme0n1 | Samsung SSD 970 EVO 1TB | 931.5 GB | NVMe (ROTA=0) | LVM → `/srv/fastdata` |
| sda | Seagate ST2000LM015 | 1.8 TB | HDD (ROTA=1) | `/srv/datalake` |

### LVM sobre NVMe

```
NVMe (nvme0n1)
└── PV → VG (vg0)
    └── LV: fastdata → 600 GB (ext4)
        └── montado en /srv/fastdata
            (resto del NVMe disponible para expandir LVM)
```

**Comandos de verificación**:
```bash
# Ver LVM
sudo pvs && sudo vgs && sudo lvs

# Ver montaje activo
findmnt /srv/fastdata
df -h /srv/fastdata
```

### /etc/fstab (master2) — líneas clave

```
# NVMe fastdata (LVM)
/dev/vg0/fastdata   /srv/fastdata   ext4   defaults,nofail   0 2

# HDD datalake (por UUID — ver blkid para el real)
UUID=<UUID_HDD_DATALAKE>   /srv/datalake   ext4   defaults,nofail   0 2
```

> Archivo versionado en: `docs/hosts/master2/etc/fstab`

### Estructura de directorios completa en master2

```
/srv/fastdata/                    (NVMe — I/O intensivo, workloads activos)
├── postgres/                     PostgreSQL 16 data directory
│   └── [archivos PG internos]    owner: 999:999, mode: 700
├── n8n/                          n8n config, workflows, credentials
├── airflow/                      Airflow DAGs, logs, plugins, Redis data
│   ├── dags/                     DAGs de Python (montado en master1 y master2)
│   ├── logs/                     Logs locales de tareas (antes de habilitar MinIO)
│   ├── plugins/                  Plugins custom de Airflow
│   └── redis/                    Persistencia Redis (broker Celery — 60s/1 key)
├── spark-tmp/                    Scratch Spark: shuffle/spill (NVMe máx velocidad)
└── jupyter/
    ├── ogiovanni/
    │   ├── work/                 Home de JupyterLab (notebooks, scripts)
    │   ├── .venv/                virtualenv IA/LLM/BigData kernels (persistente)
    │   └── .local/               kernelspecs JupyterLab
    └── odavid/
        ├── work/
        ├── .venv/
        └── .local/

/srv/datalake/                    (HDD 2TB — almacenamiento masivo)
├── minio/                        MinIO object storage (todos los buckets)
│   ├── bronze/                   → Medallion Bronze: datos crudos (CSV/JSON/Parquet, append-only)
│   ├── silver/                   → Medallion Silver: Delta Lake ACID (clean, tipado, deduplicado)
│   ├── gold/                     → Medallion Gold: Delta Lake (KPIs, features ML, reportes)
│   ├── lab-notebooks/            → exports de notebooks (.ipynb)
│   ├── airflow-logs/             → logs de tareas Airflow (remote logging)
│   └── spark-warehouse/          → Delta catalog + Spark SQL warehouse
│       └── history/              → Event logs del Spark History Server
├── datasets/                     Datasets locales (acceso directo sin MinIO)
├── models/
│   └── ollama/                   Modelos LLM en formato .gguf
│       └── [llama3/, mistral/]   Descargados por Ollama al hacer pull
├── notebooks/                    Notebooks exportados o compartidos
├── artifacts/                    Resultados de experimentos, outputs ML
└── backups/                      Backups fríos locales
```

---

## Política de uso de storage

| Tipo de dato | Dónde va | Motivo |
|--------------|----------|--------|
| PostgreSQL data | `/srv/fastdata/postgres` | IOPS crítico — NVMe evita I/O wait |
| n8n state | `/srv/fastdata/n8n` | Metadata + credentials — NVMe |
| Airflow DAGs/logs/plugins | `/srv/fastdata/airflow` | Acceso frecuente — NVMe |
| Spark shuffle/spill | `/srv/fastdata/spark-tmp` | I/O masivo en joins — NVMe obligatorio |
| OpenSearch index | `/srv/fastdata/opensearch` | Query latency — HDD en master1 (suficiente para lab) |
| Jupyter home | `/srv/fastdata/jupyter/{user}` | .venv y kernels — NVMe para pip install rápido |
| MinIO buckets | `/srv/datalake/minio` | Bulk object storage — HDD suficiente (datos fríos) |
| Modelos LLM (.gguf) | `/srv/datalake/models/ollama` | Archivos grandes (4–30 GB) — HDD suficiente |
| Datasets ML | `/srv/datalake/datasets` | Bulk data — HDD suficiente para read sequential |
| Artifacts/experimentos | `/srv/datalake/artifacts` | Outputs — HDD suficiente |
| Backups locales | `/srv/datalake/backups` | Cold storage — HDD suficiente |

---

## Permisos estándar

```bash
# Directorios de servicios (bind mounts de Docker)
sudo chown root:docker /srv/fastdata/<dir>
sudo chmod 2775 /srv/fastdata/<dir>   # SGID para grupo docker

# Postgres (corre como UID 999)
sudo chown -R 999:999 /srv/fastdata/postgres
sudo chmod 700 /srv/fastdata/postgres

# Jupyter usuarios (UIDs conocidos)
sudo chown -R 1000:1000 /srv/fastdata/jupyter/ogiovanni
sudo chown -R 1001:1001 /srv/fastdata/jupyter/odavid
sudo chmod 2770 /srv/fastdata/jupyter/ogiovanni
sudo chmod 2770 /srv/fastdata/jupyter/odavid
```

---

## Capacidad actual (estimada)

| Mount | Total | Usado | Libre | Notas |
|-------|-------|-------|-------|-------|
| `/srv/fastdata` | 600 GB | ~20 GB | ~580 GB | NVMe — headroom alto |
| `/srv/datalake` | 1.8 TB | ~50 GB | ~1.75 TB | HDD — espacio para datasets |

> Actualizar con `df -h /srv/fastdata /srv/datalake` en master2.
