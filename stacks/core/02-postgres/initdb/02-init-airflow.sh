#!/bin/sh
# ============================================================
# 02-init-airflow.sh — Crear usuario y DB para Apache Airflow
# Ejecutado por postgres en el primer arranque (volumen vacío)
# ============================================================
set -eu

AIRFLOW_PASS="$(cat /run/secrets/pg_airflow_pass)"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'airflow') THEN
    CREATE ROLE airflow LOGIN PASSWORD '${AIRFLOW_PASS}';
  END IF;
END
\$\$;

DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'airflow') THEN
    CREATE DATABASE airflow OWNER airflow
      ENCODING 'UTF8'
      LC_COLLATE 'en_US.UTF-8'
      LC_CTYPE   'en_US.UTF-8'
      TEMPLATE template0;
  END IF;
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE airflow TO airflow;
EOSQL

echo "[init] Base de datos 'airflow' y rol 'airflow' creados correctamente."
