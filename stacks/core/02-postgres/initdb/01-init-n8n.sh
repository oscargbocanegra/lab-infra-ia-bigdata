#!/bin/sh
set -eu

N8N_PASS="$(cat /run/secrets/pg_n8n_pass)"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'n8n') THEN
    CREATE ROLE n8n LOGIN PASSWORD '${N8N_PASS}';
  END IF;
END
\$\$;

-- DB n8n ya la crea POSTGRES_DB, pero dejamos esto defensivo
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n') THEN
    CREATE DATABASE n8n OWNER n8n;
  END IF;
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;
EOSQL
