# PostgreSQL 16 + pgvector — Central Database

Central relational database for all lab services, with the pgvector extension for vector similarity search.

## Overview

| Property | Value |
|---|---|
| Image | `pgvector/pgvector:pg16` |
| Node | master2 (`node.hostname == master2`) |
| Port | `5432` (mode: host — master2 LAN only) |
| Storage | `/srv/fastdata/postgres` (NVMe bind mount) |
| Access | `<master2-ip>:5432` from any cluster node |

> **Image note**: `pgvector/pgvector:pg16` is a **drop-in replacement** for `postgres:16`. It adds the `pgvector` extension and is 100% binary compatible with existing data.

## Managed Databases

| Database | User | Purpose |
|---|---|---|
| `postgres` | `postgres` (superuser) | Admin, maintenance |
| `n8n` | `n8n` | n8n workflow automation |
| `airflow` | `airflow` | Apache Airflow metadata |
| `rag` | `rag` | RAG pipelines — document metadata + pgvector embeddings |
| `openwebui` | `postgres` | Open WebUI app data (conversations, users) |

## Required Secrets

Create these Docker Swarm secrets before deploying:

```bash
echo "your-super-pass"   | docker secret create pg_super_pass -
echo "your-n8n-pass"     | docker secret create pg_n8n_pass -
echo "your-airflow-pass" | docker secret create pg_airflow_pass -
echo "your-rag-pass"     | docker secret create pg_rag_pass -
```

## pgvector Extension

The `rag` database has the `vector` extension enabled and the following schema:

```sql
-- Document chunks and metadata
CREATE TABLE documents (
  id          BIGSERIAL PRIMARY KEY,
  collection  TEXT        NOT NULL,
  filename    TEXT        NOT NULL,
  chunk_index INTEGER     NOT NULL,
  chunk_text  TEXT        NOT NULL,
  model       TEXT        NOT NULL,  -- embedding model used
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata    JSONB
);

-- Vector embeddings (768 dims for nomic-embed-text)
CREATE TABLE embeddings (
  id          BIGSERIAL PRIMARY KEY,
  document_id BIGINT      REFERENCES documents(id) ON DELETE CASCADE,
  embedding   vector(768) NOT NULL
);

-- HNSW index for fast ANN cosine similarity search
CREATE INDEX embeddings_hnsw_idx
  ON embeddings USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
```

## Deployment

### Prerequisites

1. Create all required secrets (see above)
2. Ensure `/srv/fastdata/postgres` exists on master2

### Deploy (first time or upgrade)

> **IMPORTANT**: Swarm configs are immutable. To update image or add init scripts, you must remove and redeploy the stack. Data is safe — it's in the bind-mounted volume.

```bash
# Remove existing stack (data is preserved in bind mount)
docker stack rm postgres

# Wait for complete removal
sleep 10

# Redeploy with updated image and init scripts
docker stack deploy -c stacks/core/02-postgres/stack.yml postgres
```

### Post-deploy: create openwebui database manually

Since `/srv/fastdata/postgres` already contains data, init scripts only run on empty volumes. Create the `openwebui` database manually:

```bash
# From any node with Postgres client or from a container in the overlay network
PGPASSWORD=your-super-pass psql -h <master2-ip> -U postgres -c "
  CREATE DATABASE openwebui OWNER postgres;
"
```

### Verify

```bash
# Check service
docker service ls --filter name=postgres

# List databases (from master1 if psql is available)
PGPASSWORD=pass psql -h <master2-ip> -U postgres -l

# Verify pgvector in rag database
PGPASSWORD=pass psql -h <master2-ip> -U postgres -d rag \
  -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';"
```

## Persistence

Data is stored at `/srv/fastdata/postgres` on master2's NVMe drive. This path is a bind mount — data **survives container restarts and stack redeployments**.

## Connection String Examples

```
# n8n
postgresql://n8n:pass@<master2-ip>:5432/n8n

# airflow
postgresql://airflow:pass@<master2-ip>:5432/airflow

# RAG API
postgresql://rag:pass@<master2-ip>:5432/rag

# Open WebUI
postgresql://postgres:pass@<master2-ip>:5432/openwebui
```

## Logs

Container logs → Fluent Bit → OpenSearch index `docker-logs-YYYY.MM.DD`.
