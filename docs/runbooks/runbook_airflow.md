# Runbook: Apache Airflow 2.9 — Orquestación de pipelines

> Stack: `airflow` | Executor: CeleryExecutor | Última revisión: 2026-03-30

---

## Descripción

Apache Airflow orquesta los pipelines de datos del lab: ingesta, procesamiento Spark, entrenamiento de modelos y publicación de resultados. Usa CeleryExecutor con Redis como broker para distribuir tareas entre nodos.

```
Componente          Nodo      Rol
─────────────────── ──────── ────────────────────────────────────
airflow_webserver   master1   UI + API REST
airflow_scheduler   master1   Planifica y dispara DAGs
airflow_worker      master2   Ejecuta tareas (acceso GPU/datalake)
airflow_flower      master1   Monitor de Celery workers
redis               master1   Message broker (Celery queue)
PostgreSQL          master2   Metadata de DAGs y ejecuciones
```

---

## Secrets requeridos (crear antes de deploy)

```bash
# En master1 (Swarm manager):

# Password del usuario 'airflow' en Postgres
openssl rand -base64 20 | docker secret create pg_airflow_pass -

# Fernet key para cifrar conexiones y variables sensibles en Airflow
# DEBE ser una clave Fernet válida (base64url de 32 bytes)
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" \
  | docker secret create airflow_fernet_key -

# Secret key del webserver Flask
openssl rand -base64 30 | docker secret create airflow_webserver_secret -

# MinIO (si no los creaste ya)
# echo "minioadmin" | docker secret create minio_access_key -
# openssl rand -base64 24 | docker secret create minio_secret_key -
```

---

## Preparación de directorios

```bash
# En master1:
sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins,redis}
sudo chown -R 50000:0 /srv/fastdata/airflow   # UID 50000 = usuario airflow

# En master2 (para el worker — mismos paths):
ssh master2 "sudo mkdir -p /srv/fastdata/airflow/{dags,logs,plugins}"
ssh master2 "sudo chown -R 50000:0 /srv/fastdata/airflow"
```

> **Nota sobre sincronización de DAGs**: Los DAGs se montan desde `/srv/fastdata/airflow/dags` en ambos nodos. Para mantener consistencia, desarrollá los DAGs en master1 y sincronizá a master2 con rsync o git pull. Un DAG de Airflow que clone el repo es una solución elegante para labs.

---

## Deploy (orden obligatorio)

```bash
# 1. Postgres debe estar corriendo con la DB airflow ya creada
#    (el init script 02-init-airflow.sh se ejecuta automáticamente
#     al crear el volumen por primera vez)

# 2. MinIO debe estar corriendo (para logs remotos)

# 3. Desplegar stack base
docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow

# 4. Esperar a que Redis y los servicios suban (~30 seg)
docker stack ps airflow

# 5. Inicializar la base de datos (SOLO LA PRIMERA VEZ)
docker service scale airflow_airflow_init=1
# Esperar que complete (ver logs)
docker service logs airflow_airflow_init -f
# Volver a 0 replicas tras completar
docker service scale airflow_airflow_init=0

# 6. Verificar todos los servicios
docker stack ps airflow --no-trunc
```

---

## Primer login

```
URL:      https://airflow.sexydad
Usuario:  admin
Password: contenido de airflow_webserver_secret
```

> Cambiá el password del admin desde la UI inmediatamente: Admin → Security → Users.

---

## Agregar la conexión MinIO en Airflow

Desde la UI: Admin → Connections → Add connection

```
Conn Id:    minio_s3
Conn Type:  Amazon S3
Extra:      {
              "endpoint_url": "http://minio:9000",
              "aws_access_key_id": "TU_ACCESS_KEY",
              "aws_secret_access_key": "TU_SECRET_KEY"
            }
```

O via CLI:

```bash
docker exec -it $(docker ps -q -f name=airflow_airflow_webserver) \
  airflow connections add minio_s3 \
    --conn-type s3 \
    --conn-extra '{"endpoint_url":"http://minio:9000","aws_access_key_id":"TU_KEY","aws_secret_access_key":"TU_SECRET"}'
```

---

## Agregar la conexión Spark

```
Conn Id:    spark_default
Conn Type:  Spark
Host:       spark://spark_master
Port:       7077
```

---

## Tu primer DAG de ejemplo

Crear el archivo `/srv/fastdata/airflow/dags/lab_pipeline_ejemplo.py`:

```python
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator

default_args = {
    "owner": "lab",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="lab_pipeline_ejemplo",
    default_args=default_args,
    description="Pipeline de ejemplo: ingesta → proceso → almacenamiento",
    schedule_interval="0 6 * * *",   # diario a las 6am Bogotá
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["lab", "ejemplo"],
) as dag:

    t1 = BashOperator(
        task_id="verificar_datos",
        bash_command="ls /data/datasets/ && echo 'Datos disponibles'",
    )

    def procesar_datos():
        import pandas as pd
        print("Procesando datos con pandas...")
        # Tu lógica aquí

    t2 = PythonOperator(
        task_id="procesar_datos",
        python_callable=procesar_datos,
    )

    t3 = BashOperator(
        task_id="notificar_completado",
        bash_command="echo 'Pipeline completado: $(date)'",
    )

    t1 >> t2 >> t3
```

---

## DAG con SparkSubmitOperator

```python
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator

spark_job = SparkSubmitOperator(
    task_id="spark_procesamiento",
    application="/opt/airflow/plugins/jobs/mi_job.py",
    conn_id="spark_default",
    executor_memory="4g",
    executor_cores=4,
    conf={
        "spark.hadoop.fs.s3a.endpoint": "http://minio:9000",
        "spark.hadoop.fs.s3a.path.style.access": "true",
    },
    dag=dag,
)
```

---

## Monitoreo

```bash
# Estado de todos los componentes
docker stack ps airflow

# Ver workers activos en Flower
# https://airflow-flower.sexydad

# Logs del scheduler (ver qué DAGs planificó)
docker service logs airflow_airflow_scheduler -f --tail 50

# Logs del worker (ver ejecución de tareas)
docker service logs airflow_airflow_worker -f --tail 50

# Verificar que Celery está funcionando
docker exec -it $(docker ps -q -f name=airflow_airflow_worker) \
  celery --app airflow.providers.celery.executors.celery_executor.app inspect active
```

---

## Diagnóstico de problemas comunes

### Worker no aparece en Flower

```bash
# Verificar conectividad con Redis
docker exec -it $(docker ps -q -f name=airflow_airflow_worker) \
  python3 -c "import redis; r=redis.Redis('redis'); print(r.ping())"
```

### Scheduler no dispara DAGs

```bash
# Verificar estado del scheduler
docker service logs airflow_airflow_scheduler 2>&1 | grep -i error

# Reiniciar scheduler
docker service update --force airflow_airflow_scheduler
```

### Error de Fernet key

```bash
# La Fernet key debe ser la misma en webserver, scheduler y worker
# Si la cambiás, tenés que redeploy de los 3 componentes
docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow
```

---

## Redeploy

```bash
# Redeploy completo (rolling update automático)
docker stack deploy -c stacks/automation/03-airflow/stack.yml airflow
```

---

## Estructura de archivos

```
/srv/fastdata/airflow/
├── dags/          → DAGs Python (sincronizar a master1 y master2)
├── logs/          → Logs locales (backup en MinIO s3://airflow-logs/)
├── plugins/       → Plugins y operadores custom
│   └── jobs/      → Scripts Spark a submitear
└── redis/         → Persistencia Redis (queue state)
```
