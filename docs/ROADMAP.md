# Roadmap del Laboratorio

> Última actualización: 2026-03-30

---

## Estado actual: Fase 4 completada ✅

```
Fase 1: Base del clúster (Swarm + redes + labels + GPU)     ✅
Fase 2: Storage en master2 (LVM NVMe + datalake HDD)        ✅
Fase 3: Repo IaC + estructura estándar                       ✅
Fase 4: Stacks operativos (7 servicios)                      ✅
Fase 5: Automatización + Big Data (PENDIENTE)                ⏳
Fase 6: Observabilidad + Hardening (PENDIENTE)               ⏳
```

---

## Fase 5: Automatización + Big Data

### 5.1 Airflow — Orquestación de pipelines ⏳

**Objetivo**: Programar y orquestar pipelines de datos (ingesta, procesamiento, ML training).

**Arquitectura**:
- Webserver + Scheduler → master1 (control plane)
- Workers → master2 (compute, acceso a GPU y datalake)
- Metadata DB → PostgreSQL en master2 (nueva DB: `airflow`)

**Tareas**:
- [ ] Crear DB `airflow` y usuario en Postgres
- [ ] Crear secret `airflow_fernet_key`
- [ ] Crear secret `airflow_admin_pass`
- [ ] Crear directorio `/srv/fastdata/airflow` en master2
- [ ] Crear `stacks/automation/03-airflow/stack.yml`
- [ ] Configurar dominio `airflow.sexydad`
- [ ] Crear runbook `docs/runbooks/runbook_airflow.md`
- [ ] DAG de ejemplo: pipeline de ingesta de datos

**Dependencias**: Postgres ✅, Traefik ✅

---

### 5.2 Spark — Procesamiento distribuido ⏳

**Objetivo**: Procesamiento de datasets grandes con Spark (batch + SQL + MLlib).

**Arquitectura**:
- Spark Master → master2 (mejor latencia con workers)
- Spark Worker → master2 (compute principal)
- Spark Worker secundario → master1 (opcional, solo CPU/HDD)
- Submit desde Jupyter o Airflow DAGs

**Tareas**:
- [ ] Crear `stacks/data/98-spark/stack.yml`
- [ ] Configurar integración Jupyter ↔ Spark (SparkContext desde notebooks)
- [ ] Configurar acceso a `/srv/datalake/datasets` desde Spark workers
- [ ] Crear runbook `docs/runbooks/runbook_spark.md`
- [ ] Notebook de ejemplo: lectura Parquet + operaciones Spark

**Dependencias**: Jupyter ✅, storage datalake ✅

---

## Fase 6: Observabilidad + Hardening

### 6.1 Observabilidad (Prometheus + Grafana + Loki) ⏳

**Objetivo**: Métricas de nodos, containers y aplicaciones. Logs centralizados.

**Stack propuesto**:
```yaml
Prometheus    → scrape metrics de Docker + node_exporter
node_exporter → métricas OS/hardware en ambos nodos (global)
cAdvisor      → métricas de containers
Grafana       → dashboards
Loki          → logs centralizados
Promtail      → agent de logs (global)
```

**Nodo**: master1 (tier=control) — servicios ligeros
**Storage**: `/srv/fastdata/prometheus`, `/srv/fastdata/grafana`, `/srv/fastdata/loki`

**Tareas**:
- [ ] Crear `stacks/monitoring/` con stack completo
- [ ] Dashboard Grafana: Docker Swarm overview
- [ ] Dashboard Grafana: GPU utilization (master2)
- [ ] Dashboard Grafana: Disk I/O (NVMe vs HDD)
- [ ] Alertas básicas: servicio down, OOM, disco > 80%

---

### 6.2 Backups automatizados ⏳

**Objetivo**: Backup automático de datos críticos con política de retención.

**Plan**:
```
Fuente (master2)                 Destino (master1)
─────────────────────────────    ────────────────────────────
/srv/fastdata/postgres     →     /srv/backups/postgres/
/srv/fastdata/n8n          →     /srv/backups/n8n/
/srv/fastdata/opensearch   →     /srv/backups/opensearch/
                                 (vía rsync o restic)
```

**Herramienta recomendada**: `restic` (deduplicación, cifrado, retención automática)

**Tareas**:
- [ ] Instalar restic en master1
- [ ] Script `scripts/backup/backup_postgres.sh`
- [ ] Script `scripts/backup/backup_n8n.sh`
- [ ] Cron job en master1 (o DAG de Airflow cuando esté listo)
- [ ] Script de restore + prueba de restore documentada
- [ ] Runbook `docs/runbooks/runbook_backups.md`

---

### 6.3 Hardening del OS ⏳

**Objetivo**: Reducir superficie de ataque en ambos nodos.

**Tareas**:
- [ ] UFW en master1: permitir solo :22, :80, :443 + LAN interna
- [ ] UFW en master2: permitir solo :22 + :5432 LAN + Swarm ports
- [ ] NTP/chrony verificado y activo en ambos nodos
- [ ] Actualizaciones de seguridad programadas (unattended-upgrades)
- [ ] SSH hardening: `PasswordAuthentication no`, `PermitRootLogin no`
- [ ] Documentar en `docs/hosts/master1/` y `docs/hosts/master2/`

---

## Mejoras de infraestructura identificadas

### DNS local (mejora de UX) ⏳

**Problema**: Cada cliente debe editar su `/etc/hosts` para resolver `*.sexydad`.
**Solución**: Configurar wildcard DNS en el router o un Pi-Hole/dnsmasq en la LAN.

```
# Configuración en dnsmasq (ejemplo):
address=/sexydad/192.168.80.100
```

**Beneficio**: Cualquier dispositivo de la LAN resuelve `*.sexydad` sin configuración.

---

### Versión fija para Ollama ⏳

**Problema**: `ollama/ollama:latest` puede cambiar de comportamiento entre deploys.
**Acción**: Pinear a una versión específica (ej: `ollama/ollama:0.5.x`) tras evaluar la release.

---

### Vector Database ⏳

**Objetivo**: Agregar una base de datos vectorial para RAG (Retrieval Augmented Generation).

**Opciones**:
- `Qdrant` (recomendado — nativo para Swarm, Docker image oficial)
- `Chroma` (simple, bueno para prototipado rápido)
- `pgvector` (extensión de Postgres — si quieres simplificar el stack)

**Nodo**: master2 (cerca de Ollama y Jupyter para latencia mínima)

---

### Jupyter Hub (opcional) ⏳

**Problema**: Actualmente hay 2 servicios separados (ogiovanni + odavid) con configuración duplicada.
**Solución**: JupyterHub con spawner para gestionar múltiples usuarios desde un único servicio.
**Trade-off**: Más complejidad de setup; los usuarios individuales son más simples de operar.

---

## Changelog de versiones

| Fecha | Cambio |
|-------|--------|
| 2026-03-30 | Portainer CE 2.21.0 → 2.39.1 |
| 2026-03-30 | Restructuración completa de docs/ |
| 2026-02-04 | OpenSearch 2.19.4 + Dashboards desplegados ✅ |
| 2026-02-03 | Ollama desplegado con GPU ✅ |
| 2026-01-XX | JupyterLab multi-usuario + GPU ✅ |
| 2025-12-XX | Fase 1-4: Swarm, redes, Traefik, Portainer, Postgres, n8n ✅ |
