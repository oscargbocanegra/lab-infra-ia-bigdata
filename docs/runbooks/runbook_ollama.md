# Runbook: Ollama (LLM Inference)

## Reference Data

| Parameter | Value |
| --------- | ----- |
| **Stack** | `ollama` |
| **Service** | `ollama_ollama` |
| **Node** | master2 (`tier=compute` + `gpu=nvidia`) |
| **GPU** | RTX 2080 Ti — 11 GB VRAM |
| **Persistence** | `/srv/datalake/models/ollama` (HDD) |
| **External URL** | `https://ollama.sexydad` (BasicAuth required) |
| **Internal URL** | `http://ollama:11434` (no auth, overlay internal) |

### JupyterHub and notebook clients

Kernels launched by JupyterHub run inside the Swarm overlay network. They must
use `http://ollama:11434` and do not need Basic Auth. The published
`192.168.80.200:11434` endpoint is reserved for clients on
`192.168.80.0/24`; a timeout from a JupyterHub kernel usually means the
host-published route is being used from the wrong network, before HTTP
authentication is evaluated.

```python
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://ollama:11434").rstrip("/")
response = requests.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=15)
response.raise_for_status()
```

Use Basic Auth only with `https://ollama.sexydad` or another externally
protected endpoint. If the internal URL times out, verify the service and
overlay DNS from the single-user container before changing UFW rules:

```bash
getent hosts ollama
curl -v --max-time 15 http://ollama:11434/api/tags
```

---

## 1. Daily Operations (Healthcheck)

### 1.1 Verify service

```bash
# On master1
docker service ls | grep ollama
docker service ps ollama_ollama --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'
```

### 1.2 Verify GPU is active

```bash
# On master2
nvidia-smi
# Verify that Ollama appears in the process list during active inference
```

### 1.3 Verify available models

```bash
# Internal API (from master2 or master1)
curl http://localhost:11434/api/tags
# Should return JSON with the list of downloaded models
```

---

## 2. Model Management

### Download a model

```bash
# Option A: Access the container (from master2)
CONTAINER=$(docker ps -q -f name=ollama_ollama)
docker exec -it $CONTAINER ollama pull llama3
docker exec -it $CONTAINER ollama pull mistral
docker exec -it $CONTAINER ollama pull nomic-embed-text   # embeddings

# Option B: Via API (requires BasicAuth for external endpoint)
curl -X POST https://ollama.sexydad/api/pull \
  -u admin:PASSWORD \
  -H "Content-Type: application/json" \
  -d '{"name": "llama3"}'
```

### List downloaded models

```bash
docker exec -it $(docker ps -q -f name=ollama_ollama) ollama list
```

### Delete a model

```bash
docker exec -it $(docker ps -q -f name=ollama_ollama) ollama rm llama3
```

### Test inference

```bash
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3",
    "prompt": "Hello, are you working?",
    "stream": false
  }'
```

---

## 3. Diagnostics (Incident)

### Symptom: Container won't start

```bash
docker service logs ollama_ollama --tail 30

# Common error: GPU not available
# "CUDA error: no kernel image is available for execution on the device"
# Fix: verify the NVIDIA runtime is active on master2:
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi

# Error: Generic resource not reserved
# Check that generic_resources is defined in stack.yml
```

### Symptom: Inference very slow (using CPU instead of GPU)

```bash
# Check logs — look for "GPU" at startup
docker service logs ollama_ollama | grep -i "gpu\|cuda\|nvidia"
# If you see "No GPU found" → runtime is not configured

# Fix: check daemon.json on master2
cat /etc/docker/daemon.json | grep -i runtime
# Must show: "default-runtime": "nvidia"

# Restart Docker if needed
sudo systemctl restart docker
```

### Symptom: OOM / model won't load (insufficient VRAM)

```bash
# On master2
nvidia-smi   # Check available VRAM

# If another process is using VRAM (e.g. Jupyter with a loaded model):
# 1. Set OLLAMA_MAX_LOADED_MODELS=1 in stack.yml
# 2. Use smaller models (llama3:8b instead of 70b)
# 3. Use lower quantization (Q4 instead of Q8)
```

### Symptom: ConnectTimeout desde JupyterHub (`192.168.80.200:11434`)

**Error exacto:**
```
ConnectTimeout: HTTPConnectionPool(host='192.168.80.200', port=11434):
Max retries exceeded with url: /api/tags
(Caused by ConnectTimeoutError(..., 'Connection to 192.168.80.200 timed out.'))
```

**Causa:** El notebook usa la IP publicada del host (`192.168.80.200:11434`) que
es accesible desde equipos en `192.168.80.0/24` (Postman, curl local), pero
**no** desde dentro del network namespace del contenedor Swarm. Los kernels de
JupyterHub corren en la red overlay `internal` y deben usar el DNS del servicio.

**Fix inmediato — actualizar `apis.env`:**

```bash
# Desde la terminal de JupyterHub (o desde master2 vía SSH)
sed -i 's|^OLLAMA_BASE_URL=.*|OLLAMA_BASE_URL=http://ollama:11434|' \
  ~/work/.config/llm/apis.env

# Verificar
grep OLLAMA_BASE_URL ~/work/.config/llm/apis.env
# Debe mostrar: OLLAMA_BASE_URL=http://ollama:11434
```

**Fix desde Python (celda de notebook):**

```python
import re
from pathlib import Path

env_path = Path.home() / "work" / ".config" / "llm" / "apis.env"
content = env_path.read_text()
updated = re.sub(
    r"^(OLLAMA_BASE_URL\s*=\s*).*$",
    r"\g<1>http://ollama:11434",
    content,
    flags=re.MULTILINE,
)
env_path.write_text(updated)
print("✅ OLLAMA_BASE_URL corregida — reiniciá el kernel")
```

**Notas adicionales:**

- `OLLAMA_USERNAME` / `OLLAMA_PASSWORD` no son requeridas para el endpoint
  interno. Hacerlas `required` en el código rompe el caso de uso interno.
  Dejarlas opcionales y aplicar `auth` solo si están presentes.
- Si el DNS `ollama` no resuelve, el servicio `ollama_ollama` no está corriendo
  o el contenedor no está en la red `internal`. Verificar con
  `getent hosts ollama` desde la terminal de JupyterHub.
- Template de referencia: `notebooks/config/apis.env.template`
- Notebook de diagnóstico: `notebooks/ollama_test.ipynb`

---

## 4. Using from Jupyter (internal network)

```python
import requests

def query_ollama(prompt: str, model: str = "llama3") -> str:
    """Inference via Ollama — internal access, no auth required."""
    response = requests.post(
        "http://ollama:11434/api/generate",
        json={"model": model, "prompt": prompt, "stream": False},
        timeout=120
    )
    return response.json()["response"]

# Embeddings
def embed(text: str, model: str = "nomic-embed-text") -> list:
    response = requests.post(
        "http://ollama:11434/api/embeddings",
        json={"model": model, "prompt": text}
    )
    return response.json()["embedding"]

# Test
print(query_ollama("What is the capital of France?"))
```

---

## 5. Redeploy

```bash
# On master1:
docker stack deploy -c stacks/ai-ml/02-ollama/stack.yml ollama

# Models survive (they are in /srv/datalake/models/ollama, bind mount)
# Verify:
docker service ps ollama_ollama
docker exec -it $(docker ps -q -f name=ollama_ollama) ollama list
```

## 6. GPU compatibility baseline — 2026-07-14

Validated configuration on `master2`:

- GPU: NVIDIA GeForce RTX 2080 Ti, 11 GB VRAM.
- Driver package: `nvidia-driver-580-server`.
- Active driver: `580.159.03`.
- CUDA reported by `nvidia-smi`: `13.0`.
- NVIDIA Container Toolkit: `1.19.0`.
- Docker default runtime: `nvidia`.
- Ollama validated version: `0.32.0`.
- NVIDIA Exporter: `1/1`, scraped by Prometheus.

The previous driver `535.309.01` exposed the GPU inside containers, but Ollama
rejected it because the bundled CUDA libraries required driver `550` or newer.
The result was CPU fallback with `/api/ps` reporting `size_vram=0`.

### Validation

```bash
# master2
nvidia-smi
docker info --format '{{.DefaultRuntime}}'

# master1
docker service ls | grep -E 'ollama|nvidia-exporter'

PROM_CID="$(
  docker ps -q     --filter label=com.docker.swarm.service.name=prometheus_prometheus   | head -1
)"

docker exec "${PROM_CID}"   /bin/promtool query instant   http://127.0.0.1:9090   'up{job="nvidia_gpu"}'
```

Ollama GPU inference is valid only when `/api/ps` reports `size_vram > 0`.
Logs must show CUDA device selection and model layers offloaded to GPU.

### Rollback

A rollback requires a maintenance window and reboot:

```bash
# master2
sudo apt-get install -y nvidia-driver-535-server
sudo reboot
```

Rollback restores the previous host driver but disables GPU inference for the
currently validated Ollama runtime.
