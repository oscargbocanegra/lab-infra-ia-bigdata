# ADR-009: Qdrant as Primary Vector Store (pgvector as Metadata Backend)

**Date:** 2026-04-08  
**Status:** Implemented ✅  
**Phase:** 8 — Vector DB + RAG

---

## Context

Phase 8 introduced the RAG pipeline (`04-rag-api`) and the agent layer (`06-agent`).
Both require vector similarity search to retrieve semantically relevant document chunks
given a user question.

The lab already had PostgreSQL running (Phase 3) with the `pgvector` extension installed
in the `rag` database. The question was whether to use pgvector as the vector store
or deploy a dedicated vector database.

Two options were evaluated:

1. **pgvector only** — Use the existing PostgreSQL instance for vector search
2. **Qdrant as primary + pgvector for metadata** — Deploy Qdrant as the search backend,
   keep Postgres for structured metadata and audit trail

---

## Decision

**Qdrant is the primary vector store for all semantic search operations.**  
**pgvector/PostgreSQL is the secondary store for metadata and audit trail only.**

- `ingest` writes to **both**: Qdrant (vectors + payload) and Postgres (metadata + chunk text)
- `query` and the agent RAG node search **Qdrant only** — Postgres is never queried for vectors
- Collection: `lab_documents_nomic` — 768 dimensions, cosine similarity, `nomic-embed-text` embeddings

---

## Alternatives Considered

### Option A: pgvector only (single-service approach)

Keep all vector data in the existing PostgreSQL + pgvector setup. No new service.

**Pros:**
- Zero new services — reuses the running `rag` database
- Full ACID transactions — embed + metadata write is a single atomic operation
- SQL joins — query metadata and vectors in one statement
- Familiar tooling — psql, SQLAlchemy, standard Postgres drivers

**Cons:**
- pgvector uses exact nearest-neighbor search by default (IVFFlat index requires manual tuning)
- No built-in payload filtering — collection-based filtering requires SQL `WHERE` clauses
- No dedicated Web UI for inspecting vectors and collections
- Postgres is a general-purpose database; vector workloads compete with other DB operations
- Harder to swap embedding models (schema migration required to change vector dimensions)
- No gRPC interface — REST-over-SQL adds overhead at scale

### Option B: Qdrant as primary + pgvector for metadata (hybrid approach) ✅

Deploy Qdrant as a dedicated vector database. Keep Postgres for structured metadata.

**Pros:**
- Purpose-built for ANN (Approximate Nearest Neighbor) search — HNSW index out of the box
- Payload filtering: filter by `collection`, `filename`, or any metadata field without SQL joins
- Built-in Web UI at `https://qdrant.sexydad/dashboard` — inspect collections, run test queries
- REST API (port 6333) + gRPC (port 6334) — both available from day one
- Swarm-native Docker image (`qdrant/qdrant:v1.13.4`) — deploys as a standard stack service
- Persistent storage on `/srv/fastdata/qdrant` (bind mount, 348 GB available)
- Multi-collection support: can host `documents_nomic` (768d) and `documents_bge` (1024d)
  in the same instance without schema changes
- Portfolio value: demonstrates knowledge of a dedicated vector database — a tool used
  in production RAG systems at scale

**Cons:**
- One more service to operate and monitor
- Dual-write in the ingest path adds complexity (Qdrant upsert + Postgres insert)
- No ACID guarantee across both stores — a failure after Qdrant upsert but before Postgres
  commit leaves the two stores slightly out of sync

---

## Rationale

Three factors drove this decision:

**1. Learning objectives and portfolio signal.**  
The lab is a learning environment. Having BOTH Qdrant and pgvector demonstrates that the
builder understands the tradeoffs between general-purpose and specialized vector stores —
not just that they can run `CREATE EXTENSION vector`. This is the kind of architectural
judgment that matters in real-world RAG systems.

**2. ANN search performance and payload filtering.**  
Qdrant's HNSW index gives sub-millisecond approximate nearest-neighbor search at the
scale of hundreds of thousands of vectors without manual index tuning. More importantly,
Qdrant's payload filtering — used in `query.py` to simulate per-collection search —
is a first-class feature with no SQL overhead. pgvector's IVFFlat index requires
choosing the number of probe lists upfront and doesn't compose cleanly with filtered search.

**3. Separation of concerns.**  
Postgres is excellent at what it does: relational queries, joins, ACID transactions,
structured metadata. Qdrant is excellent at what it does: fast ANN search with filtering.
Using each tool for what it's best at results in a cleaner architecture than stretching
one service to do both.

The dual-write inconsistency risk (con #3 of Option B) is acceptable for this lab:
Postgres is an audit trail, not a source of truth for search. If it lags behind Qdrant,
the search behavior is unaffected.

---

## Consequences

- ✅ Semantic search is fast and filtereable — Qdrant HNSW handles the vector workload
- ✅ Per-collection filtering works natively via Qdrant payload filters (no SQL)
- ✅ Web UI available at `https://qdrant.sexydad/dashboard` for collection inspection
- ✅ Postgres `documents` and `embeddings` tables serve as an audit trail and enable
  SQL-level analysis (chunk counts, model distribution, ingestion history)
- ✅ Architecture demonstrates knowledge of two different vector storage paradigms
- ⚠️ Ingest path writes to two services — a partial failure leaves stores out of sync
  (acceptable for a lab; production would require a transactional outbox or saga)
- ⚠️ One more service to maintain, monitor, and back up (mitigated: Qdrant is stateless
  in config, only the `/srv/fastdata/qdrant` bind mount needs backup)

---

## Implementation

### Qdrant stack

```
stacks/ai-ml/03-qdrant/stack.yml
```

- Image: `qdrant/qdrant:v1.13.4`
- Node: `master1` (tier=control)
- REST: `https://qdrant.sexydad` (via Traefik) / `http://qdrant:6333` (internal overlay)
- gRPC: `http://qdrant:6334` (internal overlay)
- Storage: `/srv/fastdata/qdrant` (bind mount)
- Auth: Docker secret `qdrant_api_key`

### Ingest path — dual write

`stacks/ai-ml/04-rag-api/app/routers/ingest.py`

```
POST /ingest
  → MinIO: store raw file
  → Ollama: embed all chunks (nomic-embed-text, 768d)
  → Qdrant: upsert PointStruct per chunk (vector + payload)
  → Postgres: INSERT into documents + embeddings tables
```

Qdrant payload per point:

```json
{
  "doc_id": "<uuid>",
  "collection": "<logical-collection>",
  "filename": "<original-filename>",
  "chunk_index": 0,
  "chunk_text": "<chunk content>",
  "minio_path": "<collection>/<doc_id>/<filename>"
}
```

### Query path — Qdrant only

`stacks/ai-ml/04-rag-api/app/routers/query.py`

```
POST /query
  → Ollama: embed question
  → Qdrant: search collection_name=lab_documents_nomic, top_k chunks
  → Qdrant payload filter if collection != "default"
  → Ollama LLM: generate answer from context
```

Postgres is NOT queried at search time.

### Agent RAG node — Qdrant only

`stacks/ai-ml/06-agent/app/nodes/rag.py`

```
rag_node(state)
  → Ollama: embed question (nomic-embed-text)
  → Qdrant: qdrant_client.search(collection_name, query_vector, limit=top_k)
  → Return: rag_chunks + rag_context for synthesizer node
```

The agent's RAG tool has no dependency on Postgres at runtime.

### pgvector schema (metadata only)

```sql
-- documents table: chunk text + metadata
CREATE TABLE documents (
  id           SERIAL PRIMARY KEY,
  collection   TEXT,
  filename     TEXT,
  source_url   TEXT,
  chunk_index  INTEGER,
  chunk_text   TEXT,
  token_count  INTEGER,
  model        TEXT,
  metadata     JSONB
);

-- embeddings table: vector column (audit/analysis only, not used for search)
CREATE TABLE embeddings (
  id           SERIAL PRIMARY KEY,
  document_id  INTEGER REFERENCES documents(id),
  embedding    VECTOR(768)
);
```
