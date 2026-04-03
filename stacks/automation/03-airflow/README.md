# Apache Airflow 2.9 — Pipeline Orchestration

## Overview

Apache Airflow orchestrates data pipelines (DAGs) across the cluster using the CeleryExecutor. Tasks are distributed to workers via a Redis message broker.

| Property | Value |
|----------|-------|
| Image | `apache/airflow:2.9.3` |
| Executor | CeleryExecutor |
| Webserver URL | https://airflow.sexydad |
| Flower URL | https://airflow-flower.sexydad |

## Components

| Service | Node | Role |
|---------|------|------|
| `airflow_webserver` | master1 | UI + REST API |
| `airflow_scheduler` | master1 | DAG scheduling |
| `airflow_worker` | master2 | Task execution (GPU + datalake access) |
| `airflow_flower` | master1 | Celery worker monitor |
| `redis` | master1 | Celery message broker |
| `airflow_init` | master1 | DB migration job (replicas=0, run manually) |

## Database

Airflow uses **PostgreSQL** for all metadata (DAG runs, task instances, connections, variables).

| Parameter | Value |
|-----------|-------|
| Host | `postgres_postgres` (Swarm overlay DNS) |
| Database | `airflow` |
| User | `airflow` |
| Password | via secret `pg_airflow_pass` |

> The `airflow` database and role are created by `stacks/core/02-postgres/initdb/02-init-airflow.sh`.

## Secrets Required

| Secret | Purpose |
|--------|---------|
| `pg_airflow_pass` | PostgreSQL password for `airflow` user |
| `airflow_fernet_key` | Fernet key for encrypting connections/variables |
| `airflow_webserver_secret` | Flask secret key for webserver sessions |
| `minio_access_key` | MinIO credentials for remote log storage |
| `minio_secret_key` | MinIO credentials for remote log storage |

## Persistence

All paths must exist on **both** master1 and master2 (worker uses same paths):

| Path (host) | Container | Node |
|-------------|-----------|------|
| `/srv/fastdata/airflow/dags` | `/opt/airflow/dags` | master1 + master2 |
| `/srv/fastdata/airflow/logs` | `/opt/airflow/logs` | master1 + master2 |
| `/srv/fastdata/airflow/plugins` | `/opt/airflow/plugins` | master1 + master2 |
| `/srv/fastdata/airflow/redis` | `/data` | master1 (Redis) |
| `/srv/datalake/datasets` | `/data/datasets` | master2 (worker only) |
| `/srv/datalake/artifacts` | `/data/artifacts` | master2 (worker only) |

```bash
# Run on master1
mkdir -p /srv/fastdata/airflow/{dags,logs,plugins,redis}
# Run on master2
mkdir -p /srv/fastdata/airflow/{dags,logs,plugins}
```

## First Deploy

```bash
# 1. Deploy the stack (airflow_init starts with 0 replicas)
docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow

# 2. Run DB migration + admin user creation (one time only)
docker service scale airflow_airflow_init=1
docker service logs airflow_airflow_init -f
# Wait for: "Airflow DB initialized and admin user created OK"
docker service scale airflow_airflow_init=0
```

Default admin credentials: `admin / admin` (change after first login).

## Remote Logging to MinIO

Remote logging is disabled by default (chicken-and-egg: Airflow needs MinIO connection, MinIO needs to be running).

To enable after first deploy:
1. Create bucket `airflow-logs` in MinIO
2. Add connection `minio_s3` in Airflow UI (Admin > Connections):
   - Conn Type: `Amazon S3`
   - Extra: `{"endpoint_url": "http://minio:9000"}`
3. Set `AIRFLOW__LOGGING__REMOTE_LOGGING=true` and redeploy

## Integrations

- **Spark**: `SparkSubmitOperator` → `spark://spark-master:7077`
- **MinIO**: `S3Hook` with `minio_s3` connection
- **PostgreSQL**: `PostgresOperator` with `pg_main` connection
- **n8n**: REST API triggers via `SimpleHttpOperator`

## Logs → OpenSearch

Logs are collected automatically by Fluent Bit via the default `json-file` driver.
Index: `docker-logs-YYYY.MM.DD` | Fields: `airflow_airflow_webserver`, `airflow_airflow_scheduler`, `airflow_airflow_worker`, `airflow_airflow_flower`, `airflow_redis`
