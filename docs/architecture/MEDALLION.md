# Arquitectura Medallón — Lab Big Data + IA

> Actualizado: 2026-03-30
> Patrón: Medallion Architecture (Bronze → Silver → Gold)
> Storage: MinIO (S3-compatible) + Delta Lake (formato transaccional)

---

## ¿Qué es la arquitectura medallón?

Es un patrón de diseño de datos que organiza la información en **capas progresivas de calidad**. Cada capa refina la anterior, separando claramente la ingesta cruda del dato listo para consumir.

```
Fuentes de datos
  │ CSV, JSON, APIs, logs, DB exports...
  ▼
┌──────────────────────────────────────────────────────────┐
│  BRONZE  — Raw Zone                                      │
│  "Los datos tal como llegaron, sin tocar"                │
│  s3a://bronze/                                           │
│  Formato: cualquiera (CSV, JSON, Parquet raw)            │
│  Política: append-only, nunca modificar, retención larga │
└────────────────────────┬─────────────────────────────────┘
                         │ Spark job: limpieza + validación
                         ▼
┌──────────────────────────────────────────────────────────┐
│  SILVER  — Curated Zone                                  │
│  "Limpio, tipado, deduplicado, enriquecido"              │
│  s3a://silver/                                           │
│  Formato: Delta Lake (Parquet + ACID + time travel)      │
│  Política: overwrite/merge según SCD                     │
└────────────────────────┬─────────────────────────────────┘
                         │ Spark job: agregaciones + reglas negocio
                         ▼
┌──────────────────────────────────────────────────────────┐
│  GOLD  — Business Zone                                   │
│  "Listo para consumir: KPIs, features ML, reportes"      │
│  s3a://gold/                                             │
│  Formato: Delta Lake (particionado por fecha/dominio)    │
│  Política: sobreescritura periódica (daily/hourly batch) │
└──────────────────────────────────────────────────────────┘
```

---

## Cómo encaja en el stack del lab

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
        │  bronze → silver: limpieza, tipado, dedup, enriquecimiento         │
        │  silver → gold:   agregaciones, features ML, KPIs                  │
        └──────────────────────────────┬─────────────────────────────────────┘
                                       │ orquesta
        ┌──────────────────────────────▼─────────────────────────────────────┐
        │                    Apache Airflow (DAGs)                            │
        │  DAG: pipeline_bronze_ingest   → cada hora                         │
        │  DAG: pipeline_silver_refine   → cada hora (depende bronze)        │
        │  DAG: pipeline_gold_aggregate  → cada día (depende silver)         │
        └──────────────────────────────┬─────────────────────────────────────┘
                                       │
        ┌──────────────────────────────▼─────────────────────────────────────┐
        │               JupyterLab (exploración y experimentación)           │
        │  Accede a cualquier capa: s3a://bronze/, s3a://silver/, s3a://gold/ │
        │  Entrena modelos desde gold/, escribe resultados a gold/features/   │
        └────────────────────────────────────────────────────────────────────┘
```

---

## Buckets MinIO y su propósito

| Bucket | Capa | Formato | Quién escribe | Quién lee |
|--------|------|---------|---------------|-----------|
| `bronze` | Raw | CSV / JSON / Parquet raw | Airflow ingest DAGs, n8n, notebooks | Spark (→silver) |
| `silver` | Curated | **Delta Lake** | Spark (desde bronze) | Spark (→gold), Jupyter |
| `gold` | Business | **Delta Lake** | Spark (desde silver) | Jupyter, n8n, Airflow |
| `airflow-logs` | Infra | texto | Airflow worker | Airflow UI |
| `spark-warehouse` | Infra | Delta catalog + history | Spark | Spark History Server |
| `lab-notebooks` | Dev | .ipynb, HTML | Jupyter | Jupyter |

---

## Estructura de prefijos dentro de cada bucket

```
bronze/
├── ventas/
│   ├── year=2026/month=03/day=30/
│   │   └── raw_20260330_143500.csv
│   └── ...
├── usuarios/
│   └── ...
└── eventos/
    └── ...

silver/
├── ventas/              ← Delta table (ACID, time travel)
│   ├── _delta_log/
│   └── part-000*.parquet
├── usuarios/
└── eventos/

gold/
├── kpis_diarios/        ← Delta table
├── features_modelo/     ← Delta table (para training ML)
├── reportes_mensuales/
└── ...

spark-warehouse/
├── history/             ← Event logs del History Server
└── delta_catalog/       ← Spark SQL catalog (si se usa)
```

---

## Delta Lake — Por qué lo usamos en Silver y Gold

Delta Lake agrega sobre Parquet las siguientes capacidades críticas:

| Feature | Qué significa en práctica |
|---------|--------------------------|
| **ACID transactions** | Si un job falla a mitad, la tabla NO queda corrupta |
| **Time travel** | `VERSION AS OF 5` — leer cómo era la tabla hace N versiones |
| **Schema evolution** | Agregar columnas sin romper readers existentes |
| **Upserts (MERGE)** | `MERGE INTO silver.ventas WHEN MATCHED THEN UPDATE...` |
| **Compaction (OPTIMIZE)** | Fusiona muchos archivos pequeños en pocos grandes |
| **Vacuum** | Borra archivos viejos que ya no son necesarios |

En Bronze NO usamos Delta porque queremos preservar el dato crudo exactamente como llegó.

---

## Patrones de escritura por capa

### Bronze — append only

```python
# Ingest desde fuente externa → escribir en bronze tal cual
df_raw.write \
    .mode("append") \
    .partitionBy("year", "month", "day") \
    .parquet("s3a://bronze/ventas/")
```

### Silver — upsert con Delta (SCD Type 1)

```python
from delta.tables import DeltaTable

# Si la tabla no existe, crearla
if not DeltaTable.isDeltaTable(spark, "s3a://silver/ventas/"):
    df_clean.write.format("delta").save("s3a://silver/ventas/")
else:
    # Merge: actualizar registros existentes, insertar nuevos
    silver_table = DeltaTable.forPath(spark, "s3a://silver/ventas/")
    silver_table.alias("target").merge(
        df_clean.alias("source"),
        "target.id = source.id"
    ).whenMatchedUpdateAll() \
     .whenNotMatchedInsertAll() \
     .execute()
```

### Gold — overwrite periódico

```python
# Los KPIs se recalculan completos cada día
df_kpis.write \
    .format("delta") \
    .mode("overwrite") \
    .option("overwriteSchema", "true") \
    .partitionBy("fecha") \
    .save("s3a://gold/kpis_diarios/")
```

---

## DAG de Airflow — estructura típica de pipeline medallón

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

## Exploración desde Jupyter (kernel BigData)

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("Exploración") \
    .master("spark://spark_master:7077") \
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
    .config("spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog") \
    .getOrCreate()

# Ver qué hay en bronze
spark.read.parquet("s3a://bronze/ventas/").show(5)

# Ver Silver con time travel
spark.read.format("delta") \
    .option("versionAsOf", 0) \
    .load("s3a://silver/ventas/") \
    .show(5)

# Ver Gold — los KPIs del día
spark.read.format("delta") \
    .load("s3a://gold/kpis_diarios/") \
    .filter("fecha = '2026-03-30'") \
    .show()

# Ver historial de cambios de una tabla Silver
from delta.tables import DeltaTable
DeltaTable.forPath(spark, "s3a://silver/ventas/").history().show()
```

---

## Consideraciones operativas

### Compaction periódica (OPTIMIZE)

Delta Lake genera muchos archivos pequeños con escrituras frecuentes.
Programar en Airflow (semanal) o ejecutar manualmente:

```python
# Compactar Silver ventas
DeltaTable.forPath(spark, "s3a://silver/ventas/").optimize().executeCompaction()

# Con Z-ordering (mejora queries por columnas específicas)
DeltaTable.forPath(spark, "s3a://silver/ventas/") \
    .optimize() \
    .executeZOrderBy("fecha", "categoria")
```

### Vacuum (limpiar archivos viejos)

```python
# Por defecto retiene 7 días de historial
DeltaTable.forPath(spark, "s3a://silver/ventas/").vacuum()

# Retención custom (ej: 3 días)
DeltaTable.forPath(spark, "s3a://silver/ventas/").vacuum(72)
```

### Monitoreo de espacio

```bash
# Ver tamaño de cada capa en MinIO
docker exec -it $(docker ps -q -f name=minio_minio) sh -c "
  mc alias set local http://localhost:9000 \$(cat /run/secrets/minio_access_key) \$(cat /run/secrets/minio_secret_key) &&
  mc du local/bronze local/silver local/gold
"
```
