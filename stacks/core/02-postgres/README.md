# PostgreSQL 16 — Central Database

## Overview

PostgreSQL is the central relational database for the cluster. Multiple services depend on it for metadata and workflow state. It runs on master2 to leverage the NVMe storage.

| Property | Value |
|----------|-------|
| Image | `postgres:16` |
| Node | master2 (`hostname=master2`) |
| Port | `5432` (host mode — LAN direct access from master2 IP) |
| Host for services | `postgres_postgres` (Swarm DNS via overlay) |

## Databases

| Database | Owner | Consumer |
|----------|-------|----------|
| `postgres` | postgres | Superuser / admin |
| `n8n` | n8n | n8n automation workflows |
| `airflow` | airflow | Airflow DAG metadata, task history |

> **Policy**: Before adding a new service, check if it can reuse Postgres. It is the preferred backend for any service that supports PostgreSQL.

## Secrets Required

| Secret | Purpose |
|--------|---------|
| `pg_super_pass` | Password for `postgres` superuser |
| `pg_n8n_pass` | Password for `n8n` user |
| `pg_airflow_pass` | Password for `airflow` user |

```bash
# Create secrets (first time only)
echo "your_super_password"  | docker secret create pg_super_pass -
echo "your_n8n_password"    | docker secret create pg_n8n_pass -
echo "your_airflow_password"| docker secret create pg_airflow_pass -
```

## Init Scripts

Executed once on first start (empty data directory):

| Config | Script | Action |
|--------|--------|--------|
| `init_n8n` | `initdb/01-init-n8n.sh` | Creates role + database `n8n` |
| `init_airflow` | `initdb/02-init-airflow.sh` | Creates role + database `airflow` |

## Persistence

| Path (host — master2) | Container | Purpose |
|-----------------------|-----------|---------|
| `/srv/fastdata/postgres` | `/var/lib/postgresql/data` | All database files |

```bash
# Run on master2 before first deploy
mkdir -p /srv/fastdata/postgres
```

## Connection Details

| Parameter | Value |
|-----------|-------|
| Host (from overlay) | `postgres_postgres` |
| Host (from LAN) | `192.168.80.200` |
| Port | `5432` |
| SSL | Not required (LAN only) |

## Deploy

```bash
docker stack deploy -c stacks/core/02-postgres/stack.yml postgres
```

## Backup

```bash
# Run from master1 — dumps all databases to /srv/fastdata/backups
docker exec $(docker ps --filter name=postgres_postgres --format "{{.ID}}") \
  pg_dumpall -U postgres > /srv/fastdata/backups/pg_dumpall_$(date +%Y%m%d).sql
```

## Logs → OpenSearch

Logs are collected automatically by Fluent Bit via the default `json-file` driver.
Index: `docker-logs-YYYY.MM.DD` | Field: `container_name = postgres_postgres`
