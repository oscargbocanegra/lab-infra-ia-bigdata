# Ollama - LLM Inference Engine

## Overview

Ollama provides GPU-accelerated LLM inference for models like Llama 3, Mistral, and others.

## Prerequisites

- ✅ GPU Generic Resource registered on master2
- ✅ Networks: `internal` and `public`
- ✅ Directory: `/srv/datalake/models/ollama` on master2

## Deployment

### 1. Create model storage directory

```bash
ssh master2
sudo mkdir -p /srv/datalake/models/ollama
sudo chown -R root:docker /srv/datalake/models/ollama
sudo chmod 2775 /srv/datalake/models/ollama
```

### 2. Update stack configuration

Replace `<INTERNAL_DOMAIN>` in `stack.yml` with your actual domain.

### 3. Deploy stack

```bash
docker stack deploy -c stacks/ai-ml/02-ollama/stack.yml ollama
```

### 4. Verify deployment

```bash
docker service ls | grep ollama
docker service logs ollama_ollama -f
```

### 5. Pull models

```bash
# Execute inside the running container
docker exec -it $(docker ps -q -f name=ollama_ollama) ollama pull llama3
docker exec -it $(docker ps -q -f name=ollama_ollama) ollama pull mistral
```

Or via API:

```bash
curl -X POST https://ollama.<INTERNAL_DOMAIN>/api/pull \
  -H "Content-Type: application/json" \
  -d '{"name": "llama3"}'
```

## Access

- **API Endpoint**: `https://ollama.<INTERNAL_DOMAIN>`
- **Health Check**: `https://ollama.<INTERNAL_DOMAIN>/api/tags`

## Usage Examples

### Generate completion

```bash
curl -X POST https://ollama.<INTERNAL_DOMAIN>/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3",
    "prompt": "Why is the sky blue?",
    "stream": false
  }'
```

### Chat completion

```bash
curl -X POST https://ollama.<INTERNAL_DOMAIN>/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3",
    "messages": [
      {"role": "user", "content": "Hello! Can you help me with Python?"}
    ],
    "stream": false
  }'
```

### From Jupyter

```python
import requests

def query_ollama(prompt, model="llama3"):
    response = requests.post(
        "http://ollama:11434/api/generate",
        json={"model": model, "prompt": prompt, "stream": False}
    )
    return response.json()["response"]

result = query_ollama("Explain machine learning in simple terms")
print(result)
```

## Resource Configuration

- **CPUs**: 4.0 reserved, 8.0 limit
- **Memory**: 8GB reserved, 16GB limit
- **GPU**: 1x RTX 2080 Ti (reserved via generic resource)

## Model Storage

Models are persisted at `/srv/datalake/models/ollama` on master2 (HDD), ensuring they survive container restarts and updates.

## Troubleshooting

### Service not starting

```bash
# Check service status
docker service ps ollama_ollama --no-trunc

# Check logs
docker service logs ollama_ollama -f
```

### GPU not detected

```bash
# Verify GPU resource on node
docker node inspect master2 --format '{{ json .Description.Resources.GenericResources }}'

# Should show: [{"DiscreteResourceSpec":{"Kind":"nvidia.com/gpu","Value":1}}]
```

### List available models

```bash
curl https://ollama.<INTERNAL_DOMAIN>/api/tags
```
