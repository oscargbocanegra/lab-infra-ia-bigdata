# Open WebUI — Chat Interface for Ollama + RAG

Full-featured ChatGPT-like interface connected to the lab's Ollama instance with RAG support.

## Overview

| Property | Value |
|---|---|
| Image | `ghcr.io/open-webui/open-webui:v0.6.5` |
| Node | master1 (`tier=control`) |
| URL | `https://chat.sexydad` |
| Storage | `/srv/fastdata/open-webui` (bind mount) |

## Features

- 💬 **Multi-model chat** — switch between any Ollama model (gemma3, qwen2.5, qwen3.5, etc.)
- 📚 **RAG Knowledge Bases** — upload documents, create collections, chat with your data
- 🔍 **Semantic search** — powered by Qdrant + nomic-embed-text embeddings
- 👥 **Multi-user** — admin + user roles, conversation history per user
- 🎛️ **Model management** — pull new Ollama models from the UI
- 🌊 **Streaming responses** — real-time token streaming

## Infrastructure Reuse

Open WebUI **reuses all existing cluster infrastructure**:

| Backend | Purpose | Stack |
|---|---|---|
| **Ollama** | LLM inference (direct host port) | `ai-ml/02-ollama` |
| **Qdrant** | RAG vector search backend | `ai-ml/03-qdrant` |
| **Postgres** | App data (reusing cluster DB, `openwebui` DB) | `core/02-postgres` |

> **DB Decision**: Open WebUI defaults to SQLite. In this lab we connect it to the **existing Postgres instance** (DB: `openwebui`) to centralize backups and support multi-user workloads. No new database service is introduced.

## Embedding Configuration

| Setting | Value |
|---|---|
| Engine | Ollama |
| Model | `nomic-embed-text` (768 dims) |
| Vector DB | Qdrant |
| Chunk size | 1000 |
| Chunk overlap | 100 |

## Deployment

### Prerequisites

```bash
# Secrets
openssl rand -base64 32 | docker secret create openwebui_secret_key -
echo "your-postgres-pass" | docker secret create pg_openwebui_pass -
# qdrant_api_key must already exist (from qdrant stack)

# Storage directory (master1)
mkdir -p /srv/fastdata/open-webui

# Create openwebui database in Postgres (one-time)
# Connect to Postgres and run:
# CREATE DATABASE openwebui OWNER postgres;
```

### Deploy

```bash
docker stack deploy -c stacks/ai-ml/05-open-webui/stack.yml open-webui
```

### First-time setup

1. Open `https://chat.sexydad`
2. Create admin account on first visit
3. Go to **Settings → Admin → Connections** — verify Ollama URL
4. Go to **Settings → Admin → RAG** — verify Qdrant connection
5. Pull embedding model: `nomic-embed-text`

## Adding a Knowledge Base

1. Go to **Workspace → Knowledge**
2. Click **+ New Knowledge**
3. Upload PDF/TXT/DOCX documents
4. Select the knowledge base when starting a new chat

## Recommended Models for RAG

| Model | VRAM | Context | Best For |
|---|---|---|---|
| `qwen2.5:7b` | ~5 GB | 128k | Long documents, precise Q&A |
| `gemma3:4b` | ~3 GB | 128k | Fast responses, conversational |
| `llama3.2:3b` | ~2 GB | 128k | Lightweight, quick prototyping |

## Logs

Container logs → Fluent Bit → OpenSearch index `docker-logs-YYYY.MM.DD`.

## Related Stacks

- `stacks/ai-ml/02-ollama/` — LLM inference backend
- `stacks/ai-ml/03-qdrant/` — Vector database
- `stacks/ai-ml/04-rag-api/` — Programmatic RAG API
- `stacks/core/02-postgres/` — Postgres with pgvector
