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
# tr -d '\r\n' elimina tanto carriage returns (\r) como newlines (\n) al final
# de los secrets. Ambos rompen el URL parsing de Python/Celery:
#   - \r causa "Port could not be cast to integer value as '0R'"
#   - \n al final corrompe la URL silenciosamente
# Los secrets creados con 'echo' o desde Windows siempre tienen uno u otro.
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

# Para airflow_init: pasar el password del usuario admin
export _AIRFLOW_WWW_USER_PASSWORD="${WEBSERVER_SECRET}"

# Ejecutar el comando que se pase como argumentos
exec "$@"
