# Runbook: Deploy Phase 5 — MinIO + Spark + Airflow

> Version: 1.0 — 2026-03-30  
> Run from: **master1** (Swarm manager)  
> Estimated time: ~30–45 minutes

This runbook covers the full deployment of the 3 new Phase 5 stacks, including the redeployment of Postgres and Jupyter to support the new dependencies.

---

## Prerequisites

Before starting, verify the base cluster is operational:

```bash
# Verify Swarm state
docker node ls
# Expected: master1 (Leader/Ready) + master2 (Ready)

# Verify active services
docker service ls
# Must be UP: traefik, portainer, postgres, n8n, jupyter, ollama, opensearch
```

---

## Step 0 — Apply updated daemon.json on master2

The `daemon.json` on master2 was updated to include the NVIDIA runtime block.
If the file on the server does not have `default-runtime: nvidia`, apply it now:

```bash
# From master1, SSH to master2:
ssh master2

# Check the current daemon.json state on the server:
cat /etc/docker/daemon.json

# If it does NOT have "default-runtime": "nvidia", replace with:
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "exec-opts": ["native.cgroupdriver=systemd"],
  "features": {
    "buildkit": true
  },
  "live-restore": true,
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
EOF

# Reload Docker (live-restore: true = no downtime for existing containers)
sudo systemctl reload docker || sudo systemctl restart docker

# Verify nvidia-container-runtime is available:
docker info | grep -i runtime
# Must show: Runtimes: nvidia runc
# And: Default Runtime: nvidia

exit  # Return to master1
```

---

## Step 1 — Create new secrets (from master1)

```bash
# Check which secrets already exist:
docker secret ls

# Create the 5 new secrets (only if they do NOT already exist):

# 1. Airflow password in Postgres
echo "$(openssl rand -base64 32)" | docker secret create pg_airflow_pass -

# 2. MinIO access key (MinIO root user — minimum 3 characters)
echo "<minio-admin-user>" | docker secret create minio_access_key -

# 3. MinIO secret key (MinIO root password — minimum 8 characters)
echo "$(openssl rand -base64 32)" | docker secret create minio_secret_key -

# 4. Airflow Fernet key (MUST be a valid Fernet key — generated with cryptography)
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" | docker secret create airflow_fernet_key -

# 5. Airflow webserver secret key (Flask secret — any random string)
echo "$(openssl rand -hex 32)" | docker secret create airflow_webserver_secret -

# Verify all 5 were created:
docker secret ls | grep -E "pg_airflow_pass|minio_access_key|minio_secret_key|airflow_fernet_key|airflow_webserver_secret"
```

**IMPORTANT**: Save the values of `minio_access_key` and `minio_secret_key` somewhere safe.
You will need them to access the MinIO UI.

---

## Step 2 — Create directories on master1

```bash
# On master1:
sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins,redis}

# Airflow runs as UID 50000 (the "airflow" user inside the container)
sudo chown -R 50000:50000 /srv/fastdata/airflow/dags
sudo chown -R 50000:50000 /srv/fastdata/airflow/logs
sudo chown -R 50000:50000 /srv/fastdata/airflow/plugins
# Redis runs as root:
sudo chown root:docker /srv/fastdata/airflow/redis
sudo chmod 2775 /srv/fastdata/airflow/redis

# OpenSearch on master1 needs vm.max_map_count (if not already set):
grep vm.max_map_count /etc/sysctl.conf || echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## Step 3 — Create directories on master2

```bash
ssh master2

# Airflow worker directories (same paths as master1 — consistent mapping)
sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins}
sudo chown -R 50000:50000 /srv/fastdata/airflow/{dags,logs,plugins}
sudo chmod 2775 /srv/fastdata/airflow/{dags,logs,plugins}

# Spark scratch: shuffle/spill on NVMe
sudo mkdir -p /srv/fastdata/spark-tmp
sudo chown root:docker /srv/fastdata/spark-tmp
sudo chmod 2775 /srv/fastdata/spark-tmp

# MinIO: object storage on 2TB HDD
sudo mkdir -p /srv/datalake/minio
sudo chown root:docker /srv/datalake/minio
sudo chmod 2775 /srv/datalake/minio

exit  # Return to master1
```

---

## Step 4 — Redeploy Postgres (needed to create airflow DB)

> **Why**: Postgres init scripts only run on an empty volume.
> Since `02-init-airflow.sh` was added, we need a fresh volume.

```bash
# FIRST: bring down all services that depend on Postgres
docker service rm n8n_n8n 2>/dev/null || true

# Bring down Postgres
docker stack rm postgres 2>/dev/null || true
# Wait for services to terminate:
sleep 15
docker service ls | grep postgres   # must be empty

# Delete the Postgres data volume (confirmed: no critical data)
ssh master2 "sudo rm -rf /srv/fastdata/postgres && sudo mkdir -p /srv/fastdata/postgres && sudo chown 999:999 /srv/fastdata/postgres && sudo chmod 700 /srv/fastdata/postgres"

# Redeploy Postgres (init scripts will create n8n + airflow DBs)
docker stack deploy -c stacks/core/02-postgres/stack.yml postgres

# Wait for Postgres to be healthy (may take 30-60s):
watch docker service ls | grep postgres
# Expected: postgres_postgres  1/1  Running

# Verify the DBs were created:
docker exec -it $(docker ps -q -f name=postgres_postgres) \
  psql -U postgres -c "\l"
# Should show: postgres, n8n, airflow
```

---

## Step 5 — Redeploy n8n (post-postgres)

```bash
docker stack deploy -c stacks/automation/02-n8n/stack.yml n8n

# Verify:
watch docker service ls | grep n8n
# Test curl:
curl -sk https://n8n.sexydad | grep -o "n8n" | head -1
```

---

## Step 6 — Deploy MinIO

```bash
docker stack deploy -c stacks/data/12-minio/stack.yml minio

# Wait for MinIO to be running (~30s):
watch docker service ls | grep minio

# Verify health:
curl -sk https://minio-api.sexydad/minio/health/live
# Expected response: HTTP 200 (no body)
```

### Create Medallion Architecture buckets in MinIO

```bash
# Via mc (MinIO Client) from inside the container
docker exec -it $(docker ps -q -f name=minio_minio) sh -c "
  mc alias set local http://localhost:9000 \$(cat /run/secrets/minio_access_key) \$(cat /run/secrets/minio_secret_key) &&
  mc mb local/bronze local/silver local/gold \
        local/lab-notebooks local/airflow-logs local/spark-warehouse &&
  mc mb local/spark-warehouse/history
"

# Verify the 6 buckets + subdirectory:
docker exec -it $(docker ps -q -f name=minio_minio) sh -c "
  mc alias set local http://localhost:9000 \$(cat /run/secrets/minio_access_key) \$(cat /run/secrets/minio_secret_key) &&
  mc ls local
"
# Expected: bronze/ silver/ gold/ lab-notebooks/ airflow-logs/ spark-warehouse/
```

---

## Step 7 — Deploy Spark

```bash
docker stack deploy -c stacks/data/98-spark/stack.yml spark

# Wait for all 3 services (master, worker, history) to be running:
watch docker service ls | grep spark

# Verify Spark Master UI:
curl -sk https://spark-master.sexydad | grep -o "Spark Master" | head -1

# Verify the worker registered with the master:
# Go to https://spark-master.sexydad → should show 1 Worker alive with 10 CPUs / 14 GB
```

---

## Step 8 — Deploy Airflow

```bash
# Deploy the full stack (redis + webserver + scheduler + worker + flower):
docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow

# Wait for redis and components to start (~60s):
watch docker service ls | grep airflow

# Initialize the Airflow database (ONLY ONCE):
# Scale airflow_init to 1 so it runs db migrate + create admin user
docker service scale airflow_airflow_init=1

# Watch the init logs:
docker service logs airflow_airflow_init -f
# Wait to see: "DB migrations done" and "Admin user admin created"

# Scale back to 0 (this is an init job, not a permanent service):
docker service scale airflow_airflow_init=0

# Verify UI:
curl -sk https://airflow.sexydad/health | python3 -m json.tool
# Expected: {"metadatabase": {"status": "healthy"}, "scheduler": {"status": "healthy"}}

# Verify Flower:
curl -sk https://airflow-flower.sexydad | grep -o "Flower" | head -1
```

---

## Step 9 — Update Jupyter

```bash
# Force update Jupyter to reload entrypoint.sh and new secrets:
docker service update --force jupyter_jupyter_<admin-user>
docker service update --force jupyter_jupyter_<second-user>

# Wait for services to restart:
watch docker service ls | grep jupyter
```

---

## Step 10 — Final Verification

### Verify all services

```bash
docker service ls
# All must have REPLICAS = X/X (e.g. 1/1)
```

### Integration test: Jupyter → MinIO (from a notebook)

```python
import boto3

s3 = boto3.client(
    's3',
    endpoint_url='http://minio:9000',
    # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are already in the environment
)
buckets = s3.list_buckets()['Buckets']
print([b['Name'] for b in buckets])
# Expected: ['airflow-logs', 'bronze', 'gold', 'lab-notebooks', 'silver', 'spark-warehouse']
```

### Integration test: Jupyter → Spark (from a notebook)

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .master("spark://spark_master:7077") \
    .appName("test") \
    .getOrCreate()

spark.range(100).count()  # Should return 100
```

### Integration test: Spark → MinIO (from a notebook)

```python
df = spark.read.parquet("s3a://bronze/")
# If the bucket has data, it will read it. If empty, no error either.
```

---

## Step 11 — /etc/hosts on LAN clients

Add to `/etc/hosts` on each client machine (Windows/Mac/Linux):

```
<master1-ip>  minio.sexydad
<master1-ip>  minio-api.sexydad
<master1-ip>  spark-master.sexydad
<master1-ip>  spark-worker.sexydad
<master1-ip>  spark-history.sexydad
<master1-ip>  airflow.sexydad
<master1-ip>  airflow-flower.sexydad
```

---

## Step 12 (Phase 6 — post-stabilization) — Enable Remote Logging in Airflow

Once Airflow is stable:

1. Create the `minio_s3` connection in the Airflow UI:
   - **Admin → Connections → +**
   - Conn Id: `minio_s3`
   - Conn Type: `Amazon S3`
   - Extra: `{"endpoint_url": "http://minio:9000"}`
   - Credentials are taken from `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` in the worker environment.

2. Update the stack:
   ```yaml
   AIRFLOW__LOGGING__REMOTE_LOGGING: "true"
   ```

3. Apply:
   ```bash
   docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow
   ```

---

## Common Troubleshooting

### MinIO won't start
```bash
docker service logs minio_minio --tail 50
# Check: permissions on /srv/datalake/minio, secrets available
```

### Spark Worker doesn't register with the Master
```bash
docker service logs spark_spark_worker --tail 50
# Check: DNS resolution of "spark_master" on the internal network
# Verify: docker network inspect internal | grep spark
```

### Airflow Worker doesn't appear in Flower
```bash
docker service logs airflow_airflow_worker --tail 50
# Check: Redis running, internal network, broker URL
docker service logs airflow_redis --tail 20
```

### Airflow init fails on DB migrate
```bash
docker service logs airflow_airflow_init --tail 100
# Check: pg_airflow_pass correct, DB "airflow" exists in Postgres
# Verify from master2:
docker exec -it $(docker ps -q -f name=postgres_postgres) \
  psql -U postgres -c "\l" | grep airflow
```

### Jupyter cannot connect to MinIO (boto3)
```bash
# Verify that environment variables are exported:
docker exec -it $(docker ps -q -f name=jupyter_jupyter_<admin-user>) \
  env | grep AWS
# Expected: AWS_ACCESS_KEY_ID=<minio-admin-user>, AWS_SECRET_ACCESS_KEY=..., AWS_ENDPOINT_URL=http://minio:9000
```

---

## Expected Final State

```
$ docker service ls

ID       NAME                          MODE        REPLICAS  IMAGE
...      traefik_traefik               global       1/1      traefik:v3.x
...      portainer_portainer           replicated   1/1      portainer/portainer-ce:2.39.1
...      portainer_portainer-agent     global       2/2      portainer/agent:2.39.1
...      postgres_postgres             replicated   1/1      postgres:16
...      n8n_n8n                       replicated   1/1      n8nio/n8n:latest
...      jupyter_jupyter_<admin-user>  replicated   1/1      jupyter/datascience-notebook:python-3.11
...      jupyter_jupyter_<second-user> replicated   1/1      jupyter/datascience-notebook:python-3.11
...      ollama_ollama                 replicated   1/1      ollama/ollama:0.6.1
...      opensearch_opensearch         replicated   1/1      opensearchproject/opensearch:2.19.4
...      opensearch_dashboards         replicated   1/1      opensearchproject/opensearch-dashboards:2.19.4
...      minio_minio                   replicated   1/1      minio/minio:RELEASE.2024-11-07T00-52-20Z
...      spark_spark_master            replicated   1/1      bitnami/spark:3.5.3
...      spark_spark_worker            replicated   1/1      bitnami/spark:3.5.3
...      spark_spark_history           replicated   1/1      bitnami/spark:3.5.3
...      airflow_redis                 replicated   1/1      redis:7.2-alpine
...      airflow_airflow_webserver     replicated   1/1      apache/airflow:2.9.3
...      airflow_airflow_scheduler     replicated   1/1      apache/airflow:2.9.3
...      airflow_airflow_worker        replicated   1/1      apache/airflow:2.9.3
...      airflow_airflow_flower        replicated   1/1      apache/airflow:2.9.3
...      airflow_airflow_init          replicated   0/0      apache/airflow:2.9.3  ← 0 replicas (correct)
```

**Total: 20 active services** (21 defined, 1 intentionally inactive: airflow_init)
