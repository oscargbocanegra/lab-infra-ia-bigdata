# Runbook: Apache Spark 3.5 — Procesamiento distribuido

> Stack: `spark` | Master: master1 | Worker: master2 | Última revisión: 2026-03-30

---

## Descripción

Apache Spark es el motor de procesamiento distribuido del lab. Permite ejecutar jobs batch, SQL analítico y ML sobre datasets grandes, usando MinIO (S3A) como capa de storage y Delta Lake como formato transaccional.

```
Componente         Nodo      Recursos             URL
──────────────── ──────── ─────────────────── ──────────────────────────
spark_master       master1  0.5 CPU / 1 GB     https://spark-master.sexydad
spark_worker       master2  10 CPUs / 14 GB    https://spark-worker.sexydad
spark_history      master1  0.25 CPU / 512 MB  https://spark-history.sexydad
```

---

## Secrets requeridos

Los mismos que MinIO (compartidos):

```bash
# Ya creados si desplegaste MinIO:
# minio_access_key
# minio_secret_key
```

---

## Preparación de directorios (master2)

```bash
ssh master2 "sudo mkdir -p /srv/fastdata/spark-tmp && sudo chmod 777 /srv/fastdata/spark-tmp"
```

---

## Deploy

```bash
# 1. MinIO debe estar desplegado y corriendo primero
#    (Spark History Server escribe logs en s3a://spark-warehouse/history)

# 2. Crear bucket spark-warehouse en MinIO (si no existe)
#    Ver runbook_minio.md — sección "Crear buckets"

# 3. Desplegar stack
docker stack deploy -c stacks/data/98-spark/stack.yml spark

# 4. Verificar
docker stack ps spark
docker service logs spark_spark_master --tail 20
docker service logs spark_spark_worker --tail 20
```

---

## Verificar que el worker se registró

```bash
# Desde la UI: https://spark-master.sexydad
# Debe mostrar 1 Worker Alive con 10 CPUs y 14 GB RAM

# O por logs:
docker service logs spark_spark_master 2>&1 | grep -i worker
# Esperado: "Registering worker ... with 10 cores, 14.0 GiB RAM"
```

---

## Usar Spark desde Jupyter (kernel BigData)

### Conexión básica al cluster

```python
import findspark
findspark.init()

from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("Mi primer job") \
    .master("spark://spark_master:7077") \
    .config("spark.executor.memory", "4g") \
    .config("spark.executor.cores", "4") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "TU_ACCESS_KEY") \
    .config("spark.hadoop.fs.s3a.secret.key", "TU_SECRET_KEY") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .getOrCreate()

print(f"Spark version: {spark.version}")
print(f"Master: {spark.sparkContext.master}")
```

### Leer CSV desde MinIO → procesar → guardar Delta

```python
# Leer datos crudos
df = spark.read \
    .option("header", "true") \
    .option("inferSchema", "true") \
    .csv("s3a://lab-datasets/ventas.csv")

df.printSchema()
df.show(5)

# Transformaciones
from pyspark.sql import functions as F

resultado = df \
    .filter(F.col("monto") > 1000) \
    .groupBy("categoria") \
    .agg(
        F.sum("monto").alias("total"),
        F.count("*").alias("cantidad")
    ) \
    .orderBy("total", ascending=False)

# Guardar como Delta Lake en MinIO
resultado.write \
    .format("delta") \
    .mode("overwrite") \
    .save("s3a://spark-warehouse/ventas_resumen/")

print("Job completado!")
spark.stop()
```

### Leer archivos locales del datalake

```python
# Los datasets también están montados directamente en /data/datasets
df = spark.read.parquet("/data/datasets/ml_dataset.parquet")
```

---

## Monitoreo

```bash
# UI Master (ver jobs activos, workers)
# https://spark-master.sexydad

# UI Worker (ver tasks en ejecución)
# https://spark-worker.sexydad

# History Server (ver jobs históricos)
# https://spark-history.sexydad

# Logs en tiempo real
docker service logs spark_spark_worker -f --tail 50
```

---

## Ajuste de recursos del Worker

Si necesitás más o menos recursos para el worker, editá `stacks/data/98-spark/stack.yml`:

```yaml
environment:
  SPARK_WORKER_CORES: "10"   # Cores ofrecidos al cluster
  SPARK_WORKER_MEMORY: 14g   # RAM ofrecida al cluster
```

> El worker solo usa lo que un job le pide. Los recursos declarados son el máximo disponible, no lo que consume idle.

---

## Diagnóstico de problemas comunes

### Worker no se conecta al master

```bash
# Verificar que ambos están en la misma red overlay (internal)
docker network inspect internal | grep -A5 spark

# Verificar resolución DNS
docker exec $(docker ps -q -f name=spark_spark_worker) \
  ping -c2 spark_master
```

### Job falla con "No space left on device"

```bash
# Limpiar scratch de Spark en master2
ssh master2 "sudo rm -rf /srv/fastdata/spark-tmp/*"
```

### History Server no muestra jobs

```bash
# Verificar que el bucket spark-warehouse/history existe en MinIO
mc ls lab/spark-warehouse/

# Verificar que los logs se escriben
docker service logs spark_spark_history --tail 30
```

---

## Redeploy

```bash
docker stack deploy -c stacks/data/98-spark/stack.yml spark
```
