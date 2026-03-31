# Runbook de Operación: JupyterLab (multi-usuario + GPU)

## Datos de referencia

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `jupyter` |
| **Servicios** | `jupyter_jupyter_ogiovanni` + `jupyter_jupyter_odavid` |
| **Nodo** | master2 (`tier=compute`, GPU RTX 2080 Ti) |
| **Persistencia** | `/srv/fastdata/jupyter/{user}` (NVMe) |
| **URLs** | `https://jupyter-ogiovanni.sexydad` / `https://jupyter-odavid.sexydad` |
| **Auth** | BasicAuth vía Traefik (secret: `jupyter_basicauth_v2`) |

---

## 1. Operación diaria (Healthcheck)

### 1.1 Verificar servicios

```bash
# En master1
docker service ls | grep jupyter
docker service ps jupyter_jupyter_ogiovanni
docker service ps jupyter_jupyter_odavid
```

### 1.2 Verificar GPU disponible en Jupyter

Desde un notebook, en una celda:

```python
import torch
print(f"CUDA disponible: {torch.cuda.is_available()}")
print(f"GPU: {torch.cuda.get_device_name(0)}")
print(f"VRAM total: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")
```

Resultado esperado: `CUDA disponible: True` / `GPU: NVIDIA GeForce RTX 2080 Ti`

---

## 2. Kernels disponibles

Los kernels se aprovisionan automáticamente en el primer arranque via `init-kernels.sh`:

| Kernel | Descripción | Paquetes clave |
|--------|-------------|----------------|
| Python 3 (default) | Kernel base de Jupyter | pandas, numpy, matplotlib |
| Python IA | Deep Learning + GPU | torch, tensorflow, transformers |
| Python LLM | Integración con Ollama | langchain, ollama, openai |

Los kernels se instalan en `/srv/fastdata/jupyter/{user}/.venv/` (persistente en NVMe).

### Si los kernels no aparecen

```bash
# Acceder al contenedor del usuario en master2
CONTAINER=$(docker ps -q -f name=jupyter_jupyter_ogiovanni)
docker exec -it $CONTAINER bash

# Verificar kernelspecs
jupyter kernelspec list

# Re-ejecutar script de inicialización manualmente
/tmp/init-kernels.sh
```

---

## 3. Diagnóstico (Incidente)

### Síntoma: JupyterLab no carga / 502 Bad Gateway

```bash
# Ver estado del servicio
docker service ps jupyter_jupyter_ogiovanni

# Si hay "Failed" recientes:
docker service logs jupyter_jupyter_ogiovanni --tail 30
```

### Síntoma: "Permission denied" al crear archivos

```bash
# El container corre como jovyan (UID 1000 para ogiovanni, 1001 para odavid)
# Fix en master2:
sudo chown -R 1000:1000 /srv/fastdata/jupyter/ogiovanni
sudo chown -R 1001:1001 /srv/fastdata/jupyter/odavid

# Reiniciar:
docker service update --force jupyter_jupyter_ogiovanni
```

### Síntoma: `pip install` falla o no persiste

El virtualenv se guarda en `/srv/fastdata/jupyter/{user}/.venv/`. Si está corrompido:

```bash
# En master2
sudo rm -rf /srv/fastdata/jupyter/ogiovanni/.venv
sudo rm -rf /srv/fastdata/jupyter/ogiovanni/.local

# Reiniciar el servicio (recrea el .venv en el arranque)
docker service update --force jupyter_jupyter_ogiovanni
```

### Síntoma: GPU no disponible en Jupyter

```bash
# Verificar que el servicio tiene Generic Resource reservado
docker service inspect jupyter_jupyter_ogiovanni | grep -A5 GenericResources

# Verificar que el container está en master2
docker service ps jupyter_jupyter_ogiovanni

# Si está en master1 (sin GPU), el placement constraint falló
# Verificar labels de master2:
docker node inspect master2 --format '{{ json .Spec.Labels }}'
# Debe incluir: "gpu":"nvidia", "tier":"compute"
```

---

## 4. Instalar librerías persistentes

Las librerías instaladas con `pip install` DENTRO del virtualenv persistido son las que sobreviven reinicios:

```bash
# Desde una terminal de JupyterLab (kernel activo):
!/home/jovyan/.venv/ia/bin/pip install nueva-libreria

# O directamente en celda:
import subprocess
subprocess.run(["/home/jovyan/.venv/ia/bin/pip", "install", "nueva-libreria"])
```

---

## 5. Redespliegue

```bash
# En master1:
docker stack deploy -c stacks/ai-ml/01-jupyter/stack.yml jupyter

# IMPORTANTE: los notebooks y .venv están en bind mounts → NO se pierden al redesplegar
# Verificar:
docker service ps jupyter_jupyter_ogiovanni
docker service ps jupyter_jupyter_odavid
```
