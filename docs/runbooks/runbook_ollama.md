# Runbook de Operación: Ollama (LLM Inference)

## Datos de referencia

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `ollama` |
| **Servicio** | `ollama_ollama` |
| **Nodo** | master2 (`tier=compute` + `gpu=nvidia`) |
| **GPU** | RTX 2080 Ti — 11 GB VRAM |
| **Persistencia** | `/srv/datalake/models/ollama` (HDD) |
| **URL externa** | `https://ollama.sexydad` (BasicAuth requerida) |
| **URL interna** | `http://ollama:11434` (sin auth, overlay internal) |

---

## 1. Operación diaria (Healthcheck)

### 1.1 Verificar servicio

```bash
# En master1
docker service ls | grep ollama
docker service ps ollama_ollama --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'
```

### 1.2 Verificar GPU activa

```bash
# En master2
nvidia-smi
# Verificar que Ollama aparece en procesos cuando hay inferencia activa
```

### 1.3 Verificar modelos disponibles

```bash
# API interna (desde master2 o master1)
curl http://localhost:11434/api/tags
# Debe retornar JSON con lista de modelos descargados
```

---

## 2. Gestión de modelos

### Descargar un modelo

```bash
# Opción A: Acceso al contenedor (desde master2)
CONTAINER=$(docker ps -q -f name=ollama_ollama)
docker exec -it $CONTAINER ollama pull llama3
docker exec -it $CONTAINER ollama pull mistral
docker exec -it $CONTAINER ollama pull nomic-embed-text   # embeddings

# Opción B: Via API (requiere BasicAuth para endpoint externo)
curl -X POST https://ollama.sexydad/api/pull \
  -u admin:PASSWORD \
  -H "Content-Type: application/json" \
  -d '{"name": "llama3"}'
```

### Listar modelos descargados

```bash
docker exec -it $(docker ps -q -f name=ollama_ollama) ollama list
```

### Eliminar un modelo

```bash
docker exec -it $(docker ps -q -f name=ollama_ollama) ollama rm llama3
```

### Test de inferencia

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

## 3. Diagnóstico (Incidente)

### Síntoma: Container no arranca

```bash
docker service logs ollama_ollama --tail 30

# Error común: GPU no disponible
# "CUDA error: no kernel image is available for execution on the device"
# Fix: verificar que el runtime NVIDIA está activo en master2:
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi

# Error: Generic resource no reservado
# Verificar en stack.yml que generic_resources esté definido
```

### Síntoma: Inferencia muy lenta (usando CPU en lugar de GPU)

```bash
# Ver logs — busca "GPU" en el arranque
docker service logs ollama_ollama | grep -i "gpu\|cuda\|nvidia"
# Si ves "No GPU found" → el runtime no está configurado

# Fix: verificar daemon.json en master2
cat /etc/docker/daemon.json | grep -i runtime
# Debe mostrar: "default-runtime": "nvidia"

# Reiniciar Docker si es necesario
sudo systemctl restart docker
```

### Síntoma: OOM / modelo no carga (VRAM insuficiente)

```bash
# En master2
nvidia-smi   # Ver VRAM disponible

# Si otro proceso ocupa VRAM (ej: Jupyter con modelo cargado):
# 1. Reducir OLLAMA_MAX_LOADED_MODELS=1 en stack.yml
# 2. Usar modelos más pequeños (llama3:8b en lugar de 70b)
# 3. Usar cuantización menor (Q4 en lugar de Q8)
```

---

## 4. Uso desde Jupyter (red interna)

```python
import requests

def query_ollama(prompt: str, model: str = "llama3") -> str:
    """Inferencia via Ollama — acceso interno sin auth."""
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
print(query_ollama("¿Cuál es la capital de Francia?"))
```

---

## 5. Redespliegue

```bash
# En master1:
docker stack deploy -c stacks/ai-ml/02-ollama/stack.yml ollama

# Los modelos sobreviven (están en /srv/datalake/models/ollama, bind mount)
# Verificar:
docker service ps ollama_ollama
docker exec -it $(docker ps -q -f name=ollama_ollama) ollama list
```
