# Checklist de Infra — lab-infra-ia-bigdata

Última actualización: 2026-02-02

Este documento centraliza el **estado real** (OK / Pendiente) para levantar la infraestructura completa del laboratorio, con **orden recomendado**, **dependencias** y **verificaciones mínimas**.

---

## Leyenda

- ✅ **OK**: implementado y verificado.
- [ ] **PEND**: falta implementar o verificar.
- [~] **PEND (no bloquea)**: pendiente, pero no impide continuar con el siguiente bloque.
- **NEXT**: siguiente bloque de trabajo sugerido.

---

## Prerequisitos generales (antes de cualquier stack)

Acceso y base del sistema:

- ✅ Acceso SSH entre nodos (master1 ↔ master2) operativo
- ✅ Docker Engine instalado y funcionando en ambos nodos
- ✅ Usuarios operativos con permisos (ideal: pertenecer al grupo `docker`)

Red / naming:

- ✅ Hostnames internos con sufijo `<INTERNAL_DOMAIN>` definidos
- ✅ Resolución desde LAN validada (incluye pruebas con `--resolve` desde master2)
- [ ] (Opcional) DNS interno formal para `*.<INTERNAL_DOMAIN>` (router/DNS local) [~]

Hardening mínimo recomendado (no bloquea, pero conviene):

- [ ] Actualizaciones de seguridad aplicadas (apt/yum) [~]
- [ ] Sincronización horaria (NTP/chrony) verificada [~]
- [ ] Firewall revisado (puertos Swarm + 80/443 en master1) [~]

---

## Resumen ejecutivo (orden de despliegue)

1) Traefik ✅
2) Portainer ✅
3) Postgres ✅
4) **n8n** (depende de Postgres)
5) OpenSearch
6) Jupyter / Ollama
7) (Último) Airflow + Spark
8) Backups / migraciones / hardening

---

## Mapa del repo (dónde vive cada stack)

Stacks ya implementados:

- Traefik: `stacks/core/00-traefik/stack.yml` (+ `stacks/core/00-traefik/dynamic.yml`)
- Portainer: `stacks/core/01-portainer/stack.yml`
- Postgres: `stacks/core/02-postgres/stack.yml` (+ initdb en `stacks/core/02-postgres/initdb/`)

Carpetas creadas (pendiente definir `stack.yml`):

- OpenSearch: `stacks/data/11-opensearch/`
- Spark: `stacks/data/98-spark/`
- n8n: `stacks/automation/02-n8n/`
- Airflow: `stacks/automation/99-airflow/`
- Jupyter: `stacks/ai-ml/20-jupyter/`
- Ollama: `stacks/ai-ml/21-ollama/`

Env de ejemplo existente:

- Traefik (config no sensible): `envs/examples/core-traefik.env.example`

---

## Gestión de secrets y certificados (Swarm)

Principios:

- ✅ No versionar secretos en Git (cubierto por `.gitignore`)
- ✅ Usar Docker Swarm secrets para valores sensibles

Convención sugerida (para lo que viene):

- [ ] Nombres en `snake_case`, con prefijo por stack (ej: `postgres_*`, `n8n_*`, `airflow_*`)
- [ ] Mantener secretos “por servicio” (evita reusar passwords entre stacks)

Traefik (actual):

- ✅ `traefik_basic_auth`
- ✅ `traefik_tls_cert`
- ✅ `traefik_tls_key`

Pendiente (por definir para stacks siguientes):

- ✅ Postgres: `pg_super_pass` y `pg_n8n_pass` creados (Swarm secrets externos)
- [ ] n8n: encryption key + credenciales admin (si aplica)
- [ ] OpenSearch: credenciales/usuarios (si se expone)
- [ ] Airflow: fernet key + credenciales/conexiones (si aplica)

Operación:

- [ ] Documentar procedimiento de creación/rotación de secrets (runbook) [~]
- [ ] Definir política de backup/restore de secretos (según tu enfoque) [~]

---

## Inventario de endpoints (LAN)

- ✅ Traefik dashboard: `https://traefik.<INTERNAL_DOMAIN>`
- ✅ Portainer: `https://portainer.<INTERNAL_DOMAIN>`
- [ ] n8n: `https://n8n.<INTERNAL_DOMAIN>`
- [ ] Jupyter: `https://jupyter.<INTERNAL_DOMAIN>`
- [ ] OpenSearch (si se publica): `https://opensearch.<INTERNAL_DOMAIN>`
- [ ] Airflow: `https://airflow.<INTERNAL_DOMAIN>`

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

Verificaciones:

- ✅ `docker network ls` lista `public` e `internal` como `overlay`
- ✅ Redes marcadas como `attachable`

### Labels de nodos
- ✅ Labels en master1 aplicados y verificados (ej: `tier=control`, `node_role=manager`)
- ✅ Labels en master2 aplicados y verificados (ej: `tier=compute`, `storage=primary`, `gpu=nvidia`)

Verificaciones:

- ✅ `docker node inspect <node> --format '{{ json .Spec.Labels }}'` refleja los labels esperados

**Resultado:** control-plane listo y red Swarm operativa.

---

## Fase 2 — Storage en master2 (HDD datalake)

- ✅ Montaje `/srv/datalake` confirmado (HDD ~1.8T)
- ✅ Persistencia en `/etc/fstab` confirmada (LABEL/UUID) y montando

Verificaciones:

- ✅ `df -h | grep /srv/datalake` muestra tamaño esperado
- ✅ Reboot y remount validado

Pendientes (más adelante; no bloquea Postgres/n8n):
- [ ] Backups master2 → master1 (rsync/restic + cron/systemd timer) [~]

---

## Fase 3 — Volúmenes y estructura en master2 (NVMe fastdata + carpetas)

### LVM + montaje
- ✅ LVM creado: LV `fastdata` = 600G
- ✅ Formateado ext4 y montado en `/srv/fastdata`
- ✅ Persistencia vía `/etc/fstab` (UUID)
- ✅ Reboot real validado

Verificaciones:

- ✅ `lsblk -f` refleja UUID correcto
- ✅ `df -h | grep /srv/fastdata` muestra el LV montado

### Estructura de carpetas
NVMe (rápido):
- ✅ `/srv/fastdata/postgres`
- ✅ `/srv/fastdata/opensearch`
- ✅ `/srv/fastdata/airflow`

Nota (para evitar confusiones):

- Portainer hoy persiste en master1 en `/srv/portainer/data` (ver stack actual).
- Traefik no persiste data en disco (solo configs/secrets montados por Swarm).

HDD (datalake):
- ✅ `/srv/datalake/datasets`
- ✅ `/srv/datalake/models`
- ✅ `/srv/datalake/notebooks`
- ✅ `/srv/datalake/artifacts`
- ✅ `/srv/datalake/backups`

Permisos/ownership:
- ✅ Ownership `root:docker`
- ✅ Permisos 2775 aplicados

Verificaciones:

- ✅ `stat -c '%U:%G %a %n' /srv/fastdata` y subdirectorios coherentes
- ✅ Bit SGID (2) presente para herencia de grupo

**Resultado:** persistencia alineada para desplegar stateful sin sorpresas.

---

## Fase 4 — Infra como código (repo)

- ✅ Repo creado: `lab-infra-ia-bigdata`
- ✅ Estructura base aplicada (`docs/`, `envs/`, `scripts/`, `stacks/`, etc.)
- ✅ `.gitignore` cubre `.env`, `secrets/`, keys, passwords, etc.
- ✅ Push a `main` resuelto
- ✅ Stacks versionados: Traefik y Portainer

Pendientes recomendados (repo):

- [ ] Crear runbooks en `docs/runbooks/` (deploy/rollback/backup/restore) [~]
- [ ] Completar `envs/examples/` para cada stack (solo config no sensible) [~]
- [ ] Crear `scripts/verify/` (healthchecks post-deploy) [~]
- [ ] Crear `scripts/backup/` (helpers para dumps/snapshots) [~]

---

## Fase 5 — Stack base en Swarm (ordenado)

### 5.1 Traefik (master1 / control)
- ✅ Traefik desplegado en Swarm (stack de Traefik)
- ✅ Hostnames internos con sufijo `<INTERNAL_DOMAIN>`
- ✅ Acceso validado desde LAN (incluye `--resolve` desde master2)
- ✅ Seguridad mínima aplicada:
  - ✅ `lan-whitelist` (<LAN_CIDR>)
  - ✅ BasicAuth (secret `traefik_basic_auth`)
- ✅ Error “port is missing” corregido (loadbalancer.server.port=8080 para dashboard/router)
- ✅ TLS interno activo (y redirect a https), operativo para gateway LAN

Secrets (requeridos por el stack):

- ✅ Secret `traefik_basic_auth` creado (usersfile)
- ✅ Secret `traefik_tls_cert` creado
- ✅ Secret `traefik_tls_key` creado

Verificaciones:

- ✅ `docker service ls | grep traefik` muestra el servicio estable
- ✅ `docker service ps traefik_traefik` sin errores repetidos
- ✅ Acceso: `https://traefik.<INTERNAL_DOMAIN>/dashboard/` responde (con BasicAuth y LAN whitelist)

En repo (fuente de verdad):

- `stacks/core/00-traefik/stack.yml`
- `stacks/core/00-traefik/dynamic.yml`

Prerequisitos del stack (según `stack.yml`):

- Secrets externos requeridos:
  - `traefik_basic_auth`
  - `traefik_tls_cert`
  - `traefik_tls_key`
- Redes Swarm externas requeridas: `public`, `internal`
- Hostnames configurados:
  - `https://traefik.<INTERNAL_DOMAIN>` (dashboard; rutas `/dashboard` y `/api`)

Comando típico de despliegue:

- `docker stack deploy -c stacks/core/00-traefik/stack.yml traefik`

### 5.2 Portainer (server en master1 / agent global)
- ✅ Portainer Server desplegado en master1
- ✅ Persistencia confirmada en `/srv/portainer/data`
- ✅ Portainer Agent corriendo global (2/2)
- ✅ Acceso por Traefik: `https://portainer.<INTERNAL_DOMAIN>/` (200 OK desde master2)
- ✅ Wizard conecta el entorno local (issue inicial resuelto)

Verificaciones:

- ✅ `docker service ps portainer_agent` corre en ambos nodos (modo global)
- ✅ `docker service ps portainer_portainer` corre en master1 (constraint tier=control)
- ✅ Acceso: `https://portainer.<INTERNAL_DOMAIN>/` responde desde LAN

En repo (fuente de verdad):

- `stacks/core/01-portainer/stack.yml`

Detalle relevante del stack actual:

- Servicios: `portainer` (replica 1) + `agent` (global)
- Persistencia: volumen host `/srv/portainer/data:/data`
- Hostname configurado: `https://portainer.<INTERNAL_DOMAIN>`

Comando típico de despliegue:

- `docker stack deploy -c stacks/core/01-portainer/stack.yml portainer`

Pendiente (upgrade / migración al final):
- [ ] Upgrade Portainer (sugerido 2.33.6) con backup + rollback plan

---

## Bloque — Postgres (master2) ✅

Objetivo: Postgres stateful en Swarm, persistiendo en `/srv/fastdata/postgres`, accesible por red `internal` para `n8n`.

Prerequisitos:

- ✅ Redes Swarm: `internal` (y `public` si se expone algo; recomendado NO)
- ✅ Directorio en master2: `/srv/fastdata/postgres`
- ✅ Secrets de Postgres creados en Swarm (passwords)

Secrets esperados (según stack actual `stacks/core/02-postgres/stack.yml`):

- ✅ `pg_super_pass` (password del usuario `postgres`)
- ✅ `pg_n8n_pass` (password del usuario/rol `n8n`)

Creación (ejemplo; ejecutar una sola vez por Swarm):

- [ ] `printf '%s' '<SUPER_PASS>' | docker secret create pg_super_pass -`
- [ ] `printf '%s' '<N8N_PASS>' | docker secret create pg_n8n_pass -`

Comando típico de despliegue:

- `docker stack deploy -c stacks/core/02-postgres/stack.yml postgres`

Checklist:
- ✅ (Repo) Stack definido: `stacks/core/02-postgres/stack.yml`
- ✅ (Repo) Init script para n8n: `stacks/core/02-postgres/initdb/01-init-n8n.sh`
- ✅ Crear secrets (`pg_super_pass`, `pg_n8n_pass`)
- ✅ Revisar/confirmar placement constraint del servicio (hoy: `node.hostname == master2`)
- ✅ Desplegar stack Postgres
- ✅ Verificar health/ready y persistencia real en `/srv/fastdata/postgres`
- ✅ Verificar que DB `n8n` + rol `n8n` quedan creados por initdb
- ✅ Validar conectividad desde un contenedor en la red `internal`
- [ ] Definir estrategia de backup (lógico) y ubicación (ideal: `/srv/datalake/backups`) [~]

Criterios de “OK” (mínimos):
- ✅ El servicio queda `running` y estable (sin restart loop)
- ✅ Al reiniciar el contenedor/servicio, la data persiste
- ✅ Existe DB `n8n` y rol `n8n`, y `n8n` puede conectar

Checks sugeridos (post-deploy):

- ✅ `docker service ls | grep postgres`
- ✅ `docker service ps postgres_postgres` sin errores
- ✅ Logs limpios (sin crashloop): `docker service logs postgres_postgres --tail 200`
- ✅ Validar objetos creados (desde el contenedor):
  - `docker exec -it $(docker ps --filter name=postgres_postgres -q | head -n1) psql -U postgres -d n8n -c "\\du"`
  - `docker exec -it $(docker ps --filter name=postgres_postgres -q | head -n1) psql -U postgres -d n8n -c "\\l"`
- ✅ Conectividad por overlay `internal` (desde un contenedor temporal):
  - `docker run --rm -it --network internal postgres:16 psql -h postgres -U n8n -d n8n`
- ✅ Persistencia: reiniciar servicio y confirmar que el directorio `/srv/fastdata/postgres` conserva data

---

## Bloque siguiente — n8n (master2)

Dependencias:
- Requiere Postgres OK.
- Requiere red `internal` operativa (ya OK).

Prerequisitos:

- ✅ Red Swarm: `internal`
- ✅ Traefik en `public` (si se va a publicar por HTTPS)
- [ ] Secrets de n8n (encryption key, etc.) creados (pendiente)

Secrets esperados (propuesto):

- [ ] `n8n_encryption_key`
- [ ] `n8n_admin_password` (si vas a forzar un admin/bootstrapping)

Comando típico de despliegue (cuando exista `stack.yml`):

- `docker stack deploy -c stacks/automation/02-n8n/stack.yml n8n`

Checklist:
- [ ] (Repo) Crear `stacks/automation/02-n8n/stack.yml`
- [ ] (Repo) Agregar `envs/examples/automation-n8n.env.example` (sin secretos) o documentar variables
- [ ] Definir env/secrets de n8n (URL pública interna, encryption key si aplica)
- [ ] Definir persistencia de n8n (volumen para datos/config según el modo elegido)
- [ ] Desplegar n8n en master2 (placement)
- [ ] Conectar a Postgres vía `internal`
- [ ] Exponer por Traefik con TLS interno
- [ ] Validar login, creación de workflow y persistencia

Criterios de “OK” (mínimos):

- [ ] El servicio queda `running` y estable
- [ ] Conexión a Postgres OK (sin errores de migración/reintentos)
- [ ] URL responde por Traefik (si se publica): `https://n8n.<INTERNAL_DOMAIN>`

Pendientes comunes de seguridad (n8n):

- [ ] Definir credenciales admin y políticas de acceso
- [ ] Revisar variables sensibles (encryption key) como Docker secrets

---

## Bloque siguiente — OpenSearch (master2)

Prerequisitos:

- ✅ Directorio en master2: `/srv/fastdata/opensearch`
- ✅ Red Swarm: `internal` (recomendado)
- [ ] Definir recursos mínimos (RAM/heap) (pendiente)

Secrets esperados (propuesto, si se habilita auth/seguridad):

- [ ] `opensearch_admin_password`

Comando típico de despliegue (cuando exista `stack.yml`):

- `docker stack deploy -c stacks/data/11-opensearch/stack.yml opensearch`

Checklist:
- [ ] (Repo) Crear `stacks/data/11-opensearch/stack.yml`
- [ ] (Repo) Agregar `envs/examples/data-opensearch.env.example` (sin secretos) o documentar variables
- [ ] Desplegar OpenSearch stateful en `/srv/fastdata/opensearch`
- [ ] Ajustar límites/ulimits/sysctl requeridos (si aplica)
- [ ] Exponer (si corresponde) por Traefik o solo `internal`
- [ ] Validar health y persistencia

Criterios de “OK” (mínimos):

- [ ] El servicio queda `running` y estable
- [ ] Health responde desde `internal` (endpoint de salud)
- [ ] Persistencia validada tras reinicio

Pendientes comunes (OpenSearch):

- [ ] Definir heap size y límites de memoria
- [ ] Definir autenticación/usuarios si se expone más allá de `internal`

---

## Bloque siguiente — Jupyter / Ollama (master2)

Prerequisitos:

- ✅ Datos disponibles en datalake: `/srv/datalake/{notebooks,datasets,models}`
- ✅ Red Swarm: `internal` (y `public` si se publica por Traefik)
- [ ] Definir si Jupyter se publica por Traefik y con qué auth (pendiente)

Secrets esperados (propuesto, si se publica Jupyter):

- [ ] `jupyter_token` (o alternativa equivalente)

Comandos típicos de despliegue (cuando existan `stack.yml`):

- `docker stack deploy -c stacks/ai-ml/20-jupyter/stack.yml jupyter`
- `docker stack deploy -c stacks/ai-ml/21-ollama/stack.yml ollama`

Checklist:
- [ ] (Repo) Crear `stacks/ai-ml/20-jupyter/stack.yml`
- [ ] Desplegar Jupyter (stack `stacks/ai-ml/20-jupyter/`)
- [ ] Montar notebooks/datasets desde `/srv/datalake/{notebooks,datasets}`
- [ ] (Repo) Crear `stacks/ai-ml/21-ollama/stack.yml`
- [ ] Desplegar Ollama (stack `stacks/ai-ml/21-ollama/`)
- [ ] (Opcional) Configurar acceso a GPU en master2 (si aplica)
- [ ] Validar conectividad entre servicios (si se integran)

Criterios de “OK” (mínimos):

- [ ] Jupyter responde (interno o por Traefik): `https://jupyter.<INTERNAL_DOMAIN>` si se publica
- [ ] Acceso a notebooks/datasets montados
- [ ] Ollama responde (API interna) y persiste modelos donde se definió

Pendientes comunes (AI/ML):

- [ ] Definir límites de recursos (CPU/RAM/GPU) por servicio
- [ ] Definir persistencia de modelos (Ollama) y ubicación (fastdata vs datalake)

---

## Bloque ÚLTIMO — Airflow y Spark

Prerequisitos:

- ✅ Directorio en master2: `/srv/fastdata/airflow`
- [ ] Postgres OK (para metadata DB) (pendiente)
- [ ] Definir si Airflow se publica por Traefik: `https://airflow.<INTERNAL_DOMAIN>` (pendiente)

Secrets esperados (propuesto):

- [ ] `airflow_fernet_key`
- [ ] `airflow_webserver_secret_key`
- [ ] `airflow_admin_password` (si creas admin por bootstrap)

Comandos típicos de despliegue (cuando existan `stack.yml`):

- `docker stack deploy -c stacks/automation/99-airflow/stack.yml airflow`
- `docker stack deploy -c stacks/data/98-spark/stack.yml spark`

Checklist:
- [ ] (Repo) Crear `stacks/automation/99-airflow/stack.yml`
- [ ] Definir arquitectura mínima de Airflow (webserver/scheduler/worker/triggerer)
- [ ] Persistencia en `/srv/fastdata/airflow`
- [ ] Integración con Postgres (metadata DB)
- [ ] (Repo) Crear `stacks/data/98-spark/stack.yml`
- [ ] Desplegar Spark (según stack `stacks/data/98-spark/` o el que definas)
- [ ] Validar jobs end-to-end

Criterios de “OK” (mínimos):

- [ ] Airflow web UI responde (interno o por Traefik)
- [ ] Scheduler/worker activos y ejecutan un DAG de prueba
- [ ] Spark ejecuta un job simple (smoke test)

Pendientes comunes (Airflow/Spark):

- [ ] Definir cómo se versionan DAGs/jobs (repo, volumen, o sync desde datalake)
- [ ] Definir conexiones/secretos de Airflow (backend + conexiones externas)

---

## Backups, hardening y operaciones (recomendado al final, pero planificar ya)

### Backups (prioridad media)
- [ ] Backup master2 → master1 (rsync/restic)
- [ ] Política de retención (diario/semanal/mensual)
- [ ] Prueba de restore (no se considera OK sin restore)

Pendientes adicionales recomendados:

- [ ] Runbook de restore por servicio (Postgres/n8n/OpenSearch/etc.)
- [ ] Validación de restore en frío (parar servicio → restore → levantar)

### Migraciones
- [ ] Portainer upgrade con backup + rollback

### Observabilidad (si la vas a incluir)
- [ ] Logs centralizados (opcional)
- [ ] Métricas/alertas (opcional)

---

## Notas / decisiones

- Mantener el orden: Postgres → n8n → OpenSearch → Jupyter/Ollama → Airflow/Spark.
- Backups no bloquean el despliegue inicial, pero deben quedar antes de “producción real”.