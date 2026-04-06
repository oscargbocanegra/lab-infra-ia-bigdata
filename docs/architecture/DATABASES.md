# Databases, Users and Credentials

> Updated: 2026-03-31

This document describes all databases in the lab, their users, roles, and how to access them.  
**Passwords are NOT stored here** — they are in Docker Swarm Secrets. See the [Secrets](#docker-swarm-secrets) section.

---

## Index

1. [PostgreSQL 16 — Central DB](#1-postgresql-16--central-db)
2. [MinIO — Object Storage](#2-minio--object-storage)
3. [Redis — Message Broker](#3-redis--message-broker)
4. [OpenSearch — Search Engine](#4-opensearch--search-engine)
5. [Docker Swarm Secrets](#docker-swarm-secrets)
6. [Access from external clients (DBeaver, psql, mc)](#access-from-external-clients)

---

## 1. PostgreSQL 16 — Central DB

**Node**: master2 (`<master2-ip>`)  
**Port**: `5432` (mode: host — directly accessible from LAN)  
**Persistence**: `/srv/fastdata/postgres` (NVMe LVM)  
**Stack**: `postgres` (`stacks/core/02-postgres/stack.yml`)

### Databases

| Database | Owner | Used by | Description |
|----------|-------|---------|-------------|
| `postgres` | `postgres` | Admin, DBA | Default database. Administrative access only |
| `n8n` | `n8n` | n8n 2.4.7 | Workflows, encrypted credentials, executions |
| `airflow` | `airflow` | Apache Airflow 2.9.3 | DAG metadata, tasks, execution logs, connections, variables |

### Users / Roles

| User | Type | Permissions | Secret |
|------|------|-------------|--------|
| `postgres` | Superuser | ALL databases, full admin | `pg_super_pass` |
| `n8n` | Application user | CRUD on `n8n` database only | `pg_n8n_pass` |
| `airflow` | Application user | CRUD on `airflow` database only | `pg_airflow_pass` |

### Connection from applications (overlay `internal`)

```
Host:     postgres_postgres
Port:     5432
```

| Application | Internal connection string |
|-------------|--------------------------|
| **n8n** | `postgresql://n8n:<pg_n8n_pass>@postgres_postgres:5432/n8n` |
| **Airflow** | `postgresql+psycopg2://airflow:<pg_airflow_pass_encoded>@postgres_postgres:5432/airflow` |

> **Important**: The Airflow password contains special characters (`/`, `=`). The `airflow-entrypoint.sh` URL-encodes it with `urllib.parse.quote()` before building the connection URL.

### Init scripts (executed once on volume creation)

```
stacks/core/02-postgres/initdb/
├── 01-init-n8n.sh      → creates n8n role + n8n database
└── 02-init-airflow.sh  → creates airflow role + airflow database
```

### LAN direct access (DBeaver, psql, DataGrip)

```
Host:     <master2-ip>
Port:     5432
SSL:      disabled (LAN only)
```

| Connection | User | Database | Usage |
|------------|------|----------|-------|
| Admin | `postgres` | `postgres` | Management, backups, object creation |
| n8n | `n8n` | `n8n` | Workflow debugging |
| Airflow | `airflow` | `airflow` | DAG debugging, metastore |

---

## 2. MinIO — Object Storage

**Node**: master2  
**Persistence**: `/srv/datalake/minio` (HDD 2TB)  
**Stack**: `minio` (`stacks/data/12-minio/stack.yml`)

### Credentials

| Role | User | Secret |
|------|------|--------|
| Root (admin) | `<minio_access_key>` | `minio_access_key` |
| Root password | `<minio_secret_key>` | `minio_secret_key` |

> The same credentials are used as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in Spark, Jupyter and Airflow.

### Buckets (Medallion Architecture)

| Bucket | Layer | Data Format | Written by |
|--------|-------|-------------|------------|
| `bronze` | Raw | CSV, JSON, Parquet (raw) | Airflow DAGs, ingest scripts |
| `silver` | Curated | **Delta Lake** (ACID) | Spark jobs (from bronze) |
| `gold` | Business | **Delta Lake** (ACID) | Spark jobs (from silver) |
| `airflow-logs` | Infra | Plain text | Airflow (remote logging — currently disabled) |
| `spark-warehouse` | Infra | Delta catalog, history | Spark SQL, History Server |
| `lab-notebooks` | Dev | `.ipynb` | Jupyter exports |

### Endpoints

| Endpoint | URL | Usage |
|----------|-----|-------|
| Console UI | `https://minio.sexydad` | Visual management, create buckets, browse objects |
| S3 API | `https://minio-api.sexydad` | External client (mc, boto3 from laptop) |
| Internal API | `http://minio:9000` | Spark, Airflow, Jupyter (overlay `internal`) |

### Configuration for S3 clients

```python
# PySpark / boto3 / s3fs
endpoint_url = "http://minio:9000"        # internal (from Jupyter/Airflow)
# or
endpoint_url = "https://minio-api.sexydad"  # external (from laptop)

region_name = "us-east-1"                # MinIO uses us-east-1 by default
path_style   = True                      # REQUIRED for MinIO
```

### PySpark configuration (Jupyter)

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

> **Note**: `apache/spark:3.5.3` does not include `hadoop-aws.jar`. To use `s3a://` from PySpark you need to add the JAR to the worker's classpath.

---

## 3. Redis — Message Broker (Celery)

**Node**: master1  
**Port**: `6379` (accessible from overlay `internal` only)  
**Stack**: `airflow` (`stacks/automation/03-airflow/stack.yml`)  
**Persistence**: `/srv/fastdata/airflow/redis` (AOF/RDB snapshot every 60s)

### Usage

Redis functions **exclusively as Celery's message broker** for Airflow. It is not an application database.

| Role | Description |
|------|-------------|
| Celery broker | Task queue between `airflow_scheduler` → `airflow_worker` |

### Connection (internal)

```
redis://airflow_redis:6379/0
```

> No password — accessible only from the `internal` overlay.

---

## 4. OpenSearch — Search Engine

**Node**: master1  
**Port**: `9200` (HTTP, overlay `internal` + Traefik only)  
**Stack**: `opensearch` (`stacks/data/11-opensearch/stack.yml`)  
**Persistence**: `/srv/fastdata/opensearch` (HDD master1)

### Configuration

```
cluster.name:   lab-opensearch
node.name:      opensearch-node1
discovery.type: single-node
security:       DISABLED (DISABLE_SECURITY_PLUGIN=true)
JVM heap:       -Xms1g -Xmx1g
```

### Access

| Method | URL | Auth |
|--------|-----|------|
| Internal API (Jupyter, n8n) | `http://opensearch:9200` | No auth (security plugin disabled) |
| External API (via Traefik) | `https://opensearch.sexydad` | BasicAuth (`opensearch_basicauth`) |
| UI Dashboards | `https://dashboards.sexydad` | BasicAuth (`dashboards_basicauth`) |

### Predefined indexes

No indexes are created by default. Indexes are created from Jupyter notebooks, n8n workflows, or directly via the API.

---

## Docker Swarm Secrets

All passwords and credentials are stored as **Docker Swarm Secrets** — never in the repository.

### Secrets inventory

| Secret | Content | Used by |
|--------|---------|---------|
| `pg_super_pass` | `postgres` superuser password | PostgreSQL |
| `pg_n8n_pass` | `n8n` user password | PostgreSQL, n8n |
| `pg_airflow_pass` | `airflow` user password | PostgreSQL, Airflow (contains special chars) |
| `minio_access_key` | MinIO root user (= AWS_ACCESS_KEY_ID) | MinIO, Jupyter, Airflow, Spark |
| `minio_secret_key` | MinIO root password (= AWS_SECRET_ACCESS_KEY) | MinIO, Jupyter, Airflow, Spark |
| `airflow_fernet_key` | Fernet key for encrypting Airflow connections | Airflow |
| `airflow_webserver_secret` | Flask secret key for Airflow webserver | Airflow |
| `n8n_encryption_key` | n8n credential encryption key | n8n |
| `n8n_user_mgmt_jwt_secret` | JWT secret for n8n user management | n8n |
| `traefik_basic_auth` | htpasswd file for Traefik dashboard | Traefik |
| `traefik_tls_cert` | Self-signed TLS certificate | Traefik |
| `traefik_tls_key` | TLS private key | Traefik |
| `jupyter_basicauth_v2` | htpasswd file for JupyterLab (both users) | Traefik → Jupyter |
| `ollama_basicauth` | htpasswd file for Ollama API | Traefik → Ollama |
| `opensearch_basicauth` | htpasswd file for OpenSearch API | Traefik → OpenSearch |
| `dashboards_basicauth` | htpasswd file for OpenSearch Dashboards | Traefik → Dashboards |

### Management commands

```bash
# List all existing secrets
docker secret ls

# Create a new secret from stdin
echo -n "my_password" | docker secret create secret_name -

# Create from file
docker secret create traefik_tls_cert ./cert.pem

# Delete a secret (only if no service is using it)
docker secret rm secret_name
```

> Secrets cannot be read once created (only containers that mount them can access them at `/run/secrets/<name>`).

---

## Access from external clients

### PostgreSQL (DBeaver, DataGrip, psql)

```
Host:     <master2-ip>
Port:     5432
SSL:      No (private LAN)
User:     postgres  (admin) | n8n | airflow
Password: see corresponding Docker Secret
```

```bash
# From the LAN, with psql installed locally
psql -h <master2-ip> -U postgres -d postgres

# Read the password from the secret (only from master2 with container access)
docker exec -it $(docker ps -q -f name=postgres_postgres) \
  psql -U postgres -d postgres
```

### MinIO (mc client, boto3 from laptop)

```bash
# Configure mc (MinIO client)
mc alias set lab https://minio-api.sexydad <access_key> <secret_key> --insecure

# List buckets
mc ls lab/

# Upload a file
mc cp ./my_dataset.csv lab/bronze/

# Browse objects in a bucket
mc ls lab/bronze/
```

### OpenSearch (curl, Python)

```bash
# From the LAN (with BasicAuth)
curl -sk -u "<user>:<pass>" https://opensearch.sexydad/_cluster/health | python3 -m json.tool

# From Python (internal, no auth)
from opensearchpy import OpenSearch
client = OpenSearch(hosts=["http://opensearch:9200"])  # only from internal containers
```
