# JupyterLab — AI / ML / BigData

## Overview

Multi-user JupyterLab with GPU, 3 specialized kernels, LSP autocompletion, and AI chat via Ollama (LAN, no cloud required).

**Hardware:** RTX 2080 Ti (11 GB VRAM) on master2  
**Users:** `<admin-user>` · `<second-user>`  
**URLs:** `https://jupyter-<admin-user>.sexydad` · `https://jupyter-<second-user>.sexydad`

---

## Available Kernels

| Kernel | Display name | Main contents |
|--------|-------------|---------------|
| `llm` | Python (LLM - PyTorch + LangChain) | PyTorch CUDA, Transformers, LangChain, Ollama client |
| `ia` | Python (IA - Scikit + TF + XGBoost) | Scikit-learn, TensorFlow, XGBoost, MLflow, Optuna |
| `bigdata` | Python (BigData - PySpark + Delta + MinIO) | PySpark 3.5, Delta Lake, boto3, s3fs, Dask |

Virtual environments are persisted at `/srv/fastdata/jupyter/<user>/.venv` (NVMe) — **idempotent on restart**.

---

## Code Intelligence Extensions

### jupyter-lsp + jedi-language-server (classic intellisense)

Autocompletion with types, docstrings, and go-to-definition for any kernel.  
Activates automatically when opening a notebook — no additional configuration required.

### jupyter-ai with Ollama (AI chat + `%%ai` magic)

Default model: **`qwen2.5-coder:7b`** — specialized in Python/SQL/Bash code.  
Internal endpoint: `http://ollama:11434` (Swarm overlay network, no latency, no cloud).

**How to use the chat panel:**
- Sidebar → ✦ icon (Jupyter AI) → type your question
- The model responds with code ready to paste into cells

**How to use the `%%ai` magic in cells:**
```python
%%ai ollama:qwen2.5-coder:7b
Write a PySpark function that reads a Delta Lake table from s3a://silver/ and filters by date
```

---

## Pre-requisite: pull the model in Ollama

Before the first deploy (or if the model is not downloaded), pull from master2:

```bash
# Option 1 — from the Ollama container (recommended)
docker exec $(docker ps -q -f name=ollama_ollama) ollama pull qwen2.5-coder:7b

# Option 2 — via API from any LAN node
curl -s http://<master2-ip>:11434/api/pull \
  -d '{"name": "qwen2.5-coder:7b"}' | jq .

# Verify the model is available
curl -s http://<master2-ip>:11434/api/tags | jq '.models[].name'
```

> The model takes ~4.7 GB on disk (`/srv/datalake/models/ollama`) and ~5.5 GB of VRAM during inference.  
> Leaves ~4.5 GB free for a second model loaded simultaneously.

---

## Deploy

```bash
# From master1 (Swarm manager)
docker stack deploy -c stacks/ai-ml/01-jupyter/stack.yml jupyter
```

### Verify

```bash
docker service ls | grep jupyter
docker service ps jupyter_jupyter_<admin-user>
docker service ps jupyter_jupyter_<second-user>
docker service logs jupyter_jupyter_<admin-user> -f
```

---

## Volume Structure

| Path in container | Host source | Description |
|-------------------|-------------|-------------|
| `/home/jovyan/work` | `/srv/fastdata/jupyter/<user>` | User notebooks (NVMe) |
| `/home/jovyan/.local` | `/srv/fastdata/jupyter/<user>/.local` | Persistent kernels and extensions |
| `/home/jovyan/.venv` | `/srv/fastdata/jupyter/<user>/.venv` | Virtual environments (NVMe) |
| `/home/jovyan/datasets` | `/srv/datalake/datasets` | Shared datasets (read-only) |
| `/home/jovyan/shared-notebooks` | `/srv/datalake/notebooks` | Shared notebooks |
| `/home/jovyan/artifacts` | `/srv/datalake/artifacts` | Shared ML artifacts |

---

## Troubleshooting

### LSP / jupyter-ai extensions not showing

The idempotency flag is at `/home/jovyan/.local/.server-extensions-installed`.  
To force reinstallation:

```bash
# Connect to the container and delete the flag
docker exec -it $(docker ps -q -f name=jupyter_<admin-user>) bash
rm /home/jovyan/.local/.server-extensions-installed
exit

# Restart the service
docker service update --force jupyter_jupyter_<admin-user>
```

### Ollama model not responding from chat

```bash
# Verify internal connectivity: Jupyter → Ollama
docker exec -it $(docker ps -q -f name=jupyter_<admin-user>) \
  curl -s http://ollama:11434/api/tags | python3 -m json.tool
```

### Review kernel init logs

```bash
docker service logs jupyter_jupyter_<admin-user> 2>&1 | grep -E "\[kernel|server-ext\]"
```
