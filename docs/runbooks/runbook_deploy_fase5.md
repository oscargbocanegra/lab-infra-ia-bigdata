# Runbook: Deploy Fase 5 — MinIO + Spark + Airflow

> Versión: 1.0 — 2026-03-30
> Ejecutar desde: **master1** (Swarm manager)
> Tiempo estimado: ~30-45 minutos

Este runbook cubre el deploy completo de los 3 stacks nuevos de la Fase 5, incluyendo
el redespliegue de Postgres y Jupyter para soportar las nuevas dependencias.

---

## Prerequisitos

Antes de empezar, verificar que el cluster base está operativo:

```bash
# Verificar estado del Swarm
docker node ls
# Esperado: master1 (Leader/Ready) + master2 (Ready)

# Verificar servicios activos
docker service ls
# Deben estar UP: traefik, portainer, postgres, n8n, jupyter, ollama, opensearch
```

---

## Paso 0 — Aplicar daemon.json actualizado en master2

El `daemon.json` de master2 fue actualizado para incluir el bloque de runtime NVIDIA.
Si el archivo en el servidor no tiene `default-runtime: nvidia`, aplicar ahora:

```bash
# Desde master1, copiar o editar en master2:
ssh master2

# Verificar el estado actual del daemon.json en el servidor:
cat /etc/docker/daemon.json

# Si NO tiene "default-runtime": "nvidia", reemplazar con:
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "exec-opts": ["native.cgroupdriver=systemd"],
  "features": {
    "buildkit": true
  },
  "live-restore": true,
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
EOF

# Recargar Docker (live-restore: true = sin downtime en contenedores existentes)
sudo systemctl reload docker || sudo systemctl restart docker

# Verificar que nvidia-container-runtime está disponible:
docker info | grep -i runtime
# Debe mostrar: Runtimes: nvidia runc
# Y: Default Runtime: nvidia

exit  # Volver a master1
```

---

## Paso 1 — Crear secrets nuevos (desde master1)

```bash
# Verificar qué secrets ya existen:
docker secret ls

# Crear los 5 secrets nuevos (solo si NO existen ya):

# 1. Password Airflow en Postgres
echo "$(openssl rand -base64 32)" | docker secret create pg_airflow_pass -

# 2. MinIO access key (usuario root de MinIO — mínimo 3 caracteres)
echo "minioadmin" | docker secret create minio_access_key -

# 3. MinIO secret key (password root de MinIO — mínimo 8 caracteres)
echo "$(openssl rand -base64 32)" | docker secret create minio_secret_key -

# 4. Airflow Fernet key (DEBE ser clave Fernet válida — generada con cryptography)
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" | docker secret create airflow_fernet_key -

# 5. Airflow webserver secret key (Flask secret — cualquier string aleatorio)
echo "$(openssl rand -hex 32)" | docker secret create airflow_webserver_secret -

# Verificar que los 5 fueron creados:
docker secret ls | grep -E "pg_airflow_pass|minio_access_key|minio_secret_key|airflow_fernet_key|airflow_webserver_secret"
```

**IMPORTANTE**: Guardar el valor de `minio_access_key` y `minio_secret_key` en un lugar seguro.
Los necesitarás para acceder a la UI de MinIO.

---

## Paso 2 — Crear directorios en master1

```bash
# En master1:
sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins,redis}

# Airflow corre como UID 50000 (usuario "airflow" en el contenedor)
sudo chown -R 50000:50000 /srv/fastdata/airflow/dags
sudo chown -R 50000:50000 /srv/fastdata/airflow/logs
sudo chown -R 50000:50000 /srv/fastdata/airflow/plugins
# Redis es root:
sudo chown root:docker /srv/fastdata/airflow/redis
sudo chmod 2775 /srv/fastdata/airflow/redis

# OpenSearch en master1 necesita vm.max_map_count (si no está ya):
grep vm.max_map_count /etc/sysctl.conf || echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## Paso 3 — Crear directorios en master2

```bash
ssh master2

# Directorios Airflow worker (mismo path que master1 — mapeo consistente)
sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins}
sudo chown -R 50000:50000 /srv/fastdata/airflow/{dags,logs,plugins}
sudo chmod 2775 /srv/fastdata/airflow/{dags,logs,plugins}

# Spark scratch: shuffle/spill en NVMe
sudo mkdir -p /srv/fastdata/spark-tmp
sudo chown root:docker /srv/fastdata/spark-tmp
sudo chmod 2775 /srv/fastdata/spark-tmp

# MinIO: object storage en HDD 2TB
sudo mkdir -p /srv/datalake/minio
sudo chown root:docker /srv/datalake/minio
sudo chmod 2775 /srv/datalake/minio

exit  # Volver a master1
```

---

## Paso 4 — Redesplegar Postgres (necesario para crear DB airflow)

> **Por qué**: Los init scripts de Postgres solo corren en volumen vacío.
> Como se agregó `02-init-airflow.sh`, necesitamos un volumen fresco.

```bash
# PRIMERO: bajar todos los servicios que dependen de Postgres
docker service rm n8n_n8n 2>/dev/null || true

# Bajar Postgres
docker stack rm postgres 2>/dev/null || true
# Esperar que los servicios terminen:
sleep 15
docker service ls | grep postgres   # debe estar vacío

# Borrar el volumen de datos de Postgres (confirmado: no hay datos críticos)
ssh master2 "sudo rm -rf /srv/fastdata/postgres && sudo mkdir -p /srv/fastdata/postgres && sudo chown 999:999 /srv/fastdata/postgres && sudo chmod 700 /srv/fastdata/postgres"

# Redesplegar Postgres (init scripts crearán n8n + airflow DBs)
cd /path/to/lab-infra-ia-bigdata
docker stack deploy -c stacks/core/02-postgres/stack.yml postgres

# Esperar a que Postgres esté healthy (puede tardar 30-60s):
watch docker service ls | grep postgres
# Esperado: postgres_postgres  1/1  Running

# Verificar que las DBs fueron creadas:
docker exec -it $(docker ps -q -f name=postgres_postgres) \
  psql -U postgres -c "\l"
# Deben aparecer: postgres, n8n, airflow
```

---

## Paso 5 — Redesplegar n8n (post-postgres)

```bash
docker stack deploy -c stacks/automation/02-n8n/stack.yml n8n

# Verificar:
watch docker service ls | grep n8n
# Curl de prueba:
curl -sk https://n8n.sexydad | grep -o "n8n" | head -1
```

---

## Paso 6 — Deploy MinIO

```bash
docker stack deploy -c stacks/data/12-minio/stack.yml minio

# Esperar a que MinIO esté running (~30s):
watch docker service ls | grep minio

# Verificar health:
curl -sk https://minio-api.sexydad/minio/health/live
# Respuesta esperada: HTTP 200 (sin body)
```

### Crear buckets iniciales en MinIO

```bash
# Opción A: via mc (MinIO Client) desde dentro del contenedor
docker exec -it $(docker ps -q -f name=minio_minio) sh -c "
  mc alias set local http://localhost:9000 \$(cat /run/secrets/minio_access_key) \$(cat /run/secrets/minio_secret_key) &&
  mc mb local/lab-datasets local/lab-artifacts local/lab-notebooks local/airflow-logs local/spark-warehouse &&
  mc mb local/spark-warehouse/history
"

# Verificar:
docker exec -it $(docker ps -q -f name=minio_minio) sh -c "
  mc alias set local http://localhost:9000 \$(cat /run/secrets/minio_access_key) \$(cat /run/secrets/minio_secret_key) &&
  mc ls local
"
```

---

## Paso 7 — Deploy Spark

```bash
docker stack deploy -c stacks/data/98-spark/stack.yml spark

# Esperar a que los 3 servicios (master, worker, history) estén running:
watch docker service ls | grep spark

# Verificar Spark Master UI:
curl -sk https://spark-master.sexydad | grep -o "Spark Master" | head -1

# Verificar que el worker registró en el master:
# Ir a https://spark-master.sexydad → debe mostrar 1 Worker alive con 10 CPUs / 14 GB
```

---

## Paso 8 — Deploy Airflow

```bash
# Deploy del stack completo (redis + webserver + scheduler + worker + flower):
docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow

# Esperar a que redis y los componentes arranquen (~60s):
watch docker service ls | grep airflow

# Inicializar la base de datos de Airflow (SOLO UNA VEZ):
# Escalar airflow_init a 1 para que corra db migrate + create admin user
docker service scale airflow_airflow_init=1

# Ver los logs del init:
docker service logs airflow_airflow_init -f
# Esperar a ver: "DB migrations done" y "Admin user admin created"

# Escalar de vuelta a 0 (es un job de init, no un servicio permanente):
docker service scale airflow_airflow_init=0

# Verificar UI:
curl -sk https://airflow.sexydad/health | python3 -m json.tool
# Esperado: {"metadatabase": {"status": "healthy"}, "scheduler": {"status": "healthy"}}

# Verificar Flower:
curl -sk https://airflow-flower.sexydad | grep -o "Flower" | head -1
```

---

## Paso 9 — Actualizar Jupyter

```bash
# Forzar update de Jupyter para recargar entrypoint.sh y secrets nuevos:
docker service update --force jupyter_jupyter_ogiovanni
docker service update --force jupyter_jupyter_odavid

# Esperar que los servicios se reinicien:
watch docker service ls | grep jupyter
```

---

## Paso 10 — Verificación final

### Verificar todos los servicios

```bash
docker service ls
# Todos deben tener REPLICAS = X/X (ej: 1/1)
```

### Test de integración Jupyter → MinIO (desde notebook)

```python
import boto3

s3 = boto3.client(
    's3',
    endpoint_url='http://minio:9000',
    # AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY ya están en el environment
)
buckets = s3.list_buckets()['Buckets']
print([b['Name'] for b in buckets])
# Esperado: ['airflow-logs', 'lab-artifacts', 'lab-datasets', 'lab-notebooks', 'spark-warehouse']
```

### Test de integración Jupyter → Spark (desde notebook)

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .master("spark://spark_master:7077") \
    .appName("test") \
    .getOrCreate()

spark.range(100).count()  # Debe retornar 100
```

### Test de integración Spark → MinIO (desde notebook)

```python
df = spark.read.parquet("s3a://lab-datasets/")
# Si hay datos en el bucket, debe leerlos. Si está vacío, no hay error tampoco.
```

---

## Paso 11 — /etc/hosts en clientes LAN

Agregar en `/etc/hosts` de cada máquina cliente (Windows/Mac/Linux):

```
192.168.80.100  minio.sexydad
192.168.80.100  minio-api.sexydad
192.168.80.100  spark-master.sexydad
192.168.80.100  spark-worker.sexydad
192.168.80.100  spark-history.sexydad
192.168.80.100  airflow.sexydad
192.168.80.100  airflow-flower.sexydad
```

---

## Paso 12 (Fase 6 — post-estabilización) — Habilitar Remote Logging en Airflow

Una vez que Airflow esté estable:

1. Crear conexión `minio_s3` en Airflow UI:
   - **Admin → Connections → +**
   - Conn Id: `minio_s3`
   - Conn Type: `Amazon S3`
   - Extra: `{"endpoint_url": "http://minio:9000"}`
   - Las credenciales se toman de `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` en el env del worker.

2. Actualizar el stack:
   ```yaml
   AIRFLOW__LOGGING__REMOTE_LOGGING: "true"
   ```

3. Aplicar:
   ```bash
   docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow
   ```

---

## Troubleshooting común

### MinIO no arranca
```bash
docker service logs minio_minio --tail 50
# Chequear: permisos en /srv/datalake/minio, secrets disponibles
```

### Spark Worker no se registra en el Master
```bash
docker service logs spark_spark_worker --tail 50
# Chequear: resolución DNS de "spark_master" en red internal
# Verificar: docker network inspect internal | grep spark
```

### Airflow Worker no aparece en Flower
```bash
docker service logs airflow_airflow_worker --tail 50
# Chequear: Redis corriendo, red internal, URL del broker
docker service logs airflow_redis --tail 20
```

### Init de Airflow falla en DB migrate
```bash
docker service logs airflow_airflow_init --tail 100
# Chequear: pg_airflow_pass correcto, DB "airflow" existe en Postgres
# Verificar desde master2:
docker exec -it $(docker ps -q -f name=postgres_postgres) \
  psql -U postgres -c "\l" | grep airflow
```

### Jupyter no puede conectar a MinIO (boto3)
```bash
# Verificar que las vars de entorno están exportadas:
docker exec -it $(docker ps -q -f name=jupyter_jupyter_ogiovanni) \
  env | grep AWS
# Esperado: AWS_ACCESS_KEY_ID=minioadmin, AWS_SECRET_ACCESS_KEY=..., AWS_ENDPOINT_URL=http://minio:9000
```

---

## Estado esperado al finalizar

```
$ docker service ls

ID       NAME                        MODE   REPLICAS  IMAGE
...      traefik_traefik             global    1/1     traefik:v3.x
...      portainer_portainer          replicated 1/1  portainer/portainer-ce:2.39.1
...      portainer_portainer-agent   global    2/2     portainer/agent:2.39.1
...      postgres_postgres           replicated 1/1   postgres:16
...      n8n_n8n                     replicated 1/1   n8nio/n8n:latest
...      jupyter_jupyter_ogiovanni   replicated 1/1   jupyter/datascience-notebook:python-3.11
...      jupyter_jupyter_odavid      replicated 1/1   jupyter/datascience-notebook:python-3.11
...      ollama_ollama               replicated 1/1   ollama/ollama:0.6.1
...      opensearch_opensearch       replicated 1/1   opensearchproject/opensearch:2.19.4
...      opensearch_dashboards       replicated 1/1   opensearchproject/opensearch-dashboards:2.19.4
...      minio_minio                 replicated 1/1   minio/minio:RELEASE.2024-11-07T00-52-20Z
...      spark_spark_master          replicated 1/1   bitnami/spark:3.5.3
...      spark_spark_worker          replicated 1/1   bitnami/spark:3.5.3
...      spark_spark_history         replicated 1/1   bitnami/spark:3.5.3
...      airflow_redis               replicated 1/1   redis:7.2-alpine
...      airflow_airflow_webserver   replicated 1/1   apache/airflow:2.9.3
...      airflow_airflow_scheduler   replicated 1/1   apache/airflow:2.9.3
...      airflow_airflow_worker      replicated 1/1   apache/airflow:2.9.3
...      airflow_airflow_flower      replicated 1/1   apache/airflow:2.9.3
...      airflow_airflow_init        replicated 0/0   apache/airflow:2.9.3  ← 0 replicas (correcto)
```

**Total: 20 servicios activos** (21 definidos, 1 inactivo por diseño: airflow_init)
