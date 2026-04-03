#!/bin/sh
# ============================================================
# 03-init-rag.sh — Create user, DB and pgvector extension for RAG
# Executed by postgres on first startup (empty volume)
# ============================================================
set -eu

RAG_PASS="$(cat /run/secrets/pg_rag_pass)"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
-- Create dedicated role for RAG
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'rag') THEN
    CREATE ROLE rag LOGIN PASSWORD '${RAG_PASS}';
  END IF;
END
\$\$;

-- Create rag database
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'rag') THEN
    CREATE DATABASE rag OWNER rag
      ENCODING 'UTF8'
      LC_COLLATE 'en_US.UTF-8'
      LC_CTYPE   'en_US.UTF-8'
      TEMPLATE template0;
  END IF;
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE rag TO rag;
EOSQL

# Enable pgvector extension inside the rag database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname="rag" <<-EOSQL
CREATE EXTENSION IF NOT EXISTS vector;

-- Documents metadata table
CREATE TABLE IF NOT EXISTS documents (
  id          BIGSERIAL PRIMARY KEY,
  collection  TEXT        NOT NULL,
  filename    TEXT        NOT NULL,
  source_url  TEXT,
  chunk_index INTEGER     NOT NULL DEFAULT 0,
  chunk_text  TEXT        NOT NULL,
  token_count INTEGER,
  model       TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata    JSONB
);

-- Embeddings table — 768 dims for nomic-embed-text
CREATE TABLE IF NOT EXISTS embeddings (
  id          BIGSERIAL PRIMARY KEY,
  document_id BIGINT      NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  embedding   vector(768) NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- HNSW index for fast ANN search (cosine similarity)
CREATE INDEX IF NOT EXISTS embeddings_hnsw_idx
  ON embeddings
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- Index on collection for filtered searches
CREATE INDEX IF NOT EXISTS documents_collection_idx ON documents (collection);
CREATE INDEX IF NOT EXISTS documents_created_at_idx ON documents (created_at DESC);

-- Grant all privileges to rag role
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO rag;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO rag;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO rag;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO rag;
EOSQL

echo "[init] Database 'rag', role 'rag', and pgvector extension created successfully."
