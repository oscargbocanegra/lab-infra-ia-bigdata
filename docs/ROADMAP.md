# Lab Infrastructure — Roadmap

> Last updated: 2026-04-07

---

## Current Status: Phase 10 Complete ✅

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
Phase 9A:  Data Governance (OpenMetadata + Great Expectations)    ✅
Phase 9B:  Agents & Evals (LangGraph + RAGAS + Benchmarks)        ✅
Phase 10:  CI/CD (GitHub Actions + self-hosted runner + tests)    ✅
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

## Phase 9A: Data Governance ✅

### 9A.1 OpenMetadata 1.4 — Data Catalog

**Stack:** `stacks/data/13-openmetadata/stack.yml`  
**ADR:** `docs/adrs/ADR-007-data-governance-openmetadata.md`  
**Architecture:** `docs/architecture/GOVERNANCE.md`

- [x] ADR written and approved
- [x] `stack.yml` created (MySQL 8 + OpenMetadata Server + OpenSearch integration)
- [x] `scripts/governance/setup-governance.sh` — secrets + dirs + MinIO buckets + GE base config
- [x] Stack deployed on master1 — all 3 services `1/1` (openmetadata-es, openmetadata-mysql, openmetadata-server)
- [x] Root cause fix: `ELASTICSEARCH_*` env vars (not `SEARCH_*`) — commit `b4c351b`
- [x] Search indices created: `SearchIndexingApplication` — status=success, 20 records
- [x] Service created: `lab-postgres` (DatabaseService — Postgres 5432 on master2)
- [x] Service created: `lab-minio` (StorageService — S3-compatible MinIO on master2)
- [x] Ingestion pipeline created: `lab-postgres-metadata-ingestion` (DatabaseMetadata)
- [x] Ingestion pipeline created: `lab-minio-metadata-ingestion` (StorageMetadata)

**Notes:**
- `PIPELINE_SERVICE_CLIENT_CLASS_NAME: NoopClient` — standard Airflow image lacks `openmetadata-managed-apis` plugin.
  Ingestion pipelines are NOT triggered via OM API — they are executed directly by Airflow DAGs using the OM Python SDK.
- `JWTTokenExpiry: "Unlimited"` is the correct enum value for the bot token generation endpoint.
- MinIO service in OpenMetadata uses VIP IP `10.0.2.28:9000` — boto3 rejects hostnames with underscores as endpoint URLs.

### 9A.2 Great Expectations — Data Quality

- [x] `governance_bronze_validate` DAG — validates raw file ingestion (bronze layer)
- [x] `governance_silver_validate` DAG — validates silver → gold promotion
- [x] DAGs deployed: both active, `has_import_errors: false`, boto3/pandas installed via `_PIP_ADDITIONAL_REQUIREMENTS`
- [x] Airflow REST API basic_auth enabled (`AIRFLOW__API__AUTH_BACKENDS`)
- [x] Sample data seeded: `bronze/sales/2026-04-06/sales_20260406.csv` (10 rows)
- [x] `governance_bronze_validate` triggered and **succeeded** — all 4 tasks PASS
- [x] Validation result saved: `governance/ge-results/sales/2026-04-06/result.json`
- [ ] OpenMetadata ↔ GE result publishing via OM Python SDK (Phase 9B scope)

---

## Phase 9B: Agents & Evals ⏳

**ADR:** `docs/adrs/ADR-008-agents-evals-langgraph.md`

### 9B.1 Hybrid LangGraph Agent

**Stack:** `stacks/ai-ml/06-agent/stack.yml`  
**URL:** `https://agent.sexydad`

Architecture:
```
User Question
      │
      ▼
 Router Node (gemma3:4b) → decides: rag | data | both
      │
  ┌───┴───┐
  ▼       ▼
RAG Node  Data Node
(Qdrant)  (Postgres SQL via qwen2.5-coder:7b)
  │       │
  └───┬───┘
      ▼
 Synthesizer (gemma3:4b) → final answer
      │
 Trace Writer → OpenSearch agent-traces-YYYY.MM.DD
```

- [x] Build image on master1: `docker build -t lab-agent:latest .`
- [x] Deploy: `docker stack deploy -c stacks/ai-ml/06-agent/stack.yml agent`
- [x] Verify: `https://agent.sexydad/docs`

**Models used:**
- `gemma3:4b` — routing + synthesis (4.3B, RTX 2080 Ti, fast)
- `qwen2.5-coder:7b` — SQL generation for Data Tool
- `nomic-embed-text` — RAG embeddings (768d, Qdrant collection: `lab_documents_nomic`)

### 9B.2 Evaluation Pipelines (Airflow DAGs)

| DAG | Schedule | Purpose |
|-----|----------|---------|
| `agent_synthetic_dataset` | Sunday 02:00 | Generate Q&A pairs with gemma3:4b → save to MinIO |
| `agent_ragas_eval` | Sunday 04:00 | LLM-as-judge RAGAS metrics → OpenSearch |
| `agent_model_benchmark` | Sunday 06:00 | Benchmark all Ollama models → leaderboard |

**RAGAS metrics tracked:**
- `faithfulness` — are answers grounded in context?
- `answer_relevancy` — is the answer on-topic?
- `context_precision` — are retrieved chunks relevant?

**Benchmark categories:** instruction_following, reasoning, coding (15 questions total)

**Storage pattern:**
```
governance/
├── ragas-datasets/YYYY-MM-DD/dataset.json   ← synthetic Q&A
├── ragas-results/YYYY-MM-DD/results.json    ← scored records + aggregate
└── benchmarks/YYYY-MM-DD/results.json       ← model leaderboard
```

- [x] Deploy Airflow DAGs to both master1 + master2 `/srv/fastdata/airflow/dags/`
- [x] Redeploy Airflow stack (adds httpx + psycopg2 to pip requirements)
- [x] Trigger `agent_synthetic_dataset` manually for first run — **SUCCESS** (2026-04-07, dataset saved to MinIO)
- [x] Trigger `agent_ragas_eval` after dataset is ready — **SUCCESS** (faithfulness, answer_relevancy, context_precision computed)
- [x] Trigger `agent_model_benchmark` for initial model scores — **SUCCESS** (qwen2.5-coder:7b, gemma3:4b, qwen3.5 benchmarked)

### 9B.3 Agent Observability

- [x] OpenSearch index pattern: `agent-traces-*` (auto-created by agent on first query)
- [x] OpenSearch index pattern: `ragas-results-*` (auto-created by eval DAG, data written 2026-04-07)
- [x] OpenSearch index pattern: `model-benchmarks-*` (auto-created by benchmark DAG, data written 2026-04-07)
- [x] Grafana dashboard: Agent Overview — `dashboards/agent-observability.json` (latency, tool distribution, RAGAS trend, model leaderboard). Requires Grafana stack redeploy.
- [ ] OpenSearch Dashboards: `top_queries-*` index pattern → use `source.query.bool.filter.range.@timestamp.from` as time field

---

## Phase 10: CI/CD ✅

**Runbook:** `docs/runbooks/cicd.md`

### 10.1 Continuous Integration (GitHub cloud runners)

**Workflow:** `.github/workflows/ci.yml`

- Runs on every push and pull request to `main`
- 3 parallel jobs: `lint` (ruff), `test-rag-api` (Python 3.11), `test-agent` (Python 3.12)
- No secrets required — safe for public repo
- Coverage: 20 tests total (9 for rag-api, 11 for agent)

**Test structure:**
```
tests/
├── rag_api/
│   ├── conftest.py         — mock Qdrant, Postgres, MinIO fixtures
│   ├── test_health.py      — 4 tests (ok, degraded states, schema)
│   └── test_ingest.py      — 5 tests (extract_text, rag_prompt, ingest flow)
└── agent/
    ├── conftest.py         — mock Qdrant, Postgres, OpenSearch, Ollama fixtures
    ├── test_health.py      — 3 tests (ok, version, no auth)
    └── test_router.py      — 8 tests (route_condition, router_node logic)
```

### 10.2 Continuous Deployment (self-hosted runner on master1)

**Workflow:** `.github/workflows/deploy.yml`

- Runs on push to `main` only
- Runner: `self-hosted` tag (GitHub Actions runner installed on master1)
- Steps: build both images → tag `latest` + `sha-<short>` → push to Docker Hub → `docker stack deploy` both stacks → health check

**Images published:**
| Image | Docker Hub |
|---|---|
| `giovannotti/lab-rag-api` | `:latest` + `:sha-XXXXXXX` |
| `giovannotti/lab-agent` | `:latest` + `:sha-XXXXXXX` |

**GitHub Secrets required:**
| Secret | Value |
|---|---|
| `DOCKER_USERNAME` | `giovannotti` |
| `DOCKER_TOKEN` | Docker Hub Personal Access Token |

### 10.3 Code Quality

**Tool:** `ruff` (lint + format, replaces flake8 + black + isort)  
**Config:** `pyproject.toml` (root)  
**Python targets:** 3.11 (rag-api) + 3.12 (agent)

- [x] `pyproject.toml` created with ruff + pytest config
- [x] `ci.yml` — lint + test on every push/PR
- [x] `deploy.yml` — build + push + deploy on push to main
- [x] 20 unit tests (all services mocked — no real infrastructure needed)
- [x] `stack.yml` files updated to use `giovannotti/*` Docker Hub images
- [x] Self-hosted runner install instructions in `docs/runbooks/cicd.md`

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
| 2026-04-07 | Phase 10 complete ✅ — GitHub Actions CI/CD (ci.yml + deploy.yml), 20 unit tests, pyproject.toml, cicd.md runbook |
| 2026-04-07 | Phase 9B complete ✅ — all 3 eval DAGs confirmed working (synthetic_dataset → ragas_eval → model_benchmark). Results in MinIO + OpenSearch |
| 2026-04-07 | Grafana: Agent Observability dashboard + OpenSearch datasource added to provisioning |
| 2026-04-07 | Fix: Docker overlay DNS for Ollama (http://ollama:11434) — host IPs unreachable from overlay containers |
| 2026-04-07 | Fix: Ollama httpx timeout 60s → 180s to handle gemma3:4b cold start |
| 2026-04-07 | Phase 9B: LangGraph Hybrid Agent (06-agent), 3 evaluation DAGs, ADR-008 |
| 2026-04-07 | Phase 9A complete ✅ — Airflow REST API basic_auth, governance DAGs running, validation results in MinIO |
| 2026-04-07 | OpenMetadata: ingestion pipelines created for lab-postgres + lab-minio via API |
| 2026-04-07 | Fix: boto3 rejects underscore hostnames — use MINIO_ENDPOINT env var (IP fallback) |
| 2026-04-07 | Fix: ELASTICSEARCH_* env vars corrected in OM stack (was SEARCH_* prefix) |
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
