# Roadmap del Laboratorio

> Última actualización: 2026-03-30

---

## Estado actual: Fase 5 completa ✅

```
Fase 1: Base del clúster (Swarm + redes + labels + GPU)          ✅
Fase 2: Storage en master2 (LVM NVMe + datalake HDD)             ✅
Fase 3: Repo IaC + estructura estándar                            ✅
Fase 4: Stacks operativos (Traefik, Portainer, Postgres,
        n8n, JupyterLab x2, Ollama, OpenSearch)                  ✅
Fase 5: Big Data + Automatización (MinIO, Spark, Airflow)         ✅ COMPLETO
Fase 6: Observabilidad + Hardening                                ⏳
```

---

## Fase 5: Big Data + Automatización

### 5.1 MinIO — Object Storage S3-compatible 🔧

**Stack listo en repo**: `stacks/data/12-minio/stack.yml`

**Pendiente en producción**:
- [ ] Crear secrets `minio_access_key` y `minio_secret_key`
- [ ] Crear directorio `/srv/datalake/minio` en master2
- [ ] `docker stack deploy -c stacks/data/12-minio/stack.yml minio`
- [ ] Crear buckets iniciales (ver `runbook_minio.md`)

**Integración con**:
- Spark (s3a:// lectura/escritura de datasets y Delta Lake)
- Airflow (logs remotos + S3Hook en DAGs)
- Jupyter (boto3/s3fs para acceso Python directo)

---

### 5.2 Apache Spark 3.5 — Procesamiento distribuido 🔧

**Stack listo en repo**: `stacks/data/98-spark/stack.yml`

**Pendiente en producción**:
- [ ] MinIO debe estar corriendo primero
- [ ] Crear directorio `/srv/fastdata/spark-tmp` en master2
- [ ] `docker stack deploy -c stacks/data/98-spark/stack.yml spark`
- [ ] Verificar registro del worker en Master UI

**Capacidad del worker**: 10 CPUs / 14 GB RAM (master2)

**Integración con**:
- Jupyter (kernel BigData: PySpark + Delta Lake)
- MinIO (storage s3a://)
- Airflow (SparkSubmitOperator)

---

### 5.3 Apache Airflow 2.9 — Orquestación CeleryExecutor 🔧

**Stack listo en repo**: `stacks/automation/03-airflow/stack.yml`

**Pendiente en producción**:
- [ ] Crear secrets: `pg_airflow_pass`, `airflow_fernet_key`, `airflow_webserver_secret`
- [ ] Crear directorios `/srv/fastdata/airflow/{dags,logs,plugins,redis}` en master1
- [ ] Crear directorios `/srv/fastdata/airflow/{dags,logs,plugins}` en master2
- [ ] `docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow`
- [ ] `docker service scale airflow_airflow_init=1` (solo primera vez)
- [ ] Configurar conexiones en UI: `minio_s3`, `spark_default`
- [ ] Crear DAG de ejemplo

**Arquitectura**:
```
Redis (broker) → Scheduler → Worker (master2)
                ↓
             Webserver (UI)
             Flower (monitor)
```

---

## Fase 6: Observabilidad + Hardening

### 6.1 Observabilidad (Prometheus + Grafana + Loki) ⏳

**Stack propuesto**: `stacks/monitoring/`

```
Prometheus    → scrape Docker + node_exporter + MinIO metrics
node_exporter → métricas OS en ambos nodos (global)
cAdvisor      → métricas containers
Grafana       → dashboards (Docker Swarm, GPU, Disk I/O)
Loki          → logs centralizados
Promtail      → agent de logs (global)
```

**Dashboards prioritarios**:
- [ ] Docker Swarm overview
- [ ] GPU utilization (master2 RTX 2080 Ti)
- [ ] Spark job metrics
- [ ] MinIO throughput + space
- [ ] Alertas: servicio down, OOM, disco > 80%

---

### 6.2 Backups automatizados ⏳

```
Origen (master2)              Destino (master1 o externo)
─────────────────────────── → ────────────────────────────────
/srv/fastdata/postgres          /srv/backups/postgres/
/srv/fastdata/n8n               /srv/backups/n8n/
MinIO buckets (mc mirror)       /srv/backups/minio/
```

**Herramienta**: `restic` (deduplicación + cifrado + retención)

- [ ] Instalar restic en master1
- [ ] Script `scripts/backup/backup_postgres.sh`
- [ ] DAG de Airflow para backup automatizado
- [ ] Runbook `docs/runbooks/runbook_backups.md`

---

### 6.3 Hardening del OS ⏳

- [ ] UFW en master1: permitir solo `:22`, `:80`, `:443` + LAN interna
- [ ] UFW en master2: permitir solo `:22` + `:5432` LAN + Swarm ports
- [ ] SSH hardening: `PasswordAuthentication no`, `PermitRootLogin no`
- [ ] `unattended-upgrades` activado en ambos nodos
- [ ] NTP/chrony verificado

---

## Mejoras de infraestructura identificadas

### DNS wildcard LAN ⏳

**Problema**: cada cliente edita `/etc/hosts` manualmente.
**Solución**: dnsmasq en router o Pi-Hole en LAN:

```bash
# dnsmasq:
address=/sexydad/192.168.80.100
```

---

### Vector Database para RAG ⏳

**Opciones**:
- `Qdrant` (recomendado — Docker image oficial, nativo para Swarm)
- `pgvector` (extensión Postgres — simplifica el stack)

**Nodo**: master2 (cerca de Ollama y Jupyter)

---

### JupyterHub ⏳ (opcional)

**Trade-off**: JupyterHub centraliza gestión de usuarios pero agrega complejidad.
Actualmente los 2 servicios separados son más simples de operar.
Evaluar cuando se agreguen más de 3 usuarios.

---

## Changelog de versiones

| Fecha | Cambio |
|-------|--------|
| 2026-04-03 | jupyter-ai + LSP instalados en JupyterLab — %%JARVIS magic + chat panel via Ollama |
| 2026-04-03 | Ollama upgrade 0.6.1 → 0.19.0 — bug fix GGML parser + puerto 11434 publicado |
| 2026-04-03 | JupyterLab: 3 kernels especializados (LLM, AI/ML, BigData) |
| 2026-03-31 | README principal reescrito en inglés con badges para portfolio |
| 2026-03-30 | Fase 5: MinIO + Spark + Airflow — stacks creados |
| 2026-03-30 | Jupyter: reservations optimizadas + kernel BigData |
| 2026-03-30 | Ollama: versión pineada a 0.6.1 |
| 2026-03-30 | Postgres: DB default neutral + init Airflow |
| 2026-03-30 | Portainer CE 2.21.0 → 2.39.1 |
| 2026-03-30 | Restructuración completa de docs/ |
| 2026-02-04 | OpenSearch 2.19.4 + Dashboards desplegados ✅ |
| 2026-02-03 | Ollama desplegado con GPU ✅ |
| 2026-01-XX | JupyterLab multi-usuario + GPU ✅ |
| 2025-12-XX | Fase 1–4: Swarm, redes, Traefik, Portainer, Postgres, n8n ✅ |
