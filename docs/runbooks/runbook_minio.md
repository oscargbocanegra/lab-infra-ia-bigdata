# Runbook: MinIO — Object Storage S3-compatible (Medallion Architecture)

> Stack: `minio` | Nodo: master2 | Última revisión: 2026-03-30

---

## Descripción

MinIO es el object storage S3-compatible del lab. Reemplaza a HDFS como capa de almacenamiento distribuido para Spark, Airflow y notebooks. Implementa la **Medallion Architecture** (Bronze → Silver → Gold) donde Silver y Gold usan **Delta Lake** para garantizar ACID, time travel y schema evolution.

```
Capa       Bucket           Formato         Quién escribe
────────── ──────────────── ─────────────── ─────────────────────────────
Bronze     bronze/          CSV/JSON/Parquet Airflow ingesta, scripts ETL
Silver     silver/          Delta Lake       Spark (limpieza + tipado)
Gold       gold/            Delta Lake       Spark (KPIs, features ML)
─ Infra ──────────────────────────────────────────────────────────────────
           airflow-logs/    Texto plano      Airflow (remote logging)
           spark-warehouse/ Delta catalog    Spark SQL + History Server
           lab-notebooks/   .ipynb           Jupyter exports
```

Ver arquitectura completa: [`docs/architecture/MEDALLION.md`](../architecture/MEDALLION.md)

---

## Secrets requeridos (crear antes de deploy)

```bash
# En master1 (Swarm manager):

# Access key (usuario root MinIO — usar como AWS_ACCESS_KEY_ID)
echo "minioadmin" | docker secret create minio_access_key -

# Secret key (password root MinIO — mínimo 8 caracteres)
echo "$(openssl rand -base64 32)" | docker secret create minio_secret_key -
```

> **Importante**: los mismos secrets (`minio_access_key`, `minio_secret_key`) son usados por Jupyter, Spark y Airflow para conectarse a MinIO vía S3A. Guardá el access key en un lugar seguro — lo necesitás para la UI.

---

## Deploy

```bash
# 1. Crear directorio de datos en master2
ssh master2 "sudo mkdir -p /srv/datalake/minio && sudo chown root:docker /srv/datalake/minio && sudo chmod 2775 /srv/datalake/minio"

# 2. Desplegar stack
docker stack deploy -c stacks/data/12-minio/stack.yml minio

# 3. Verificar que arrancó (~30s)
watch docker service ls | grep minio
# Esperado: minio_minio  replicated  1/1

# 4. Health check
curl -sk https://minio-api.sexydad/minio/health/live && echo "OK"
```

---

## Crear buckets Medallion Architecture (post-deploy)

**CRÍTICO**: Crear los buckets antes de desplegar Spark (el History Server necesita `spark-warehouse/history`).

### Opción A — Desde CLI con `mc` (dentro del contenedor)

```bash
docker exec -it $(docker ps -q -f name=minio_minio) sh -c "
  mc alias set local http://localhost:9000 \$(cat /run/secrets/minio_access_key) \$(cat /run/secrets/minio_secret_key) &&

  # Medallion layers
  mc mb local/bronze &&
  mc mb local/silver &&
  mc mb local/gold &&

  # Infraestructura
  mc mb local/lab-notebooks &&
  mc mb local/airflow-logs &&
  mc mb local/spark-warehouse &&
  mc mb local/spark-warehouse/history &&

  # Verificar
  mc ls local
"
```

### Opción B — Desde la UI web (`https://minio.sexydad`)

```
Credenciales: minio_access_key / minio_secret_key
Crear buckets: bronze, silver, gold, lab-notebooks, airflow-logs, spark-warehouse
Dentro de spark-warehouse: crear "carpeta" history/
```

### Opción C — Con `mc` instalado en master1

```bash
# Instalar mc
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# Configurar alias (usar credenciales reales)
mc alias set lab https://minio-api.sexydad MINIO_ACCESS_KEY MINIO_SECRET_KEY

# Crear buckets
mc mb lab/bronze lab/silver lab/gold
mc mb lab/lab-notebooks lab/airflow-logs lab/spark-warehouse
mc mb lab/spark-warehouse/history

mc ls lab
```

---

## Uso desde PySpark — Medallion con Delta Lake (kernel BigData en Jupyter)

### Configuración de sesión Spark con S3A + Delta

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

print(f"Spark {spark.version} conectado — Delta Lake listo")
```

### Bronze → ingestar datos crudos

```python
# Ingestar CSV crudo en Bronze (append-only, sin transformar)
df_raw = spark.read \
    .option("header", "true") \
    .option("inferSchema", "true") \
    .csv("/data/datasets/ventas.csv")   # mount local o s3a://bronze/raw/

# Guardar en Bronze como Parquet (formato raw)
df_raw.write \
    .mode("append") \
    .partitionBy("fecha") \
    .parquet("s3a://bronze/ventas/")

print(f"Bronze: {df_raw.count()} registros ingestados")
```

### Bronze → Silver — limpiar y tipar con Delta Lake

```python
from pyspark.sql import functions as F

# Leer desde Bronze
df_bronze = spark.read.parquet("s3a://bronze/ventas/")

# Transformaciones: limpiar, deduplicar, tipar
df_silver = df_bronze \
    .dropDuplicates(["id_transaccion"]) \
    .filter(F.col("monto").isNotNull()) \
    .filter(F.col("monto") > 0) \
    .withColumn("fecha", F.to_date(F.col("fecha"), "yyyy-MM-dd")) \
    .withColumn("monto", F.col("monto").cast("double")) \
    .withColumn("_ingest_ts", F.current_timestamp())

# Escribir en Silver como Delta Lake (ACID, time travel)
df_silver.write \
    .format("delta") \
    .mode("overwrite") \
    .option("overwriteSchema", "true") \
    .partitionBy("fecha") \
    .save("s3a://silver/ventas/")

print(f"Silver: {df_silver.count()} registros limpios guardados")
```

### Silver → Gold — agregar KPIs con Delta Lake

```python
# Leer desde Silver
df_silver = spark.read.format("delta").load("s3a://silver/ventas/")

# Calcular KPIs diarios
df_gold = df_silver \
    .groupBy("fecha", "categoria") \
    .agg(
        F.sum("monto").alias("total_ventas"),
        F.count("*").alias("cantidad_transacciones"),
        F.avg("monto").alias("ticket_promedio"),
        F.max("monto").alias("venta_maxima")
    ) \
    .withColumn("_gold_ts", F.current_timestamp())

# Guardar en Gold como Delta Lake
df_gold.write \
    .format("delta") \
    .mode("overwrite") \
    .partitionBy("fecha") \
    .save("s3a://gold/ventas_kpis_diarios/")

print(f"Gold: {df_gold.count()} registros de KPIs calculados")
```

### Time Travel en Delta Lake

```python
# Leer versión anterior de Silver (time travel)
df_v0 = spark.read.format("delta") \
    .option("versionAsOf", 0) \
    .load("s3a://silver/ventas/")

# O por timestamp
df_ayer = spark.read.format("delta") \
    .option("timestampAsOf", "2026-03-29") \
    .load("s3a://silver/ventas/")

# Ver historial de versiones
from delta.tables import DeltaTable

dt = DeltaTable.forPath(spark, "s3a://silver/ventas/")
dt.history().show(10)
```

---

## Uso desde Python — boto3 / s3fs (capa Bronze)

Las credenciales ya están exportadas en el entorno del contenedor Jupyter (vía `entrypoint.sh`):
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

# Subir archivo crudo a Bronze
s3.upload_file("/home/jovyan/work/datos.csv", "bronze", "raw/datos.csv")

# Listar objetos en Bronze
for obj in s3.list_objects(Bucket="bronze").get("Contents", []):
    print(obj["Key"])

# Listar todos los buckets
print([b["Name"] for b in s3.list_buckets()["Buckets"]])
```

```python
# Con s3fs (más Pythónico, integra con pandas)
import s3fs, pandas as pd, os

fs = s3fs.S3FileSystem(
    endpoint_url=os.environ["AWS_ENDPOINT_URL"],
    key=os.environ["AWS_ACCESS_KEY_ID"],
    secret=os.environ["AWS_SECRET_ACCESS_KEY"],
)

# Leer CSV crudo desde Bronze
df = pd.read_csv(fs.open("bronze/raw/datos.csv"))

# Listar contenido de Silver
fs.ls("silver/ventas/")
```

---

## Diagnóstico

```bash
# Estado del servicio
docker service ps minio_minio

# Logs en tiempo real
docker service logs minio_minio --tail 50 -f

# Health check (via Traefik)
curl -sk https://minio-api.sexydad/minio/health/live && echo "OK"
curl -sk https://minio-api.sexydad/minio/health/ready && echo "Ready"

# Health check directo (desde master2)
curl -f http://localhost:9000/minio/health/live && echo "OK"

# Espacio en disco
ssh master2 "df -h /srv/datalake/minio"

# Listar buckets con mc
docker exec -it $(docker ps -q -f name=minio_minio) sh -c "
  mc alias set local http://localhost:9000 \$(cat /run/secrets/minio_access_key) \$(cat /run/secrets/minio_secret_key) &&
  mc ls local"
```

---

## Redeploy / Update de versión

```bash
# Actualizar versión (cambiar tag en stack.yml primero)
docker stack deploy -c stacks/data/12-minio/stack.yml minio

# Forzar recreación del container (mismo tag)
docker service update --force minio_minio
```

---

## Backup

MinIO almacena todos los objetos en `/srv/datalake/minio` en master2. El backup de esta ruta incluye todos los buckets.

```bash
# Backup con mc mirror (sincronización):
mc mirror lab/bronze   /backup/bronze/
mc mirror lab/silver   /backup/silver/
mc mirror lab/gold     /backup/gold/

# O backup completo del filesystem (desde master1 → backup externo)
rsync -avz --delete master2:/srv/datalake/minio/ /backup/minio/
```
