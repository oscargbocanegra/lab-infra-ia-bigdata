# Qdrant — Vector Database

High-performance vector similarity search engine for RAG pipelines.

## Overview

| Property | Value |
|---|---|
| Image | `qdrant/qdrant:v1.13.4` |
| Node | master1 (`tier=control`) |
| Web UI | `https://qdrant.sexydad` |
| REST API | `http://qdrant:6333` (internal) |
| gRPC API | `http://qdrant:6334` (internal) |
| Storage | `/srv/fastdata/qdrant` (bind mount) |
| Auth | API key via `qdrant_api_key` secret |

## Purpose

Qdrant is the **primary semantic search backend** for all RAG pipelines in the lab. It stores dense vector embeddings and provides fast Approximate Nearest Neighbor (ANN) search using HNSW indexes.

### Why Qdrant over pgvector alone?

| Feature | Qdrant | pgvector |
|---|---|---|
| Dedicated vector index | HNSW optimized | HNSW via extension |
| Payload filtering | ✅ Native | Via WHERE clause |
| Sparse + dense hybrid | ✅ Built-in | Manual |
| Web UI | ✅ Built-in | None |
| Scale target | Millions of vectors | Hundreds of thousands |

Both are used in this lab: **Qdrant** for semantic search, **pgvector** (in the existing Postgres) for metadata + relational filtering.

## Collections

| Collection | Model | Dimensions | Distance |
|---|---|---|---|
| `lab_documents_nomic` | nomic-embed-text | 768 | Cosine |
| `lab_documents_bge` | bge-m3 | 1024 | Cosine |

Collections are auto-created by the RAG API on startup.

## Deployment

### Prerequisites

```bash
# Create persistent storage directory (master1)
mkdir -p /srv/fastdata/qdrant

# Create API key secret
echo "your-api-key" | docker secret create qdrant_api_key -
```

### Deploy

```bash
docker stack deploy -c stacks/ai-ml/03-qdrant/stack.yml qdrant
```

### Verify

```bash
# Check service is running
docker service ls --filter name=qdrant

# Test REST API (internal)
curl http://localhost:6333/healthz

# Test via Traefik (HTTPS)
curl -k https://qdrant.sexydad/healthz
```

## Persistence

Vector data is stored at `/srv/fastdata/qdrant` on master1. This directory must exist before deployment and is backed by the `/srv` logical volume (367 GB).

## Logs

Container logs are captured automatically by Fluent Bit and sent to OpenSearch index `docker-logs-YYYY.MM.DD`.

## Related Stacks

- `stacks/ai-ml/04-rag-api/` — FastAPI service that ingests and queries Qdrant
- `stacks/ai-ml/05-open-webui/` — Chat UI that uses Qdrant as RAG backend
- `stacks/core/02-postgres/` — pgvector for hybrid search and document metadata
