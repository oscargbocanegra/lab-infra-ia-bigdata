# Inventario de Servicios

> Actualizado: 2026-03-30

---

## Estado general

```
✅ OPERATIVO     — Desplegado, funcionando, persistente post-reboot
⏳ PENDIENTE     — Directorio/stack creado, no desplegado
🔧 EN PROGRESO   — En configuración/optimización
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
| **Runbook** | [`docs/runbooks/runbook_traefik.md`](../runbooks/runbook_traefik.md) |

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
| **Estado** | ✅ OPERATIVO |
| **URL** | `https://portainer.sexydad` |
| **Runbook** | [`docs/runbooks/runbook_portainer.md`](../runbooks/runbook_portainer.md) |

> **Actualización pendiente en producción**: Pasar de 2.21.0 a 2.39.1. Ejecutar: `docker stack deploy -c stacks/core/01-portainer/stack.yml portainer`

---

### 3. PostgreSQL — Base de datos relacional

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `postgres` |
| **Archivo** | `stacks/core/02-postgres/stack.yml` |
| **Imagen** | `postgres:16` |
| **Nodo** | master2 (`hostname=master2`) |
| **Persistencia** | `/srv/fastdata/postgres` (NVMe) |
| **Puerto** | `5432` (`mode: host`) |
| **Databases** | `postgres` (super), `n8n` (app) |
| **Secrets** | `pg_super_pass` `pg_n8n_pass` |
| **Estado** | ✅ OPERATIVO |
| **Acceso interno** | `postgres_postgres:5432` (overlay internal) |
| **Acceso LAN** | `192.168.80.X:5432` (DBeaver / psql) |
| **Runbook** | [`docs/runbooks/runbook_postgres.md`](../runbooks/runbook_postgres.md) |

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
| **Secrets** | `pg_n8n_pass` `n8n_encryption_key` `n8n_user_mgmt_jwt_secret` |
| **Estado** | ✅ OPERATIVO |
| **URL** | `https://n8n.sexydad` |
| **Runbook** | [`docs/runbooks/runbook_n8n.md`](../runbooks/runbook_n8n.md) |

---

### 5–6. JupyterLab — Entorno multi-usuario IA/ML + GPU

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `jupyter` |
| **Archivo** | `stacks/ai-ml/01-jupyter/stack.yml` |
| **Imagen** | `jupyter/datascience-notebook:python-3.11` |
| **Nodo** | master2 (`tier=compute` + `hostname=master2`) |
| **Usuarios** | `ogiovanni` (uid 1000) + `odavid` (uid 1001) |
| **Persistencia** | `/srv/fastdata/jupyter/{user}` (NVMe) |
| **Recursos** | 8 CPUs límite, 12 GB RAM, GPU RTX 2080 Ti |
| **Kernels** | Python IA (PyTorch/TF), Python LLM (langchain/ollama) |
| **Secrets** | `jupyter_basicauth_v2` |
| **Estado** | ✅ OPERATIVO |
| **URLs** | `https://jupyter-ogiovanni.sexydad` `https://jupyter-odavid.sexydad` |
| **Runbook** | [`docs/runbooks/runbook_jupyter.md`](../runbooks/runbook_jupyter.md) |

---

### 7. Ollama — LLM Inference Engine

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `ollama` |
| **Archivo** | `stacks/ai-ml/02-ollama/stack.yml` |
| **Imagen** | `ollama/ollama:latest` |
| **Nodo** | master2 (`tier=compute` + `gpu=nvidia`) |
| **Persistencia** | `/srv/datalake/models/ollama` (HDD 2TB) |
| **GPU** | RTX 2080 Ti — 11 GB VRAM — CUDA 12.2 |
| **Recursos** | 6–12 CPUs, 12–24 GB RAM |
| **Optimizaciones** | Flash Attention, KV cache f16, 4 parallel requests |
| **Secrets** | `ollama_basicauth` |
| **Estado** | ✅ OPERATIVO |
| **URL externa** | `https://ollama.sexydad` (BasicAuth) |
| **URL interna** | `http://ollama:11434` (sin auth, desde Jupyter/n8n) |
| **Runbook** | [`docs/runbooks/runbook_ollama.md`](../runbooks/runbook_ollama.md) |

---

### 8–9. OpenSearch + Dashboards — Search & Analytics

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `opensearch` |
| **Archivo** | `stacks/data/11-opensearch/stack.yml` |
| **Imagen** | `opensearchproject/opensearch:2.19.4` |
| **Nodo (engine)** | master1 (`tier=control`) |
| **Nodo (dashboards)** | master1 (`tier=control`) |
| **Persistencia** | `/srv/fastdata/opensearch` (HDD master1) |
| **Recursos (engine)** | 1–3 CPUs, 2–6 GB RAM, 1 GB JVM heap |
| **Recursos (dashboards)** | 0.5–2 CPUs, 1–3 GB RAM |
| **Seguridad** | Plugin disabled — BasicAuth + LAN Whitelist vía Traefik |
| **Cluster** | Single-node (`discovery.type=single-node`) |
| **Secrets** | `opensearch_basicauth` `dashboards_basicauth` |
| **Estado** | ✅ OPERATIVO |
| **URL API** | `https://opensearch.sexydad` (BasicAuth) |
| **URL UI** | `https://dashboards.sexydad` (BasicAuth) |
| **URL interna** | `http://opensearch:9200` (sin auth) |
| **Runbook** | [`docs/runbooks/runbook_opensearch.md`](../runbooks/runbook_opensearch.md) |

---

## Servicios pendientes

### Airflow — Orquestación de pipelines

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `airflow` |
| **Archivo** | `stacks/automation/03-airflow/stack.yml` (pendiente crear) |
| **Nodo webserver/scheduler** | master1 (`tier=control`) |
| **Nodo workers** | master2 (`tier=compute`) |
| **DB Backend** | PostgreSQL en master2 (nueva DB: `airflow`) |
| **Estado** | ⏳ Directorio creado, stack.yml pendiente |

**Dependencias**:
- [ ] Crear DB `airflow` en Postgres
- [ ] Crear secret `airflow_fernet_key`
- [ ] Crear secret `airflow_admin_pass`
- [ ] Crear directorio `/srv/fastdata/airflow` en master2

---

### Spark — Procesamiento distribuido

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `spark` |
| **Archivo** | `stacks/data/98-spark/stack.yml` (pendiente crear) |
| **Nodo master** | master1 (control) o master2 (compute, mejor latencia) |
| **Nodo workers** | master2 (`tier=compute`) |
| **Estado** | ⏳ Directorio creado, stack.yml pendiente |

---

## Resumen de recursos comprometidos

### master2 (Compute) — Recursos usados aprox.

```
CPUs comprometidas (reservations):
  PostgreSQL: 1.0
  n8n:        1.0
  Jupyter x2: 4.0 + 4.0 = 8.0
  Ollama:     6.0
  ─────────────────────────
  Total:      ~16.0 / 16 CPUs (al límite)

RAM comprometida (reservations):
  PostgreSQL: 0.5 GB
  n8n:        0.5 GB
  Jupyter x2: 8 + 8 = 16 GB
  Ollama:     12 GB
  ─────────────────────────
  Total:      ~29 GB / 32 GB RAM

GPU VRAM:
  Ollama:     hasta 10 GB / 11 GB disponibles
  Jupyter:    comparte con Ollama cuando accede GPU
```

> **Implicación**: Airflow workers y Spark workers en master2 deben usar recursos mínimos o coordinar con los servicios existentes. Revisar `limits` vs `reservations` antes de desplegar.

### master1 (Control) — Recursos usados aprox.

```
CPUs comprometidas: ~3–4 / 8 CPUs (abundante disponibilidad)
RAM comprometida:   ~5–6 GB / 32 GB (muy holgado)
```

> master1 tiene recursos más que suficientes para Airflow web/scheduler, Spark master y servicios de observabilidad (Prometheus + Grafana si se agregan).
