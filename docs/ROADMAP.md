# Lab Infrastructure — Roadmap

> Last updated: 2026-04-06

---

## Current Status: Phase 9A in progress ⏳

```
Phase 1: Cluster base (Swarm + networks + labels + GPU)           ✅
Phase 2: Storage on master2 (LVM NVMe + datalake HDD)            ✅
Phase 3: IaC repo + standard structure                            ✅
Phase 4: Operational stacks (Traefik, Portainer, Postgres,
         n8n, JupyterLab x2, Ollama, OpenSearch)                  ✅
Phase 5: Big Data + Automation (MinIO, Spark, Airflow)            ✅
Phase 6.1: Centralized logs (Fluent Bit → OpenSearch)             ✅
Phase 6.2: Metrics (Prometheus + Grafana + exporters)             ✅
Phase 7:   Hardening + Backups                                    ✅
Phase 8:   Vector DB + RAG + Chat UI                              ✅
Phase 9A:  Data Governance (OpenMetadata + Great Expectations)    ⏳
Phase 9B:  Agents & Evals (LangGraph + RAGAS + Benchmarks)        ⏳
```

---

## Phase 5: Big Data + Automation

### 5.1 MinIO — S3-compatible Object Storage ✅

**Stack:** `stacks/data/12-minio/stack.yml`

**Integration with:**
- Spark (s3a:// read/write for datasets and Delta Lake)
- Airflow (remote logs + S3Hook in DAGs)
- Jupyter (boto3/s3fs for direct Python access)

---

### 5.2 Apache Spark 3.5 — Distributed Processing ✅

**Stack:** `stacks/data/98-spark/stack.yml`

**Worker capacity:** 10 CPUs / 14 GB RAM (master2)

**Integration with:**
- Jupyter (BigData kernel: PySpark + Delta Lake)
- MinIO (storage s3a://)
- Airflow (SparkSubmitOperator)

---

### 5.3 Apache Airflow 2.9 — CeleryExecutor Orchestration ✅

**Stack:** `stacks/automation/03-airflow/stack.yml`

**Architecture:**
```
Redis (broker) → Scheduler → Worker (master2)
                ↓
             Webserver (UI)
             Flower (monitor)
```

---

## Phase 6: Observability

### 6.1 Centralized Logs (Fluent Bit → OpenSearch) ✅

**Stack:** `stacks/monitoring/00-fluent-bit/stack.yml`  
**Setup script:** `scripts/observability/setup-opensearch-logs.sh`

**Architecture:**
```
master1 containers ──┐
                     ├── Fluent Bit (global) ──► OpenSearch ──► Dashboards
master2 containers ──┘

Index:     docker-logs-YYYY.MM.DD  (daily rollover)
Retention: 7 days → auto-delete via ISM policy
```

**Deploy:**
```bash
# 1. Configure OpenSearch (run once from Swarm manager)
bash scripts/observability/setup-opensearch-logs.sh

# 2. Create state directories on both nodes
mkdir -p /srv/fastdata/fluent-bit                                        # manager node
ssh <user>@<worker-node> "mkdir -p /srv/fastdata/fluent-bit"             # worker node

# 3. Deploy
docker stack deploy -c stacks/monitoring/00-fluent-bit/stack.yml fluent-bit
```

---

### 6.2 Metrics (Prometheus + Grafana) ✅

**Stacks:** `stacks/monitoring/01-prometheus/` + `stacks/monitoring/02-grafana/` + `stacks/monitoring/03-nvidia-exporter/`  
**Setup script:** `scripts/observability/setup-prometheus.sh`

**Architecture:**
```
node_exporter  (master1) ──┐
node_exporter  (master2) ──┤
cAdvisor       (master1) ──┤── Prometheus ──► Grafana
cAdvisor       (master2) ──┤       ▲
nvidia-exporter(master2) ──┤       │ self-monitoring
traefik        (master1) ──┘

Retention: 15 days (TSDB on /srv/fastdata/prometheus)
```

**Services deployed:**
- `prometheus` — TSDB + scrape engine (control node) — `prom/prometheus:v2.53.5`
- `node-exporter` — OS metrics, master1 — `prom/node-exporter:v1.10.2`
- `node-exporter-compute` — OS metrics, master2 — `prom/node-exporter:v1.10.2`
- `cadvisor` — container metrics, master1 — `ghcr.io/google/cadvisor:v0.56.2`
- `cadvisor-compute` — container metrics, master2 — `ghcr.io/google/cadvisor:v0.56.2`
- `nvidia-exporter` — NVIDIA RTX 2080 Ti metrics, master2 — `utkuozdemir/nvidia_gpu_exporter:1.4.1`
- `grafana` — dashboards (auto-provisioned with Prometheus datasource) — `grafana/grafana:11.6.14`

**Recommended Grafana dashboards (import by ID):**
- `1860` — Node Exporter Full (OS metrics)
- `14282` — cAdvisor (container metrics)
- `14574` — NVIDIA GPU exporter
- `17346` — Traefik

**Deploy:**
```bash
# 1. Run setup script (creates dirs + Swarm Secrets interactively)
bash scripts/observability/setup-prometheus.sh

# 2. Redeploy Traefik (adds metrics endpoint + new secrets)
docker stack deploy -c stacks/core/00-traefik/stack.yml traefik

# 3. Deploy Prometheus
docker stack deploy -c stacks/monitoring/01-prometheus/stack.yml prometheus

# 4. Deploy NVIDIA GPU exporter
docker stack deploy -c stacks/monitoring/03-nvidia-exporter/stack.yml nvidia-exporter

# 5. Deploy Grafana
docker stack deploy -c stacks/monitoring/02-grafana/stack.yml grafana
```

---

## Phase 7: Hardening + Backups ✅

### 7.1 Automated Backups ✅

**Tool:** `restic` (deduplication + encryption + retention)

**Implemented:**
- [x] restic installed on master1 and master2
- [x] Restic repo initialized in MinIO bucket `backups/master2` (s3 backend)
- [x] Script `scripts/hardening/restic-backup.sh` — daily snapshots of postgres + n8n data
- [x] Cron job on master2: daily at 02:00 (`/etc/cron.d/restic-backup`)
- [x] First snapshot verified: `cfbae982` (90.5 MiB — postgres + n8n data)

**Notes:**
- MinIO has no host port binding — restic connects via `localhost:9000` from master2 only
- Env file `/etc/restic/env` on master2 contains MinIO credentials (chmod 600)
- Restic password stored in `/etc/restic/password` on master2 (chmod 600)

---

### 7.2 OS Hardening ✅

- [x] UFW on master1: `:22`, `:80`, `:443` open; Swarm ports from master2 only; DOCKER-USER chain
- [x] UFW on master2: `:22` open; `:5432` + `:9000` + Swarm ports from master1 only; DOCKER-USER chain
- [x] SSH hardening both nodes: `PasswordAuthentication no`, `AllowGroups sshusers`
- [x] `sshusers` group created on both nodes; `<admin-user>` and `<second-user>` added
- [x] `<second-user>` authorized_keys configured on both nodes
- [x] PostgreSQL personal roles: `<admin-user>` and `<second-user>` created as SUPERUSER

### 7.3 TLS Cert Rotation ✅

- [x] Script `scripts/hardening/cert-rotate.sh` — checks cert expiry, renews if < 30 days
- [x] Cron job on master1: weekly Sunday 03:00 (`/etc/cron.d/cert-rotate`)

---

## Phase 9A: Data Governance ⏳

### 9A.1 OpenMetadata 1.4 — Data Catalog

**Stack:** `stacks/data/13-openmetadata/stack.yml`  
**ADR:** `docs/adrs/ADR-007-data-governance-openmetadata.md`  
**Architecture:** `docs/architecture/GOVERNANCE.md`

- [x] ADR written and approved
- [x] `stack.yml` created (MySQL 8 + OpenMetadata Server + OpenSearch integration)
- [x] `scripts/governance/setup-governance.sh` — secrets + dirs + MinIO buckets + GE base config
- [x] Stack deployed on master1 — all 3 services `1/1` (openmetadata-es, openmetadata-mysql, openmetadata-server)
- [ ] Connectors configured: Postgres, MinIO, Airflow

### 9A.2 Great Expectations — Data Quality

- [x] `governance_bronze_validate` DAG — validates raw file ingestion
- [x] `governance_silver_validate` DAG — validates silver → gold promotion
- [ ] DAGs deployed and verified in Airflow UI
- [ ] OpenMetadata ↔ GE result publishing via OM Python SDK

---

## Phase 9B: Agents & Evals ⏳

- [ ] LangGraph agents integrated with Ollama + Qdrant
- [ ] Batch evaluation pipelines for RAG quality (RAGAS metrics)
- [ ] Model benchmarks (MMLU, coding benchmarks on local models)
- [ ] Agent observability via OpenSearch + Grafana dashboards

---

## Infrastructure Improvements

### LAN Wildcard DNS ⏳

**Problem:** Every LAN client edits `/etc/hosts` manually.  
**Solution:** dnsmasq on router or Pi-Hole on LAN:

```bash
# dnsmasq:
address=/sexydad/<master1-ip>
```

---

### Vector Database for RAG ⏳

**Options:**
- `Qdrant` (recommended — official Docker image, Swarm-native)
- `pgvector` (Postgres extension — simpler stack)

**Node:** master2 (co-located with Ollama and Jupyter)

---

### JupyterHub ⏳ (optional)

**Trade-off:** JupyterHub centralizes user management but adds complexity.  
Current 2 separate services are simpler to operate.  
Re-evaluate when more than 3 users are needed.

---

## Changelog

| Date | Change |
|------|--------|
| 2026-04-06 | Phase 9A: Data governance foundations — OpenMetadata stack, GE DAGs, ADR-007, GOVERNANCE.md |
| 2026-04-05 | Phase 7: SSH hardening (both nodes), UFW + DOCKER-USER chains, PostgreSQL personal roles, restic backup to MinIO, cert rotation cron |
| 2026-04-03 | Phase 6.2: Prometheus + Grafana + node_exporter + cAdvisor + NVIDIA GPU exporter deployed |
| 2026-04-03 | Traefik: added `--metrics.prometheus` on port 8082, `prometheus_basicauth` secret |
| 2026-04-03 | Phase 6.1: Fluent Bit → OpenSearch centralized logs + ISM 7d retention |
| 2026-04-03 | Ollama upgrade 0.6.1 → 0.19.0 — GGML parser fix + port 11434 published |
| 2026-04-03 | JupyterLab: 3 specialized kernels (LLM, AI/ML, BigData) |
| 2026-03-31 | Main README rewritten in English with portfolio badges |
| 2026-03-30 | Phase 5: MinIO + Spark + Airflow — stacks created and deployed |
| 2026-03-30 | Jupyter: optimized resource reservations + BigData kernel |
| 2026-03-30 | Ollama: version pinned to 0.6.1 |
| 2026-03-30 | Postgres: neutral default DB + Airflow init |
| 2026-03-30 | Portainer CE 2.21.0 → 2.39.1 |
| 2026-03-30 | Full docs/ restructure |
| 2026-02-04 | OpenSearch 2.19.4 + Dashboards deployed ✅ |
| 2026-02-03 | Ollama deployed with GPU ✅ |
| 2026-01-XX | JupyterLab multi-user + GPU ✅ |
| 2025-12-XX | Phase 1–4: Swarm, networks, Traefik, Portainer, Postgres, n8n ✅ |
