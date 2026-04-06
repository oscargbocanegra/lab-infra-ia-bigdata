# Runbook: Ollama (LLM Inference)

## Reference Data

| Parameter | Value |
|-----------|-------|
| **Stack** | `ollama` |
| **Service** | `ollama_ollama` |
| **Node** | master2 (`tier=compute` + `gpu=nvidia`) |
| **GPU** | RTX 2080 Ti — 11 GB VRAM |
| **Persistence** | `/srv/datalake/models/ollama` (HDD) |
| **External URL** | `https://ollama.sexydad` (BasicAuth required) |
| **Internal URL** | `http://ollama:11434` (no auth, overlay internal) |

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
