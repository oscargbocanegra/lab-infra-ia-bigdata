# Checklist de Infra — lab-infra-ia-bigdata

Última actualización: 2026-02-03 (Update: Ollama OPERATIVO + Infrastructure Complete)

Este documento centraliza el **estado real** (OK / Pendiente) para levantar la infraestructura completa del laboratorio, con **orden recomendado**, **dependencias** y **verificaciones mínimas**.

---

## Leyenda

- ✅ **OK**: implementado, verificado y persistente.
- ⏳ **PEND / EN CURSO**: falta implementar o en proceso de optimización.
- [~] **PEND (no bloquea)**: pendiente, pero no impide continuar con el siguiente bloque.
- **NEXT**: siguiente bloque de trabajo sugerido.

---

## Prerequisitos generales (antes de cualquier stack)

Acceso y base del sistema:

- ✅ Acceso SSH entre nodos (master1 ↔ master2) operativo
- ✅ Docker Engine instalado y funcionando en ambos nodos
- ✅ Usuarios operativos con permisos (ideal: pertenecer al grupo `docker`)
- ✅ **GPU NVIDIA RTX 2080 Ti** registrada como Generic Resource en Swarm (master2)

Red / naming:

- ✅ Hostnames internos con sufijo \`<INTERNAL_DOMAIN>\` definidos
- ✅ Resolución desde LAN validada (incluye pruebas con \`--resolve\` desde master2)
- ⏳ (Opcional) DNS interno formal para \`*.<INTERNAL_DOMAIN>\` (router/DNS local) [~]

Hardening mínimo recomendado (no bloquea, pero conviene):

- ⏳ Actualizaciones de seguridad aplicadas (apt/yum) [~]
- ⏳ Sincronización horaria (NTP/chrony) verificada [~]
- ⏳ Firewall revisado (puertos Swarm + 80/443 en master1) [~]

---

## Resumen ejecutivo (Estado de Despliegue)

| # | Stack | Estado | Versión/Detalle |
|---|-------|--------|-----------------|
| 1 | **Traefik** | ✅ | Reverse Proxy + TLS + BasicAuth |
| 2 | **Portainer** | ✅ | v2.11 - Web UI para Swarm |
| 3 | **Postgres** | ✅ | v16 - Stateful DB (fastdata) |
| 4 | **n8n** | ✅ | Automation Core + Postgres Backend |
| 5 | **Jupyter Lab** | ✅ | Multi-usuario (ogiovanni, odavid) + GPU + Kernels IA/LLM |
| 6 | **Ollama** | ✅ | LLM API + GPU (RTX 2080 Ti) - OPERATIVO |
| 7 | **OpenSearch** | ⏳ | Pendiente - Directorio creado |
| 8 | **Airflow** | ⏳ | Pendiente - Directorio creado |
| 9 | **Spark** | ⏳ | Pendiente - Directorio creado |
| 10 | **Backups/Hardening** | ⏳ | Pendiente planificación |

---

## Mapa del repo (Donde vive cada stack)

Stacks implementados y funcionales:

- **Traefik**: [stacks/core/00-traefik/stack.yml](stacks/core/00-traefik/stack.yml)
- **Portainer**: [stacks/core/01-portainer/stack.yml](stacks/core/01-portainer/stack.yml)
- **Postgres**: [stacks/core/02-postgres/stack.yml](stacks/core/02-postgres/stack.yml)
- **n8n**: [stacks/automation/02-n8n/stack.yml](stacks/automation/02-n8n/stack.yml)
- **Jupyter**: [stacks/ai-ml/01-jupyter/stack.yml](stacks/ai-ml/01-jupyter/stack.yml)

Stacks listos para despliegue:

- **Ollama**: [stacks/ai-ml/02-ollama/stack.yml](stacks/ai-ml/02-ollama/stack.yml) ✅ NUEVO

Carpetas creadas (Pendiente definir/finalizar \`stack.yml\`):

- ~~Ollama: [stacks/ai-ml/02-ollama/](stacks/ai-ml/02-ollama/)~~ ✅ **COMPLETADO**
- OpenSearch: [stacks/data/11-opensearch/](stacks/data/11-opensearch/)
- Spark: [stacks/data/98-spark/](stacks/data/98-spark/)
- Airflow: [stacks/automation/99-airflow/](stacks/automation/99-airflow/)

Env de ejemplo existente:

- Traefik (config no sensible): [envs/examples/core-traefik.env.example](envs/examples/core-traefik.env.example)

---

## Gestión de secrets y certificados (Swarm)

Principios:

- ✅ No versionar secretos en Git (cubierto por \`.gitignore\`)
- ✅ Usar Docker Swarm secrets para valores sensibles

Convención sugerida (para lo que viene):

- ✅ Nombres en \`snake_case\`, con prefijo por stack (ej: \`postgres_*\`, \`n8n_*\`, \`airflow_*\`)
- ✅ Mantener secretos “por servicio” (evita reusar passwords entre stacks)

Traefik (actual):

- ✅ \`traefik_basic_auth\`
- ✅ \`traefik_tls_cert\`
- ✅ \`traefik_tls_key\`

Jupyter (actual):
- ✅ \`jupyter_basicauth_v2\` (Bcrypt hash para acceso web)

Postgres (actual):
- ✅ \`pg_super_pass\`
- ✅ \`pg_n8n_pass\`

Pendiente (por definir para stacks siguientes):
- ⏳ n8n: encryption key + credenciales admin (si aplica)
- ⏳ OpenSearch: credenciales/usuarios (si se expone)
- ⏳ Airflow: fernet key + credenciales/conexiones (si aplica)

Operación:

- ⏳ Documentar procedimiento de creación/rotación de secrets (runbook) [~]
- ⏳ Definir política de backup/restore de secretos (según tu enfoque) [~]

---

## Inventario de endpoints (LAN)

| Servicio | URL | Estado |
|----------|-----|--------|
| **Traefik Dashboard** | `https://traefik.<INTERNAL_DOMAIN>` | ✅ |
| **Portainer** | `https://portainer.<INTERNAL_DOMAIN>` | ✅ |
| **n8n** | `https://n8n.<INTERNAL_DOMAIN>` | ✅ |
| **Jupyter (ogiovanni)** | `https://jupyter-ogiovanni.<INTERNAL_DOMAIN>` | ✅ |
| **Jupyter (odavid)** | `https://jupyter-odavid.<INTERNAL_DOMAIN>` | ✅ |
| **Ollama** | `https://ollama.sexydad` | ✅ OPERATIVO |
| **OpenSearch** | `https://opensearch.<INTERNAL_DOMAIN>` | ⏳ Pendiente |
| **Airflow** | `https://airflow.<INTERNAL_DOMAIN>` | ⏳ Pendiente |

---

## Fase 1 — Base del cluster (Swarm / red / labels)

### Docker + Swarm
- ✅ Docker instalado en master1
- ✅ Docker instalado en master2
- ✅ Swarm inicializado en master1 (manager/leader)
- ✅ master2 unido al Swarm como worker

Verificaciones:

- ✅ \`docker node ls\` muestra master1 (Leader) + master2 (Ready)
- ✅ \`docker info\` indica Swarm: active

### Networking (overlay)
- ✅ Red overlay \`public\` creada (attachable)
- ✅ Red overlay \`internal\` creada (attachable)

Verificaciones:

- ✅ \`docker network ls\` lista \`public\` e \`internal\` como \`overlay\`
- ✅ Redes marcadas como \`attachable\`

### Labels de nodos & Recursos
- ✅ Labels en master1 aplicados y verificados (ej: \`tier=control\`, \`node_role=manager\`)
- ✅ Labels en master2 aplicados y verificados (ej: \`tier=compute\`, \`storage=primary\`, \`gpu=nvidia\`)
- ✅ **Generic Resource GPU**: Registrada en \`master2\` (\`nvidia.com/gpu=1\`) para permitir \`reservations\` en Swarm mode.

Verificaciones:

- ✅ \`docker node inspect master2 --format '{{ json .Description.Resources.GenericResources }}'\` muestra la GPU.

**Resultado:** control-plane listo y red Swarm operativa con soporte GPU.

---

## Fase 2 — Storage en master2 (HDD datalake)

- ✅ Montaje \`/srv/datalake\` confirmado (HDD ~1.8T)
- ✅ Persistencia en \`/etc/fstab\` confirmada (LABEL/UUID) y montando

Verificaciones:

- ✅ \`df -h | grep /srv/datalake\` muestra tamaño esperado
- ✅ Reboot y remount validado

---

## Fase 3 — Volúmenes y estructura en master2 (NVMe fastdata + carpetas)

### LVM + montaje
- ✅ LVM creado: LV \`fastdata\` = 600G
- ✅ Formateado ext4 y montado en \`/srv/fastdata\`
- ✅ Persistencia vía \`/etc/fstab\` (UUID)
- ✅ Reboot real validado

### Estructura de carpetas
NVMe (rápido):
- ✅ \`/srv/fastdata/postgres\`
- ✅ \`/srv/fastdata/opensearch\`
- ✅ \`/srv/fastdata/airflow\`
- ✅ \`/srv/fastdata/jupyter/{ogiovanni,odavid}\`
- ✅ \`/srv/fastdata/jupyter/{user}/.venv\` (Persistencia de librerías de kernels IA/LLM)
- ✅ \`/srv/fastdata/jupyter/{user}/.local\` (Persistencia de kernelspecs)

HDD (datalake):
- ✅ \`/srv/datalake/datasets\`
- ✅ \`/srv/datalake/models\`
- ✅ \`/srv/datalake/notebooks\`
- ✅ \`/srv/datalake/artifacts\`
- ✅ \`/srv/datalake/backups\`

Permisos/ownership:
- ✅ Ownership \`root:docker\`
- ✅ Permisos 2775 aplicados (SGID presente)

**Resultado:** persistencia alineada para desplegar stateful sin sorpresas.

---

## Fase 4 — Infra como código (repo)

- ✅ Repo creado: \`lab-infra-ia-bigdata\`
- ✅ Estructura base aplicada (\`docs/\`, \`envs/\`, \`scripts/\`, \`stacks/\`, etc.)
- ✅ \`.gitignore\` cubre \`.env\`, \`secrets/\`, keys, passwords, etc.

---

## Bloque — Postgres (master2) ✅

Objetivo: Postgres stateful en Swarm, persistiendo en \`/srv/fastdata/postgres\`, accesible por red \`internal\`.

Secrets:
- ✅ \`pg_super_pass\`
- ✅ \`pg_n8n_pass\`

Criterios de “OK”:
- ✅ Servicio estable.
- ✅ DB \`n8n\` y rol \`n8n\` creados por initdb.
- ✅ Persistencia verificada tras reinicio.

---

## Bloque — n8n (master2) ✅

Objetivo: n8n conectado a Postgres para automatización de flujos con acceso seguro vīa Traefik.

Dependencias:
- ✅ Postgres OK.
- ✅ Red \`internal\` operativa.

Criterios de “OK”:
- ✅ El servicio queda \`running\` y estable.
- ✅ Conexión a Postgres validada.
- ✅ URL responde: \`https://n8n.<INTERNAL_DOMAIN>\`

---

## Bloque — Jupyter Lab (master2) ✅

Objetivo: Entorno Multi-usuario (ogiovanni, odavid) optimizado para IA/LLM con aceleración GPU (RTX 2080 Ti).

Prerequisitos:
- ✅ **GPU Generic Resource** registrado en master2.
- ✅ Red Swarm: \`internal\` y \`public\`.
- ✅ Secret: \`jupyter_basicauth_v2\`.
- ✅ Datos en datalake: \`/srv/datalake/{notebooks,datasets,models}\`.

Checklist:
- ✅ (Repo) Stack optimizado: [stacks/ai-ml/01-jupyter/stack.yml](stacks/ai-ml/01-jupyter/stack.yml)
- ✅ (Repo) Init Script de Kernels: Automático venv (IA, LLM).
- ✅ Configuración de Recursos:
  - ✅ **8.0 CPUs** por servicio.
  - ✅ **12GB RAM** por servicio.
  - ✅ **GPU Reservation**: Aceleración por hardware habilitada.
- ✅ Persistencia avanzada:
  - ✅ Home directories en \`/srv/fastdata/jupyter/{user}\`.
  - ✅ Librerías persistentes en \`.venv\` (evita reinstalar al reiniciar).
  - ✅ Kernels persistentes en \`.local\`.
- ✅ Seguridad: Traefik BasicAuth (Bcrypt) + LAN Whitelist.

Criterios de “OK”:
- ✅ Jupyter responde en: \`https://jupyter-{user}.<INTERNAL_DOMAIN>\`.
- ✅ Kernels \`IA\` y \`LLM\` aparecen automáticamente tras el primer arranque.
- ✅ \`torch.cuda.is_available()\` es \`True\` dentro de los kernels.
- ✅ Persistencia de librerías verificada tras \`service update\`.

---

## Bloque — Ollama (master2) ✅

Objetivo: LLM Inference Engine con aceleración GPU para modelos como Llama3, Mistral, etc.

Prerequisitos:
- ✅ GPU Generic Resource registrado en master2.
- ✅ Red Swarm: \`internal\` y \`public\`.
- ✅ Directorio: \`/srv/datalake/models/ollama\` para persistencia de modelos.

Checklist:
- ✅ (Repo) Stack creado: [stacks/ai-ml/02-ollama/stack.yml](stacks/ai-ml/02-ollama/stack.yml)
- ✅ (Repo) README con API completa y ejemplos: [stacks/ai-ml/02-ollama/README.md](stacks/ai-ml/02-ollama/README.md)
- ✅ Configuración de Recursos:
  - ✅ **6.0 CPUs** reservados, **12.0 CPUs** límite.
  - ✅ **12GB RAM** reservada, **24GB RAM** límite.
  - ✅ **GPU RTX 2080 Ti**: 11GB VRAM - Aceleración habilitada.
  - ✅ Variables optimizadas: Flash Attention, KV cache f16, parallel requests.
- ✅ Persistencia: Modelos en \`/srv/datalake/models/ollama\`.
- ✅ Seguridad: Traefik LAN Whitelist + BasicAuth (\`ollama_basicauth\`).
- ✅ Health checks configurados.
- ✅ Directorio creado en master2 con permisos correctos.
- ✅ Dominio configurado: \`ollama.sexydad\`.

Estado actual:
- ✅ **OPERATIVO** - Servicio desplegado y corriendo en master2.
- ✅ GPU detectada y disponible (11GB VRAM).
- ✅ API REST respondiendo correctamente.

Acceso:
- **Interno (Jupyter)**: \`http://ollama:11434\` (sin auth)
- **Externo**: \`https://ollama.sexydad\` (requiere BasicAuth)
- **Nota**: Agregar en \`/etc/hosts\` local: \`192.168.80.100 ollama.sexydad\`

Criterios de "OK":
- ✅ Servicio estable y corriendo.
- ✅ Ollama responde en: \`https://ollama.sexydad\`.
- ✅ API \`/api/tags\` retorna \`{"models":[]}\`.
- ✅ GPU detectada en logs: \`Nvidia GPU detected\`.
- ⏳ Pendiente: Descargar modelos LLM (bajo demanda).

---

## Bloque siguiente — OpenSearch (master2) ⏳

Prerequisitos:
- ✅ Directorio en master2: \`/srv/fastdata/opensearch\`
- ✅ Red Swarm: \`internal\` (recomendado).

Checklist:
- ⏳ (Repo) Crear [stacks/data/11-opensearch/stack.yml](stacks/data/11-opensearch/stack.yml)
- ⏳ Desplegar OpenSearch stateful.

---

## Bloque ÚLTIMO — Airflow y Spark ⏳

Prerequisitos:
- ✅ Directorio en master2: \`/srv/fastdata/airflow\`
- ✅ Postgres OK.

Checklist:
- ⏳ (Repo) Crear [stacks/automation/99-airflow/stack.yml](stacks/automation/99-airflow/stack.yml)
- ⏳ (Repo) Crear [stacks/data/98-spark/stack.yml](stacks/data/98-spark/stack.yml)

---

## Backups, hardening y operaciones ⏳

### Backups ⏳
- ⏳ Backup master2 → master1 (rsync/restic).
- ⏳ Política de retención.
- ⏳ Prueba de restore (Crítico).

### Observabilidad / Hardening ⏳
- ⏳ Firewall hardening (master1).
- ⏳ Logs/Métricas (opcional).

---

## Notas / decisiones

- ✅ El orden de prioridad actual es: **Ollama** ✅ (Stack completo) → **OpenSearch** → **Airflow**.
- ✅ La GPU se reserva para stacks en \`master2\` con soporte aceleración: Jupyter, Ollama.
- ✅ Los kernels de Jupyter son autónomos (auto-provisioning en primer arranque).
- ✅ Persistencia optimizada: NVMe (fastdata) para workloads activos, HDD (datalake) para datasets/modelos.
- ✅ Todos los servicios expuestos vía Traefik con TLS + BasicAuth + LAN Whitelist.

---

## Changelog Reciente

### 2026-02-03: Ollama Stack DEPLOYED ✅
- ✅ Stack desplegado y operativo en master2
- ✅ GPU RTX 2080 Ti detectada (11GB VRAM)
- ✅ Recursos optimizados: 6-12 CPUs, 12-24GB RAM
- ✅ Variables GPU: Flash Attention, parallel requests (4), KV cache f16
- ✅ Persistencia en \`/srv/datalake/models/ollama\`
- ✅ Seguridad: BasicAuth + LAN Whitelist
- ✅ Dominio: \`ollama.sexydad\` (requiere entrada en \`/etc/hosts\` local)
- ✅ API REST 100% funcional
- ✅ README completo con 7 endpoints documentados + ejemplos Postman/Python
- ✅ Integración lista con Jupyter notebooks (red interna sin auth)

### Estado anterior (pre-2026-02-03):
- ✅ Jupyter multi-usuario operativo (ogiovanni, odavid)
- ✅ Kernels IA/LLM con persistencia de virtualenvs
- ✅ GPU Generic Resource configurado en Swarm
- ✅ n8n + Postgres + Portainer + Traefik operativos
