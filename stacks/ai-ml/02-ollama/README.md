# Ollama — LLM Inference Engine

## Overview

Ollama provides GPU-accelerated LLM inference for models like Llama 3, Mistral, Phi, and others.

**Hardware:** RTX 2080 Ti (11GB VRAM) on master2  
**Endpoint:** `https://ollama.sexydad`  
**Security:** BasicAuth + LAN Whitelist

> **Note:** To access from your local machine (Postman, browser):
>
> 1. **Add to your hosts file:**
>    - Linux/Mac: `/etc/hosts`
>    - Windows: `C:\Windows\System32\drivers\etc\hosts`
>    ```
>    <master1-ip>  ollama.sexydad
>    ```
>
> 2. **Disable SSL verification** (self-signed certificate):
>    - **Postman:** Settings → General → SSL certificate verification (OFF)
>    - **cURL:** Use flag `-k` or `--insecure`
>    ```bash
>    curl -k -u <admin-user>:<your-password> https://ollama.sexydad/api/tags
>    ```

## Prerequisites

- ✅ Networks: `internal` and `public`
- ✅ Directory: `/srv/datalake/models/ollama` on master2
- ✅ Secret: `ollama_basicauth` created

## Deployment

### 1. Create model storage directory

```bash
ssh <admin-user>@<master2-ip>
sudo mkdir -p /srv/datalake/models/ollama
sudo chown root:docker /srv/datalake/models/ollama
sudo chmod 2775 /srv/datalake/models/ollama
```

### 2. Create BasicAuth secret

```bash
docker secret create ollama_basicauth secrets/ollama_basicauth
```

### 3. Add Traefik middleware (one-time setup)

The `ollama-auth` middleware is defined as a label in the Traefik stack (same as jupyter-auth). Already configured if you deployed with the updated stack.

Verify:
```bash
docker service inspect traefik_traefik --format '{{json .Spec.Labels}}' | grep ollama-auth
```

### 4. Deploy stack

```bash
docker stack deploy -c stacks/ai-ml/02-ollama/stack.yml ollama
```

### 5. Verify deployment

```bash
docker service ls | grep ollama
docker service ps ollama_ollama
docker service logs ollama_ollama -f
```

## Authentication

All API requests require **BasicAuth**:

- **Username:** `<admin-user>` or `<second-user>`
- **Password:** `<your-password>`

---

## API Reference

Base URL: `https://ollama.sexydad`

### 1. Health Check — List Models

```http
GET /api/tags
Authorization: Basic <base64(username:password)>
```

**Response:**
```json
{
  "models": [
    {
      "name": "llama3.2:3b",
      "model": "llama3.2:3b",
      "size": 2019393189,
      "digest": "a80c4f17acd5...",
      "modified_at": "2026-02-03T10:30:00Z"
    }
  ]
}
```

---

### 2. Pull Model (Download)

```http
POST /api/pull
Authorization: Basic <base64(username:password)>
Content-Type: application/json

{
  "name": "llama3.2:3b"
}
```

**Response (streaming):**
```json
{"status":"pulling manifest"}
{"status":"downloading digestname","digest":"sha256:...","total":2019393189,"completed":524288}
{"status":"verifying sha256 digest"}
{"status":"success"}
```

---

### 3. Generate Completion

```http
POST /api/generate
Authorization: Basic <base64(username:password)>
Content-Type: application/json

{
  "model": "llama3.2:3b",
  "prompt": "Why is the sky blue?",
  "stream": false,
  "options": {
    "temperature": 0.7,
    "top_p": 0.9,
    "max_tokens": 2048
  }
}
```

**Response:**
```json
{
  "model": "llama3.2:3b",
  "created_at": "2026-02-03T10:35:00Z",
  "response": "The sky appears blue because...",
  "done": true,
  "total_duration": 2500000000,
  "load_duration": 100000000,
  "prompt_eval_count": 10,
  "eval_count": 85
}
```

---

### 4. Chat Completion

```http
POST /api/chat
Authorization: Basic <base64(username:password)>
Content-Type: application/json

{
  "model": "llama3.2:3b",
  "messages": [
    {"role": "system", "content": "You are a helpful AI assistant."},
    {"role": "user", "content": "Explain transformers in AI"}
  ],
  "stream": false,
  "options": {
    "temperature": 0.7,
    "top_p": 0.9
  }
}
```

**Response:**
```json
{
  "model": "llama3.2:3b",
  "created_at": "2026-02-03T10:40:00Z",
  "message": {
    "role": "assistant",
    "content": "Transformers are a type of neural network..."
  },
  "done": true,
  "total_duration": 3200000000
}
```

---

### 5. Show Model Info

```http
POST /api/show
Authorization: Basic <base64(username:password)>
Content-Type: application/json

{
  "name": "llama3.2:3b"
}
```

**Response:**
```json
{
  "modelfile": "FROM llama3.2:3b\n...",
  "parameters": "...",
  "template": "...",
  "details": {
    "format": "gguf",
    "family": "llama",
    "parameter_size": "3B",
    "quantization_level": "Q4_0"
  }
}
```

---

### 6. Delete Model

```http
DELETE /api/delete
Authorization: Basic <base64(username:password)>
Content-Type: application/json

{
  "name": "llama3.2:3b"
}
```

---

### 7. Generate Embeddings

```http
POST /api/embeddings
Authorization: Basic <base64(username:password)>
Content-Type: application/json

{
  "model": "llama3.2:3b",
  "prompt": "The quick brown fox jumps over the lazy dog"
}
```

**Response:**
```json
{
  "embedding": [0.123, -0.456, 0.789, ...]
}
```

---

## Postman Configuration

### Setup
1. Create new request
2. Set Auth Type: **Basic Auth**
   - Username: `<admin-user>`
   - Password: `<your-password>`
3. Base URL: `https://ollama.sexydad`

### Example Collections

**Collection 1: Health Check**
```
GET https://ollama.sexydad/api/tags
```

**Collection 2: Pull Model**
```
POST https://ollama.sexydad/api/pull
Body (JSON):
{
  "name": "llama3.2:3b"
}
```

**Collection 3: Generate Text**
```
POST https://ollama.sexydad/api/generate
Body (JSON):
{
  "model": "llama3.2:3b",
  "prompt": "Write a Python function to calculate fibonacci",
  "stream": false
}
```

---

## Usage from Python

### Basic Example

```python
import requests
from requests.auth import HTTPBasicAuth

BASE_URL = "https://ollama.sexydad"
AUTH = HTTPBasicAuth("<admin-user>", "<your-password>")

def list_models():
    response = requests.get(f"{BASE_URL}/api/tags", auth=AUTH)
    return response.json()

def generate_text(prompt, model="llama3.2:3b"):
    response = requests.post(
        f"{BASE_URL}/api/generate",
        auth=AUTH,
        json={
            "model": model,
            "prompt": prompt,
            "stream": False
        }
    )
    return response.json()["response"]

def chat(messages, model="llama3.2:3b"):
    response = requests.post(
        f"{BASE_URL}/api/chat",
        auth=AUTH,
        json={
            "model": model,
            "messages": messages,
            "stream": False
        }
    )
    return response.json()["message"]["content"]

# Usage
print(list_models())
print(generate_text("Explain quantum computing"))
print(chat([
    {"role": "user", "content": "What is Docker?"}
]))
```

### From Jupyter (Internal Network)

```python
import requests

# No auth needed on internal network
BASE_URL = "http://ollama:11434"

def generate_text(prompt, model="llama3.2:3b"):
    response = requests.post(
        f"{BASE_URL}/api/generate",
        json={
            "model": model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.7,
                "top_p": 0.9
            }
        }
    )
    return response.json()["response"]

# Usage in notebook
result = generate_text("Explain pandas DataFrame")
print(result)
```

### Streaming Responses

```python
import requests
import json
from requests.auth import HTTPBasicAuth

def generate_streaming(prompt, model="llama3.2:3b"):
    response = requests.post(
        "https://ollama.sexydad/api/generate",
        auth=HTTPBasicAuth("<admin-user>", "<your-password>"),
        json={
            "model": model,
            "prompt": prompt,
            "stream": True
        },
        stream=True
    )

    for line in response.iter_lines():
        if line:
            chunk = json.loads(line)
            if "response" in chunk:
                print(chunk["response"], end="", flush=True)
            if chunk.get("done"):
                print("\n")
                break

# Usage
generate_streaming("Write a short poem about AI")
```

---

## Recommended Models for RTX 2080 Ti (11GB VRAM)

| Model | Size | VRAM | Speed | Use Case |
|-------|------|------|-------|----------|
| `llama3.2:1b` | 1.3GB | ~2GB | ⚡⚡⚡ | Fast tasks, testing |
| `llama3.2:3b` | 2.0GB | ~3GB | ⚡⚡⚡ | General purpose, recommended |
| `mistral:7b` | 4.1GB | ~5GB | ⚡⚡ | Balanced quality/speed |
| `phi3:medium` | 7.9GB | ~9GB | ⚡ | High quality, slower |
| `llama3:8b` | 4.7GB | ~6GB | ⚡⚡ | Meta's flagship 8B |
| `codellama:7b` | 3.8GB | ~5GB | ⚡⚡ | Code generation |

### Pull Commands

```bash
# From container
docker exec $(docker ps -q -f name=ollama_ollama) ollama pull llama3.2:3b
docker exec $(docker ps -q -f name=ollama_ollama) ollama pull mistral:7b
docker exec $(docker ps -q -f name=ollama_ollama) ollama pull phi3:medium

# Via API (from Postman)
POST https://ollama.sexydad/api/pull
{"name": "llama3.2:3b"}
```

---

## Troubleshooting

### Check if service is running
```bash
docker service ps ollama_ollama
docker service logs ollama_ollama -f
```

### Test API from internal network
```bash
docker run --rm --network internal curlimages/curl:latest \
  curl -s http://ollama:11434/api/tags
```

### Check GPU usage
```bash
ssh <admin-user>@<master2-ip>
nvidia-smi
watch -n 1 nvidia-smi
```

### View model storage
```bash
ssh <admin-user>@<master2-ip>
ls -lh /srv/datalake/models/ollama/models/
du -sh /srv/datalake/models/ollama/
```

---

## Performance Tips

1. **Keep models loaded:** Set `OLLAMA_KEEP_ALIVE=5m` to avoid reload overhead
2. **Use smaller models:** 3B models are 2-3x faster than 7B
3. **Batch requests:** Process multiple prompts in parallel
4. **Adjust temperature:** Lower = faster, more deterministic
5. **Monitor VRAM:** Keep usage under 10GB to avoid OOM

---

## Integration Examples

### n8n Integration
Use HTTP Request node with BasicAuth to call Ollama API for automation workflows.

### Airflow Integration
Create DAG tasks that call Ollama for data processing and enrichment.

### Jupyter Integration
Use internal network (`http://ollama:11434`) for zero-latency access from notebooks.
