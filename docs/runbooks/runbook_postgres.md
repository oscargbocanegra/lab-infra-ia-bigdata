# Runbook: Postgres (Core DB)

## Reference Data
- **Stack**: `postgres` (service `postgres_postgres`)
- **Node**: `master2` (tier=compute, storage=primary)
- **Port**: 5432 (Host Mode: exposed ONLY on LAN)
- **Persistence**: `/srv/fastdata/postgres` with strict permissions (UID 999)
- **Main databases**: `n8n`, `postgres`, `airflow`

---

## 1. Daily Operations (Healthcheck)
**Goal:** Verify that the database accepts connections.

### 1.1 Verify service in Swarm
Run on **master1**:
```bash
# Quick view (replicas)
docker service ls | egrep 'postgres_postgres|n8n_n8n|traefik_traefik|portainer_'

# Tasks with useful format (detailed state)
docker service ps postgres_postgres --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'
```

### 1.2 Access Check (via internal network)
Spin up an ephemeral container to test a real connection (avoids needing psql on the host):
```bash
docker run --rm --network internal postgres:16 psql -h postgres -U postgres -c "SELECT 1;"
```
_Expected result:_ `1`.

### 1.3 Access Check (via LAN host port)
From **master1** (or another LAN machine), pointing to **master2**:
```bash
nc -zv master2 5432
```

---

## 2. Quick Diagnostics (Incident)
**Symptom:** "n8n can't connect" / "Connection refused".

### 2.1 Engine logs
```bash
docker service logs --tail 100 postgres_postgres
```
- Look for: "FATAL: password authentication failed" (bad password).
- Look for: "PANIC" or filesystem failures.

### 2.2 Verify Persistence
If the service restarts constantly, verify the mount on **master2**:
1. SSH to master2.
2. Check folder permissions:
   ```bash
   ls -ld /srv/fastdata/postgres
   ```
   _Expected:_ `drwx------ ... 999:999` (or root but accessible by 999).
3. Check disk space:
   ```bash
   df -h /srv/fastdata
   ```

---

## 3. Recovery
### Case: Reset superuser password
If you lost the `postgres` password:
1. Generate a new secret:
   ```bash
   printf "new_pass" | docker secret create pg_super_pass_v2 -
   ```
2. Update the stack (`core/02-postgres/stack.yml`) to use `pg_super_pass_v2` and update `POSTGRES_PASSWORD_FILE`.
3. Redeploy:
   ```bash
   docker stack deploy -c stacks/core/02-postgres/stack.yml postgres
   ```
   *Note: This may require restarting the container so it picks up the new file.*

### Case: "Database is locked" / Dead connections
If there are locks or too many connections:
1. Enter the container (via SSH to master2):
   ```bash
   CID=$(docker ps -qf name=postgres_postgres)
   docker exec -it $CID psql -U postgres
   ```
2. Kill blocking queries:
   ```sql
   SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle';
   ```

---

## 4. Appendix: Backup Management

### Manual backup (pg_dumpall)
Run from **master2** (where the container runs):
```bash
CID=$(docker ps -qf name=postgres_postgres)
# Compressed dump
docker exec $CID pg_dumpall -U postgres -c | gzip > /srv/datalake/backups/postgres_full_$(date +%F).sql.gz
```

### Restore (pg_restore)
```bash
# Decompress and pipe to psql
zcat backup.sql.gz | docker exec -i $CID psql -U postgres
```
