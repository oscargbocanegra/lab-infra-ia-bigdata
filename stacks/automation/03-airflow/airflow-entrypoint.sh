#!/usr/bin/env bash
# ============================================================
# airflow-entrypoint.sh — Wrapper para inyectar Swarm secrets
# como variables de entorno antes de ejecutar Airflow.
#
# Docker Swarm secrets se montan en /run/secrets/<nombre>.
# Airflow no soporta _FILE suffix para SQL_ALCHEMY_CONN.
# Este script lee los secrets y los exporta antes de llamar
# al entrypoint original de la imagen apache/airflow.
#
# NOTA: tr -d '\r\n' elimina carriage returns Y newlines de los secrets
# (ocurre cuando fueron creados con echo o desde Windows).
# NOTA: urllib.parse.quote() URL-encodes el password para que
# caracteres especiales (/, =, @, +) no rompan el parsing de la URL.
# ============================================================
set -euo pipefail

# Leer secrets de Swarm y exportar como variables de entorno
PG_PASS=$(tr -d '\r\n' < /run/secrets/pg_airflow_pass)
FERNET_KEY=$(tr -d '\r\n' < /run/secrets/airflow_fernet_key)
WEBSERVER_SECRET=$(tr -d '\r\n' < /run/secrets/airflow_webserver_secret)

# URL-encode el password para que caracteres especiales (/, =, @, +) no
# rompan el parsing de la URL de conexión SQLAlchemy / Celery backend.
PG_PASS_ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${PG_PASS}")

export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:${PG_PASS_ENCODED}@postgres_postgres:5432/airflow"
export AIRFLOW__CELERY__RESULT_BACKEND="db+postgresql://airflow:${PG_PASS_ENCODED}@postgres_postgres:5432/airflow"
export AIRFLOW__CORE__FERNET_KEY="${FERNET_KEY}"
export AIRFLOW__WEBSERVER__SECRET_KEY="${WEBSERVER_SECRET}"

# Para airflow_init: usar secret dedicado para la contraseña del admin UI.
# El webserver_secret es una clave criptográfica interna de Flask, no una contraseña.
if [ -f /run/secrets/airflow_admin_password ]; then
  export _AIRFLOW_WWW_USER_PASSWORD="$(tr -d '\r\n' < /run/secrets/airflow_admin_password)"
else
  # Fallback: usar webserver_secret (solo para compatibilidad retroactiva)
  export _AIRFLOW_WWW_USER_PASSWORD="${WEBSERVER_SECRET}"
fi

# Export MinIO credentials as standard AWS env vars so governance DAGs
# can use boto3 to connect to MinIO without Airflow Connections setup.
# minio_access_key / minio_secret_key are Swarm secrets mounted in /run/secrets/.
if [ -f /run/secrets/minio_access_key ]; then
  export AWS_ACCESS_KEY_ID="$(tr -d '\r\n' < /run/secrets/minio_access_key)"
  export AWS_SECRET_ACCESS_KEY="$(tr -d '\r\n' < /run/secrets/minio_secret_key)"
fi

# Export RAG Postgres password for agent DAGs (synthetic dataset, RAGAS eval).
# Used by DAGs that query the rag schema directly via psycopg2.
if [ -f /run/secrets/pg_rag_pass ]; then
  export PG_RAG_PASS="$(tr -d '\r\n' < /run/secrets/pg_rag_pass)"
fi

# Ejecutar el comando que se pase como argumentos
exec "$@"
