# Medallion Architecture — Big Data + AI Lab

> Updated: 2026-03-30
> Pattern: Medallion Architecture (Bronze → Silver → Gold)
> Storage: MinIO (S3-compatible) + Delta Lake (transactional format)

---

## What is Medallion Architecture?

It is a data design pattern that organizes information in **progressive quality layers**. Each layer refines the previous one, clearly separating raw ingestion from data ready to consume.

```
Data sources
  │ CSV, JSON, APIs, logs, DB exports...
  ▼
┌──────────────────────────────────────────────────────────┐
│  BRONZE  — Raw Zone                                      │
│  "Data exactly as it arrived, untouched"                 │
│  s3a://bronze/                                           │
│  Format: any (CSV, JSON, raw Parquet)                    │
│  Policy: append-only, never modify, long retention       │
└────────────────────────┬─────────────────────────────────┘
                         │ Spark job: clean + validate
                         ▼
┌──────────────────────────────────────────────────────────┐
│  SILVER  — Curated Zone                                  │
│  "Clean, typed, deduplicated, enriched"                  │
│  s3a://silver/                                           │
│  Format: Delta Lake (Parquet + ACID + time travel)       │
│  Policy: overwrite/merge according to SCD                │
└────────────────────────┬─────────────────────────────────┘
                         │ Spark job: aggregations + business rules
                         ▼
┌──────────────────────────────────────────────────────────┐
│  GOLD  — Business Zone                                   │
│  "Ready to consume: KPIs, ML features, reports"          │
│  s3a://gold/                                             │
│  Format: Delta Lake (partitioned by date/domain)         │
│  Policy: periodic overwrite (daily/hourly batch)         │
└──────────────────────────────────────────────────────────┘
```

---

## How it fits into the lab stack

```
                    ┌─────────────────────────────────────────────────────┐
                    │                    MinIO (master2)                  │
                    │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
                    │  │ bronze/  │  │ silver/  │  │  gold/   │          │
                    │  │ (raw)    │  │ (delta)  │  │ (delta)  │          │
                    │  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
                    │       │             │              │                 │
                    └───────┼─────────────┼──────────────┼─────────────────┘
                            │             │              │
        ┌───────────────────▼─────────────▼──────────────▼──────────────────┐
        │                       Apache Spark (PySpark)                       │
        │  bronze → silver: clean, type, dedup, enrich                       │
        │  silver → gold:   aggregate, ML features, KPIs                     │
        └──────────────────────────────┬─────────────────────────────────────┘
                                       │ orchestrates
        ┌──────────────────────────────▼─────────────────────────────────────┐
        │                    Apache Airflow (DAGs)                            │
        │  DAG: pipeline_bronze_ingest   → every hour                        │
        │  DAG: pipeline_silver_refine   → every hour (depends bronze)       │
        │  DAG: pipeline_gold_aggregate  → every day (depends silver)        │
        └──────────────────────────────┬─────────────────────────────────────┘
                                       │
        ┌──────────────────────────────▼─────────────────────────────────────┐
        │               JupyterLab (exploration and experimentation)         │
        │  Accesses any layer: s3a://bronze/, s3a://silver/, s3a://gold/     │
        │  Trains models from gold/, writes results to gold/features/        │
        └────────────────────────────────────────────────────────────────────┘
```

---

## MinIO buckets and their purpose

| Bucket | Layer | Format | Written by | Read by |
|--------|-------|--------|------------|---------|
| `bronze` | Raw | CSV / JSON / raw Parquet | Airflow ingest DAGs, n8n, notebooks | Spark (→silver) |
| `silver` | Curated | **Delta Lake** | Spark (from bronze) | Spark (→gold), Jupyter |
| `gold` | Business | **Delta Lake** | Spark (from silver) | Jupyter, n8n, Airflow |
| `airflow-logs` | Infra | plain text | Airflow worker | Airflow UI |
| `spark-warehouse` | Infra | Delta catalog + history | Spark | Spark History Server |
| `lab-notebooks` | Dev | .ipynb, HTML | Jupyter | Jupyter |

---

## Prefix structure inside each bucket

```
bronze/
├── sales/
│   ├── year=2026/month=03/day=30/
│   │   └── raw_20260330_143500.csv
│   └── ...
├── users/
│   └── ...
└── events/
    └── ...

silver/
├── sales/              ← Delta table (ACID, time travel)
│   ├── _delta_log/
│   └── part-000*.parquet
├── users/
└── events/

gold/
├── daily_kpis/         ← Delta table
├── model_features/     ← Delta table (for ML training)
├── monthly_reports/
└── ...

spark-warehouse/
├── history/            ← History Server event logs
└── delta_catalog/      ← Spark SQL catalog (if used)
```

---

## Delta Lake — Why we use it on Silver and Gold

Delta Lake adds the following critical capabilities on top of Parquet:

| Feature | What it means in practice |
|---------|--------------------------|
| **ACID transactions** | If a job fails halfway, the table does NOT become corrupted |
| **Time travel** | `VERSION AS OF 5` — read how the table looked N versions ago |
| **Schema evolution** | Add columns without breaking existing readers |
| **Upserts (MERGE)** | `MERGE INTO silver.sales WHEN MATCHED THEN UPDATE...` |
| **Compaction (OPTIMIZE)** | Merges many small files into fewer large ones |
| **Vacuum** | Deletes old files that are no longer needed |

In Bronze we do NOT use Delta because we want to preserve raw data exactly as it arrived.

---

## Write patterns per layer

### Bronze — append only

```python
# Ingest from external source → write to bronze as-is
df_raw.write \
    .mode("append") \
    .partitionBy("year", "month", "day") \
    .parquet("s3a://bronze/sales/")
```

### Silver — upsert with Delta (SCD Type 1)

```python
from delta.tables import DeltaTable

# If table does not exist, create it
if not DeltaTable.isDeltaTable(spark, "s3a://silver/sales/"):
    df_clean.write.format("delta").save("s3a://silver/sales/")
else:
    # Merge: update existing records, insert new ones
    silver_table = DeltaTable.forPath(spark, "s3a://silver/sales/")
    silver_table.alias("target").merge(
        df_clean.alias("source"),
        "target.id = source.id"
    ).whenMatchedUpdateAll() \
     .whenNotMatchedInsertAll() \
     .execute()
```

### Gold — periodic overwrite

```python
# KPIs are fully recalculated every day
df_kpis.write \
    .format("delta") \
    .mode("overwrite") \
    .option("overwriteSchema", "true") \
    .partitionBy("date") \
    .save("s3a://gold/daily_kpis/")
```

---

## Airflow DAG — typical medallion pipeline structure

```python
# dags/pipeline_medallion.py
from airflow.decorators import dag, task
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from datetime import datetime

@dag(
    schedule_interval="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["medallion", "batch"]
)
def pipeline_medallion():

    ingest_bronze = SparkSubmitOperator(
        task_id="ingest_bronze",
        application="/opt/airflow/dags/jobs/ingest_bronze.py",
        conn_id="spark_default",
        application_args=["--date", "{{ ds }}"],
    )

    refine_silver = SparkSubmitOperator(
        task_id="refine_silver",
        application="/opt/airflow/dags/jobs/refine_silver.py",
        conn_id="spark_default",
    )

    aggregate_gold = SparkSubmitOperator(
        task_id="aggregate_gold",
        application="/opt/airflow/dags/jobs/aggregate_gold.py",
        conn_id="spark_default",
    )

    ingest_bronze >> refine_silver >> aggregate_gold

pipeline_medallion()
```

---

## Exploration from Jupyter (BigData kernel)

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("Exploration") \
    .master("spark://spark_master:7077") \
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
    .config("spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog") \
    .getOrCreate()

# See what's in bronze
spark.read.parquet("s3a://bronze/sales/").show(5)

# See Silver with time travel
spark.read.format("delta") \
    .option("versionAsOf", 0) \
    .load("s3a://silver/sales/") \
    .show(5)

# See Gold — today's KPIs
spark.read.format("delta") \
    .load("s3a://gold/daily_kpis/") \
    .filter("date = '2026-03-30'") \
    .show()

# See change history of a Silver table
from delta.tables import DeltaTable
DeltaTable.forPath(spark, "s3a://silver/sales/").history().show()
```

---

## Operational considerations

### Periodic compaction (OPTIMIZE)

Delta Lake generates many small files with frequent writes.
Schedule in Airflow (weekly) or run manually:

```python
# Compact Silver sales
DeltaTable.forPath(spark, "s3a://silver/sales/").optimize().executeCompaction()

# With Z-ordering (improves queries on specific columns)
DeltaTable.forPath(spark, "s3a://silver/sales/") \
    .optimize() \
    .executeZOrderBy("date", "category")
```

### Vacuum (clean up old files)

```python
# Default retains 7 days of history
DeltaTable.forPath(spark, "s3a://silver/sales/").vacuum()

# Custom retention (e.g.: 3 days)
DeltaTable.forPath(spark, "s3a://silver/sales/").vacuum(72)
```

### Space monitoring

```bash
# Check size of each layer in MinIO
docker exec -it $(docker ps -q -f name=minio_minio) sh -c "
  mc alias set local http://localhost:9000 \$(cat /run/secrets/minio_access_key) \$(cat /run/secrets/minio_secret_key) &&
  mc du local/bronze local/silver local/gold
"
```
