# ADR-010: Migrate to gemma4:26b MoE and Introduce Global Model Pattern

**Date:** 2026-04-08  
**Status:** Implemented ✅  
**Phase:** 9B — Agents & Evals (model upgrade)

---

## Context

Phase 9B deployed a LangGraph hybrid agent using two specialized models:
- `gemma3:4b` — routing and synthesis
- `qwen2.5-coder:7b` — SQL generation via the Data Tool

Additionally, a third model (`qwen3.5:latest`, 9.7 GB) existed in Ollama with no clear provenance
— its name does not correspond to any official Ollama model and its origin is unknown.

Three problems motivated this ADR:

### Problem 1: VRAM saturation

| Model | VRAM |
|-------|------|
| gemma3:4b | ~3.5 GB |
| qwen2.5-coder:7b | ~6.0 GB |
| qwen3.5:latest | ~8.0 GB |
| nomic-embed-text | ~0.3 GB |
| bge-m3 | ~1.5 GB |

With `OLLAMA_MAX_LOADED_MODELS=2`, the RTX 2080 Ti (11 GB VRAM) swaps models constantly
when routing (gemma3:4b) and SQL generation (qwen2.5-coder:7b) run sequentially within the
same agent invocation. Measured latency: 8–14 seconds per tool call due to model eviction.

### Problem 2: Capability gaps

`gemma3:4b` lacks native function calling and thinking mode. This blocks progress toward
agentic patterns that require tool use via structured outputs (ReAct, Plan-and-Execute).

`qwen2.5-coder:7b` is a pure coding model — it lacks general reasoning capability needed
for hybrid agent synthesis and has 32K context vs the 256K context now available in
newer models.

### Problem 3: No single source of truth for the active model

Each stack (`06-agent`, `04-rag-api`, `01-jupyter`) hardcoded model names independently.
Switching models required editing 3+ files and redeploying all stacks individually, with
high risk of inconsistency.

---

## Decision

### 1. Replace all LLM models with gemma4:26b (MoE)

**gemma4:26b** is a Mixture-of-Experts architecture:
- 25.2B total parameters, only **3.8B active per token**
- Inference speed equivalent to a 4B dense model
- VRAM footprint: **~8–9 GB** (fits in RTX 2080 Ti alongside bge-m3)
- Native **function calling** (structured tool use)
- **Thinking mode** (extended reasoning via `<think>` tokens)
- **256K context window** (vs 32K in previous models)
- Multimodal image input (for future use)

One model replaces three. Routing, synthesis, and SQL generation all use gemma4:26b.

**Models removed:**

| Model | Reason |
|-------|--------|
| `gemma3:4b` | No function calling, no thinking mode, replaced by gemma4:26b |
| `qwen2.5-coder:7b` | Coding-only, 32K ctx, VRAM pressure, replaced by gemma4:26b |
| `qwen3.5:latest` | Unknown provenance, not an official Ollama model name, never referenced in stacks |
| `nomic-embed-text` | 768d, superseded by bge-m3 (1024d, multi-lingual, 8K ctx) |

**Model retained:** `bge-m3:latest` (embeddings — 1024d, no replacement needed)

### 2. Introduce the global model pattern via `/etc/lab/lab.env`

A new file `envs/lab.env.example` defines all lab-wide model variables:

```bash
LAB_LLM_MODEL=gemma4:26b
LAB_EMBED_MODEL=bge-m3
LAB_EMBED_DIMS=1024
LAB_JARVIS_MODEL=ollama:gemma4:26b
LAB_OLLAMA_URL=http://192.168.80.200:11434
```

**How it integrates with Docker Swarm:**

All `stack.yml` files use `${VAR:-fallback}` syntax:

```yaml
AGENT_MODEL: "${LAB_LLM_MODEL:-gemma4:26b}"
```

When `docker stack deploy` runs, Swarm interpolates variables from the current shell.
If `/etc/lab/lab.env` is sourced in `~/.bashrc`, the exported value is used.
If not sourced, the hardcoded fallback (`gemma4:26b`) ensures the deploy never fails.

**To switch models across all stacks at once:**

```bash
# Edit the one source of truth
sudo nano /etc/lab/lab.env        # change LAB_LLM_MODEL
source /etc/lab/lab.env

# Redeploy all AI stacks
docker stack deploy -c stacks/ai-ml/06-agent/stack.yml agent
docker stack deploy -c stacks/ai-ml/04-rag-api/stack.yml rag-api
docker stack deploy -c stacks/ai-ml/01-jupyter/stack.yml jupyter
```

**To switch a single service without redeploying (Portainer path):**
`Portainer → Services → agent_agent → Environment → edit AGENT_MODEL → Update`

### 3. Migrate Qdrant collection to bge-m3 (1024d)

The previous collection `lab_documents_nomic` used 768-dimensional vectors (nomic-embed-text).
The new collection `lab_documents_bge` uses 1024-dimensional vectors (bge-m3).

Since all content is lab-generated (no production data), there is no migration risk — the
collection is re-indexed from scratch on first ingest.

---

## Considered Alternatives

### gemma4:e4b (dense 4B)
- Pros: ~6 GB VRAM, more headroom for parallel requests
- Cons: Significantly lower quality than the MoE 26B effective capacity
- Decision: gemma4:26b MoE wins on quality-per-VRAM ratio

### qwen3:8b
- Pros: 5.2 GB disk, ~5 GB VRAM, native function calling, thinking mode
- Cons: Smaller context (128K vs 256K), Qwen architecture vs Gemma's broader ecosystem support
- Decision: gemma4:26b preferred given superior context window and Google ecosystem alignment

### Two-model setup (router + coder)
- Pros: Specialized models for each task
- Cons: VRAM pressure, model eviction latency, maintenance overhead across multiple stacks
- Decision: Single model simplifies ops and eliminates inter-model swap latency

---

## Consequences

### Positive
- Single model in VRAM at all times → zero model eviction latency
- Native function calling unlocks ReAct and Plan-and-Execute agent patterns
- Thinking mode enables step-by-step reasoning for complex multi-tool queries
- 256K context allows full document ingestion without chunking for short docs
- One variable (`LAB_LLM_MODEL`) controls all stacks
- `envs/lab.env.example` documents the full model inventory with VRAM estimates

### Negative
- Re-indexing required for Qdrant: `lab_documents_nomic` is no longer valid.
  All documents must be re-ingested via `POST /ingest` to populate `lab_documents_bge`.
- Airflow eval DAGs (`agent_synthetic_dataset`, `agent_ragas_eval`, `agent_model_benchmark`)
  reference old model names (`gemma3:4b`, `qwen2.5-coder:7b`). These must be updated
  before the next scheduled run (Sunday 02:00).

### Neutral
- `qwen3.5:latest` removal has no functional impact (was never referenced in any stack.yml)
- `CODER_MODEL` and `AGENT_MODEL` remain as separate env vars in `06-agent/stack.yml`
  for forward compatibility — they both point to `gemma4:26b` via `LAB_LLM_MODEL`

---

## Files Changed

| File | Change |
|------|--------|
| `stacks/ai-ml/02-ollama/stack.yml` | Image `0.19.0` → `latest` (required for gemma4 pull) |
| `stacks/ai-ml/06-agent/stack.yml` | `gemma3:4b` + `qwen2.5-coder:7b` → `${LAB_LLM_MODEL:-gemma4:26b}`; collection `lab_documents_bge` |
| `stacks/ai-ml/04-rag-api/stack.yml` | `nomic-embed-text` + old LLM → global variables pattern |
| `stacks/ai-ml/01-jupyter/stack.yml` | `JARVIS_MODEL` → `${LAB_JARVIS_MODEL:-ollama:gemma4:26b}` |
| `envs/lab.env.example` | New file — global model variables with install instructions |

---

## Ollama Commands (run on master1 after deploy)

```bash
# Pull new model (~18 GB download)
docker exec $(docker ps -q -f name=ollama_ollama) ollama pull gemma4:26b

# Remove obsolete models
docker exec $(docker ps -q -f name=ollama_ollama) ollama rm gemma3:4b
docker exec $(docker ps -q -f name=ollama_ollama) ollama rm qwen2.5-coder:7b
docker exec $(docker ps -q -f name=ollama_ollama) ollama rm qwen3.5:latest
docker exec $(docker ps -q -f name=ollama_ollama) ollama rm nomic-embed-text

# Verify VRAM after loading gemma4:26b + bge-m3
ssh <user>@<master2-ip> nvidia-smi
# Expected: ~10.5 GB used / 11 GB total (within limits)
```
