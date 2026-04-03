# MinIO — S3-Compatible Object Storage

## Overview

MinIO provides S3-compatible object storage for the cluster's data lake. It is the backbone for raw data ingestion, Delta Lake tables, ML artifacts, Airflow logs, and Spark event logs.

| Property | Value |
|----------|-------|
| Image | `minio/minio:RELEASE.2024-11-07T00-52-20Z` |
| Node | master2 (`tier=compute`, `hostname=master2`) |
| Console UI | https://minio.sexydad |
| S3 API Endpoint | https://minio-api.sexydad (or `http://minio:9000` from overlay) |
| Region | `us-east-1` (standard, for boto3/s3fs compatibility) |

## Credentials

| Secret | Env Variable | Purpose |
|--------|-------------|---------|
| `minio_access_key` | `MINIO_ROOT_USER` | S3 Access Key ID |
| `minio_secret_key` | `MINIO_ROOT_PASSWORD` | S3 Secret Access Key |

## Persistence

| Path (host — master2) | Container | Purpose |
|-----------------------|-----------|---------|
| `/srv/datalake/minio` | `/data` | All bucket data (HDD 2TB) |

```bash
# Run on master2 before first deploy
mkdir -p /srv/datalake/minio
```

## Bucket Layout — Medallion Architecture

| Bucket | Layer | Purpose |
|--------|-------|---------|
| `bronze` | Raw | CSV/JSON/Parquet from ingestion (append-only) |
| `silver` | Curated | Delta Lake ACID tables (clean, typed, deduplicated) |
| `gold` | Business | Delta Lake KPIs, ML features, reports |
| `airflow-logs` | Ops | Airflow task log files |
| `spark-warehouse` | Ops | Delta catalog + Spark History Server logs |
| `lab-notebooks` | Dev | Exported notebooks (.ipynb) |

```bash
# Create buckets via MinIO Client (mc) after first deploy
docker run --rm --network internal minio/mc \
  alias set lab http://minio:9000 $ACCESS_KEY $SECRET_KEY

docker run --rm --network internal minio/mc \
  mb lab/bronze lab/silver lab/gold lab/airflow-logs lab/spark-warehouse lab/lab-notebooks
```

## Connecting from Python (boto3 / s3fs)

```python
import boto3

s3 = boto3.client(
    "s3",
    endpoint_url="http://minio:9000",       # from overlay
    # or "https://minio-api.sexydad"          # from LAN
    aws_access_key_id="<minio_access_key>",
    aws_secret_access_key="<minio_secret_key>",
    region_name="us-east-1",
)
```

## Connecting from PySpark (s3a)

> Requires `hadoop-aws.jar` in the Spark image — see Spark stack README.

```python
spark.conf.set("spark.hadoop.fs.s3a.endpoint", "http://minio:9000")
spark.conf.set("spark.hadoop.fs.s3a.path.style.access", "true")
df.write.format("delta").save("s3a://silver/my-table/")
```

## Prometheus Metrics

MinIO exposes metrics at `http://minio:9000/minio/v2/metrics/cluster` (auth type: public, no token required in this lab config).

> To add MinIO as a Prometheus scrape target, add to `prometheus.yml`:
> ```yaml
> - job_name: minio
>   metrics_path: /minio/v2/metrics/cluster
>   static_configs:
>     - targets: ["minio:9000"]
> ```

## Deploy

```bash
docker stack deploy -c stacks/data/12-minio/stack.yml minio
```

## Logs → OpenSearch

Logs are collected automatically by Fluent Bit via the default `json-file` driver.
Index: `docker-logs-YYYY.MM.DD` | Field: `container_name = minio_minio`
