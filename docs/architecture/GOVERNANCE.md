# Data Governance Architecture

> Part of Phase 9A — Governance foundations

---

## Overview

Data governance in this lab ensures that data moving through the Medallion pipeline
(bronze → silver → gold) is **cataloged**, **validated**, and **traceable**.

It is implemented in two layers that complement each other:

```
┌─────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                             │
│         APIs / Files / Notebooks / External feeds               │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LAYER 1 — DATA QUALITY                       │
│              Great Expectations (inside Airflow)                │
│                                                                 │
│  bronze ingest DAG:                                             │
│    1. Land raw data → bronze/<source>/<date>/                   │
│    2. Run GE suite  → validate schema + nulls + types           │
│    3. Pass → promote to silver/    Fail → alert + stop          │
│                                                                 │
│  Results → MinIO governance/ge-results/  +  OpenSearch logs     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LAYER 2 — DATA CATALOG                       │
│                       OpenMetadata                              │
│                                                                 │
│  Catalog    → all tables, columns, types, owners, descriptions  │
│  Lineage    → bronze → silver → gold, DAG-level tracing         │
│  Profiling  → row counts, nullability, value distributions      │
│  Tags       → PII, sensitive, public, internal                  │
│  Quality    → GE results imported as OpenMetadata tests         │
└─────────────────────────────────────────────────────────────────┘
```

---

## MinIO Naming Convention

All pipelines MUST follow this structure. Enforced by `setup-governance.sh`:

```
bronze/
  <source>/
    <YYYY-MM-DD>/
      <filename>.<ext>          ← raw files as-is (CSV, JSON, Parquet)

silver/
  <domain>/
    <table>/
      <YYYY-MM-DD>/
        part-*.parquet          ← clean, typed, deduplicated Delta Lake

gold/
  <report-name>/
    <YYYY-MM-DD>/
      part-*.parquet            ← KPIs, ML features, business aggregates

governance/
  ge-results/
    <pipeline>/
      <YYYY-MM-DD>/
        result.json             ← Great Expectations validation results
  catalogs/                     ← OpenMetadata metadata exports (backup)
```

**Why strict naming?**
- OpenMetadata connectors use path patterns to auto-discover datasets
- Airflow DAGs use date partitioning for idempotent reruns
- Lineage tracing requires consistent source → target paths

---

## Great Expectations Integration

Great Expectations (GE) runs as a Python task inside each ingestion DAG.

### Expectation Suites per layer

| Suite name | Applied on | Key checks |
|---|---|---|
| `bronze_landing` | Raw files just ingested | File exists, non-empty, parseable |
| `silver_promotion` | Before bronze → silver | Schema match, null rate < 5%, no duplicates on PK |
| `gold_promotion` | Before silver → gold | All required columns present, value ranges valid |

### Result storage

```python
# Airflow DAG task (simplified)
from great_expectations.data_context import DataContext

def validate_bronze(source: str, date: str):
    context = DataContext("/opt/airflow/great_expectations")
    batch = context.get_batch(f"s3://bronze/{source}/{date}/")
    result = context.run_validation_operator(
        "action_list_operator",
        assets_to_validate=[batch],
        run_id=f"{source}/{date}"
    )
    if not result["success"]:
        raise ValueError(f"GE validation failed for {source}/{date}")
```

Results are saved to `MinIO: governance/ge-results/` and logs flow to OpenSearch.

---

## OpenMetadata — Connected Services

| Service | Connector | What it catalogs |
|---|---|---|
| Postgres | `DatabaseServiceType.Postgres` | All schemas, tables, columns, row counts |
| MinIO | `StorageServiceType.S3` | All buckets, prefixes, file types |
| Airflow | `PipelineServiceType.Airflow` | All DAGs, tasks, lineage between datasets |
| OpenSearch | `SearchServiceType.ElasticSearch` | All indices, mappings |

---

## Lineage Flow Example

```
[Airflow DAG: ingest_sales]
        │
        ├──► bronze/sales/2026-04-06/raw.csv          (MinIO)
        │         │
        │    [GE: bronze_landing suite] ✅
        │         │
        ├──► silver/commerce/sales/2026-04-06/         (MinIO Delta Lake)
        │         │
        │    [GE: silver_promotion suite] ✅
        │         │
        └──► gold/kpi_revenue/2026-04-06/              (MinIO Delta Lake)

OpenMetadata shows this full chain automatically via OpenLineage.
```

---

## Access

| Service | URL | Auth |
|---|---|---|
| OpenMetadata UI | https://openmetadata.sexydad | admin / (set on first login) |
| Great Expectations results | MinIO → governance/ge-results/ | MinIO credentials |
| Airflow lineage | https://airflow.sexydad | Airflow admin |

---

## Related Documents

- [ADR-007: Data Governance with OpenMetadata](../adrs/ADR-007-data-governance-openmetadata.md)
- [MEDALLION.md](./MEDALLION.md) — storage layer architecture
- [DATABASES.md](./DATABASES.md) — database strategy
