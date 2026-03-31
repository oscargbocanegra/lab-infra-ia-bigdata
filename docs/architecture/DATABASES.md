# Bases de Datos, Usuarios y Credenciales

> Actualizado: 2026-03-31

Este documento describe todas las bases de datos del lab, sus usuarios, roles, y cómo acceder a ellas.  
**Los passwords NO están aquí** — están en Docker Swarm Secrets. Ver sección [Secrets](#docker-swarm-secrets).

---

## Índice

1. [PostgreSQL 16 — DB central](#1-postgresql-16--db-central)
2. [MinIO — Object Storage](#2-minio--object-storage)
3. [Redis — Message Broker](#3-redis--message-broker)
4. [OpenSearch — Search Engine](#4-opensearch--search-engine)
5. [Docker Swarm Secrets](#docker-swarm-secrets)
6. [Acceso desde clientes externos (DBeaver, psql, mc)](#acceso-desde-clientes-externos)

---

## 1. PostgreSQL 16 — DB central

**Nodo**: master2 (`192.168.80.200`)  
**Puerto**: `5432` (mode: host — accesible desde LAN directamente)  
**Persistencia**: `/srv/fastdata/postgres` (NVMe LVM)  
**Stack**: `postgres` (`stacks/core/02-postgres/stack.yml`)

### Bases de datos

| Base de datos | Dueño | Usado por | Descripción |
|---------------|-------|-----------|-------------|
| `postgres` | `postgres` | Admin, DBA | Base por defecto. Solo acceso administrativo |
| `n8n` | `n8n` | n8n 2.4.7 | Workflows, credenciales cifradas, ejecuciones |
| `airflow` | `airflow` | Apache Airflow 2.9.3 | Metadata de DAGs, tareas, logs de ejecución, conexiones, variables |

### Usuarios / Roles

| Usuario | Tipo | Permisos | Secret |
|---------|------|----------|--------|
| `postgres` | Superusuario | TODAS las bases, admin total | `pg_super_pass` |
| `n8n` | Usuario de aplicación | CRUD en base `n8n` solamente | `pg_n8n_pass` |
| `airflow` | Usuario de aplicación | CRUD en base `airflow` solamente | `pg_airflow_pass` |

### Conexión desde aplicaciones (overlay `internal`)

```
Host:     postgres_postgres
Puerto:   5432
```

| Aplicación | Cadena de conexión interna |
|------------|--------------------------|
| **n8n** | `postgresql://n8n:<pg_n8n_pass>@postgres_postgres:5432/n8n` |
| **Airflow** | `postgresql+psycopg2://airflow:<pg_airflow_pass_encoded>@postgres_postgres:5432/airflow` |

> **Importante**: El password de Airflow tiene caracteres especiales (`/`, `=`). El `airflow-entrypoint.sh` lo URL-encoda con `urllib.parse.quote()` antes de construir la URL.

### Init scripts (ejecutados una sola vez al crear el volumen)

```
stacks/core/02-postgres/initdb/
├── 01-init-n8n.sh      → crea rol n8n + base de datos n8n
└── 02-init-airflow.sh  → crea rol airflow + base de datos airflow
```

### Acceso LAN directo (DBeaver, psql, DataGrip)

```
Host:     192.168.80.200
Puerto:   5432
SSL:      deshabilitado (LAN solo)
```

| Conexión | Usuario | Base | Uso |
|----------|---------|------|-----|
| Admin | `postgres` | `postgres` | Gestión, backups, creación de objetos |
| n8n | `n8n` | `n8n` | Debug de workflows |
| Airflow | `airflow` | `airflow` | Debug de DAGs, metastore |

---

## 2. MinIO — Object Storage

**Nodo**: master2  
**Persistencia**: `/srv/datalake/minio` (HDD 2TB)  
**Stack**: `minio` (`stacks/data/12-minio/stack.yml`)

### Credenciales

| Rol | Usuario | Secret |
|-----|---------|--------|
| Root (admin) | `<minio_access_key>` | `minio_access_key` |
| Root password | `<minio_secret_key>` | `minio_secret_key` |

> Las mismas credenciales se usan como `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` en Spark, Jupyter y Airflow.

### Buckets (Medallion Architecture)

| Bucket | Capa | Formato de datos | Escritura desde |
|--------|------|-----------------|-----------------|
| `bronze` | Raw | CSV, JSON, Parquet (raw) | Airflow DAGs, scripts de ingest |
| `silver` | Curated | **Delta Lake** (ACID) | Spark jobs (desde bronze) |
| `gold` | Business | **Delta Lake** (ACID) | Spark jobs (desde silver) |
| `airflow-logs` | Infra | Texto plano | Airflow (remote logging — actualmente deshabilitado) |
| `spark-warehouse` | Infra | Delta catalog, history | Spark SQL, History Server |
| `lab-notebooks` | Dev | `.ipynb` | Jupyter exports |

### Endpoints

| Endpoint | URL | Uso |
|----------|-----|-----|
| Console UI | `https://minio.sexydad` | Gestión visual, crear buckets, ver objetos |
| S3 API | `https://minio-api.sexydad` | Cliente externo (mc, boto3 desde laptop) |
| API interna | `http://minio:9000` | Spark, Airflow, Jupyter (overlay `internal`) |

### Configuración para clientes S3

```python
# PySpark / boto3 / s3fs
endpoint_url = "http://minio:9000"        # interno (desde Jupyter/Airflow)
# ó
endpoint_url = "https://minio-api.sexydad"  # externo (desde laptop)

region_name = "us-east-1"                # MinIO usa us-east-1 por defecto
path_style   = True                      # OBLIGATORIO en MinIO
```

### Configuración en PySpark (Jupyter)

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "<minio_access_key>") \
    .config("spark.hadoop.fs.s3a.secret.key", "<minio_secret_key>") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .getOrCreate()
```

> **Nota**: `apache/spark:3.5.3` no incluye `hadoop-aws.jar`. Para usar `s3a://` desde PySpark hay que agregar el JAR al classpath del worker.

---

## 3. Redis — Message Broker (Celery)

**Nodo**: master1  
**Puerto**: `6379` (solo accesible desde overlay `internal`)  
**Stack**: `airflow` (`stacks/automation/03-airflow/stack.yml`)  
**Persistencia**: `/srv/fastdata/airflow/redis` (AOF/RDB snapshot cada 60s)

### Uso

Redis funciona **exclusivamente como broker de mensajes de Celery** para Airflow. No es una base de datos de aplicación.

| Rol | Descripción |
|-----|-------------|
| Broker de Celery | Cola de tareas entre `airflow_scheduler` → `airflow_worker` |

### Conexión (interna)

```
redis://airflow_redis:6379/0
```

> No tiene contraseña — accesible solo desde el overlay `internal`.

---

## 4. OpenSearch — Search Engine

**Nodo**: master1  
**Puerto**: `9200` (HTTP, solo overlay `internal` + Traefik)  
**Stack**: `opensearch` (`stacks/data/11-opensearch/stack.yml`)  
**Persistencia**: `/srv/fastdata/opensearch` (HDD master1)

### Configuración

```
cluster.name:   lab-opensearch
node.name:      opensearch-node1
discovery.type: single-node
security:       DESHABILITADO (DISABLE_SECURITY_PLUGIN=true)
JVM heap:       -Xms1g -Xmx1g
```

### Acceso

| Método | URL | Auth |
|--------|-----|------|
| API interna (Jupyter, n8n) | `http://opensearch:9200` | Sin auth (security plugin deshabilitado) |
| API externa (via Traefik) | `https://opensearch.sexydad` | BasicAuth (`opensearch_basicauth`) |
| UI Dashboards | `https://dashboards.sexydad` | BasicAuth (`dashboards_basicauth`) |

### Índices predefinidos

No hay índices creados por defecto. Los índices se crean desde Jupyter notebooks, n8n workflows, o directamente via API.

---

## Docker Swarm Secrets

Todos los passwords y credenciales están en **Docker Swarm Secrets** — nunca en el repositorio.

### Inventario de secrets

| Secret | Contenido | Usado por |
|--------|-----------|-----------|
| `pg_super_pass` | Password superusuario `postgres` | PostgreSQL |
| `pg_n8n_pass` | Password usuario `n8n` | PostgreSQL, n8n |
| `pg_airflow_pass` | Password usuario `airflow` | PostgreSQL, Airflow (tiene chars especiales) |
| `minio_access_key` | MinIO root user (= AWS_ACCESS_KEY_ID) | MinIO, Jupyter, Airflow, Spark (futuro) |
| `minio_secret_key` | MinIO root password (= AWS_SECRET_ACCESS_KEY) | MinIO, Jupyter, Airflow, Spark (futuro) |
| `airflow_fernet_key` | Clave Fernet para cifrar conexiones en Airflow | Airflow |
| `airflow_webserver_secret` | Flask secret key del webserver Airflow | Airflow |
| `n8n_encryption_key` | Clave de cifrado de credenciales de n8n | n8n |
| `n8n_user_mgmt_jwt_secret` | JWT secret para gestión de usuarios n8n | n8n |
| `traefik_basic_auth` | Archivo htpasswd para el dashboard de Traefik | Traefik |
| `traefik_tls_cert` | Certificado TLS self-signed | Traefik |
| `traefik_tls_key` | Clave privada TLS self-signed | Traefik |
| `jupyter_basicauth_v2` | Archivo htpasswd para JupyterLab (ambos usuarios) | Traefik → Jupyter |
| `ollama_basicauth` | Archivo htpasswd para Ollama API | Traefik → Ollama |
| `opensearch_basicauth` | Archivo htpasswd para OpenSearch API | Traefik → OpenSearch |
| `dashboards_basicauth` | Archivo htpasswd para OpenSearch Dashboards | Traefik → Dashboards |

### Comandos de gestión

```bash
# Ver todos los secrets existentes
docker secret ls

# Crear un nuevo secret desde un archivo
echo -n "mi_password" | docker secret create nombre_secret -

# Crear desde archivo
docker secret create traefik_tls_cert ./cert.pem

# Eliminar un secret (solo si ningún servicio lo usa)
docker secret rm nombre_secret
```

> Los secrets no se pueden leer una vez creados (solo los contenedores que los montan pueden accederlos en `/run/secrets/<nombre>`).

---

## Acceso desde clientes externos

### PostgreSQL (DBeaver, DataGrip, psql)

```
Host:     192.168.80.200
Puerto:   5432
SSL:      No (LAN privada)
Usuario:  postgres  (admin) | n8n | airflow
Password: ver Docker Secret correspondiente
```

```bash
# Desde la LAN, con psql instalado localmente
psql -h 192.168.80.200 -U postgres -d postgres

# Leer el password desde el secret (solo desde master2 con acceso al container)
docker exec -it $(docker ps -q -f name=postgres_postgres) \
  psql -U postgres -d postgres
```

### MinIO (mc client, boto3 desde laptop)

```bash
# Configurar mc (MinIO client)
mc alias set lab https://minio-api.sexydad <access_key> <secret_key> --insecure

# Listar buckets
mc ls lab/

# Subir un archivo
mc cp ./mi_dataset.csv lab/bronze/

# Ver objetos en un bucket
mc ls lab/bronze/
```

### OpenSearch (curl, Python)

```bash
# Desde la LAN (con BasicAuth)
curl -sk -u "<user>:<pass>" https://opensearch.sexydad/_cluster/health | python3 -m json.tool

# Desde Python (interno, sin auth)
from opensearchpy import OpenSearch
client = OpenSearch(hosts=["http://opensearch:9200"])  # solo desde containers internos
```
