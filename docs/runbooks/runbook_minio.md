# Runbook: MinIO — S3-compatible Object Storage (Medallion Architecture)

> Stack: `minio` | Node: master2 | Last updated: 2026-03-30

---

## Description

MinIO is the S3-compatible object storage for the lab. It replaces HDFS as the distributed storage layer for Spark, Airflow, and notebooks. It implements the **Medallion Architecture** (Bronze → Silver → Gold) where Silver and Gold use **Delta Lake** to guarantee ACID transactions, time travel, and schema evolution.

```
Layer      Bucket           Format          Who writes
────────── ──────────────── ─────────────── ─────────────────────────────
Bronze     bronze/          CSV/JSON/Parquet Airflow ingestion, ETL scripts
Silver     silver/          Delta Lake       Spark (cleaning + typing)
Gold       gold/            Delta Lake       Spark (KPIs, ML features)
─ Infra ──────────────────────────────────────────────────────────────────
           airflow-logs/    Plain text       Airflow (remote logging)
           spark-warehouse/ Delta catalog    Spark SQL + History Server
           lab-notebooks/   .ipynb           Jupyter exports
```

See full architecture: [`docs/architecture/MEDALLION.md`](../architecture/MEDALLION.md)

---

## Required Secrets (create before deploying)

```bash
# On master1 (Swarm manager):

# Access key (MinIO root user — used as AWS_ACCESS_KEY_ID)
echo "<minio-admin-user>" | docker secret create minio_access_key -

# Secret key (MinIO root password — minimum 8 characters)
echo "$(openssl rand -base64 32)" | docker secret create minio_secret_key -
```

> **Important**: The same secrets (`minio_access_key`, `minio_secret_key`) are used by Jupyter, Spark, and Airflow to connect to MinIO via S3A. Save the access key somewhere safe — you need it to log in to the UI.

---

## Deploy

```bash
# 1. Create data directory on master2
ssh master2 "sudo mkdir -p /srv/datalake/minio && sudo chown root:docker /srv/datalake/minio && sudo chmod 2775 /srv/datalake/minio"

# 2. Deploy stack
docker stack deploy -c stacks/data/12-minio/stack.yml minio

# 3. Wait for it to start (~30s)
watch docker service ls | grep minio
# Expected: minio_minio  replicated  1/1

# 4. Health check
curl -sk https://minio-api.sexydad/minio/health/live && echo "OK"
```

---

## Create Medallion Architecture Buckets (post-deploy)

**CRITICAL**: Create the buckets before deploying Spark (the History Server needs `spark-warehouse/history`).

### Option A — From CLI with `mc` (inside the container)

```bash
docker exec -it $(docker ps -q -f name=minio_minio) sh -c "
  mc alias set local http://localhost:9000 \$(cat /run/secrets/minio_access_key) \$(cat /run/secrets/minio_secret_key) &&

  # Medallion layers
  mc mb local/bronze &&
  mc mb local/silver &&
  mc mb local/gold &&

  # Infrastructure
  mc mb local/lab-notebooks &&
  mc mb local/airflow-logs &&
  mc mb local/spark-warehouse &&
  mc mb local/spark-warehouse/history &&

  # Verify
  mc ls local
"
```

### Option B — From the web UI (`https://minio.sexydad`)

```
Credentials: minio_access_key / minio_secret_key (as configured in Docker secrets)
Create buckets: bronze, silver, gold, lab-notebooks, airflow-logs, spark-warehouse
Inside spark-warehouse: create a "folder" named history/
```

### Option C — With `mc` installed on master1

```bash
# Install mc
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# Configure alias (use actual credentials from Docker secrets)
mc alias set lab https://minio-api.sexydad <MINIO_ACCESS_KEY> <MINIO_SECRET_KEY>

# Create buckets
mc mb lab/bronze lab/silver lab/gold
mc mb lab/lab-notebooks lab/airflow-logs lab/spark-warehouse
mc mb lab/spark-warehouse/history

mc ls lab
```

---

## Using from PySpark — Medallion with Delta Lake (BigData kernel in Jupyter)

### Spark session configuration with S3A + Delta

```python
from pyspark.sql import SparkSession
import os

spark = SparkSession.builder \
    .appName("Medallion ETL") \
    .master("spark://spark_master:7077") \
    .config("spark.executor.memory", "4g") \
    .config("spark.executor.cores", "4") \
    # S3A → MinIO
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", os.environ["AWS_ACCESS_KEY_ID"]) \
    .config("spark.hadoop.fs.s3a.secret.key", os.environ["AWS_SECRET_ACCESS_KEY"]) \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    # Delta Lake
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog") \
    .getOrCreate()

print(f"Spark {spark.version} connected — Delta Lake ready")
```

### Bronze → ingest raw data

```python
# Ingest raw CSV into Bronze (append-only, no transformation)
df_raw = spark.read \
    .option("header", "true") \
    .option("inferSchema", "true") \
    .csv("/data/datasets/sales.csv")   # local mount or s3a://bronze/raw/

# Save to Bronze as Parquet (raw format)
df_raw.write \
    .mode("append") \
    .partitionBy("date") \
    .parquet("s3a://bronze/sales/")

print(f"Bronze: {df_raw.count()} records ingested")
```

### Bronze → Silver — clean and type with Delta Lake

```python
from pyspark.sql import functions as F

# Read from Bronze
df_bronze = spark.read.parquet("s3a://bronze/sales/")

# Transformations: clean, deduplicate, type
df_silver = df_bronze \
    .dropDuplicates(["transaction_id"]) \
    .filter(F.col("amount").isNotNull()) \
    .filter(F.col("amount") > 0) \
    .withColumn("date", F.to_date(F.col("date"), "yyyy-MM-dd")) \
    .withColumn("amount", F.col("amount").cast("double")) \
    .withColumn("_ingest_ts", F.current_timestamp())

# Write to Silver as Delta Lake (ACID, time travel)
df_silver.write \
    .format("delta") \
    .mode("overwrite") \
    .option("overwriteSchema", "true") \
    .partitionBy("date") \
    .save("s3a://silver/sales/")

print(f"Silver: {df_silver.count()} clean records saved")
```

### Silver → Gold — aggregate KPIs with Delta Lake

```python
# Read from Silver
df_silver = spark.read.format("delta").load("s3a://silver/sales/")

# Calculate daily KPIs
df_gold = df_silver \
    .groupBy("date", "category") \
    .agg(
        F.sum("amount").alias("total_sales"),
        F.count("*").alias("transaction_count"),
        F.avg("amount").alias("average_ticket"),
        F.max("amount").alias("max_sale")
    ) \
    .withColumn("_gold_ts", F.current_timestamp())

# Save to Gold as Delta Lake
df_gold.write \
    .format("delta") \
    .mode("overwrite") \
    .partitionBy("date") \
    .save("s3a://gold/sales_daily_kpis/")

print(f"Gold: {df_gold.count()} KPI records calculated")
```

### Delta Lake Time Travel

```python
# Read a previous version of Silver (time travel)
df_v0 = spark.read.format("delta") \
    .option("versionAsOf", 0) \
    .load("s3a://silver/sales/")

# Or by timestamp
df_yesterday = spark.read.format("delta") \
    .option("timestampAsOf", "2026-03-29") \
    .load("s3a://silver/sales/")

# View version history
from delta.tables import DeltaTable

dt = DeltaTable.forPath(spark, "s3a://silver/sales/")
dt.history().show(10)
```

---

## Using from Python — boto3 / s3fs (Bronze layer)

Credentials are already exported in the Jupyter container environment (via `entrypoint.sh`):
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_ENDPOINT_URL=http://minio:9000`

```python
import boto3, os

s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["AWS_ENDPOINT_URL"],
    aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
    region_name="us-east-1"
)

# Upload raw file to Bronze
s3.upload_file("/home/jovyan/work/data.csv", "bronze", "raw/data.csv")

# List objects in Bronze
for obj in s3.list_objects(Bucket="bronze").get("Contents", []):
    print(obj["Key"])

# List all buckets
print([b["Name"] for b in s3.list_buckets()["Buckets"]])
```

```python
# With s3fs (more Pythonic, integrates with pandas)
import s3fs, pandas as pd, os

fs = s3fs.S3FileSystem(
    endpoint_url=os.environ["AWS_ENDPOINT_URL"],
    key=os.environ["AWS_ACCESS_KEY_ID"],
    secret=os.environ["AWS_SECRET_ACCESS_KEY"],
)

# Read raw CSV from Bronze
df = pd.read_csv(fs.open("bronze/raw/data.csv"))

# List Silver content
fs.ls("silver/sales/")
```

---

## Diagnostics

```bash
# Service status
docker service ps minio_minio

# Real-time logs
docker service logs minio_minio --tail 50 -f

# Health check (via Traefik)
curl -sk https://minio-api.sexydad/minio/health/live && echo "OK"
curl -sk https://minio-api.sexydad/minio/health/ready && echo "Ready"

# Direct health check (from master2)
curl -f http://localhost:9000/minio/health/live && echo "OK"

# Disk space
ssh master2 "df -h /srv/datalake/minio"

# List buckets with mc
docker exec -it $(docker ps -q -f name=minio_minio) sh -c "
  mc alias set local http://localhost:9000 \$(cat /run/secrets/minio_access_key) \$(cat /run/secrets/minio_secret_key) &&
  mc ls local"
```

---

## Redeploy / Version Update

```bash
# Update version (change tag in stack.yml first)
docker stack deploy -c stacks/data/12-minio/stack.yml minio

# Force container recreation (same tag)
docker service update --force minio_minio
```

---

## Backup

MinIO stores all objects in `/srv/datalake/minio` on master2. Backing up this path includes all buckets.

```bash
# Backup with mc mirror (sync):
mc mirror lab/bronze   /backup/bronze/
mc mirror lab/silver   /backup/silver/
mc mirror lab/gold     /backup/gold/

# Or full filesystem backup (from master1 → external backup)
rsync -avz --delete master2:/srv/datalake/minio/ /backup/minio/
```
