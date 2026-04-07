#!/usr/bin/env python3
"""
Re-ingest the agent architecture document into the RAG pipeline.

This script uploads agent_architecture.txt to the RAG API (rag-api.sexydad),
replacing any stale version that contained the old host IP for Ollama.

Usage (run from master1 or any host with network access to rag-api.sexydad):
    python3 reingest_agent_architecture.py

The document is created inline — no file needed on disk.
"""

import httpx
import sys

RAG_API_URL = "http://rag-api.sexydad"

AGENT_ARCHITECTURE_DOC = """# Lab Agent Architecture

## Overview

The lab uses a LangGraph-based hybrid agent deployed on master1 (192.168.80.100).
It can answer questions using two tools:

1. **RAG Tool** — semantic search against documents ingested into Qdrant.
2. **Data Tool** — natural language to SQL queries against Postgres.

## Service URLs (internal Docker overlay DNS)

- Agent API:   http://agent:8000   (from overlay) / https://agent.sexydad (external)
- Ollama:      http://ollama:11434  (Docker overlay DNS — do NOT use host IPs)
- Qdrant:      http://qdrant:6333
- Postgres:    postgres:5432
- MinIO:       Use MINIO_ENDPOINT env var (internal VIP)

## Important: Docker overlay networking

Services inside a Docker Swarm overlay network MUST use service DNS names, not host IPs.
The IP 192.168.80.200 is NOT reachable from inside overlay containers.
Always use: OLLAMA_BASE_URL=http://ollama:11434

## Models

| Model               | Use case                        |
|---------------------|---------------------------------|
| gemma3:4b           | Routing + synthesis (primary)   |
| qwen2.5-coder:7b    | SQL generation for Data Tool    |
| qwen3.5:latest      | Heavy reasoning fallback        |
| nomic-embed-text    | Embedding (768d, Qdrant)        |

## Airflow Evaluation DAGs

| DAG                      | Schedule     | Output                                       |
|--------------------------|--------------|----------------------------------------------|
| agent_synthetic_dataset  | Sunday 02:00 | governance/ragas-datasets/YYYY-MM-DD/        |
| agent_ragas_eval         | Sunday 04:00 | governance/ragas-results/YYYY-MM-DD/         |
| agent_model_benchmark    | Sunday 06:00 | governance/benchmarks/YYYY-MM-DD/            |

## OpenSearch Indices

- agent-traces-YYYY.MM.DD   — per-query agent traces (latency, tool used, answer)
- ragas-results-YYYY-MM-DD  — RAGAS evaluation aggregate results
- model-benchmarks-YYYY-MM-DD — per-model benchmark leaderboard

## Deployment

Stack: stacks/ai-ml/06-agent/stack.yml
Image: lab-agent:latest (built locally on master1)
Node:  master1 (tier=control label)
"""


def main():
    print(f"Ingesting agent_architecture.txt into RAG API at {RAG_API_URL}...")

    doc_bytes = AGENT_ARCHITECTURE_DOC.encode("utf-8")

    with httpx.Client(timeout=120.0) as client:
        resp = client.post(
            f"{RAG_API_URL}/ingest/",
            files={"file": ("agent_architecture.txt", doc_bytes, "text/plain")},
            data={"collection": "agent"},
        )

    if resp.status_code == 200:
        data = resp.json()
        print(f"✅ Ingestion successful!")
        print(f"   document_id:    {data['document_id']}")
        print(f"   chunks_indexed: {data['chunks_indexed']}")
        print(f"   minio_path:     {data['minio_path']}")
    else:
        print(f"❌ Ingestion failed: HTTP {resp.status_code}")
        print(resp.text)
        sys.exit(1)


if __name__ == "__main__":
    main()
