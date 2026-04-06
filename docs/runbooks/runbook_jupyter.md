# Runbook: JupyterLab (multi-user + GPU)

## Reference Data

| Parameter | Value |
|-----------|-------|
| **Stack** | `jupyter` |
| **Services** | `jupyter_jupyter_<admin-user>` + `jupyter_jupyter_<second-user>` |
| **Node** | master2 (`tier=compute`, GPU RTX 2080 Ti) |
| **Persistence** | `/srv/fastdata/jupyter/{user}` (NVMe) |
| **URLs** | `https://jupyter-<admin-user>.sexydad` / `https://jupyter-<second-user>.sexydad` |
| **Auth** | BasicAuth via Traefik (secret: `jupyter_basicauth_v2`) |

---

## 1. Daily Operations (Healthcheck)

### 1.1 Verify services

```bash
# On master1
docker service ls | grep jupyter
docker service ps jupyter_jupyter_<admin-user>
docker service ps jupyter_jupyter_<second-user>
```

### 1.2 Verify GPU availability in Jupyter

From a notebook cell:

```python
import torch
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"GPU: {torch.cuda.get_device_name(0)}")
print(f"Total VRAM: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")
```

Expected result: `CUDA available: True` / `GPU: NVIDIA GeForce RTX 2080 Ti`

---

## 2. Available Kernels

Kernels are provisioned automatically on first startup via `init-kernels.sh`:

| Kernel | Description | Key packages |
|--------|-------------|--------------|
| Python 3 (default) | Jupyter base kernel | pandas, numpy, matplotlib |
| Python IA | Deep Learning + GPU | torch, tensorflow, transformers |
| Python LLM | Ollama integration | langchain, ollama, openai |

Kernels are installed in `/srv/fastdata/jupyter/{user}/.venv/` (persistent on NVMe).

### If kernels don't appear

```bash
# Access the user's container on master2
CONTAINER=$(docker ps -q -f name=jupyter_jupyter_<admin-user>)
docker exec -it $CONTAINER bash

# Check kernelspecs
jupyter kernelspec list

# Re-run the initialization script manually
/tmp/init-kernels.sh
```

---

## 3. Diagnostics (Incident)

### Symptom: JupyterLab won't load / 502 Bad Gateway

```bash
# Check service state
docker service ps jupyter_jupyter_<admin-user>

# If there are recent "Failed" entries:
docker service logs jupyter_jupyter_<admin-user> --tail 30
```

### Symptom: "Permission denied" when creating files

```bash
# The container runs as jovyan (UID 1000 for admin-user, 1001 for second-user)
# Fix on master2:
sudo chown -R 1000:1000 /srv/fastdata/jupyter/<admin-user>
sudo chown -R 1001:1001 /srv/fastdata/jupyter/<second-user>

# Restart:
docker service update --force jupyter_jupyter_<admin-user>
```

### Symptom: `pip install` fails or doesn't persist

The virtualenv is saved at `/srv/fastdata/jupyter/{user}/.venv/`. If it is corrupted:

```bash
# On master2
sudo rm -rf /srv/fastdata/jupyter/<admin-user>/.venv
sudo rm -rf /srv/fastdata/jupyter/<admin-user>/.local

# Restart the service (it recreates the .venv on startup)
docker service update --force jupyter_jupyter_<admin-user>
```

### Symptom: GPU not available in Jupyter

```bash
# Verify the service has a Generic Resource reserved
docker service inspect jupyter_jupyter_<admin-user> | grep -A5 GenericResources

# Verify the container is on master2
docker service ps jupyter_jupyter_<admin-user>

# If it landed on master1 (no GPU), the placement constraint failed
# Check master2 labels:
docker node inspect master2 --format '{{ json .Spec.Labels }}'
# Must include: "gpu":"nvidia", "tier":"compute"
```

---

## 4. Installing Persistent Libraries

Libraries installed with `pip install` inside the persisted virtualenv survive restarts:

```bash
# From a JupyterLab terminal (active kernel):
!/home/jovyan/.venv/ia/bin/pip install new-library

# Or directly in a cell:
import subprocess
subprocess.run(["/home/jovyan/.venv/ia/bin/pip", "install", "new-library"])
```

---

## 5. Redeploy

```bash
# On master1:
docker stack deploy -c stacks/ai-ml/01-jupyter/stack.yml jupyter

# IMPORTANT: notebooks and .venv are in bind mounts → NOT lost on redeploy
# Verify:
docker service ps jupyter_jupyter_<admin-user>
docker service ps jupyter_jupyter_<second-user>
```
