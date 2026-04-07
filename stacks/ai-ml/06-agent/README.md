# Lab Hybrid Agent — LangGraph RAG + Data Agent

Hybrid LangGraph agent that answers natural-language questions using two tools: semantic RAG search and natural-language-to-SQL.

## Overview

| Property | Value |
|---|---|
| Image | `giovannotti/lab-agent:latest` (Docker Hub) |
| Node | master1 (`tier=control`) |
| URL | `https://agent.sexydad` |
| Swagger UI | `https://agent.sexydad/docs` |
| Framework | FastAPI + LangGraph + Python 3.12 |
| CI/CD | GitHub Actions — `.github/workflows/ci.yml` + `deploy.yml` |

## Architecture

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

## Models

| Model | Role | Size |
|---|---|---|
| `gemma3:4b` | Router + Synthesizer | 4.3B |
| `qwen2.5-coder:7b` | SQL generation (Data tool) | 7B |
| `nomic-embed-text` | RAG embeddings (768d) | — |

All inference runs on **master2** (RTX 2080 Ti) via Ollama.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/chat` | Hybrid agent query (RAG + Data) |
| `GET` | `/health` | Liveness probe |

## Infrastructure Reuse

| Backend | Purpose | Stack |
|---|---|---|
| **Qdrant** | Semantic document search | `ai-ml/03-qdrant` |
| **Postgres/pgvector** | NL→SQL structured queries | `core/02-postgres` |
| **OpenSearch** | Agent trace sink | `monitoring/04-opensearch` |
| **Ollama** | LLM inference + embeddings | `ai-ml/02-ollama` |

## CI/CD

This service is built and deployed automatically via GitHub Actions.

| Workflow | Trigger | Runner | What it does |
|---|---|---|---|
| `ci.yml` | push / PR to any branch | GitHub cloud | `ruff` lint + 11 pytest tests |
| `deploy.yml` | push to `main` | self-hosted (master1) | build → push `giovannotti/lab-agent:{latest,sha-XXXX}` → `docker stack deploy` |

Tests live in `tests/agent/`. They mock Qdrant, Postgres, OpenSearch, and Ollama — no real services needed.

## Deployment

### Prerequisites

```bash
# Secrets (must exist before deploying)
echo "your-qdrant-key"  | docker secret create qdrant_api_key -
echo "your-pg-password" | docker secret create pg_rag_pass -
```

### Deploy (automated via CI/CD)

On every push to `main`, GitHub Actions builds and pushes the image, then runs:

```bash
docker stack deploy -c stacks/ai-ml/06-agent/stack.yml agent --with-registry-auth
```

### Manual deploy (if needed)

```bash
docker pull giovannotti/lab-agent:latest
docker stack deploy -c stacks/ai-ml/06-agent/stack.yml agent --with-registry-auth
```

## Observability

- **Traces:** OpenSearch index `agent-traces-YYYY.MM.DD` — every request logged with latency, tool used, model
- **Logs:** json-file → Fluent Bit → OpenSearch `docker-logs-YYYY.MM.DD`
- **Grafana:** Agent Overview dashboard (`dashboards/agent-observability.json`)

## Evaluation DAGs (Airflow)

| DAG | Schedule | Purpose |
|-----|----------|---------|
| `agent_synthetic_dataset` | Sunday 02:00 | Generate Q&A pairs with gemma3:4b → MinIO |
| `agent_ragas_eval` | Sunday 04:00 | LLM-as-judge RAGAS metrics → OpenSearch |
| `agent_model_benchmark` | Sunday 06:00 | Benchmark all Ollama models → leaderboard |

RAGAS metrics: `faithfulness`, `answer_relevancy`, `context_precision`.

## ADR

See `docs/adrs/ADR-008-agents-evals-langgraph.md`.
