# Checklist de Infra — lab-infra-ia-bigdata

Última actualización: 2026-03-30 — Fase 5: MinIO + Spark + Airflow implementados

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
- ✅ **`default-runtime: nvidia`** en `/etc/docker/daemon.json` de master2 (requerido para Jupyter + Ollama GPU)

Red / naming:

- ✅ Hostnames internos con sufijo `<INTERNAL_DOMAIN>` definidos
- ✅ Resolución desde LAN validada (incluye pruebas con `--resolve` desde master2)
- ⏳ (Opcional) DNS interno formal para `*.<INTERNAL_DOMAIN>` (router/DNS local) [~]

Hardening mínimo recomendado (no bloquea, pero conviene):

- ⏳ Actualizaciones de seguridad aplicadas (apt/yum) [~]
- ⏳ Sincronización horaria (NTP/chrony) verificada [~]
- ⏳ Firewall revisado (puertos Swarm + 80/443 en master1) [~]

---

## Resumen ejecutivo (Estado de Despliegue)

| # | Stack | Estado | Versión/Detalle |
|---|-------|--------|-----------------|
| 1 | **Traefik** | ✅ | Reverse Proxy + TLS + BasicAuth |
| 2 | **Portainer** | ✅ | v2.39.1 - Web UI para Swarm |
| 3 | **Postgres** | ✅ | v16 - Multi-DB: postgres, n8n, airflow |
| 4 | **n8n** | ✅ | Automation Core + Postgres Backend |
| 5 | **Jupyter Lab** | ✅ | Multi-usuario + GPU + Kernels IA/LLM/BigData |
| 6 | **Ollama** | ✅ | v0.6.1 LLM API + GPU (RTX 2080 Ti) - OPERATIVO |
| 7 | **OpenSearch** | ✅ | v2.19.4 - Search & Analytics + Dashboards UI - OPERATIVO |
| 8 | **MinIO** | ⏳ | Stack listo — pendiente deploy + crear buckets |
| 9 | **Spark** | ⏳ | Stack listo — pendiente deploy + crear bucket spark-warehouse/history |
| 10 | **Airflow** | ⏳ | Stack listo — pendiente deploy + secrets + db init |
| 11 | **Backups/Hardening** | ⏳ | Pendiente planificación |

---

## Mapa del repo (Donde vive cada stack)

Stacks implementados y funcionales (operativos en cluster):

- **Traefik**: [stacks/core/00-traefik/stack.yml](stacks/core/00-traefik/stack.yml)
- **Portainer**: [stacks/core/01-portainer/stack.yml](stacks/core/01-portainer/stack.yml)
- **Postgres**: [stacks/core/02-postgres/stack.yml](stacks/core/02-postgres/stack.yml)
- **n8n**: [stacks/automation/02-n8n/stack.yml](stacks/automation/02-n8n/stack.yml)
- **Jupyter**: [stacks/ai-ml/01-jupyter/stack.yml](stacks/ai-ml/01-jupyter/stack.yml)
- **Ollama**: [stacks/ai-ml/02-ollama/stack.yml](stacks/ai-ml/02-ollama/stack.yml) ✅ OPERATIVO
- **OpenSearch**: [stacks/data/11-opensearch/stack.yml](stacks/data/11-opensearch/stack.yml) ✅ OPERATIVO

Stacks listos para deploy (código completo, pendiente ejecución):

- **MinIO**: [stacks/data/12-minio/stack.yml](stacks/data/12-minio/stack.yml)
- **Spark**: [stacks/data/98-spark/stack.yml](stacks/data/98-spark/stack.yml)
- **Airflow**: [stacks/automation/03-airflow/stack.yml](stacks/automation/03-airflow/stack.yml)

Runbooks disponibles:

- [docs/runbooks/runbook_traefik.md](docs/runbooks/runbook_traefik.md)
- [docs/runbooks/runbook_postgres.md](docs/runbooks/runbook_postgres.md)
- [docs/runbooks/runbook_n8n.md](docs/runbooks/runbook_n8n.md)
- [docs/runbooks/runbook_jupyter.md](docs/runbooks/runbook_jupyter.md)
- [docs/runbooks/runbook_ollama.md](docs/runbooks/runbook_ollama.md)
- [docs/runbooks/runbook_opensearch.md](docs/runbooks/runbook_opensearch.md)
- [docs/runbooks/runbook_portainer.md](docs/runbooks/runbook_portainer.md)
- [docs/runbooks/runbook_minio.md](docs/runbooks/runbook_minio.md)
- [docs/runbooks/runbook_spark.md](docs/runbooks/runbook_spark.md)
- [docs/runbooks/runbook_airflow.md](docs/runbooks/runbook_airflow.md)

---

## Gestión de secrets y certificados (Swarm)

Principios:

- ✅ No versionar secretos en Git (cubierto por `.gitignore`)
- ✅ Usar Docker Swarm secrets para valores sensibles
- ✅ Nombres en `snake_case`, con prefijo por stack (ej: `postgres_*`, `n8n_*`, `airflow_*`)

### Inventario de secrets

| Secret | Stack | Estado |
|--------|-------|--------|
| `traefik_basic_auth` | Traefik | ✅ Creado |
| `traefik_tls_cert` | Traefik | ✅ Creado |
| `traefik_tls_key` | Traefik | ✅ Creado |
| `jupyter_basicauth_v2` | Traefik/Jupyter | ✅ Creado |
| `ollama_basicauth` | Traefik/Ollama | ✅ Creado |
| `opensearch_basicauth` | Traefik/OpenSearch | ✅ Creado |
| `dashboards_basicauth` | Traefik/Dashboards | ✅ Creado |
| `pg_super_pass` | Postgres | ✅ Creado |
| `pg_n8n_pass` | Postgres, n8n | ✅ Creado |
| `pg_airflow_pass` | Postgres, Airflow | ⏳ **Crear antes de deploy** |
| `minio_access_key` | MinIO, Spark, Jupyter, Airflow | ⏳ **Crear antes de deploy** |
| `minio_secret_key` | MinIO, Spark, Jupyter, Airflow | ⏳ **Crear antes de deploy** |
| `airflow_fernet_key` | Airflow | ⏳ **Crear antes de deploy** |
| `airflow_webserver_secret` | Airflow | ⏳ **Crear antes de deploy** |

### Comandos para crear los secrets nuevos

```bash
# En master1 (Swarm manager):

# pg_airflow_pass
echo "$(openssl rand -base64 32)" | docker secret create pg_airflow_pass -

# MinIO credentials (access key: mínimo 3 chars, secret key: mínimo 8 chars)
echo "minioadmin" | docker secret create minio_access_key -
echo "$(openssl rand -base64 32)" | docker secret create minio_secret_key -

# Airflow Fernet key (DEBE ser una clave Fernet válida de 32 bytes base64url)
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" | docker secret create airflow_fernet_key -

# Airflow webserver secret key (Flask)
echo "$(openssl rand -hex 32)" | docker secret create airflow_webserver_secret -
```

---

## Inventario de endpoints (LAN)

| Servicio | URL | Estado |
|----------|-----|--------|
| **Traefik Dashboard** | `https://traefik.sexydad` | ✅ |
| **Portainer** | `https://portainer.sexydad` | ✅ |
| **n8n** | `https://n8n.sexydad` | ✅ |
| **Jupyter (ogiovanni)** | `https://jupyter-ogiovanni.sexydad` | ✅ |
| **Jupyter (odavid)** | `https://jupyter-odavid.sexydad` | ✅ |
| **Ollama** | `https://ollama.sexydad` | ✅ OPERATIVO |
| **OpenSearch API** | `https://opensearch.sexydad` | ✅ OPERATIVO |
| **OpenSearch Dashboards** | `https://dashboards.sexydad` | ✅ OPERATIVO |
| **MinIO Console** | `https://minio.sexydad` | ⏳ Pendiente deploy |
| **MinIO S3 API** | `https://minio-api.sexydad` | ⏳ Pendiente deploy |
| **Spark Master UI** | `https://spark-master.sexydad` | ⏳ Pendiente deploy |
| **Spark History Server** | `https://spark-history.sexydad` | ⏳ Pendiente deploy |
| **Airflow** | `https://airflow.sexydad` | ⏳ Pendiente deploy |
| **Airflow Flower** | `https://airflow-flower.sexydad` | ⏳ Pendiente deploy |

### /etc/hosts a configurar en clientes LAN

```
192.168.80.100  traefik.sexydad
192.168.80.100  portainer.sexydad
192.168.80.100  n8n.sexydad
192.168.80.100  opensearch.sexydad
192.168.80.100  dashboards.sexydad
192.168.80.100  ollama.sexydad
192.168.80.100  jupyter-ogiovanni.sexydad
192.168.80.100  jupyter-odavid.sexydad
192.168.80.100  minio.sexydad
192.168.80.100  minio-api.sexydad
192.168.80.100  spark-master.sexydad
192.168.80.100  spark-worker.sexydad
192.168.80.100  spark-history.sexydad
192.168.80.100  airflow.sexydad
192.168.80.100  airflow-flower.sexydad
```

---

## Fase 1 — Base del cluster (Swarm / red / labels)

### Docker + Swarm
- ✅ Docker instalado en master1
- ✅ Docker instalado en master2
- ✅ Swarm inicializado en master1 (manager/leader)
- ✅ master2 unido al Swarm como worker

Verificaciones:

- ✅ `docker node ls` muestra master1 (Leader) + master2 (Ready)
- ✅ `docker info` indica Swarm: active

### Networking (overlay)
- ✅ Red overlay `public` creada (attachable)
- ✅ Red overlay `internal` creada (attachable)

### Labels de nodos & Recursos
- ✅ Labels en master1 aplicados y verificados (ej: `tier=control`, `node_role=manager`)
- ✅ Labels en master2 aplicados y verificados (ej: `tier=compute`, `storage=primary`, `gpu=nvidia`)
- ✅ **Generic Resource GPU**: Registrada en `master2` (`nvidia.com/gpu=1`) para permitir `reservations` en Swarm mode.

Verificaciones:

- ✅ `docker node inspect master2 --format '{{ json .Description.Resources.GenericResources }}'` muestra la GPU.

**Resultado:** control-plane listo y red Swarm operativa con soporte GPU.

---

## Fase 2 — Storage en master2 (HDD datalake)

- ✅ Montaje `/srv/datalake` confirmado (HDD ~1.8T)
- ✅ Persistencia en `/etc/fstab` confirmada (LABEL/UUID) y montando

Verificaciones:

- ✅ `df -h | grep /srv/datalake` muestra tamaño esperado
- ✅ Reboot y remount validado

---

## Fase 3 — Volúmenes y estructura en master2 (NVMe fastdata + carpetas)

### LVM + montaje
- ✅ LVM creado: LV `fastdata` = 600G
- ✅ Formateado ext4 y montado en `/srv/fastdata`
- ✅ Persistencia vía `/etc/fstab` (UUID)
- ✅ Reboot real validado

### Estructura de carpetas existente

NVMe (rápido):
- ✅ `/srv/fastdata/postgres`
- ✅ `/srv/fastdata/n8n`
- ✅ `/srv/fastdata/opensearch`
- ✅ `/srv/fastdata/airflow`
- ✅ `/srv/fastdata/jupyter/{ogiovanni,odavid}`
- ✅ `/srv/fastdata/jupyter/{user}/.venv`
- ✅ `/srv/fastdata/jupyter/{user}/.local`

Nuevas carpetas a crear (Fase 5 — antes de deploy):
- ⏳ `/srv/fastdata/airflow/dags` — DAGs en master1 **y** master2
- ⏳ `/srv/fastdata/airflow/logs` — en master1
- ⏳ `/srv/fastdata/airflow/plugins` — en master1
- ⏳ `/srv/fastdata/airflow/redis` — en master1
- ⏳ `/srv/fastdata/spark-tmp` — en master2 (shuffle/spill Spark Worker)

HDD (datalake):
- ✅ `/srv/datalake/datasets`
- ✅ `/srv/datalake/models`
- ✅ `/srv/datalake/notebooks`
- ✅ `/srv/datalake/artifacts`
- ✅ `/srv/datalake/backups`
- ⏳ `/srv/datalake/minio` — en master2 (volumen principal de MinIO)

### Permisos para nuevas carpetas

```bash
# En master1:
sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins,redis}
sudo chown root:docker /srv/fastdata/airflow/{dags,logs,plugins,redis}
sudo chmod 2775 /srv/fastdata/airflow/{dags,logs,plugins,redis}
# Airflow corre como UID 50000:
sudo chown 50000:50000 /srv/fastdata/airflow/{dags,logs,plugins}

# En master2:
sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins}
sudo chown 50000:50000 /srv/fastdata/airflow/{dags,logs,plugins}

sudo mkdir -p /srv/fastdata/spark-tmp
sudo chown root:docker /srv/fastdata/spark-tmp
sudo chmod 2775 /srv/fastdata/spark-tmp

sudo mkdir -p /srv/datalake/minio
sudo chown root:docker /srv/datalake/minio
sudo chmod 2775 /srv/datalake/minio
```

**Resultado:** persistencia alineada para desplegar stateful sin sorpresas.

---

## Fase 4 — Infra como código (repo)

- ✅ Repo creado: `lab-infra-ia-bigdata`
- ✅ Estructura base aplicada (`docs/`, `envs/`, `scripts/`, `stacks/`, etc.)
- ✅ `.gitignore` cubre `.env`, `secrets/`, keys, passwords, etc.

---

## Bloque — Postgres (master2) ✅

Objetivo: Postgres stateful en Swarm, persistiendo en `/srv/fastdata/postgres`, accesible por red `internal`.

Secrets:
- ✅ `pg_super_pass`
- ✅ `pg_n8n_pass`
- ⏳ `pg_airflow_pass` — crear antes del redeploy

**IMPORTANTE al redesplegar**: PostgreSQL init scripts solo corren en volumen vacío.
Si el volumen ya tiene datos, hay que:
1. Bajar todos los servicios que usen Postgres (n8n, airflow)
2. `docker service rm postgres_postgres`
3. Borrar el volumen: `sudo rm -rf /srv/fastdata/postgres`
4. Redesplegar Postgres — los init scripts crearán n8n, airflow automáticamente.

Criterios de "OK":
- ✅ Servicio estable.
- ⏳ DB `airflow` y rol `airflow` creados por initdb.
- ✅ Persistencia verificada tras reinicio.

---

## Bloque — n8n (master2) ✅

Objetivo: n8n conectado a Postgres para automatización de flujos con acceso seguro vía Traefik.

Criterios de "OK":
- ✅ El servicio queda `running` y estable.
- ✅ Conexión a Postgres validada.
- ✅ URL responde: `https://n8n.sexydad`

---

## Bloque — Jupyter Lab (master2) ✅

Objetivo: Entorno Multi-usuario (ogiovanni, odavid) optimizado para IA/LLM/BigData con GPU.

Checklist:
- ✅ (Repo) Stack actualizado con kernels IA, LLM, BigData (PySpark + Delta + boto3)
- ✅ Reservations ajustadas (2 CPUs / 4GB) para dejar headroom a Spark + Airflow
- ✅ Secrets MinIO montados (`minio_access_key`, `minio_secret_key`)
- ✅ entrypoint.sh exporta `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL`
- ✅ GPU reservation habilitada

Criterios de "OK":
- ✅ Jupyter responde en: `https://jupyter-{user}.sexydad`
- ✅ `torch.cuda.is_available()` es `True`
- ✅ Kernel BigData puede conectarse a `spark://spark_master:7077`
- ✅ `boto3.client('s3', endpoint_url='http://minio:9000')` funciona

---

## Bloque — Ollama (master2) ✅ OPERATIVO

Estado actual:
- ✅ **OPERATIVO** - Servicio desplegado y corriendo en master2.
- ✅ GPU detectada y disponible (11GB VRAM). Versión: 0.6.1
- ✅ API REST respondiendo correctamente.
- ⏳ Pendiente: Descargar modelos LLM (bajo demanda).

---

## Bloque — OpenSearch (master1) ✅ OPERATIVO

Estado actual:
- ✅ **OPERATIVO** - Cluster status GREEN, versión 2.19.4
- ✅ OpenSearch Dashboards UI operativa.

---

## Bloque — MinIO (master2) ⏳ NEXT

Prerequisitos:
- ⏳ Secret `minio_access_key` creado en Swarm
- ⏳ Secret `minio_secret_key` creado en Swarm
- ⏳ Directorio `/srv/datalake/minio` creado en master2 con permisos correctos

Checklist:
- ✅ (Repo) Stack creado: [stacks/data/12-minio/stack.yml](stacks/data/12-minio/stack.yml)
- ✅ (Repo) Runbook: [docs/runbooks/runbook_minio.md](docs/runbooks/runbook_minio.md)
- ⏳ Deploy: `docker stack deploy -c stacks/data/12-minio/stack.yml minio`
- ⏳ Crear buckets Medallion Architecture via MinIO Console o `mc`:
  - `bronze`          → capa raw (CSV/JSON/Parquet, append-only)
  - `silver`          → capa curated (Delta Lake, ACID)
  - `gold`            → capa business (Delta Lake, KPIs/ML features)
  - `lab-notebooks`   → exports de notebooks
  - `airflow-logs`    → logs de tareas Airflow
  - `spark-warehouse` (y dentro: `spark-warehouse/history/`)

Criterios de "OK":
- ⏳ `https://minio.sexydad` responde con UI de MinIO
- ⏳ `https://minio-api.sexydad/minio/health/live` → HTTP 200
- ⏳ Bucket `spark-warehouse` existe (requerido por Spark History Server)

---

## Bloque — Spark (master1 + master2) ⏳

Prerequisitos:
- ⏳ **MinIO operativo** y bucket `spark-warehouse/history` creado
- ⏳ Directorio `/srv/fastdata/spark-tmp` creado en master2
- ⏳ Secret `minio_access_key` y `minio_secret_key` existentes

Checklist:
- ✅ (Repo) Stack creado: [stacks/data/98-spark/stack.yml](stacks/data/98-spark/stack.yml)
- ✅ (Repo) Runbook: [docs/runbooks/runbook_spark.md](docs/runbooks/runbook_spark.md)
- ⏳ Deploy: `docker stack deploy -c stacks/data/98-spark/stack.yml spark`

Criterios de "OK":
- ⏳ `https://spark-master.sexydad` muestra UI del Master con 1 worker alive
- ⏳ Worker registrado con 10 CPUs / 14 GB
- ⏳ PySpark desde Jupyter puede conectar: `spark://spark_master:7077`

---

## Bloque — Airflow (master1 + master2) ⏳

Prerequisitos:
- ⏳ **Postgres redespliegue** (para que init script cree DB airflow)
- ⏳ Secret `pg_airflow_pass` creado
- ⏳ Secret `airflow_fernet_key` creado
- ⏳ Secret `airflow_webserver_secret` creado
- ⏳ Secrets `minio_access_key`, `minio_secret_key` existentes
- ⏳ Directorios en master1 y master2 creados (ver Fase 3)

Checklist:
- ✅ (Repo) Stack creado: [stacks/automation/03-airflow/stack.yml](stacks/automation/03-airflow/stack.yml)
- ✅ (Repo) Init script DB: [stacks/core/02-postgres/initdb/02-init-airflow.sh](stacks/core/02-postgres/initdb/02-init-airflow.sh)
- ✅ (Repo) Runbook: [docs/runbooks/runbook_airflow.md](docs/runbooks/runbook_airflow.md)
- ⏳ Redesplegar Postgres (volumen limpio → init scripts corren)
- ⏳ Deploy Redis + Airflow:
  ```bash
  docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow
  ```
- ⏳ Inicializar DB Airflow (una sola vez):
  ```bash
  docker service scale airflow_airflow_init=1
  # Verificar logs hasta ver "DB migrations done"
  docker service scale airflow_airflow_init=0
  ```
- ⏳ Crear usuario admin en Airflow UI

Criterios de "OK":
- ⏳ `https://airflow.sexydad` muestra UI de Airflow
- ⏳ `https://airflow-flower.sexydad` muestra Flower con 1 worker online
- ⏳ Scheduler y Worker en estado `running`
- ⏳ DAG de prueba ejecuta con estado `success`

Nota sobre Remote Logging:
- Remote logging a MinIO está **deshabilitado** por defecto.
- Habilitarlo después (Fase 6): crear conexión `minio_s3` en UI, luego cambiar `REMOTE_LOGGING: "true"`.

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

- ✅ El orden de prioridad es: **MinIO** → **Spark** → **Airflow** (Airflow depende de ambos)
- ✅ La GPU se reserva para stacks en `master2`: Jupyter, Ollama (genérica), no Spark/Airflow.
- ✅ Remote logging de Airflow deshabilitado para primer deploy — habilitar en Fase 6.
- ✅ `dag_airflow_dags` se monta en master1 (webserver/scheduler) Y en master2 (worker).
  - Opción A (actual): misma estructura de dirs; el usuario copia/sincroniza DAGs manualmente.
  - Opción B (futura): NFS share o git-sync sidecar.
- ✅ HDFS descartado: MinIO como objeto storage es suficiente para lab (512MB vs 3+ GB).
- ✅ CeleryExecutor elegido sobre LocalExecutor: realismo productivo + worker distribuido en master2.

---

## Changelog Reciente

### 2026-03-30: Fase 5 — MinIO + Spark + Airflow (stacks listos) ⏳ Pendiente deploy
- ✅ `stacks/data/12-minio/stack.yml` — MinIO RELEASE.2024-11-07, storage en /srv/datalake/minio
- ✅ `stacks/data/98-spark/stack.yml` — bitnami/spark:3.5.3, master en master1, worker en master2
- ✅ `stacks/automation/03-airflow/stack.yml` — apache/airflow:2.9.3, CeleryExecutor + Redis
- ✅ `stacks/core/02-postgres/initdb/02-init-airflow.sh` — crea DB airflow + rol
- ✅ `stacks/core/02-postgres/stack.yml` — POSTGRES_DB cambiado a 'postgres' (neutral), agrega pg_airflow_pass
- ✅ `stacks/ai-ml/01-jupyter/stack.yml` — reservations optimizados, secrets MinIO, mounts datalake
- ✅ `stacks/ai-ml/01-jupyter/init-kernels.sh` — kernel BigData (pyspark + delta-spark + boto3 + s3fs)
- ✅ `stacks/ai-ml/01-jupyter/entrypoint.sh` — exporta AWS_ACCESS_KEY_ID/SECRET desde secrets
- ✅ `stacks/ai-ml/02-ollama/stack.yml` — imagen pinned a 0.6.1
- ✅ `docs/hosts/master2/etc/docker/daemon.json` — agregado default-runtime: nvidia + runtimes block
- ✅ `docs/architecture/NODES.md` — servicios actualizados para Fase 5
- ✅ `docs/architecture/NETWORKING.md` — dominios y puertos Fase 5
- ✅ `docs/architecture/STORAGE.md` — paths nuevos: minio, spark-tmp, airflow subdirs
- ✅ `docs/runbooks/runbook_minio.md` — nuevo
- ✅ `docs/runbooks/runbook_spark.md` — nuevo
- ✅ `docs/runbooks/runbook_airflow.md` — nuevo

### 2026-03-30: Portainer Upgrade + Docs restructuración ✅
- ✅ Portainer CE + Agent actualizados: **2.21.0 → 2.39.1**
- ✅ README raíz reescrito con arquitectura completa
- ✅ 6 ADRs documentados en `docs/adrs/`
- ✅ Runbooks para OpenSearch, Ollama, Jupyter, Portainer

### 2026-02-04: OpenSearch Stack DEPLOYED ✅
- ✅ Cluster status: **GREEN**, versión 2.19.4, UI Dashboards operativa

### 2026-02-03: Ollama Stack DEPLOYED ✅
- ✅ GPU RTX 2080 Ti detectada (11GB VRAM), API REST funcional

### Estado anterior:
- ✅ Jupyter multi-usuario operativo (ogiovanni, odavid) con GPU
- ✅ n8n + Postgres + Portainer + Traefik operativos
