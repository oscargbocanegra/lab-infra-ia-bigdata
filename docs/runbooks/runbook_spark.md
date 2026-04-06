# Runbook: Apache Spark 3.5 — Distributed Processing

> Stack: `spark` | Master: master1 | Worker: master2 | Last updated: 2026-03-30

---

## Description

Apache Spark is the lab's distributed processing engine. It runs batch jobs, analytical SQL, and ML over large datasets, using MinIO (S3A) as the storage layer and Delta Lake as the transactional format.

```
Component          Node      Resources            URL
──────────────── ──────── ─────────────────── ──────────────────────────
spark_master       master1  0.5 CPU / 1 GB     https://spark-master.sexydad
spark_worker       master2  10 CPUs / 14 GB    https://spark-worker.sexydad
spark_history      master1  0.25 CPU / 512 MB  https://spark-history.sexydad
```

---

## Required Secrets

Same as MinIO (shared):

```bash
# Already created if MinIO was deployed:
# minio_access_key
# minio_secret_key
```

---

## Directory Preparation (master2)

```bash
ssh master2 "sudo mkdir -p /srv/fastdata/spark-tmp && sudo chmod 777 /srv/fastdata/spark-tmp"
```

---

## Deploy

```bash
# 1. MinIO must be deployed and running first
#    (Spark History Server writes logs to s3a://spark-warehouse/history)

# 2. Create the spark-warehouse bucket in MinIO (if it doesn't exist)
#    See runbook_minio.md — "Create buckets" section

# 3. Deploy the stack
docker stack deploy -c stacks/data/98-spark/stack.yml spark

# 4. Verify
docker stack ps spark
docker service logs spark_spark_master --tail 20
docker service logs spark_spark_worker --tail 20
```

---

## Verify the worker registered

```bash
# From the UI: https://spark-master.sexydad
# Should show 1 Worker Alive with 10 CPUs and 14 GB RAM

# Or via logs:
docker service logs spark_spark_master 2>&1 | grep -i worker
# Expected: "Registering worker ... with 10 cores, 14.0 GiB RAM"
```

---

## Using Spark from Jupyter (BigData kernel)

### Basic cluster connection with S3A + Delta Lake

```python
from pyspark.sql import SparkSession
import os

spark = SparkSession.builder \
    .appName("My first job") \
    .master("spark://spark_master:7077") \
    .config("spark.executor.memory", "4g") \
    .config("spark.executor.cores", "4") \
    # MinIO via S3A (credentials already in environment)
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", os.environ["AWS_ACCESS_KEY_ID"]) \
    .config("spark.hadoop.fs.s3a.secret.key", os.environ["AWS_SECRET_ACCESS_KEY"]) \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    # Delta Lake
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog") \
    .getOrCreate()

print(f"Spark version: {spark.version}")
print(f"Master: {spark.sparkContext.master}")
```

### Medallion Pipeline: Bronze → Silver → Gold

```python
from pyspark.sql import functions as F

# ── Bronze: ingest raw CSV ─────────────────────────────────────────────
df_raw = spark.read \
    .option("header", "true") \
    .option("inferSchema", "true") \
    .csv("/data/datasets/sales.csv")

df_raw.write \
    .mode("append") \
    .partitionBy("date") \
    .parquet("s3a://bronze/sales/")

# ── Silver: clean + type + Delta Lake ───────────────────────────────────
df_bronze = spark.read.parquet("s3a://bronze/sales/")

df_silver = df_bronze \
    .dropDuplicates(["transaction_id"]) \
    .filter(F.col("amount").isNotNull() & (F.col("amount") > 0)) \
    .withColumn("date", F.to_date(F.col("date"), "yyyy-MM-dd")) \
    .withColumn("amount", F.col("amount").cast("double")) \
    .withColumn("_ingest_ts", F.current_timestamp())

df_silver.write \
    .format("delta") \
    .mode("overwrite") \
    .option("overwriteSchema", "true") \
    .partitionBy("date") \
    .save("s3a://silver/sales/")

# ── Gold: KPIs + Delta Lake ────────────────────────────────────────────
df_silver = spark.read.format("delta").load("s3a://silver/sales/")

df_gold = df_silver \
    .groupBy("date", "category") \
    .agg(
        F.sum("amount").alias("total_sales"),
        F.count("*").alias("transaction_count"),
        F.avg("amount").alias("average_ticket")
    )

df_gold.write \
    .format("delta") \
    .mode("overwrite") \
    .partitionBy("date") \
    .save("s3a://gold/sales_daily_kpis/")

print("Medallion pipeline complete.")
spark.stop()
```

### Delta Lake Time Travel

```python
from delta.tables import DeltaTable

# View version history
dt = DeltaTable.forPath(spark, "s3a://silver/sales/")
dt.history().select("version", "timestamp", "operation").show()

# Read a specific version
df_v0 = spark.read.format("delta") \
    .option("versionAsOf", 0) \
    .load("s3a://silver/sales/")

# Restore to a previous version
dt.restoreToVersion(0)
```

### Read local datalake files

```python
# Datasets are also mounted directly at /data/datasets
df = spark.read.parquet("/data/datasets/ml_dataset.parquet")
```

---

## Monitoring

```bash
# Master UI (see active jobs, workers)
# https://spark-master.sexydad

# Worker UI (see running tasks)
# https://spark-worker.sexydad

# History Server (see historical jobs)
# https://spark-history.sexydad

# Real-time logs
docker service logs spark_spark_worker -f --tail 50
```

---

## Adjusting Worker Resources

To allocate more or fewer resources to the worker, edit `stacks/data/98-spark/stack.yml`:

```yaml
environment:
  SPARK_WORKER_CORES: "10"   # Cores offered to the cluster
  SPARK_WORKER_MEMORY: 14g   # RAM offered to the cluster
```

> The worker only uses what a job requests. The declared resources are the maximum available, not what it consumes when idle.

---

## Common Troubleshooting

### Worker can't connect to the master

```bash
# Verify both are on the same overlay network (internal)
docker network inspect internal | grep -A5 spark

# Verify DNS resolution
docker exec $(docker ps -q -f name=spark_spark_worker) \
  ping -c2 spark_master
```

### Job fails with "No space left on device"

```bash
# Clean Spark scratch on master2
ssh master2 "sudo rm -rf /srv/fastdata/spark-tmp/*"
```

### History Server shows no jobs

```bash
# Verify that the spark-warehouse/history bucket exists in MinIO
mc ls lab/spark-warehouse/

# Verify that logs are being written
docker service logs spark_spark_history --tail 30
```

---

## Redeploy

```bash
docker stack deploy -c stacks/data/98-spark/stack.yml spark
```
