-- pg-admin-roles.sql — Create personal PostgreSQL superuser roles for ogiovanni and odavid
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ogiovanni') THEN
    CREATE ROLE ogiovanni WITH LOGIN PASSWORD 'jupyter2024' SUPERUSER CREATEDB CREATEROLE;
    RAISE NOTICE 'Created role: ogiovanni';
  ELSE
    RAISE NOTICE 'Role ogiovanni already exists — skipping';
  END IF;

  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'odavid') THEN
    CREATE ROLE odavid WITH LOGIN PASSWORD 'jupyter2024' SUPERUSER CREATEDB CREATEROLE;
    RAISE NOTICE 'Created role: odavid';
  ELSE
    RAISE NOTICE 'Role odavid already exists — skipping';
  END IF;
END
$$;

SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolcanlogin
FROM pg_roles
WHERE rolname IN ('ogiovanni', 'odavid')
ORDER BY rolname;
