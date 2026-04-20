# JupyterLab — AI / ML / BigData

## Overview

Multi-user JupyterLab with GPU, 3 specialized kernels, LSP autocompletion, and a full **JARVIS AI Copilot** powered by a local Ollama LLM (no cloud, no API key required).

**Hardware:** RTX 2080 Ti (11 GB VRAM) on master2  
**Users:** `<admin-user>` · `<second-user>`  
**URLs:** `https://jupyter-<admin-user>.sexydad` · `https://jupyter-<second-user>.sexydad`  
**Model:** `qwen2.5-coder:14b` (default) — specialized in Python/SQL/Bash, ~25-30 tok/s

---

## Available Kernels

| Kernel | Display name | Main contents |
|--------|-------------|---------------|
| `llm` | Python (LLM - PyTorch + LangChain) | PyTorch CUDA, Transformers, LangChain, Ollama client |
| `ia` | Python (IA - Scikit + TF + XGBoost) | Scikit-learn, TensorFlow, XGBoost, MLflow, Optuna |
| `bigdata` | Python (BigData - PySpark + Delta + MinIO) | PySpark 3.5, Delta Lake, boto3, s3fs, Dask |

Virtual environments are persisted at `/srv/fastdata/jupyter/<user>/.venv` (NVMe) — **idempotent on restart**.

---

## JARVIS AI Copilot

Three ways to interact with the local LLM — all use `JARVIS_MODEL` (env var, default `qwen2.5-coder:14b`).

### 1. `/jarvis` — Inline cell transformer (recommended)

Write `/jarvis <prompt>` as the **first line** of any cell, with optional code below. JARVIS intercepts the cell before execution, sends it to Ollama, and returns the response.

```python
/jarvis explain this code

import plotly.graph_objects as go
fig = go.Figure(go.Scatter(x=[1,2,3], y=[1,4,9], mode="markers"))
fig.show()
```

**Read-only prompts** (explain, analyze, describe) → response rendered directly in cell output.  
**Modifying prompts** (fix, refactor, optimize, test, add comments, document) → shows a preview panel with **✅ Insert cell** / **✕ Discard** buttons before applying anything.

**Supported slash commands inside `/jarvis`:**

| Command | Expansion |
|---------|-----------|
| `/fix` | Fix bugs and errors in this code |
| `/refactor` | Refactor for clarity and best practices |
| `/optimize` | Optimize for performance |
| `/test` | Write unit tests |
| `/comments` | Add inline comments |
| `/document` | Write docstrings |
| `/explain` | Explain what this code does |

> **How it works internally:** `/jarvis` is intercepted by a patch on `input_transformer_manager.transform_cell` — the only hook that runs *before* IPython's own `EscapedCommand` token transformer (which would otherwise convert `/jarvis msg` → `jarvis(msg)`).

---

### 2. `%%JARVIS` — Cell magic

Use `%%JARVIS` as a standard IPython cell magic. The entire cell body is sent as a prompt.

```python
%%JARVIS
Write a PySpark function that reads a Delta Lake table from s3a://silver/
and filters rows where date > '2024-01-01', partitioned by product category.
```

---

### 3. JARVIS Widget — Iron Man Copilot Panel

Click the **Iron Man helmet button** (🔴 top-right of every cell, or run `jarvis` in a cell) to open the interactive panel:

- Type a prompt or pick a slash command chip (`/explain`, `/fix`, `/refactor`, `/optimize`, `/test`)
- Hit **Send** or press `Enter`
- Response streams live into the panel
- Panel stays open for follow-up questions; close with ✕

```python
# Open the JARVIS panel from a cell
jarvis
```

---

## Data Wrangler (Fabric-style)

Three functions available in all kernels for interactive DataFrame exploration:

| Function | Description |
|----------|-------------|
| `display(df)` | Interactive table (overrides default display — uses itables) |
| `panel_inspect(df)` / `dw(df)` | Interactive table + sidebar with per-column stats (Missing, Unique, histogram) |
| `profile(df)` | Full ydata-profiling report embedded inline |

```python
import pandas as pd
df = pd.read_csv("datasets/sales.csv")

panel_inspect(df)   # Fabric-style Data Wrangler
profile(df)         # Full profiling report
```

---

## Code Intelligence (LSP)

`jupyter-lsp` + `jedi-language-server` — autocompletion with types, docstrings, and go-to-definition for all kernels. Activates automatically when opening a notebook.

---

## Configuration

### Changing the JARVIS model

**Without redeploy** (immediate, per service):
```
Portainer → Services → jupyter_jupyter_<user> → Environment → JARVIS_MODEL → Update
```

**Persistent** (survives redeploy):
```bash
# On master1 — edit /etc/lab/lab.env
LAB_JARVIS_MODEL=ollama:qwen2.5-coder:14b
```

Available models (must be pulled in Ollama first):
- `ollama:qwen2.5-coder:14b` — 9.0 GB, ~25-30 tok/s, best for code (default)
- `ollama:gemma4:26b` — 16.7 GB, ~16 tok/s, MoE with function calling + thinking

---

## Deploy

```bash
# From master1 (Swarm manager)
docker stack deploy \
  --with-registry-auth \
  -c stacks/ai-ml/01-jupyter/stack.yml \
  jupyter
```

> **Note on configs:** `entrypoint.sh` and `init-kernels.sh` are deployed as Docker Swarm configs (immutable). Every change to these files **must** bump the `_vN` suffix in `stack.yml` — otherwise Swarm silently uses the cached old version.

### Verify

```bash
docker service ls | grep jupyter
docker service ps jupyter_jupyter_<admin-user>
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

### `/jarvis` still executes as `jarvis(msg)` instead of calling JARVIS

The startup script runs on kernel init. If the issue persists after a kernel restart:

```bash
# Verify the startup script is present in the container
docker exec -it $(docker ps -q -f name=jupyter_jupyter_<user>) \
  cat /home/jovyan/.ipython/profile_default/startup/01-jarvis-widget.py | grep transform_cell

# Should output the patched function — if empty, configs may be stale
# Solution: bump _vN in stack.yml and redeploy
```

### LSP / extensions not showing

```bash
docker exec -it $(docker ps -q -f name=jupyter_jupyter_<user>) bash
rm /home/jovyan/.local/.server-extensions-installed
exit
docker service update --force jupyter_jupyter_<user>
```

### Ollama model not responding

```bash
docker exec -it $(docker ps -q -f name=jupyter_jupyter_<user>) \
  curl -s http://ollama:11434/api/tags | python3 -m json.tool
```

### Review kernel init logs

```bash
docker service logs jupyter_jupyter_<user> 2>&1 | grep -E "\[kernel|server-ext|jarvis\]"
```
