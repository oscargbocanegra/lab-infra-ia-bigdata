# ADR-008: Hybrid LangGraph Agent + RAGAS Evaluation Pipeline

**Date:** 2026-04-07  
**Status:** Accepted  
**Phase:** 9B — Agents & Evals

---

## Context

Phase 9A established a complete data governance layer (OpenMetadata + Great Expectations).
Phase 9B adds intelligent agents that can answer questions about both **documents** (RAG) and
**structured data** (Postgres/MinIO), plus evaluation pipelines to measure agent quality over time.

### Available infrastructure (reuse)

| Service | Role |
|---------|------|
| Qdrant (qdrant.sexydad) | Vector store — `lab_documents_nomic` collection (768d cosine) |
| RAG API (rag-api.sexydad) | Existing ingest + simple query pipeline |
| Ollama (master2, :11434) | LLM + embedding inference on RTX 2080 Ti |
| Postgres (master2, :5432) | `rag` DB with pgvector, `airflow` DB |
| MinIO (internal) | Bronze/silver/gold datalake + rag-documents bucket |
| Airflow (airflow.sexydad) | DAG orchestration for batch evals |
| OpenSearch (internal) | Log aggregation + agent trace index |
| Grafana (grafana.sexydad) | Dashboards — add agent observability panel |

### Available models in Ollama

| Model | Parameters | Use case |
|-------|-----------|----------|
| gemma3:4b | 4.3B | Primary reasoning / chat |
| qwen2.5-coder:7b | 7B | SQL generation / code tasks |
| qwen3.5:latest | 9.7B | Heavy reasoning fallback |
| nomic-embed-text:latest | 137M | Primary embedding (768d) |
| bge-m3:latest | 567M | Secondary embedding (1024d) |

---

## Decision

### D1 — LangGraph as agent orchestration framework

**Chosen:** LangGraph (Python) over LangChain LCEL, AutoGen, or raw prompt chaining.

**Rationale:**
- Graph-based state machine is explicit and inspectable — you can see every node, edge, and decision
- Native support for conditional routing (Router → RAG branch OR Data branch)
- Built-in support for tool calls, memory, and cycles (retry loops)
- Same ecosystem as LangChain (shared abstractions) but with explicit control flow
- Aligns with the lab's philosophy: UNDERSTAND the plumbing, don't hide it

**Trade-offs:**
- More verbose than simple LangChain chains
- Requires understanding of graph theory concepts (nodes, edges, state)
- Smaller community than plain LangChain

### D2 — Hybrid agent: RAG tool + Data tool

**Design:** One agent with two tools:
1. **RAG Tool** — embeds question → Qdrant semantic search → retrieved chunks as context
2. **Data Tool** — natural language → SQL (qwen2.5-coder:7b) → Postgres query → structured result

The agent (gemma3:4b) decides which tool to invoke based on question intent:
- "What does our sales policy say about discounts?" → RAG Tool
- "How many sales records are in the bronze layer for April?" → Data Tool
- Complex questions → both tools, synthesized answer

**Alternative considered:** Separate specialized agents connected via message passing (multi-agent).
**Rejected because:** Adds latency + complexity for a 2-node lab. Single hybrid agent is cleaner.

### D3 — Synthetic dataset for RAGAS evaluation

**Approach:** Generate Q&A pairs synthetically using gemma3:4b against:
- Documents ingested into Qdrant (RAG ground truth)
- Sample queries against the bronze CSV data (Data ground truth)

**Format:** RAGAS-compatible JSON — `{"question": ..., "answer": ..., "contexts": [...], "ground_truth": ...}`

**Storage:** MinIO bucket `governance/ragas-datasets/` (versioned by date)

**Why synthetic:** No human-labeled dataset exists. Synthetic generation + LLM-as-judge is
the standard approach for local model evaluation when ground truth is unavailable.

### D4 — RAGAS metrics to track

| Metric | What it measures |
|--------|-----------------|
| `faithfulness` | Does the answer contain only claims supported by context? |
| `answer_relevancy` | Is the answer relevant to the question? |
| `context_precision` | Are the retrieved chunks actually useful? |
| `context_recall` | Did retrieval find all relevant information? |

Results stored in MinIO `governance/ragas-results/` and indexed into OpenSearch for trending.

### D5 — Model benchmarks approach

**What:** Test each available model against a fixed set of prompts in 3 categories:
1. **Instruction following** — simple Q&A, format compliance
2. **Reasoning** — multi-step logic problems
3. **Coding** — Python/SQL generation (qwen2.5-coder:7b focus)

**Format:** Each benchmark run stores results in `governance/benchmarks/YYYY-MM-DD/`

**NOT doing:** Full MMLU (requires downloading 57-subject dataset — impractical for local lab).
Instead: curated 20-question benchmark per category, run on every model.

### D6 — Agent observability via OpenSearch

Every agent invocation writes a trace document to OpenSearch index `agent-traces-YYYY.MM.DD`:

```json
{
  "@timestamp": "...",
  "trace_id": "uuid",
  "question": "...",
  "tool_used": "rag | data | both",
  "answer": "...",
  "latency_ms": 1234,
  "model": "gemma3:4b",
  "chunks_retrieved": 5,
  "sources": [...],
  "ragas_faithfulness": 0.87
}
```

Grafana dashboard queries this index for:
- Average latency per model
- Tool usage distribution
- RAGAS score trends over time

---

## Architecture

```
                          ┌─────────────────────────────────────────────┐
                          │           06-agent (master1)                 │
                          │                                               │
 User / Airflow DAG ──── ▶│  POST /agent/query                          │
                          │           │                                   │
                          │    ┌──────▼──────┐                           │
                          │    │ AgentState  │ (LangGraph StateGraph)    │
                          │    │  question   │                           │
                          │    │  messages   │                           │
                          │    │  tool_calls │                           │
                          │    │  answer     │                           │
                          │    └──────┬──────┘                           │
                          │           │                                   │
                          │    ┌──────▼──────┐                           │
                          │    │   Router    │ gemma3:4b decides         │
                          │    │    Node     │ rag / data / both         │
                          │    └──────┬──────┘                           │
                          │      ┌────┴────┐                             │
                          │      ▼         ▼                             │
                          │  ┌───────┐ ┌──────┐                         │
                          │  │  RAG  │ │ Data │                         │
                          │  │  Node │ │ Node │                         │
                          │  └───┬───┘ └──┬───┘                         │
                          │      │         │                             │
                          │      └────┬────┘                             │
                          │           ▼                                   │
                          │    ┌──────────────┐                          │
                          │    │  Synthesizer │ gemma3:4b final answer  │
                          │    └──────┬───────┘                          │
                          │           │                                   │
                          │    ┌──────▼───────┐                          │
                          │    │  Trace Write │──► OpenSearch            │
                          │    └──────────────┘                          │
                          └─────────────────────────────────────────────┘
                                    │
                          ┌─────────┴──────────┐
                          │                    │
                     Qdrant:6333          Postgres:5432
                   (lab_documents_nomic)  (rag DB)
```

---

## Deployment

**Stack:** `stacks/ai-ml/06-agent/stack.yml`  
**URL:** `https://agent.sexydad`  
**Docs:** `https://agent.sexydad/docs`  
**Node:** master1 (tier=control)  
**Image:** `lab-agent:latest` — built locally on master1

**New Airflow DAGs:**
- `agent_synthetic_dataset` — weekly, generates Q&A pairs, stores in MinIO
- `agent_ragas_eval` — weekly (after synthetic_dataset), runs RAGAS, stores results
- `agent_model_benchmark` — weekly, benchmarks all Ollama models

---

## Consequences

- **Positive:** Complete AI observability loop — build → eval → improve → repeat
- **Positive:** Learning resource for LangGraph graph-based agents pattern
- **Positive:** RAGAS pipeline reusable for future agent versions
- **Neutral:** Agent depends on Qdrant having ingested documents (RAG tool needs data)
- **Negative:** gemma3:4b is good but not GPT-4 quality — faithfulness scores will reflect this
