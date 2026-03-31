# Inventario de Servicios

> Actualizado: 2026-03-31 — Lab 100% operativo (20 servicios)

---

## Estado general

```
✅ OPERATIVO     — Desplegado, funcionando, persistente post-reboot
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
Airflow Web      ✅               MinIO             ✅
Airflow Sched.   ✅               Spark Worker      ✅
Airflow Flower   ✅               Airflow Worker    ✅
Redis (Celery)   ✅               Portainer Agent   ✅
Spark Master     ✅
Spark History    ✅
Portainer Agent  ✅
```

**Total: 20 servicios / 20 operativos ✅**

---

## Servicios operativos

### 1. Traefik — Reverse Proxy + TLS

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `traefik` |
| **Archivo** | `stacks/core/00-traefik/stack.yml` |
| **Imagen** | `traefik:v2.11` |
| **Nodo** | master1 (`tier=control`) |
| **Puertos** | `:80` (redirect→HTTPS) `:443` (TLS) — `mode: host` |
| **Estado** | ✅ OPERATIVO |
| **URL** | `https://traefik.sexydad/dashboard/` |
| **Auth** | BasicAuth (`traefik_basic_auth`) + LAN whitelist |
| **Secrets** | `traefik_basic_auth` `traefik_tls_cert` `traefik_tls_key` + auth secrets de otros servicios |
| **Restart** | `condition: any` |
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
| **Persistencia** | `/srv/fastdata/portainer:/data` (HDD master1) |
| **Estado** | ✅ OPERATIVO |
| **URL** | `https://portainer.sexydad` |
| **Auth** | Usuarios internos de Portainer |
| **Restart** | `condition: any` |
| **Runbook** | [`runbook_portainer.md`](../runbooks/runbook_portainer.md) |

> **Nota operativa**: Portainer tiene un timeout de ~5 min en primera instalación para crear el admin. Si expira: `docker service update --force portainer_portainer` y crear admin inmediatamente.

---

### 3. PostgreSQL 16 — Base de datos central

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `postgres` |
| **Archivo** | `stacks/core/02-postgres/stack.yml` |
| **Imagen** | `postgres:16` |
| **Nodo** | master2 (`hostname=master2`) |
| **Persistencia** | `/srv/fastdata/postgres` (NVMe LVM) |
| **Puerto** | `5432` (`mode: host`) — solo accesible desde master2 |
| **Databases** | `postgres` (default/admin), `n8n`, `airflow` |
| **Usuarios** | `postgres` (superuser), `n8n`, `airflow` |
| **Secrets** | `pg_super_pass` `pg_n8n_pass` `pg_airflow_pass` |
| **Estado** | ✅ OPERATIVO |
| **Acceso interno** | `postgres_postgres:5432` (overlay internal) |
| **Acceso LAN directo** | `192.168.80.200:5432` (DBeaver, psql) |
| **Restart** | `condition: any`, `max_attempts: 0` (infinito — crítico) |
| **Runbook** | [`runbook_postgres.md`](../runbooks/runbook_postgres.md) |

> Ver detalle completo de bases de datos y usuarios: [`DATABASES.md`](DATABASES.md)

---

### 4. n8n — Automatización de flujos

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `n8n` |
| **Archivo** | `stacks/automation/02-n8n/stack.yml` |
| **Imagen** | `n8nio/n8n:2.4.7` |
| **Nodo** | master2 (`tier=compute`) |
| **Persistencia** | `/srv/fastdata/n8n` (NVMe) |
| **DB Backend** | PostgreSQL (`n8n` database en master2) |
| **Estado** | ✅ OPERATIVO |
| **URL** | `https://n8n.sexydad` |
| **Auth** | Usuarios internos de n8n |
| **Secrets** | `pg_n8n_pass` `n8n_encryption_key` `n8n_user_mgmt_jwt_secret` |
| **Restart** | `condition: any`, `max_attempts: 0` |
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
| **Persistencia** | `/srv/fastdata/jupyter/{user}/work` (NVMe) |
| **Volumes extra** | `/srv/datalake/datasets` (ro), `shared-notebooks`, `artifacts` |
| **GPU** | RTX 2080 Ti (compartida entre usuarios + Ollama) |
| **Recursos (c/u)** | límite: 8 CPUs / 12 GB — reserva: 2 CPUs / 4 GB |
| **Kernels** | Python LLM · Python IA · Python BigData (PySpark + Delta) |
| **Estado** | ✅ OPERATIVO |
| **URLs** | `https://jupyter-ogiovanni.sexydad` / `https://jupyter-odavid.sexydad` |
| **Auth** | BasicAuth (`jupyter_basicauth_v2`) vía Traefik |
| **Secrets** | `minio_access_key` `minio_secret_key` |
| **Restart** | `condition: any` |
| **Token Jupyter** | `docker service logs jupyter_jupyter_{user} 2>&1 \| grep token` |
| **Runbook** | [`runbook_jupyter.md`](../runbooks/runbook_jupyter.md) |

---

### 7. Ollama — LLM Inference Engine

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `ollama` |
| **Archivo** | `stacks/ai-ml/02-ollama/stack.yml` |
| **Imagen** | `ollama/ollama:0.6.1` (versión pineada) |
| **Nodo** | master2 (`tier=compute` + `gpu=nvidia`) |
| **Persistencia** | `/srv/datalake/models/ollama` (HDD 2TB) |
| **GPU** | RTX 2080 Ti — 11 GB VRAM — CUDA 12.2 |
| **VRAM reservada** | 10 GB para modelos (1 GB overhead) |
| **Estado** | ✅ OPERATIVO (sin modelos descargados aún) |
| **URL externa** | `https://ollama.sexydad` (BasicAuth + LAN whitelist) |
| **URL interna** | `http://ollama:11434` |
| **Auth** | BasicAuth (`ollama_basicauth`) |
| **Secrets** | `ollama_basicauth` |
| **Restart** | `condition: any` |
| **Descargar modelo** | `docker exec -it <container_id> ollama pull llama3` |
| **Runbook** | [`runbook_ollama.md`](../runbooks/runbook_ollama.md) |

---

### 8–9. OpenSearch + Dashboards

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `opensearch` |
| **Archivo** | `stacks/data/11-opensearch/stack.yml` |
| **Imagen OpenSearch** | `opensearchproject/opensearch:2.19.4` |
| **Imagen Dashboards** | `opensearchproject/opensearch-dashboards:2.19.4` |
| **Nodo** | master1 (`tier=control`) |
| **Persistencia** | `/srv/fastdata/opensearch` (HDD master1) |
| **Modo** | `single-node`, security plugin DESHABILITADO |
| **Memoria JVM** | `-Xms1g -Xmx1g` |
| **Estado** | ✅ OPERATIVO |
| **URL API** | `https://opensearch.sexydad` |
| **URL UI** | `https://dashboards.sexydad` |
| **URL interna** | `http://opensearch:9200` |
| **Auth** | BasicAuth (`opensearch_basicauth` / `dashboards_basicauth`) |
| **Restart** | `condition: any` |
| **Runbook** | [`runbook_opensearch.md`](../runbooks/runbook_opensearch.md) |

> **ADR-004**: Security plugin deshabilitado. En lab LAN-only con BasicAuth+Whitelist en Traefik es suficiente.

---

### 10. MinIO — Object Storage S3-compatible

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `minio` |
| **Archivo** | `stacks/data/12-minio/stack.yml` |
| **Imagen** | `minio/minio:RELEASE.2024-11-07T00-52-20Z` |
| **Nodo** | master2 (`tier=compute`) |
| **Persistencia** | `/srv/datalake/minio` (HDD 2TB) |
| **Recursos** | límite: 4 CPUs / 2 GB — reserva: 0.5 CPU / 512 MB |
| **Estado** | ✅ OPERATIVO |
| **URL Console** | `https://minio.sexydad` |
| **URL S3 API** | `https://minio-api.sexydad` |
| **URL interna** | `http://minio:9000` (Spark/Airflow/Jupyter) |
| **Secrets** | `minio_access_key` `minio_secret_key` |
| **Restart** | `condition: any` |
| **Buckets Medallion** | `bronze` · `silver` · `gold` · `airflow-logs` · `spark-warehouse` · `lab-notebooks` |
| **Región** | `us-east-1` (para compatibilidad boto3/s3fs) |
| **Runbook** | [`runbook_minio.md`](../runbooks/runbook_minio.md) |

---

### 11. Apache Spark 3.5 — Procesamiento distribuido

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `spark` |
| **Archivo** | `stacks/data/98-spark/stack.yml` |
| **Imagen** | `apache/spark:3.5.3` (imagen oficial ASF) |
| **Nodo master** | master1 (`tier=control`) |
| **Nodo worker** | master2 (`tier=compute`) |
| **Worker recursos** | límite: 12 CPUs / 16 GB — oferta al cluster: 10 CPUs / 14 GB |
| **Master recursos** | límite: 2 CPUs / 2 GB |
| **Estado** | ✅ OPERATIVO |
| **URL Master UI** | `https://spark-master.sexydad` |
| **URL Worker UI** | `https://spark-worker.sexydad` |
| **URL History** | `https://spark-history.sexydad` |
| **URL interna** | `spark://spark-master:7077` |
| **Event logs** | `/srv/fastdata/spark-history` (filesystem local — NFS implícito entre master/worker/history) |
| **Restart** | `condition: any` |
| **Runbook** | [`runbook_spark.md`](../runbooks/runbook_spark.md) |

> **Nota**: `apache/spark:3.5.3` NO incluye `hadoop-aws.jar`. Los event logs usan filesystem local. Hostnames con **guión** (spark-master, no spark_master) — Spark valida como URL Java.

---

### 12–16. Apache Airflow 2.9 — Orquestación de pipelines

| Componente | Nodo | Recursos (reserva) | Estado |
|------------|------|-------------------|--------|
| `airflow_redis` | master1 | 0.1 CPU / 128 MB | ✅ |
| `airflow_webserver` | master1 | 0.5 CPU / 1 GB | ✅ |
| `airflow_scheduler` | master1 | 0.5 CPU / 512 MB | ✅ |
| `airflow_flower` | master1 | 0.1 CPU / 128 MB | ✅ |
| `airflow_worker` | master2 | 1 CPU / 1 GB | ✅ |

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `airflow` |
| **Archivo** | `stacks/automation/03-airflow/stack.yml` |
| **Imagen** | `apache/airflow:2.9.3` |
| **Executor** | `CeleryExecutor` + Redis 7 como broker |
| **DB Backend** | PostgreSQL `airflow` en master2 |
| **DAGs path** | `/srv/fastdata/airflow/dags` (master1 + master2, mismo path) |
| **Logs** | `/srv/fastdata/airflow/logs` (local — remote logging en MinIO deshabilitado por defecto) |
| **Secrets** | `pg_airflow_pass` `airflow_fernet_key` `airflow_webserver_secret` `minio_access_key` `minio_secret_key` |
| **Config Docker** | `airflow_entrypoint_v4` — URL-encodes el password de Postgres antes de construir la URL SQLAlchemy |
| **URL Webserver** | `https://airflow.sexydad` |
| **URL Flower** | `https://airflow-flower.sexydad` |
| **Restart** | `condition: any` |
| **Runbook** | [`runbook_airflow.md`](../runbooks/runbook_airflow.md) |

> **Bug crítico resuelto**: El password de Postgres contiene caracteres especiales (`/`, `=`). El entrypoint `airflow-entrypoint.sh` usa `urllib.parse.quote()` para URL-encodear el password antes de construir la URL de SQLAlchemy y Celery. Sin esto, `ValueError: Port could not be cast to integer value`.

---

## Mapa de recursos comprometidos (estado actual)

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
Redis (Celery)         0.1         128 MB
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
Jupyter ogiovanni      2.0         4 GB
Jupyter odavid         2.0         4 GB
Ollama (GPU)           6.0         12 GB
MinIO                  0.5         512 MB
Spark Worker           2.0         2 GB
Airflow Worker         1.0         1 GB
Portainer Agent        ~0.1        ~64 MB
────────────────────── ─────────── ──────────────
TOTAL                  ~14.3 CPU   ~24.3 GB / 32 GB  ✅ RESPIRA
```
