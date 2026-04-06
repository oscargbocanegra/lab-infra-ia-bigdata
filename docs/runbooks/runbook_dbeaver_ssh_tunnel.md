# Runbook: DBeaver — PostgreSQL via SSH Tunnel

> **Target audience:** `ogiovanni`, `odavid`  
> **Last updated:** 2026-04-05

Connect to PostgreSQL running on **master2** (192.168.80.200:5432) from any LAN machine using DBeaver, via an SSH tunnel through **master1** (192.168.80.100).

---

## Architecture

```
Your machine (DBeaver)
       │
       │  SSH :22
       ▼
   master1  (192.168.80.100)    ← SSH jump host (public-facing)
       │
       │  TCP tunnel → :5432
       ▼
   master2  (192.168.80.200)    ← PostgreSQL runs here
```

PostgreSQL port 5432 is **not exposed to the LAN** — it only accepts connections from master1 via UFW. The SSH tunnel forwards a local port on your machine through master1 directly to PostgreSQL on master2.

---

## Prerequisites

- **DBeaver** installed on your machine (any version)
- Your **SSH private key** for `ogiovanni` or `odavid` on master1
- Your machine is on the **192.168.80.0/24** LAN

---

## Step-by-step Setup

### 1. Open DBeaver and create a new connection

`Database` menu → `New Database Connection` → select **PostgreSQL** → click **Next**

---

### 2. Fill in the Main tab

| Field | Value |
|-------|-------|
| Host | `192.168.80.200` |
| Port | `5432` |
| Database | `postgres` |
| Authentication | Database Native |
| Username | `ogiovanni` or `odavid` |
| Password | `jupyter2024` |

> **Do not click Finish yet** — you need to configure the SSH tunnel first.

---

### 3. Configure the SSH Tunnel tab

Click the **SSH** tab (or **SSH Tunnel** depending on DBeaver version).

Enable SSH tunnel:

| Field | Value |
|-------|-------|
| ☑ Use SSH Tunnel | **checked** |
| Host/IP | `192.168.80.100` |
| Port | `22` |
| User Name | `ogiovanni` or `odavid` |
| Authentication Method | **Public Key** |
| Private Key | path to your `id_ed25519` private key file |

> **Important:** Leave the **Password** field empty when using public key auth.

Click **Test tunnel configuration** — you should see `Connected`.

---

### 4. Test the full connection

Go back to the **Main** tab and click **Test Connection**.

Expected result: `Connected` banner with PostgreSQL version info.

---

### 5. Click Finish

The connection appears in the left panel. Expand it to browse databases, schemas, and tables.

---

## Troubleshooting

### `Connection refused` on SSH test

- Verify your SSH private key path is correct
- Your public key must be in `~/.ssh/authorized_keys` on master1 for your user
- Test manually from a terminal: `ssh ogiovanni@192.168.80.100`

### `Connection refused` on DB test (tunnel OK)

- Verify UFW on master2 allows 5432 from master1 (already configured in Phase 7)
- Verify PostgreSQL is running: `ssh ogiovanni@192.168.80.100 'ssh ogiovanni@192.168.80.200 sudo -n docker ps | grep postgres'`

### `FATAL: password authentication failed`

- Use password `jupyter2024` for both `ogiovanni` and `odavid`
- Verify the role exists: connect as `postgres` superuser and run `\du`

### `Host key verification failed`

- On first connection DBeaver may prompt to accept master1's host key — click **Yes / Trust**

---

## Useful queries once connected

```sql
-- List all databases
SELECT datname FROM pg_database WHERE datistemplate = false;

-- List all roles
\du

-- Check active connections
SELECT pid, usename, application_name, state
FROM pg_stat_activity
WHERE state = 'active';

-- Check PostgreSQL version
SELECT version();
```

---

## Available databases

| Database | Owner | Description |
|----------|-------|-------------|
| `postgres` | postgres | Default admin DB |
| `airflow` | airflow | Airflow metadata |
| `n8n` | n8n | n8n workflow data |
| `openwebui` | openwebui | Open WebUI users + chat history |

---

## Personal roles (Phase 7)

Both `ogiovanni` and `odavid` have been provisioned as **SUPERUSER** with full access:

```sql
-- Created via scripts/hardening/pg-admin-roles.sql
CREATE ROLE ogiovanni WITH LOGIN SUPERUSER CREATEDB CREATEROLE PASSWORD 'jupyter2024';
CREATE ROLE odavid    WITH LOGIN SUPERUSER CREATEDB CREATEROLE PASSWORD 'jupyter2024';
```

> These roles can connect to any database, create new databases, and manage other roles.
