# Nodos del Clúster

> Actualizado: 2026-03-30

---

## master1 — Control Plane

| Atributo | Detalle |
|----------|---------|
| **Hostname** | `master1` |
| **Rol Swarm** | Manager / Leader |
| **CPU** | Intel Core i7-6700T @ 2.80 GHz |
| **Cores / Threads** | 4C / 8T |
| **RAM Total** | 32 GB |
| **RAM libre (típico)** | ~25 GB disponible |
| **Swap** | 2 GB |
| **Disco** | WDC WD5000LPLX-0 — 500 GB HDD (ROTA=1) |
| **GPU** | Ninguna |
| **OS** | Ubuntu (familia Debian) |
| **IP LAN** | `<IP_MASTER1>` (fija, red 192.168.80.0/24) |

### Labels Swarm (master1)

```bash
docker node update --label-add tier=control master1
docker node update --label-add node_role=manager master1
docker node update --label-add storage=backup master1
docker node update --label-add net=lan master1
```

### Servicios que corren en master1

| Servicio | Stack | Constraint |
|----------|-------|------------|
| Traefik | core/00-traefik | `tier=control` |
| Portainer | core/01-portainer | `tier=control` |
| Portainer Agent | core/01-portainer | global |
| OpenSearch | data/11-opensearch | `tier=control` |
| OpenSearch Dashboards | data/11-opensearch | `tier=control` |

### Mounts en master1

```
/srv/fastdata/        → HDD local (no LVM) — Portainer data, OpenSearch data
/srv/fastdata/portainer
/srv/fastdata/opensearch
/srv/backups/master2  → (planeado) backups recibidos desde master2 por rsync
```

### Configuración del sistema relevante

- **systemd override**: `RequiresMountsFor=/srv/fastdata` antes de iniciar Docker
- **Docker daemon.json**: log driver `json-file`, runtime default estándar

---

## master2 — Compute + Data + GPU

| Atributo | Detalle |
|----------|---------|
| **Hostname** | `master2` |
| **Rol Swarm** | Worker |
| **CPU** | Intel Core i9-9900K @ 3.60 GHz |
| **Cores / Threads** | 8C / 16T |
| **RAM Total** | 32 GB |
| **RAM libre (típico)** | ~4–8 GB disponible (Jupyter + Ollama activos) |
| **Swap** | 8 GB |
| **Disco 1** | Samsung SSD 970 EVO — 931.5 GB NVMe (ROTA=0) |
| **Disco 2** | Seagate ST2000LM015 — 1.8 TB HDD (ROTA=1) |
| **GPU** | NVIDIA GeForce RTX 2080 Ti |
| **VRAM** | 11 GB |
| **Driver NVIDIA** | 535.288.01 |
| **CUDA Version** | 12.2 |
| **OS** | Ubuntu (familia Debian) |
| **IP LAN** | `<IP_MASTER2>` (fija, red 192.168.80.0/24) |

### Labels Swarm (master2)

```bash
docker node update --label-add tier=compute master2
docker node update --label-add node_role=worker master2
docker node update --label-add storage=primary master2
docker node update --label-add gpu=nvidia master2
docker node update --label-add net=lan master2
```

### GPU: Generic Resource registrado

```bash
# En /etc/docker/daemon.json de master2:
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "node-generic-resources": ["nvidia.com/gpu=1"]
}

# Verificar:
docker node inspect master2 --format '{{ json .Description.Resources.GenericResources }}'
# Debe mostrar: [{"DiscreteResourceSpec":{"Kind":"nvidia.com/gpu","Value":1}}]
```

### Servicios que corren en master2

| Servicio | Stack | Constraint | Storage |
|----------|-------|------------|---------|
| PostgreSQL 16 | core/02-postgres | `hostname=master2` | `/srv/fastdata/postgres` (NVMe) |
| n8n | automation/02-n8n | `tier=compute` | `/srv/fastdata/n8n` (NVMe) |
| JupyterLab (ogiovanni) | ai-ml/01-jupyter | `tier=compute` + hostname | `/srv/fastdata/jupyter/ogiovanni` (NVMe) |
| JupyterLab (odavid) | ai-ml/01-jupyter | `tier=compute` + hostname | `/srv/fastdata/jupyter/odavid` (NVMe) |
| Ollama | ai-ml/02-ollama | `tier=compute` + `gpu=nvidia` | `/srv/datalake/models/ollama` (HDD) |
| Portainer Agent | core/01-portainer | global | — |

### Mounts en master2

```
/srv/fastdata/        → LVM sobre NVMe (600 GB, ext4)
│   ├── postgres/     → PostgreSQL data
│   ├── n8n/          → n8n config/data
│   ├── opensearch/   → (prep) OpenSearch si se mueve a master2
│   ├── airflow/      → (prep) Airflow metadata
│   └── jupyter/
│       ├── ogiovanni/
│       │   ├── .venv/   → virtualenv IA/LLM kernels (persistente)
│       │   └── .local/  → kernelspecs (persistente)
│       └── odavid/
│           ├── .venv/
│           └── .local/

/srv/datalake/        → HDD 2TB (montado por fstab, UUID)
    ├── datasets/     → datos crudos (CSV, Parquet, JSON)
    ├── models/
    │   └── ollama/   → modelos .gguf de Ollama
    ├── notebooks/    → notebooks exportados / compartidos
    ├── artifacts/    → resultados de entrenamientos, experimentos
    └── backups/      → backups fríos locales
```

### Configuración crítica del sistema (master2)

```ini
# /etc/systemd/system/docker.service.d/override.conf
# Docker NO inicia hasta que los discos están montados
[Unit]
After=network-online.target srv-fastdata.mount srv-datalake.mount
Wants=network-online.target
RequiresMountsFor=/srv/fastdata /srv/datalake
```

> **Sin este override**: Docker arranca antes de que `/srv/fastdata` esté disponible → Postgres/n8n fallan al intentar abrir volúmenes → bucle de reinicios.

---

## Comparativa de recursos

```
Recurso         master1 (Control)    master2 (Compute)
─────────────── ──────────────────   ──────────────────────
CPU             i7-6700T 4C/8T       i9-9900K 8C/16T       ← 2x más cores
RAM             32 GB                32 GB
Disco rápido    HDD 500 GB           NVMe 1TB              ← 10-20x más IOPS
Disco masivo    —                    HDD 2TB               ← 4x capacidad
GPU             —                    RTX 2080 Ti 11GB VRAM ← único con GPU
Rol             Control/Gateway      Compute/Data/AI
```
