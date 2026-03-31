# lab-infra-ia-bigdata

Infraestructura reproducible en **Docker Swarm** para laboratorio de **IA / Big Data**, con seguridad por defecto, observabilidad y despliegue por fases.

> **Estado actual**: Fase 4 completada — 7 stacks operativos. Pendientes: Airflow, Spark y observabilidad.

---

## Índice

- [Arquitectura del clúster](#arquitectura-del-clúster)
- [Nodos del clúster](#nodos-del-clúster)
- [Servicios activos](#servicios-activos)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Orden de despliegue](#orden-de-despliegue)
- [Endpoints LAN](#endpoints-lan)
- [Documentación](#documentación)

---

## Arquitectura del clúster

```
╔══════════════════════════════════════════════════════════════════════════╗
║                    LAB INFRA — Docker Swarm (LAN only)                  ║
╠══════════════════╦═══════════════════════════════════════════════════════╣
║   master1        ║   master2                                             ║
║   CONTROL PLANE  ║   COMPUTE + DATA + GPU                                ║
║   i7-6700T       ║   i9-9900K                                            ║
║   32 GB RAM      ║   32 GB RAM                                           ║
║   HDD 500 GB     ║   NVMe 1TB + HDD 2TB                                  ║
║   Swarm Manager  ║   Swarm Worker                                        ║
║                  ║   RTX 2080 Ti (11 GB VRAM)                            ║
╠══════════════════╩═══════════════════════════════════════════════════════╣
║                                                                          ║
║  LAN (192.168.80.0/24)   ──────────────────────────────────────────────  ║
║                                                                          ║
║  Usuario LAN                                                             ║
║       │                                                                  ║
║       ▼                                                                  ║
║  Traefik :443 (master1)  ─── overlay: public ──────────────────────────  ║
║  Reverse Proxy + TLS     ─── overlay: internal ────────────────────────  ║
║       │                                                                  ║
║       ├──► portainer.sexydad  → Portainer CE (master1)                  ║
║       ├──► traefik.sexydad    → Traefik Dashboard (master1)             ║
║       ├──► n8n.sexydad        → n8n Automation (master2)                ║
║       ├──► opensearch.sexydad → OpenSearch API (master1)                ║
║       ├──► dashboards.sexydad → OpenSearch Dashboards (master1)         ║
║       ├──► jupyter-ogiovanni.sexydad → JupyterLab (master2 + GPU)       ║
║       ├──► jupyter-odavid.sexydad    → JupyterLab (master2 + GPU)       ║
║       └──► ollama.sexydad     → Ollama LLM API (master2 + GPU)          ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## Nodos del clúster

| Atributo         | master1 (Control Plane)         | master2 (Compute + Data)              |
|------------------|---------------------------------|---------------------------------------|
| **Rol Swarm**    | Manager / Leader                | Worker                                |
| **CPU**          | Intel i7-6700T (4C/8T @ 2.8GHz)| Intel i9-9900K (8C/16T @ 3.6GHz)     |
| **RAM**          | 32 GB                           | 32 GB                                 |
| **Storage**      | HDD 500 GB (ROTA)               | NVMe Samsung 970 EVO 1TB + HDD 2TB   |
| **GPU**          | —                               | NVIDIA RTX 2080 Ti (11 GB VRAM, CUDA 12.2) |
| **Labels Swarm** | `tier=control` `node_role=manager` | `tier=compute` `node_role=worker` `storage=primary` `gpu=nvidia` |
| **Mounts**       | `/srv/fastdata` (HDD local)     | `/srv/fastdata` (LVM sobre NVMe) `/srv/datalake` (HDD 2TB) |

> Ver detalles completos en [`docs/architecture/NODES.md`](docs/architecture/NODES.md)

---

## Servicios activos

| # | Stack | Versión | Nodo | URL |
|---|-------|---------|------|-----|
| 1 | **Traefik** | v2.11 | master1 | `https://traefik.sexydad/dashboard/` |
| 2 | **Portainer CE** | v2.39.1 | master1 | `https://portainer.sexydad` |
| 3 | **PostgreSQL** | 16 | master2 | interno `:5432` |
| 4 | **n8n** | 2.4.7 | master2 | `https://n8n.sexydad` |
| 5 | **JupyterLab** (ogiovanni) | python-3.11 + GPU | master2 | `https://jupyter-ogiovanni.sexydad` |
| 6 | **JupyterLab** (odavid) | python-3.11 + GPU | master2 | `https://jupyter-odavid.sexydad` |
| 7 | **Ollama** | latest | master2 | `https://ollama.sexydad` |
| 8 | **OpenSearch** | 2.19.4 | master1 | `https://opensearch.sexydad` |
| 9 | **OpenSearch Dashboards** | 2.19.4 | master1 | `https://dashboards.sexydad` |

> Ver inventario completo con estado en [`docs/architecture/SERVICES.md`](docs/architecture/SERVICES.md)

---

## Estructura del repositorio

```
lab-infra-ia-bigdata/
├── docs/
│   ├── architecture/         # Diseño del sistema (ARCHITECTURE, NODES, STORAGE, NETWORKING, SERVICES)
│   ├── adrs/                 # Architecture Decision Records
│   ├── hosts/                # Configs de host versionadas (fstab, daemon.json)
│   ├── runbooks/             # Operación día a día por servicio
│   └── ROADMAP.md            # Pendientes y siguiente fase
│
├── stacks/
│   ├── core/
│   │   ├── 00-traefik/       # Gateway LAN + TLS
│   │   ├── 01-portainer/     # Web UI Swarm
│   │   └── 02-postgres/      # DB core (stateful)
│   ├── automation/
│   │   ├── 02-n8n/           # Automatización de flujos
│   │   └── 03-airflow/       # ⏳ Pendiente
│   ├── data/
│   │   ├── 10-postgres/      # (alias/duplicado - unificar)
│   │   ├── 11-opensearch/    # Search & Analytics
│   │   └── 98-spark/         # ⏳ Pendiente
│   └── ai-ml/
│       ├── 01-jupyter/       # JupyterLab multi-usuario + GPU
│       └── 02-ollama/        # LLM inference engine + GPU
│
├── envs/
│   ├── examples/             # .env.example por stack (sin secretos)
│   └── ollama.env            # Config Ollama (no sensible)
│
├── scripts/
│   ├── bootstrap/            # Setup inicial de nodos
│   ├── verify/               # Healthchecks post-reboot
│   ├── backup/               # Scripts de backup
│   └── diagnostics/          # Diagnóstico de servicios
│
└── secrets/                  # NO versionado (.gitignore)
```

---

## Orden de despliegue

Ejecutar **siempre desde master1** (Swarm manager):

```bash
# Fase 1: Core (dependencias base)
docker stack deploy -c stacks/core/00-traefik/stack.yml traefik
docker stack deploy -c stacks/core/01-portainer/stack.yml portainer
docker stack deploy -c stacks/core/02-postgres/stack.yml postgres

# Fase 2: Automation
docker stack deploy -c stacks/automation/02-n8n/stack.yml n8n

# Fase 3: AI/ML (requieren GPU en master2)
docker stack deploy -c stacks/ai-ml/01-jupyter/stack.yml jupyter
docker stack deploy -c stacks/ai-ml/02-ollama/stack.yml ollama

# Fase 4: Data
docker stack deploy -c stacks/data/11-opensearch/stack.yml opensearch

# Fase 5 (pendiente):
# docker stack deploy -c stacks/data/98-spark/stack.yml spark
# docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow
```

---

## Endpoints LAN

Configurar en `/etc/hosts` (o DNS local):

```
192.168.80.100  traefik.sexydad
192.168.80.100  portainer.sexydad
192.168.80.100  n8n.sexydad
192.168.80.100  opensearch.sexydad
192.168.80.100  dashboards.sexydad
192.168.80.100  ollama.sexydad
192.168.80.100  jupyter-ogiovanni.sexydad
192.168.80.100  jupyter-odavid.sexydad
```

> Todos los servicios usan TLS con certificado self-signed. Aceptar la excepción en el navegador.

---

## Documentación

| Documento | Descripción |
|-----------|-------------|
| [`docs/architecture/ARCHITECTURE.md`](docs/architecture/ARCHITECTURE.md) | Diseño del sistema, flujos y decisiones |
| [`docs/architecture/NODES.md`](docs/architecture/NODES.md) | Specs físicas de master1 y master2 |
| [`docs/architecture/STORAGE.md`](docs/architecture/STORAGE.md) | Mapa de discos, LVM y paths |
| [`docs/architecture/NETWORKING.md`](docs/architecture/NETWORKING.md) | Redes overlay, dominios y flujo de tráfico |
| [`docs/architecture/SERVICES.md`](docs/architecture/SERVICES.md) | Inventario completo de servicios y versiones |
| [`docs/architecture/Checklist_Infra_Lab.md`](docs/architecture/Checklist_Infra_Lab.md) | Estado detallado de implementación |
| [`docs/adrs/`](docs/adrs/) | Architecture Decision Records |
| [`docs/runbooks/`](docs/runbooks/) | Operación y troubleshooting por servicio |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Próximas fases y mejoras planificadas |

---

## Principios operativos

- **Todo stateful → master2** (NVMe + GPU): Postgres, OpenSearch, Ollama, Jupyter
- **Todo control → master1** (HDD): Traefik, Portainer, Airflow web, Spark master
- **Swarm placement via labels**: `tier=control` / `tier=compute` / `gpu=nvidia`
- **Secretos vía Docker Secrets**: cero passwords en repo
- **Dominio interno**: `*.sexydad` resuelto por `/etc/hosts` en LAN
- **Persistencia garantizada**: systemd `RequiresMountsFor` en master2 antes de Docker
