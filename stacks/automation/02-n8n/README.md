# n8n — Workflow Automation

## Overview

n8n is a self-hosted workflow automation platform. It handles event-driven pipelines, webhook integrations, scheduled jobs, and connects services across the cluster.

| Property | Value |
|----------|-------|
| Image | `n8nio/n8n:2.4.7` |
| Node | master2 (`tier=compute`, `hostname=master2`) |
| URL | https://n8n.sexydad |
| Auth | n8n native user management (no BasicAuth middleware) |

## Database

n8n uses **PostgreSQL** as its metadata store (workflows, credentials, execution history).

| Parameter | Value |
|-----------|-------|
| Host | `postgres_postgres` (Swarm overlay DNS) |
| Port | `5432` |
| Database | `n8n` |
| User | `n8n` |
| Password | via secret `pg_n8n_pass` |

> The `n8n` database and role are created automatically by `stacks/core/02-postgres/initdb/01-init-n8n.sh` on first Postgres start.

## Secrets Required

| Secret | Purpose |
|--------|---------|
| `pg_n8n_pass` | PostgreSQL password for `n8n` user |
| `n8n_encryption_key` | Key for encrypting stored credentials |
| `n8n_user_mgmt_jwt_secret` | JWT secret for user management |

## Persistence

| Path (host — master2) | Container | Purpose |
|-----------------------|-----------|---------|
| `/srv/fastdata/n8n` | `/home/node/.n8n` | Local files, SQLite fallback, static assets |

> Primary state is in PostgreSQL. The bind mount is a safety net for local n8n files.

```bash
# Run on master2 before first deploy
mkdir -p /srv/fastdata/n8n
chown 1000:1000 /srv/fastdata/n8n
```

## Networks

| Network | Purpose |
|---------|---------|
| `internal` | n8n ↔ postgres, n8n ↔ other services |
| `public` | Traefik routing |

## Deploy

```bash
# Pre-requisite: postgres stack must be running
docker stack deploy -c stacks/automation/02-n8n/stack.yml n8n
```

## Useful Integrations

- **Airflow**: trigger DAGs via Airflow REST API
- **MinIO**: file event triggers via MinIO webhook notifications
- **OpenSearch**: index events via OpenSearch HTTP node
- **Postgres**: direct query node for reporting pipelines

## Logs → OpenSearch

Logs are collected automatically by Fluent Bit via the default `json-file` driver.
Index: `docker-logs-YYYY.MM.DD` | Field: `container_name = n8n_n8n`
