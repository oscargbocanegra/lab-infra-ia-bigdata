# Inventario de Servicios

> Actualizado: 2026-03-30

---

## Estado general

```
✅ OPERATIVO     — Desplegado, funcionando, persistente post-reboot
⏳ PENDIENTE     — Stack creado en repo, no desplegado aún en producción
🔧 EN PROGRESO   — En configuración/optimización
```

---

## Resumen del cluster

```
master1 (Control/Gateway)         master2 (Compute/Data/GPU)
──────────────────────────────    ──────────────────────────────────────
Traefik          ✅               PostgreSQL        ✅
Portainer        ✅               n8n               ✅
OpenSearch       ✅               JupyterLab x2     ✅
Dashboards       ✅               Ollama (GPU)      ✅
Airflow Web      ⏳               MinIO             ⏳
Airflow Sched.   ⏳               Spark Worker      ⏳
Airflow Flower   ⏳               Airflow Worker    ⏳
Redis (Celery)   ⏳
Spark Master     ⏳
Spark History    ⏳
```

---

## Servicios operativos

### 1. Traefik — Reverse Proxy + TLS

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `traefik` |
| **Archivo** | `stacks/core/00-traefik/stack.yml` |
| **Imagen** | `traefik:v2.11` |
| **Nodo** | master1 (`tier=control`) |
| **Puertos** | `:80` (redirect) `:443` (TLS) — `mode: host` |
| **Estado** | ✅ OPERATIVO |
| **URL** | `https://traefik.sexydad/dashboard/` |
| **Secrets** | `traefik_basic_auth` `traefik_tls_cert` `traefik_tls_key` |
| **Runbook** | [`runbook_traefik.md`](../runbooks/runbook_traefik.md) |

---

### 2. Portainer CE — Gestión del clúster Swarm

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `portainer` |
| **Archivo** | `stacks/core/01-portainer/stack.yml` |
| **Imagen (server)** | `portainer/portainer-ce:2.39.1` |
| **Imagen (agent)** | `portainer/agent:2.39.1` |
| **Nodo server** | master1 (`tier=control`) |
| **Nodo agent** | global (master1 + master2) |
| **Persistencia** | `/srv/fastdata/portainer:/data` |
| **Estado** | ✅ OPERATIVO (actualizar a 2.39.1 en producción) |
| **URL** | `https://portainer.sexydad` |
| **Runbook** | [`runbook_portainer.md`](../runbooks/runbook_portainer.md) |

---

### 3. PostgreSQL 16 — Base de datos central

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `postgres` |
| **Archivo** | `stacks/core/02-postgres/stack.yml` |
| **Imagen** | `postgres:16` |
| **Nodo** | master2 (`hostname=master2`) |
| **Persistencia** | `/srv/fastdata/postgres` (NVMe) |
| **Puerto** | `5432` (`mode: host`) |
| **Databases** | `postgres` (default), `n8n`, `airflow` |
| **Secrets** | `pg_super_pass` `pg_n8n_pass` `pg_airflow_pass` |
| **Estado** | ✅ OPERATIVO |
| **Acceso interno** | `postgres_postgres:5432` |
| **Acceso LAN** | `<IP_MASTER2>:5432` |
| **Runbook** | [`runbook_postgres.md`](../runbooks/runbook_postgres.md) |

> **Cambio v2**: `POSTGRES_DB` cambiado a `postgres` (neutral). Añadido `02-init-airflow.sh`.

---

### 4. n8n — Automatización de flujos

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `n8n` |
| **Archivo** | `stacks/automation/02-n8n/stack.yml` |
| **Imagen** | `n8nio/n8n:2.4.7` |
| **Nodo** | master2 (`tier=compute`) |
| **Persistencia** | `/srv/fastdata/n8n` (NVMe) |
| **DB Backend** | PostgreSQL (`n8n` database) |
| **Estado** | ✅ OPERATIVO |
| **URL** | `https://n8n.sexydad` |
| **Runbook** | [`runbook_n8n.md`](../runbooks/runbook_n8n.md) |

---

### 5–6. JupyterLab — Entorno multi-usuario IA/ML/BigData

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `jupyter` |
| **Archivo** | `stacks/ai-ml/01-jupyter/stack.yml` |
| **Imagen** | `jupyter/datascience-notebook:python-3.11` |
| **Nodo** | master2 (`tier=compute` + `hostname=master2`) |
| **Usuarios** | `ogiovanni` (uid 1000) + `odavid` (uid 1001) |
| **Persistencia** | `/srv/fastdata/jupyter/{user}` (NVMe) |
| **Recursos** | límite: 8 CPUs / 12 GB — reserva: **2 CPUs / 4 GB** (optimizado) |
| **Kernels** | Python LLM · Python IA · **Python BigData** (nuevo) |
| **Volumes extra** | `/srv/datalake/datasets` (ro), `notebooks`, `artifacts` |
| **Estado** | ✅ OPERATIVO |
| **URLs** | `https://jupyter-ogiovanni.sexydad` `https://jupyter-odavid.sexydad` |
| **Runbook** | [`runbook_jupyter.md`](../runbooks/runbook_jupyter.md) |

> **Cambios v2**: reservations reducidas (4→2 CPUs, 8→4 GB por usuario), nuevo kernel BigData (PySpark + Delta + MinIO), mount datalake compartido.

---

### 7. Ollama — LLM Inference Engine

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `ollama` |
| **Archivo** | `stacks/ai-ml/02-ollama/stack.yml` |
| **Imagen** | `ollama/ollama:0.6.1` (pineado) |
| **Nodo** | master2 (`tier=compute` + `gpu=nvidia`) |
| **Persistencia** | `/srv/datalake/models/ollama` (HDD 2TB) |
| **GPU** | RTX 2080 Ti — 11 GB VRAM — CUDA 12.2 |
| **Estado** | ✅ OPERATIVO |
| **URL externa** | `https://ollama.sexydad` (BasicAuth) |
| **URL interna** | `http://ollama:11434` |
| **Runbook** | [`runbook_ollama.md`](../runbooks/runbook_ollama.md) |

> **Cambio v2**: imagen `latest` → `0.6.1` (versión pineada).

---

### 8–9. OpenSearch + Dashboards

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `opensearch` |
| **Archivo** | `stacks/data/11-opensearch/stack.yml` |
| **Imagen** | `opensearchproject/opensearch:2.19.4` |
| **Nodo** | master1 (`tier=control`) |
| **Persistencia** | `/srv/fastdata/opensearch` (HDD master1) |
| **Estado** | ✅ OPERATIVO |
| **URL API** | `https://opensearch.sexydad` |
| **URL UI** | `https://dashboards.sexydad` |
| **Runbook** | [`runbook_opensearch.md`](../runbooks/runbook_opensearch.md) |

---

## Servicios nuevos (pendientes de deploy)

### 10. MinIO — Object Storage S3-compatible

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `minio` |
| **Archivo** | `stacks/data/12-minio/stack.yml` |
| **Imagen** | `minio/minio:RELEASE.2024-11-07T00-52-20Z` |
| **Nodo** | master2 (`tier=compute`) |
| **Persistencia** | `/srv/datalake/minio` (HDD 2TB) |
| **Recursos** | límite: 4 CPUs / 2 GB — reserva: 0.5 CPU / 512 MB |
| **Estado** | ⏳ PENDIENTE |
| **URL Console** | `https://minio.sexydad` |
| **URL API S3** | `https://minio-api.sexydad` |
| **URL interna** | `http://minio:9000` (para Spark/Airflow/Jupyter) |
| **Buckets** | `lab-datasets` `lab-artifacts` `lab-notebooks` `airflow-logs` `spark-warehouse` |
| **Secrets** | `minio_access_key` `minio_secret_key` |
| **Runbook** | [`runbook_minio.md`](../runbooks/runbook_minio.md) |

---

### 11. Apache Spark 3.5 — Procesamiento distribuido

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `spark` |
| **Archivo** | `stacks/data/98-spark/stack.yml` |
| **Imagen** | `bitnami/spark:3.5.3` |
| **Nodo master** | master1 (`tier=control`) |
| **Nodo worker** | master2 (`tier=compute`) |
| **Worker recursos** | límite: 12 CPUs / 16 GB — oferta: 10 CPUs / 14 GB |
| **Estado** | ⏳ PENDIENTE |
| **URL Master UI** | `https://spark-master.sexydad` |
| **URL Worker UI** | `https://spark-worker.sexydad` |
| **URL History** | `https://spark-history.sexydad` |
| **URL interna** | `spark://spark_master:7077` |
| **Runbook** | [`runbook_spark.md`](../runbooks/runbook_spark.md) |

---

### 12–16. Apache Airflow 2.9 — Orquestación de pipelines

| Componente | Nodo | Recursos (reserva) | Estado |
|------------|------|-------------------|--------|
| `airflow_webserver` | master1 | 0.5 CPU / 1 GB | ⏳ |
| `airflow_scheduler` | master1 | 0.5 CPU / 512 MB | ⏳ |
| `airflow_worker` | master2 | 1 CPU / 1 GB | ⏳ |
| `airflow_flower` | master1 | 0.1 CPU / 128 MB | ⏳ |
| `redis` | master1 | 0.1 CPU / 128 MB | ⏳ |

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `airflow` |
| **Archivo** | `stacks/automation/03-airflow/stack.yml` |
| **Imagen** | `apache/airflow:2.9.3` |
| **Executor** | CeleryExecutor + Redis broker |
| **DB Backend** | PostgreSQL `airflow` en master2 |
| **DAGs path** | `/srv/fastdata/airflow/dags` (master1 + master2) |
| **Logs** | Local + remoto en `s3://airflow-logs/` (MinIO) |
| **URL Webserver** | `https://airflow.sexydad` |
| **URL Flower** | `https://airflow-flower.sexydad` |
| **Secrets** | `pg_airflow_pass` `airflow_fernet_key` `airflow_webserver_secret` |
| **Runbook** | [`runbook_airflow.md`](../runbooks/runbook_airflow.md) |

---

## Mapa de recursos comprometidos (post full-deploy)

### master1 — Control Plane (32 GB RAM / 8 threads)

```
Servicio               CPU reserva   RAM reserva
────────────────────── ─────────── ──────────────
Traefik                ~0.1        ~128 MB
Portainer              ~0.1        ~128 MB
Portainer Agent        ~0.1        ~64 MB
OpenSearch             1.0         2 GB
Dashboards             0.5         1 GB
Airflow Webserver      0.5         1 GB
Airflow Scheduler      0.5         512 MB
Airflow Flower         0.1         128 MB
Redis                  0.1         128 MB
Spark Master           0.5         1 GB
Spark History          0.25        512 MB
────────────────────── ─────────── ──────────────
TOTAL                  ~3.75 CPU   ~6.6 GB / 32 GB  ✅ MUY HOLGADO
```

### master2 — Compute Node (32 GB RAM / 16 threads)

```
Servicio               CPU reserva   RAM reserva
────────────────────── ─────────── ──────────────
PostgreSQL             0.5         512 MB
n8n                    ~0.2        ~256 MB
Jupyter ogiovanni      2.0         4 GB   ← optimizado (era 4/8)
Jupyter odavid         2.0         4 GB   ← optimizado (era 4/8)
Ollama (GPU)           6.0         12 GB
MinIO                  0.5         512 MB
Spark Worker           2.0         2 GB
Airflow Worker         1.0         1 GB
Portainer Agent        ~0.1        ~64 MB
────────────────────── ─────────── ──────────────
TOTAL                  ~14.3 CPU   ~24.3 GB / 32 GB  ✅ RESPIRA (era ~29 GB)
```

> **Ahorro conseguido**: ~4.7 GB RAM liberados en master2 al bajar reservations de Jupyter.
> El Spark Worker y Airflow Worker caben cómodamente.
