# Medallion architecture

> Reviewed 2026-08-22. Target pattern implemented on MinIO and Spark; concrete tables and DAGs are versioned per project.

## Layers

```text
sources -> Bronze (raw) -> Spark/validation -> Silver (curated) -> Gold (consumption)
                         Airflow orchestrates and Jupyter supports exploration
```

- **Bronze**: data received without transformation.
- **Silver**: typed, deduplicated, and enriched data, preferably Delta/Parquet.
- **Gold**: aggregates, KPIs, and consumable features.

MinIO runs on `master2` (`/srv/datalake/minio`). Spark declares Delta extensions and uses the worker on `master2`; Airflow runs governance, promotion, and evaluation DAGs.

## Buckets and responsibilities

| Bucket/prefix | Purpose |
|---|---|
| `bronze/` | raw landing zone |
| `silver/` | curated datasets |
| `gold/` | analytics and ML products |
| `governance/` | validation/catalog results, if enabled |
| `airflow-logs/` | reserved for remote logs (Airflow is configured for local logging by default) |
| `spark-warehouse/` | warehouse and events as configured |

Do not assume a bucket exists merely because it appears in an example; verify it in MinIO before running a DAG.
