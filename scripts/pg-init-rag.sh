#!/bin/sh
set -e

PGPASSWORD=$(cat /run/secrets/pg_super_pass)
RAG_PASS=$(cat /run/secrets/pg_rag_pass)
export PGPASSWORD

echo "=== Testing connection to postgres ==="
psql -h 192.168.80.200 -U postgres -c "SELECT version()"

echo "=== Creating rag role ==="
psql -h 192.168.80.200 -U postgres -c \
  "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'rag') THEN CREATE ROLE rag LOGIN PASSWORD '${RAG_PASS}'; END IF; END \$\$"

echo "=== Creating rag database ==="
psql -h 192.168.80.200 -U postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname = 'rag'" | grep -q 1 \
  || psql -h 192.168.80.200 -U postgres -c \
  "CREATE DATABASE rag OWNER rag ENCODING UTF8 TEMPLATE template0"

echo "=== Granting privileges on rag ==="
psql -h 192.168.80.200 -U postgres -c \
  "GRANT ALL PRIVILEGES ON DATABASE rag TO rag"

echo "=== Enabling pgvector in rag DB ==="
psql -h 192.168.80.200 -U postgres -d rag -c \
  "CREATE EXTENSION IF NOT EXISTS vector"

echo "=== Creating documents table ==="
psql -h 192.168.80.200 -U postgres -d rag -c \
  "CREATE TABLE IF NOT EXISTS documents (
    id BIGSERIAL PRIMARY KEY,
    collection TEXT NOT NULL,
    filename TEXT NOT NULL,
    source_url TEXT,
    chunk_index INTEGER NOT NULL DEFAULT 0,
    chunk_text TEXT NOT NULL,
    token_count INTEGER,
    model TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
  )"

echo "=== Creating embeddings table ==="
psql -h 192.168.80.200 -U postgres -d rag -c \
  "CREATE TABLE IF NOT EXISTS embeddings (
    id BIGSERIAL PRIMARY KEY,
    document_id BIGINT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    embedding vector(768) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )"

echo "=== Creating indexes ==="
psql -h 192.168.80.200 -U postgres -d rag -c \
  "CREATE INDEX IF NOT EXISTS embeddings_hnsw_idx ON embeddings USING hnsw (embedding vector_cosine_ops) WITH (m=16, ef_construction=64)"
psql -h 192.168.80.200 -U postgres -d rag -c \
  "CREATE INDEX IF NOT EXISTS documents_collection_idx ON documents (collection)"

echo "=== Granting privileges to rag role on all tables ==="
psql -h 192.168.80.200 -U postgres -d rag -c \
  "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO rag;
   GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO rag;
   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO rag;
   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO rag"

echo "=== Creating openwebui database ==="
psql -h 192.168.80.200 -U postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname = 'openwebui'" | grep -q 1 \
  || psql -h 192.168.80.200 -U postgres -c \
  "CREATE DATABASE openwebui OWNER postgres ENCODING UTF8 TEMPLATE template0"

echo "=== ALL DONE - listing databases ==="
psql -h 192.168.80.200 -U postgres -c "\l"
