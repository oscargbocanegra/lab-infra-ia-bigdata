# Apache Spark 3.5 — Distributed Processing

## Overview

Apache Spark provides distributed data processing for PySpark jobs from Jupyter and pipeline tasks from Airflow. The cluster uses a standalone master/worker topology.

| Property | Value |
|----------|-------|
| Image | `apache/spark:3.5.3` |
| Master URL | `spark://spark-master:7077` |
| Master UI | https://spark-master.sexydad |
| History Server UI | https://spark-history.sexydad |

## Components

| Service | Node | Role | Resources |
|---------|------|------|-----------|
| `spark_master` | master1 (`tier=control`) | Coordinator, job scheduler | 2 CPU / 2G RAM |
| `spark_worker` | master2 (`tier=compute`) | Task execution | 10 CPU / 14G RAM |
| `spark_history` | master1 | Job history viewer | 1 CPU / 1G RAM |

## Important: Hostname Must Use Hyphens

Spark validates worker and master hostnames as valid Java URLs. **Underscores are not allowed** — they cause `Invalid master URL` errors at worker registration.

| Config | Value |
|--------|-------|
| Master hostname | `spark-master` ✅ |
| Worker hostname | `spark-worker` ✅ |

## Persistence & Storage

| Path (host) | Container | Node | Purpose |
|-------------|-----------|------|---------|
| `/srv/fastdata/spark-history` | `/opt/spark/history` | master1 | Event log files (shared read-write) |
| `/srv/fastdata/spark-history` | `/opt/spark/history` (ro) | master1 (history server) | History server reads same volume |
| `/srv/fastdata/spark-tmp` | `/opt/spark/work` | master2 | Shuffle spill to NVMe |
| `/srv/datalake/datasets` | `/data/datasets` (ro) | master2 | Direct dataset access |

```bash
# Run on master1
mkdir -p /srv/fastdata/spark-history
# Run on master2
mkdir -p /srv/fastdata/spark-tmp
```

## Connecting from Jupyter

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .master("spark://spark-master:7077") \
    .appName("my-job") \
    .getOrCreate()
```

## Connecting from Airflow

```python
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator

SparkSubmitOperator(
    task_id="my_spark_job",
    conn_id="spark_default",   # conn_type=Spark, host=spark://spark-master:7077
    application="/opt/airflow/dags/my_job.py",
)
```

## S3A / MinIO Integration

> `apache/spark:3.5.3` does **not** include `hadoop-aws.jar`. S3A filesystem is **not available** out of the box.
>
> To enable it, add `hadoop-aws-3.3.4.jar` and `aws-java-sdk-bundle-1.11.1026.jar` to `/opt/spark/jars/` via a custom image or init script, then configure:
> ```
> spark.hadoop.fs.s3a.endpoint=http://minio:9000
> spark.hadoop.fs.s3a.path.style.access=true
> ```

## Delta Lake

Delta Lake extension is pre-configured via environment variables:
```
spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension
spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog
```

## Deploy

```bash
docker stack deploy -c stacks/data/98-spark/stack.yml spark
```

## Logs → OpenSearch

Logs are collected automatically by Fluent Bit via the default `json-file` driver.
Index: `docker-logs-YYYY.MM.DD` | Fields: `spark_spark_master`, `spark_spark_worker`, `spark_spark_history`
