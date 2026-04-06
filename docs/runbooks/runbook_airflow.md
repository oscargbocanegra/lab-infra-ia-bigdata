# Runbook: Apache Airflow 2.9 — Pipeline Orchestration

> Stack: `airflow` | Executor: CeleryExecutor | Last updated: 2026-03-30

---

## Description

Apache Airflow orchestrates the lab's data pipelines: ingestion, Spark processing, model training, and publishing results. It uses CeleryExecutor with Redis as the broker to distribute tasks across nodes.

```
Component           Node      Role
─────────────────── ──────── ────────────────────────────────────
airflow_webserver   master1   UI + REST API
airflow_scheduler   master1   Schedules and triggers DAGs
airflow_worker      master2   Executes tasks (GPU/datalake access)
airflow_flower      master1   Celery worker monitor
redis               master1   Message broker (Celery queue)
PostgreSQL          master2   DAG and execution metadata
```

---

## Required Secrets (create before deploying)

```bash
# On master1 (Swarm manager):

# Password for the 'airflow' user in Postgres
openssl rand -base64 20 | docker secret create pg_airflow_pass -

# Fernet key to encrypt connections and sensitive variables in Airflow
# MUST be a valid Fernet key (base64url of 32 bytes)
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" \
  | docker secret create airflow_fernet_key -

# Webserver Flask secret key
openssl rand -base64 30 | docker secret create airflow_webserver_secret -

# MinIO (if not already created — see runbook_minio.md)
# echo "<minio-admin-user>" | docker secret create minio_access_key -
# openssl rand -base64 24 | docker secret create minio_secret_key -
```

---

## Directory Preparation

```bash
# On master1:
sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins,redis}
sudo chown -R 50000:0 /srv/fastdata/airflow   # UID 50000 = airflow user

# On master2 (for the worker — same paths):
ssh master2 "sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins}"
ssh master2 "sudo chown -R 50000:0 /srv/fastdata/airflow"
```

> **Note on DAG synchronization**: DAGs are mounted from `/srv/fastdata/airflow/dags` on both nodes. To keep them consistent, develop DAGs on master1 and sync to master2 with rsync or git pull. A DAG that clones the repo is an elegant solution for labs.

---

## Deploy (required order)

```bash
# 1. Postgres must be running with the airflow DB already created
#    (the init script 02-init-airflow.sh runs automatically
#     when the volume is created for the first time)

# 2. MinIO must be running (for remote logs)

# 3. Deploy the base stack
docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow

# 4. Wait for Redis and services to come up (~30 sec)
docker stack ps airflow

# 5. Initialize the database (FIRST TIME ONLY)
docker service scale airflow_airflow_init=1
# Wait for it to complete (watch logs)
docker service logs airflow_airflow_init -f
# Scale back to 0 replicas after completion
docker service scale airflow_airflow_init=0

# 6. Verify all services
docker stack ps airflow --no-trunc
```

---

## First Login

```
URL:      https://airflow.sexydad
Username: admin
Password: value of airflow_webserver_secret
```

> Change the admin password from the UI immediately: Admin → Security → Users.

---

## Add the MinIO Connection in Airflow

From the UI: Admin → Connections → Add connection

```
Conn Id:    minio_s3
Conn Type:  Amazon S3
Extra:      {
              "endpoint_url": "http://minio:9000",
              "aws_access_key_id": "YOUR_ACCESS_KEY",
              "aws_secret_access_key": "YOUR_SECRET_KEY"
            }
```

Or via CLI:

```bash
docker exec -it $(docker ps -q -f name=airflow_airflow_webserver) \
  airflow connections add minio_s3 \
    --conn-type s3 \
    --conn-extra '{"endpoint_url":"http://minio:9000","aws_access_key_id":"YOUR_KEY","aws_secret_access_key":"YOUR_SECRET"}'
```

---

## Add the Spark Connection

```
Conn Id:    spark_default
Conn Type:  Spark
Host:       spark://spark_master
Port:       7077
```

---

## Example DAG

Create the file `/srv/fastdata/airflow/dags/lab_example_pipeline.py`:

```python
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator

default_args = {
    "owner": "lab",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="lab_example_pipeline",
    default_args=default_args,
    description="Example pipeline: ingest → process → store",
    schedule_interval="0 6 * * *",   # daily at 6am
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["lab", "example"],
) as dag:

    t1 = BashOperator(
        task_id="check_data",
        bash_command="ls /data/datasets/ && echo 'Data available'",
    )

    def process_data():
        import pandas as pd
        print("Processing data with pandas...")
        # Your logic here

    t2 = PythonOperator(
        task_id="process_data",
        python_callable=process_data,
    )

    t3 = BashOperator(
        task_id="notify_complete",
        bash_command="echo 'Pipeline complete: $(date)'",
    )

    t1 >> t2 >> t3
```

---

## DAG with SparkSubmitOperator

```python
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator

spark_job = SparkSubmitOperator(
    task_id="spark_processing",
    application="/opt/airflow/plugins/jobs/my_job.py",
    conn_id="spark_default",
    executor_memory="4g",
    executor_cores=4,
    conf={
        "spark.hadoop.fs.s3a.endpoint": "http://minio:9000",
        "spark.hadoop.fs.s3a.path.style.access": "true",
    },
    dag=dag,
)
```

---

## Monitoring

```bash
# Status of all components
docker stack ps airflow

# View active workers in Flower
# https://airflow-flower.sexydad

# Scheduler logs (see which DAGs were scheduled)
docker service logs airflow_airflow_scheduler -f --tail 50

# Worker logs (see task execution)
docker service logs airflow_airflow_worker -f --tail 50

# Verify that Celery is working
docker exec -it $(docker ps -q -f name=airflow_airflow_worker) \
  celery --app airflow.providers.celery.executors.celery_executor.app inspect active
```

---

## Common Troubleshooting

### Worker doesn't appear in Flower

```bash
# Verify connectivity with Redis
docker exec -it $(docker ps -q -f name=airflow_airflow_worker) \
  python3 -c "import redis; r=redis.Redis('redis'); print(r.ping())"
```

### Scheduler doesn't trigger DAGs

```bash
# Check scheduler state
docker service logs airflow_airflow_scheduler 2>&1 | grep -i error

# Restart scheduler
docker service update --force airflow_airflow_scheduler
```

### Fernet key error

```bash
# The Fernet key must be the same in webserver, scheduler, and worker
# If you change it, you must redeploy all 3 components
docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow
```

---

## Redeploy

```bash
# Full redeploy (automatic rolling update)
docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow
```

---

## File Structure

```
/srv/fastdata/airflow/
├── dags/          → Python DAGs (sync to master1 and master2)
├── logs/          → Local logs (backup in MinIO s3://airflow-logs/)
├── plugins/       → Custom plugins and operators
│   └── jobs/      → Spark scripts to submit
└── redis/         → Redis persistence (queue state)
```
