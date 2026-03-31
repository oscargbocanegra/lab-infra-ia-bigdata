# Arquitectura del Laboratorio — lab-infra-ia-bigdata

> Última actualización: 2026-03-31 — Lab 100% operativo (20 servicios)

---

## Índice

1. [Visión general](#1-visión-general)
2. [Diagrama físico del clúster](#2-diagrama-físico-del-clúster)
3. [Diagrama lógico de servicios](#3-diagrama-lógico-de-servicios)
4. [Flujo de tráfico LAN](#4-flujo-de-tráfico-lan)
5. [Flujo de datos en pipelines AI/Data](#5-flujo-de-datos-en-pipelines-aidata)
6. [Estrategia de placement](#6-estrategia-de-placement)
7. [Redes Docker Swarm](#7-redes-docker-swarm)
8. [Modelo de seguridad](#8-modelo-de-seguridad)
9. [Decisiones arquitecturales clave](#9-decisiones-arquitecturales-clave)

---

## 1. Visión general

El laboratorio es un clúster **Docker Swarm de 2 nodos** orientado a experimentación con **IA, Big Data y automatización**. El diseño sigue un principio de **separación de responsabilidades**:

- **master1** (Control Plane): gateway, orquestación, servicios ligeros
- **master2** (Compute + Data): workloads GPU, bases de datos, almacenamiento primario

Todo el tráfico externo ingresa por **Traefik** (en master1) vía HTTPS con TLS self-signed, accesible solo desde LAN `192.168.80.0/24`.

---

## 2. Diagrama físico del clúster

```
┌─────────────────────────────────────────────────────────────────────┐
│                        LAN 192.168.80.0/24                          │
│                                                                     │
│  ┌──────────────────────────┐    ┌──────────────────────────────┐   │
│  │        master1           │    │          master2             │   │
│  │   (Control Plane)        │    │    (Compute + Data + GPU)    │   │
│  │                          │    │                              │   │
│  │  Intel i7-6700T          │    │  Intel i9-9900K              │   │
│  │  4C/8T @ 2.8 GHz         │    │  8C/16T @ 3.6 GHz            │   │
│  │  32 GB RAM               │    │  32 GB RAM                   │   │
│  │                          │    │                              │   │
│  │  💾 HDD 500 GB (ROTA)    │    │  💾 NVMe 1TB (970 EVO)       │   │
│  │  └─ /srv/fastdata        │    │  └─ /srv/fastdata (LVM 600G) │   │
│  │     (HDD local)          │    │     postgres/ opensearch/    │   │
│  │                          │    │     airflow/ jupyter/        │   │
│  │  Swarm: MANAGER/LEADER   │    │  💾 HDD 2TB (ST2000LM015)   │   │
│  │  Labels:                 │    │  └─ /srv/datalake            │   │
│  │   tier=control           │    │     datasets/ models/        │   │
│  │   node_role=manager      │    │     notebooks/ artifacts/    │   │
│  │   storage=backup         │    │     backups/                 │   │
│  │   net=lan                │    │                              │   │
│  │                          │    │  🎮 NVIDIA RTX 2080 Ti       │   │
│  │                          │    │     11 GB VRAM               │   │
│  │                          │    │     CUDA 12.2                │   │
│  │                          │    │     Driver 535.288.01        │   │
│  │                          │    │                              │   │
│  │                          │    │  Swarm: WORKER               │   │
│  │                          │    │  Labels:                     │   │
│  │                          │    │   tier=compute               │   │
│  │                          │    │   node_role=worker           │   │
│  │                          │    │   storage=primary            │   │
│  │                          │    │   gpu=nvidia                 │   │
│  │                          │    │   net=lan                    │   │
│  └──────────┬───────────────┘    └──────────────┬───────────────┘   │
│             │                                   │                   │
│             └──────────── Overlay Networks ─────┘                   │
│                    (public + internal)                               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Diagrama lógico de servicios

```
╔══════════════════════════════════════╗  ╔═══════════════════════════════════════════╗
║         master1  (tier=control)      ║  ║         master2  (tier=compute)           ║
╠══════════════════════════════════════╣  ╠═══════════════════════════════════════════╣
║                                      ║  ║                                           ║
║  ┌──────────────────────────────┐    ║  ║  ┌──────────────────────────────────┐    ║
║  │  Traefik v2.11               │    ║  ║  │  PostgreSQL 16                   │    ║
║  │  :80 :443 (host mode)        │    ║  ║  │  /srv/fastdata/postgres (NVMe)   │    ║
║  │  Reverse Proxy + TLS + LAN   │    ║  ║  │  :5432 (host mode)               │    ║
║  └──────────────────────────────┘    ║  ║  │  bases: postgres / n8n / airflow │    ║
║                                      ║  ║  └──────────────────────────────────┘    ║
║  ┌──────────────────────────────┐    ║  ║                                           ║
║  │  Portainer CE 2.39.1         │    ║  ║  ┌──────────────────────────────────┐    ║
║  │  /srv/fastdata/portainer     │    ║  ║  │  n8n 2.4.7                       │    ║
║  │  → tcp://tasks.agent:9001    │    ║  ║  │  /srv/fastdata/n8n (NVMe)        │    ║
║  └──────────────────────────────┘    ║  ║  │  → postgres:5432 (n8n DB)        │    ║
║                                      ║  ║  └──────────────────────────────────┘    ║
║  ┌──────────────────────────────┐    ║  ║                                           ║
║  │  OpenSearch 2.19.4           │    ║  ║  ┌──────────────────────────────────┐    ║
║  │  /srv/fastdata/opensearch    │    ║  ║  │  JupyterLab (ogiovanni)          │    ║
║  │  :9200 (internal)            │    ║  ║  │  /srv/fastdata/jupyter/ogiovanni │    ║
║  └──────────────────────────────┘    ║  ║  │  GPU + 8CPU + 12GB — uid 1000    │    ║
║                                      ║  ║  └──────────────────────────────────┘    ║
║  ┌──────────────────────────────┐    ║  ║                                           ║
║  │  OpenSearch Dashboards       │    ║  ║  ┌──────────────────────────────────┐    ║
║  │  2.19.4  :5601               │    ║  ║  │  JupyterLab (odavid)             │    ║
║  └──────────────────────────────┘    ║  ║  │  /srv/fastdata/jupyter/odavid    │    ║
║                                      ║  ║  │  GPU + 8CPU + 12GB — uid 1001    │    ║
║  ┌──────────────────────────────┐    ║  ║  └──────────────────────────────────┘    ║
║  │  Redis 7.2 (Celery broker)   │    ║  ║                                           ║
║  │  /srv/fastdata/airflow/redis │    ║  ║  ┌──────────────────────────────────┐    ║
║  └──────────────────────────────┘    ║  ║  │  Ollama 0.6.1                    │    ║
║                                      ║  ║  │  /srv/datalake/models/ollama     │    ║
║  ┌──────────────────────────────┐    ║  ║  │  GPU RTX 2080 Ti (11 GB VRAM)    │    ║
║  │  Airflow Webserver 2.9.3     │    ║  ║  │  :11434 (internal)               │    ║
║  │  /srv/fastdata/airflow/dags  │    ║  ║  └──────────────────────────────────┘    ║
║  │  :8080 (internal)            │    ║  ║                                           ║
║  └──────────────────────────────┘    ║  ║  ┌──────────────────────────────────┐    ║
║                                      ║  ║  │  MinIO RELEASE.2024-11-07        │    ║
║  ┌──────────────────────────────┐    ║  ║  │  /srv/datalake/minio (HDD 2TB)   │    ║
║  │  Airflow Scheduler           │    ║  ║  │  :9000 S3 API / :9001 Console    │    ║
║  │  /srv/fastdata/airflow/dags  │    ║  ║  └──────────────────────────────────┘    ║
║  └──────────────────────────────┘    ║  ║                                           ║
║                                      ║  ║  ┌──────────────────────────────────┐    ║
║  ┌──────────────────────────────┐    ║  ║  │  Spark Worker 3.5.3              │    ║
║  │  Airflow Flower              │    ║  ║  │  /srv/fastdata/spark-tmp (NVMe)  │    ║
║  │  :5555 (internal)            │    ║  ║  │  10 CPUs / 14 GB oferta          │    ║
║  └──────────────────────────────┘    ║  ║  │  → spark-master:7077             │    ║
║                                      ║  ║  └──────────────────────────────────┘    ║
║  ┌──────────────────────────────┐    ║  ║                                           ║
║  │  Spark Master 3.5.3          │    ║  ║  ┌──────────────────────────────────┐    ║
║  │  /srv/fastdata/spark-history │    ║  ║  │  Airflow Worker (Celery)         │    ║
║  │  :7077 (internal)            │    ║  ║  │  /srv/fastdata/airflow/dags      │    ║
║  └──────────────────────────────┘    ║  ║  │  /srv/datalake/datasets (ro)     │    ║
║                                      ║  ║  └──────────────────────────────────┘    ║
║  ┌──────────────────────────────┐    ║  ║                                           ║
║  │  Spark History Server        │    ║  ║  ┌──────────────────────────────────┐    ║
║  │  /srv/fastdata/spark-history │    ║  ║  │  Portainer Agent                 │    ║
║  │  :18080 (internal)           │    ║  ║  │  (global: ambos nodos)           │    ║
║  └──────────────────────────────┘    ║  ║  └──────────────────────────────────┘    ║
║                                      ║  ║                                           ║
║  ┌──────────────────────────────┐    ║  ╚═══════════════════════════════════════════╝
║  │  Portainer Agent             ║    ║
║  │  (global: ambos nodos)       ║    ║
║  └──────────────────────────────┘    ║
╚══════════════════════════════════════╝
```

---

## 4. Flujo de tráfico LAN

```
Usuario (PC LAN)
       │
       │  HTTPS :443
       ▼
┌──────────────────┐
│  Traefik v2.11   │  master1:443 (mode: host)
│  192.168.80.100  │  HTTP→HTTPS redirect en :80
└────────┬─────────┘
         │
         │  Middleware chain por ruta:
         │  1. lan-whitelist (192.168.80.0/24)
         │  2. basicauth (según servicio)
         │  3. TLS termination (cert self-signed)
         │
         ├──[portainer.sexydad]──────────────► Portainer :9000 (master1)
         ├──[traefik.sexydad]────────────────► Traefik Dashboard :8080 (master1)
         ├──[n8n.sexydad]────────────────────► n8n :5678 (master2)
         ├──[opensearch.sexydad]─────────────► OpenSearch :9200 (master1)
         ├──[dashboards.sexydad]─────────────► OpenSearch Dashboards :5601 (master1)
         ├──[ollama.sexydad]─────────────────► Ollama :11434 (master2)
         ├──[jupyter-ogiovanni.sexydad]───────► JupyterLab :8888 (master2)
         ├──[jupyter-odavid.sexydad]──────────► JupyterLab :8888 (master2)
         ├──[minio.sexydad]──────────────────► MinIO Console :9001 (master2)
         ├──[minio-api.sexydad]──────────────► MinIO S3 API :9000 (master2)
         ├──[spark-master.sexydad]───────────► Spark Master UI :8080 (master1)
         ├──[spark-worker.sexydad]───────────► Spark Worker UI :8081 (master2)
         ├──[spark-history.sexydad]──────────► Spark History :18080 (master1)
         ├──[airflow.sexydad]────────────────► Airflow Webserver :8080 (master1)
         └──[airflow-flower.sexydad]──────────► Celery Flower :5555 (master1)


Comunicación interna (service-to-service vía overlay "internal"):
  n8n              ──► postgres:5432
  airflow_*        ──► postgres:5432  (metadata de DAGs)
  airflow_*        ──► redis:6379     (broker Celery)
  airflow_*        ──► minio:9000     (logs remotos — deshabilitado por defecto)
  airflow_worker   ──► ollama:11434   (inference desde DAGs)
  opensearch-dashboards ──► opensearch:9200
  jupyter          ──► ollama:11434   (sin auth, red interna)
  jupyter          ──► opensearch:9200
  jupyter          ──► minio:9000     (S3 API para datasets)
  jupyter          ──► spark-master:7077 (submit jobs)
  spark_worker     ──► spark-master:7077
  spark_history    ──► /opt/spark/history (filesystem compartido)
```

---

## 5. Flujo de datos en pipelines AI/Data

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Flujo de datos — Medallion Architecture           │
└─────────────────────────────────────────────────────────────────────┘

INGESTA (Bronze):
  Airflow DAGs / n8n / scripts manuales
       │
       ▼
  s3a://bronze/  (MinIO — HDD 2TB, CSV/JSON/Parquet raw, append-only)

PROCESAMIENTO (Silver):
  Airflow → SparkSubmitOperator
       │
       ▼
  Spark Job (master1:7077 → worker master2)
       │   lee  s3a://bronze/
       │   escribe → s3a://silver/  (Delta Lake ACID: limpio, tipado, deduplicado)
       └── event logs → /srv/fastdata/spark-history

AGREGACIÓN (Gold):
  Airflow → SparkSubmitOperator
       │
       ▼
  Spark Job
       │   lee  s3a://silver/
       └── escribe → s3a://gold/  (Delta Lake: KPIs, features ML, reportes)

ANÁLISIS / ML:
  JupyterLab (PySpark + Delta + boto3)
       │   lee  s3a://bronze/ | silver/ | gold/
       │   accede GPU ◄── RTX 2080 Ti (CUDA)
       │   usa Ollama ◄── http://ollama:11434 (LLM inference)
       │   indexa en OpenSearch ──► http://opensearch:9200
       └── guarda resultados ──► /srv/datalake/artifacts

VISUALIZACIÓN:
  OpenSearch Dashboards ◄──── Índices + Aggregations
  (https://dashboards.sexydad)

AUTOMATIZACIÓN:
  n8n (https://n8n.sexydad) ──► webhooks, integraciones externas, notificaciones
  Airflow (https://airflow.sexydad) ──► orquesta TODO el pipeline

MODELOS LLM:
  Ollama ──► /srv/datalake/models/ollama (HDD 2TB, persistente)
  Jupyter ──► acceso via http://ollama:11434/api/generate
  Airflow ──► acceso via http://ollama:11434 desde worker
```

---

## 6. Estrategia de placement

Docker Swarm distribuye containers usando **labels de nodo + constraints en el stack**:

```yaml
# Ejemplo de constraint (en stack.yml de cada servicio):
deploy:
  placement:
    constraints:
      - node.labels.tier == control    # → master1
      - node.labels.tier == compute    # → master2
      - node.labels.gpu == nvidia      # → master2 (solo GPU)
```

| Servicio | Nodo | Label usado | Motivo |
|----------|------|-------------|--------|
| Traefik | master1 | `tier=control` | Puertos :80/:443 en control plane |
| Portainer | master1 | `tier=control` | UI de administración |
| OpenSearch | master1 | `tier=control` | master2 saturado con GPU workloads |
| OpenSearch Dashboards | master1 | `tier=control` | Frontend ligero |
| Redis (Celery) | master1 | `tier=control` | Broker ligero, junto al scheduler |
| Airflow Webserver | master1 | `tier=control` | UI + API REST |
| Airflow Scheduler | master1 | `tier=control` | Planificador ligero |
| Airflow Flower | master1 | `tier=control` | Monitor ligero |
| Spark Master | master1 | `tier=control` | Coordinador ligero |
| Spark History | master1 | `tier=control` | Lee logs del filesystem |
| PostgreSQL | master2 | `hostname=master2` | NVMe para I/O intensivo |
| n8n | master2 | `tier=compute` | Junto con Postgres (misma red) |
| JupyterLab | master2 | `tier=compute` + `hostname=master2` | GPU + NVMe para notebooks |
| Ollama | master2 | `tier=compute` + `gpu=nvidia` | GPU obligatorio |
| MinIO | master2 | `tier=compute` + `hostname=master2` | HDD 2TB datalake |
| Spark Worker | master2 | `tier=compute` + `hostname=master2` | NVMe para shuffle/spill |
| Airflow Worker | master2 | `tier=compute` + `hostname=master2` | Acceso a GPU, NVMe, datalake HDD |
| Portainer Agent | GLOBAL | — | Corre en TODOS los nodos |

---

## 7. Redes Docker Swarm

```
┌─────────────────────────────────────────────────────────────┐
│                    Redes Overlay                             │
├────────────┬───────────────────────────────────────────────┤
│  public    │  attachable, overlay                           │
│            │  Usado para: Traefik ↔ backends                │
│            │  Servicios: traefik, portainer, n8n,           │
│            │             jupyter, ollama,                   │
│            │             opensearch, dashboards,            │
│            │             minio, spark_*, airflow_webserver, │
│            │             airflow_flower                     │
├────────────┼───────────────────────────────────────────────┤
│  internal  │  attachable, overlay                           │
│            │  Usado para: service-to-service                │
│            │  Servicios: postgres, n8n, traefik,            │
│            │             jupyter, ollama,                   │
│            │             opensearch, portainer-agent,       │
│            │             minio, spark_*, redis,             │
│            │             airflow_* (todos)                  │
└────────────┴───────────────────────────────────────────────┘
```

**Regla de acceso**:
- Un servicio en `public` puede ser alcanzado por Traefik
- Un servicio en `internal` puede comunicarse con otros servicios sin exponer puertos
- Los servicios que necesitan AMBOS (ser accedidos externamente Y hablar con otros servicios) se unen a las dos redes

---

## 8. Modelo de seguridad

```
┌─────────────────────────────────────────────────────────────────┐
│                    Capas de seguridad                            │
│                                                                  │
│  1. Perimetral: LAN solo (192.168.80.0/24)                       │
│     └─ Traefik middleware: lan-whitelist / lan-allow             │
│                                                                  │
│  2. Autenticación: BasicAuth por servicio (donde aplica)         │
│     └─ Secrets: traefik_basic_auth, jupyter_basicauth_v2,        │
│                 ollama_basicauth, opensearch_basicauth,           │
│                 dashboards_basicauth                              │
│     └─ Auth nativa: Portainer, Airflow, MinIO, n8n               │
│                                                                  │
│  3. Transporte: TLS self-signed en todos los endpoints           │
│     └─ Secrets: traefik_tls_cert, traefik_tls_key               │
│                                                                  │
│  4. Credenciales DB/App: Docker Swarm Secrets                    │
│     └─ Secrets: pg_super_pass, pg_n8n_pass, pg_airflow_pass      │
│                 minio_access_key, minio_secret_key               │
│                 n8n_encryption_key, n8n_user_mgmt_jwt_secret     │
│                 airflow_fernet_key, airflow_webserver_secret      │
│                                                                  │
│  5. Red interna: Overlay cifrado (no expuesto a LAN directa)     │
│     └─ Servicios internos: NO tienen puertos publicados         │
└─────────────────────────────────────────────────────────────────┘
```

**Qué NO está implementado** (backlog):
- [ ] Firewall (UFW/iptables) endurecido en ambos nodos
- [ ] Rotación automática de secrets
- [ ] Certificados de una CA interna real (en lugar de self-signed)
- [ ] Autenticación OpenID/OAuth (para Jupyter/Airflow)

---

## 9. Decisiones arquitecturales clave

> Ver ADRs completos en [`docs/adrs/`](../adrs/)

### ADR-001: Docker Swarm sobre Kubernetes
**Decisión**: Usar Docker Swarm para orquestación.  
**Motivo**: 2 nodos no justifican la complejidad operativa de K8s. Swarm es suficiente para lab, más simple de mantener y con deployment declarativo por stacks.

### ADR-002: master1 como gateway exclusivo
**Decisión**: Traefik corre solo en master1 (mode: host en puertos :80/:443).  
**Motivo**: Un solo punto de entrada simplifica certificados, whitelist y logging. master2 queda libre para workloads GPU/data.

### ADR-003: Separación fastdata/datalake
**Decisión**: Dos puntos de montaje diferenciados en master2.  
**Motivo**: `/srv/fastdata` (NVMe) para I/O intensivo (DBs, metadata). `/srv/datalake` (HDD 2TB) para datos masivos (modelos, datasets, artifacts). Maximiza performance sin despilfarrar NVMe.

### ADR-004: Security plugin OpenSearch deshabilitado
**Decisión**: `DISABLE_SECURITY_PLUGIN=true` en OpenSearch.  
**Motivo**: En laboratorio LAN-only con BasicAuth+Whitelist en Traefik es suficiente. El plugin de seguridad agrega complejidad de certificados internos que no aporta en este contexto.

### ADR-005: GPU Generic Resources en Swarm
**Decisión**: Registrar GPU como Generic Resource (`nvidia.com/gpu=1`) en lugar de usar el driver de runtime directamente.  
**Motivo**: Swarm no tiene soporte nativo para `--gpus`. Generic Resources permite reservar y hacer placement correcto. El `default-runtime: nvidia` en `daemon.json` de master2 habilita el runtime.

### ADR-006: OpenSearch en master1 (no master2)
**Decisión**: OpenSearch corre en master1 a pesar de tener HDD en lugar de NVMe.  
**Motivo**: En el momento del despliegue, master2 tenía 14/16 CPUs y 28/31GB RAM comprometidos por Jupyter x2 + Ollama. OpenSearch es un servicio de soporte/observabilidad; HDD suficiente para workload de lab.
