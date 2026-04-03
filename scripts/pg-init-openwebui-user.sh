#!/bin/sh
set -e

PGPASSWORD=$(cat /run/secrets/pg_super_pass)
OWU_PASS=$(cat /run/secrets/pg_openwebui_pass)
export PGPASSWORD

echo "=== Creating openwebui role ==="
psql -h 192.168.80.200 -U postgres -c \
  "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'openwebui') THEN CREATE ROLE openwebui LOGIN PASSWORD '${OWU_PASS}'; END IF; END \$\$"

echo "=== Granting privileges on openwebui DB ==="
psql -h 192.168.80.200 -U postgres -c \
  "GRANT ALL PRIVILEGES ON DATABASE openwebui TO openwebui"
psql -h 192.168.80.200 -U postgres -c \
  "ALTER DATABASE openwebui OWNER TO openwebui"

echo "=== Grant schema privileges ==="
psql -h 192.168.80.200 -U postgres -d openwebui -c \
  "GRANT ALL ON SCHEMA public TO openwebui"
psql -h 192.168.80.200 -U postgres -d openwebui -c \
  "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO openwebui"
psql -h 192.168.80.200 -U postgres -d openwebui -c \
  "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO openwebui"

echo "=== ALL DONE ==="
psql -h 192.168.80.200 -U postgres -c "\du openwebui"
