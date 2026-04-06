#!/usr/bin/env bash
# pg-create-admin-roles.sh — Create personal PostgreSQL superuser roles
# Run from: master1 via docker exec on the postgres container (master2)
# Usage: bash scripts/hardening/pg-create-admin-roles.sh
set -euo pipefail

POSTGRES_CONTAINER="core_postgres_1"  # adjust if container name differs
POSTGRES_HOST="192.168.80.200"

echo "=== Creating PostgreSQL admin roles for ogiovanni and odavid ==="

# Check container is running on master2
ssh ogiovanni@"${POSTGRES_HOST}" "docker ps --filter name=postgres --format '{{.Names}}'"

ssh ogiovanni@"${POSTGRES_HOST}" "docker exec -i \$(docker ps --filter name=postgres -q) psql -U postgres << 'SQL'
-- Create personal superuser roles
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ogiovanni') THEN
    CREATE ROLE ogiovanni WITH LOGIN PASSWORD 'jupyter2024' SUPERUSER CREATEDB CREATEROLE;
    RAISE NOTICE 'Created role: ogiovanni';
  ELSE
    RAISE NOTICE 'Role ogiovanni already exists';
  END IF;

  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'odavid') THEN
    CREATE ROLE odavid WITH LOGIN PASSWORD 'jupyter2024' SUPERUSER CREATEDB CREATEROLE;
    RAISE NOTICE 'Created role: odavid';
  ELSE
    RAISE NOTICE 'Role odavid already exists';
  END IF;
END
\$\$;

-- Verify
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolcanlogin
FROM pg_roles
WHERE rolname IN ('ogiovanni', 'odavid', 'postgres')
ORDER BY rolname;
SQL"

echo "=== PostgreSQL roles created ==="
