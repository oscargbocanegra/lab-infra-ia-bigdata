# RAG API — FastAPI RAG Orchestration Service

REST API that orchestrates the complete Retrieval-Augmented Generation (RAG) workflow.

## Overview

| Property | Value |
|---|---|
| Image | `giovannotti/lab-rag-api:latest` (Docker Hub) |
| Node | master1 (`tier=control`) |
| URL | `https://rag-api.sexydad` |
| Swagger UI | `https://rag-api.sexydad/docs` |
| Framework | FastAPI + Python 3.11 |
| CI/CD | GitHub Actions — `.github/workflows/ci.yml` + `deploy.yml` |

## Architecture

```
User / Client
     │
     ▼
RAG API (FastAPI)
     │
     ├── /ingest → MinIO (raw file) + Ollama (embed) + Qdrant + pgvector
     │
     └── /query  → Ollama (embed question) → Qdrant (ANN search)
                   → Build context → Ollama LLM (generate answer)
```

## Infrastructure Reuse

This service **reuses all existing cluster infrastructure**:

| Backend | Purpose | Stack |
|---|---|---|
| **Qdrant** | Primary vector store (semantic search) | `ai-ml/03-qdrant` |
| **Postgres/pgvector** | Document metadata + hybrid filtering | `core/02-postgres` (DB: `rag`) |
| **MinIO** | Raw document storage (S3) | `data/12-minio` |
| **Ollama** | Embeddings + LLM inference | `ai-ml/02-ollama` |

No new databases are introduced. Everything uses existing cluster services.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/ingest/` | Upload and index a document |
| `POST` | `/query/` | RAG query (synchronous) |
| `POST` | `/query/stream` | RAG query with SSE streaming |
| `GET` | `/collections/` | List Qdrant collections |
| `GET` | `/collections/{name}` | Collection details |
| `DELETE` | `/collections/{name}` | Delete a collection |
| `GET` | `/health` | Liveness probe |

## Embedding Models

| Model | Dimensions | Use Case |
|---|---|---|
| `nomic-embed-text` | 768 | Default — best quality/size ratio |
| `bge-m3` | 1024 | Multilingual (EN + ES) |

## RAG Pipeline Details

### Ingestion (`POST /ingest/`)

1. Upload raw file to MinIO bucket `rag-documents`
2. Extract text (PDF → pypdf, DOCX → python-docx, TXT/MD → direct)
3. Chunk with `RecursiveCharacterTextSplitter` (size=1000, overlap=150)
4. Batch embed all chunks via Ollama `/api/embed`
5. Upsert vectors into Qdrant (`lab_documents_nomic` collection)
6. Store metadata + chunks in Postgres `documents` table
7. Store vectors in Postgres `embeddings` table (pgvector HNSW index)

### Query (`POST /query/`)

1. Embed the question via Ollama
2. ANN search in Qdrant (top-K=5 by default)
3. Filter by `collection` payload field
4. Build RAG prompt with retrieved chunks
5. Generate answer via Ollama LLM (`qwen2.5:7b` by default)
6. Return answer + sources with scores

## CI/CD

This service is built and deployed automatically via GitHub Actions.

| Workflow | Trigger | Runner | What it does |
|---|---|---|---|
| `ci.yml` | push / PR to any branch | GitHub cloud | `ruff` lint + 9 pytest tests |
| `deploy.yml` | push to `main` | self-hosted (master1) | build → push `giovannotti/lab-rag-api:{latest,sha-XXXX}` → `docker stack deploy` |

Tests live in `tests/rag_api/`. They mock Qdrant, Postgres, and MinIO — no real services needed.

## Deployment

### Prerequisites

```bash
# Secrets (create once)
echo "your-password" | docker secret create pg_rag_pass -
echo "your-qdrant-key" | docker secret create qdrant_api_key -
# minio_access_key and minio_secret_key must already exist (from minio stack)
```

### Deploy (automated via CI/CD)

On every push to `main`, GitHub Actions builds and pushes the image, then runs:

```bash
docker stack deploy -c stacks/ai-ml/04-rag-api/stack.yml rag-api --with-registry-auth
```

### Manual deploy (if needed)

```bash
docker pull giovannotti/lab-rag-api:latest
docker stack deploy -c stacks/ai-ml/04-rag-api/stack.yml rag-api --with-registry-auth
```

## Configuration

All configuration is via environment variables. Key variables:

| Variable | Default | Description |
|---|---|---|
| `OLLAMA_BASE_URL` | `http://<master2-ip>:11434` | Ollama endpoint |
| `EMBED_MODEL` | `nomic-embed-text` | Embedding model |
| `LLM_MODEL` | `qwen2.5:7b` | LLM for answer generation |
| `QDRANT_URL` | `http://qdrant:6333` | Qdrant REST endpoint |
| `CHUNK_SIZE` | `1000` | Characters per chunk |
| `CHUNK_OVERLAP` | `150` | Overlap between chunks |
| `TOP_K` | `5` | Chunks to retrieve per query |

## Logs

Container logs → Fluent Bit → OpenSearch index `docker-logs-YYYY.MM.DD`.
