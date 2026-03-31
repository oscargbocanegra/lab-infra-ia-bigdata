# Runbook: MinIO — Object Storage S3-compatible

> Stack: `minio` | Nodo: master2 | Última revisión: 2026-03-30

---

## Descripción

MinIO es un object storage 100% compatible con la API de Amazon S3. En este lab reemplaza a HDFS como capa de almacenamiento distribuido para Spark, Airflow y notebooks. Todos los datos masivos (datasets, modelos, artefactos, logs) viven aquí.

```
Aplicación       Protocolo    Bucket
──────────────── ──────────── ───────────────────────
PySpark          s3a://       spark-warehouse/
Airflow          S3Hook       airflow-logs/
Jupyter (boto3)  S3 API       lab-datasets/
n8n              HTTP API     lab-artifacts/
```

---

## Secrets requeridos (crear antes de deploy)

```bash
# En master1 (Swarm manager):

# Access key (usuario root MinIO — usar como AWS_ACCESS_KEY_ID)
echo "minioadmin" | docker secret create minio_access_key -

# Secret key (password root MinIO — usar como AWS_SECRET_ACCESS_KEY)
# Usar una contraseña fuerte en producción
openssl rand -base64 24 | docker secret create minio_secret_key -
```

> **Importante**: los mismos secrets (`minio_access_key`, `minio_secret_key`) son usados por Jupyter, Spark y Airflow para conectarse a MinIO vía S3A.

---

## Deploy

```bash
# 1. Crear directorio de datos en master2
ssh master2 "sudo mkdir -p /srv/datalake/minio && sudo chown 1000:1000 /srv/datalake/minio"

# 2. Desplegar stack
docker stack deploy -c stacks/data/12-minio/stack.yml minio

# 3. Verificar
docker stack ps minio
docker service logs minio_minio --tail 30
```

---

## Crear buckets iniciales (post-deploy)

Opción A — Desde la UI web (`https://minio.sexydad`):

```
Credenciales: minio_access_key / minio_secret_key
Crear buckets: lab-datasets, lab-artifacts, lab-notebooks,
               airflow-logs, spark-warehouse
```

Opción B — Desde CLI con `mc` (MinIO Client):

```bash
# Instalar mc en master1
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# Configurar alias
mc alias set lab https://minio-api.sexydad \
  $(docker secret inspect minio_access_key --format '{{.Spec.Name}}') \
  $(cat /run/secrets/minio_secret_key)

# FORMA PRÁCTICA — correr mc desde el container:
docker run --rm --network lab-infra-ia-bigdata_internal \
  minio/mc:latest alias set lab http://minio:9000 minioadmin TU_SECRET

# Crear buckets
mc mb lab/lab-datasets
mc mb lab/lab-artifacts
mc mb lab/lab-notebooks
mc mb lab/airflow-logs
mc mb lab/spark-warehouse

# Verificar
mc ls lab
```

---

## Uso desde PySpark (kernel BigData en Jupyter)

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("MinIO Test") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "TU_ACCESS_KEY") \
    .config("spark.hadoop.fs.s3a.secret.key", "TU_SECRET_KEY") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .getOrCreate()

# Leer dataset desde MinIO
df = spark.read.parquet("s3a://lab-datasets/ventas.parquet")
df.show()

# Escribir resultado en Delta Lake
df.write.format("delta").save("s3a://spark-warehouse/ventas_procesadas/")
```

---

## Uso desde Python (boto3 / s3fs en Jupyter)

```python
import boto3

s3 = boto3.client(
    "s3",
    endpoint_url="http://minio:9000",   # URL interna overlay
    aws_access_key_id="TU_ACCESS_KEY",
    aws_secret_access_key="TU_SECRET_KEY",
    region_name="us-east-1"
)

# Subir archivo
s3.upload_file("/home/jovyan/work/datos.csv", "lab-datasets", "datos.csv")

# Listar objetos
for obj in s3.list_objects(Bucket="lab-datasets")["Contents"]:
    print(obj["Key"])
```

```python
# Con s3fs (más Pythónico, integra con pandas)
import s3fs
import pandas as pd

fs = s3fs.S3FileSystem(
    endpoint_url="http://minio:9000",
    key="TU_ACCESS_KEY",
    secret="TU_SECRET_KEY",
)

df = pd.read_csv(fs.open("lab-datasets/datos.csv"))
```

---

## Diagnóstico

```bash
# Estado del servicio
docker service ps minio_minio

# Logs
docker service logs minio_minio --tail 50 -f

# Health check
curl -f http://master2-ip:9000/minio/health/live && echo "OK"
curl -f http://master2-ip:9000/minio/health/ready && echo "Ready"

# Espacio en disco
ssh master2 "df -h /srv/datalake/minio"
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

MinIO almacena datos en `/srv/datalake/minio`. El backup de esta ruta es suficiente para recuperar todos los objetos.

```bash
# Backup incremental con rsync (desde master1 → backup externo)
rsync -avz --delete master2:/srv/datalake/minio/ /backup/minio/

# O con mc mirror:
mc mirror lab/lab-datasets /backup/lab-datasets/
```
