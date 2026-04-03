# JupyterLab — IA / ML / BigData

## Overview

JupyterLab multi-usuario con GPU, 3 kernels especializados, autocompletado LSP y chat IA vía Ollama (LAN, sin cloud).

**Hardware:** RTX 2080 Ti (11 GB VRAM) en master2  
**Usuarios:** `ogiovanni` · `odavid`  
**URLs:** `https://jupyter-ogiovanni.sexydad` · `https://jupyter-odavid.sexydad`

---

## Kernels disponibles

| Kernel | Display name | Contenido principal |
|--------|-------------|---------------------|
| `llm` | Python (LLM - PyTorch + LangChain) | PyTorch CUDA, Transformers, LangChain, Ollama client |
| `ia` | Python (IA - Scikit + TF + XGBoost) | Scikit-learn, TensorFlow, XGBoost, MLflow, Optuna |
| `bigdata` | Python (BigData - PySpark + Delta + MinIO) | PySpark 3.5, Delta Lake, boto3, s3fs, Dask |

Los venvs se persisten en `/srv/fastdata/jupyter/<user>/.venv` (NVMe) — **idempotente al reiniciar**.

---

## Extensiones de inteligencia de código

### jupyter-lsp + jedi-language-server (intellisense clásico)

Autocompletado con tipos, docstrings y go-to-definition para cualquier kernel.  
Se activa automáticamente al abrir un notebook — no requiere configuración adicional.

### jupyter-ai con Ollama (chat IA + magic `%%ai`)

Modelo por defecto: **`qwen2.5-coder:7b`** — especializado en código Python/SQL/Bash.  
Endpoint interno: `http://ollama:11434` (red Swarm, sin latencia, sin cloud).

**Cómo usar el chat:**
- Panel lateral → ícono ✦ (Jupyter AI) → escribís tu pregunta
- El modelo responde con código listo para pegar en celdas

**Cómo usar el magic `%%ai` en celdas:**
```python
%%ai ollama:qwen2.5-coder:7b
Escribí una función PySpark que lea un Delta Lake desde s3a://silver/ y filtre por fecha
```

---

## Pre-requisito: pull del modelo en Ollama

Antes del primer deploy (o si el modelo no está descargado), hacer el pull desde master2:

```bash
# Opción 1 — desde el container de Ollama (recomendado)
docker exec $(docker ps -q -f name=ollama_ollama) ollama pull qwen2.5-coder:7b

# Opción 2 — vía API desde cualquier nodo de la LAN
curl -s http://192.168.80.200:11434/api/pull \
  -d '{"name": "qwen2.5-coder:7b"}' | jq .

# Verificar que el modelo está disponible
curl -s http://192.168.80.200:11434/api/tags | jq '.models[].name'
```

> El modelo ocupa ~4.7 GB en disco (`/srv/datalake/models/ollama`) y ~5.5 GB de VRAM al inferir.  
> Deja ~4.5 GB libres para un segundo modelo cargado simultáneamente.

---

## Deploy

```bash
# Desde master1 (Swarm manager)
docker stack deploy -c stacks/ai-ml/01-jupyter/stack.yml jupyter
```

### Verificar

```bash
docker service ls | grep jupyter
docker service ps jupyter_jupyter_ogiovanni
docker service ps jupyter_jupyter_odavid
docker service logs jupyter_jupyter_ogiovanni -f
```

---

## Estructura de volúmenes

| Path en el container | Fuente en host | Descripción |
|----------------------|----------------|-------------|
| `/home/jovyan/work` | `/srv/fastdata/jupyter/<user>` | Notebooks del usuario (NVMe) |
| `/home/jovyan/.local` | `/srv/fastdata/jupyter/<user>/.local` | Kernels y extensiones persistentes |
| `/home/jovyan/.venv` | `/srv/fastdata/jupyter/<user>/.venv` | Entornos virtuales (NVMe) |
| `/home/jovyan/datasets` | `/srv/datalake/datasets` | Datasets compartidos (read-only) |
| `/home/jovyan/shared-notebooks` | `/srv/datalake/notebooks` | Notebooks compartidos |
| `/home/jovyan/artifacts` | `/srv/datalake/artifacts` | Artefactos ML compartidos |

---

## Troubleshooting

### Las extensiones LSP / jupyter-ai no aparecen

El flag de idempotencia está en `/home/jovyan/.local/.server-extensions-installed`.  
Para forzar reinstalación:

```bash
# Conectarse al container y borrar el flag
docker exec -it $(docker ps -q -f name=jupyter_ogiovanni) bash
rm /home/jovyan/.local/.server-extensions-installed
exit

# Reiniciar el servicio
docker service update --force jupyter_jupyter_ogiovanni
```

### El modelo Ollama no responde desde el chat

```bash
# Verificar conectividad interna Jupyter → Ollama
docker exec -it $(docker ps -q -f name=jupyter_ogiovanni) \
  curl -s http://ollama:11434/api/tags | python3 -m json.tool
```

### Revisar logs de init de kernels

```bash
docker service logs jupyter_jupyter_ogiovanni 2>&1 | grep -E "\[kernel|server-ext\]"
```
