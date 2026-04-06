# Runbook: n8n (Automation)

## Reference Data
- **Stack**: `automation` (service `n8n_n8n`)
- **URL**: `https://n8n.sexydad`
- **Execution node**: `master2` (tier=compute)
- **Persistence**: `/srv/fastdata/n8n` (on master2) → `/home/node/.n8n`
- **Dependency**: Postgres (`postgres_postgres` on the internal network)

---

## 1. Daily Operations (Healthcheck)
**Goal:** "Is n8n alive?" in under 5 minutes.

### 1.1 Verify Swarm task
Run on **master1** (manager):
```bash
# Quick view (replicas)
docker service ls | egrep 'postgres_postgres|n8n_n8n|traefik_traefik|portainer_'

# Tasks with useful format (detailed state)
docker service ps n8n_n8n --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'
```

### 1.2 Verify endpoint (from LAN)
```bash
# Should respond with 200/401 (if auth required) or redirect
curl -I https://n8n.sexydad
```

### 1.3 Check recent logs (Signs of life)
```bash
# Last 50 lines to see recent activity
docker service logs --tail 50 n8n_n8n
```
_Expected result:_ "n8n ready on 0.0.0.0, port 5678" / "Editor is now accessible".

---

## 2. Quick Diagnostics (Incident)
**Symptom:** UI won't load / service is restarting.

### 2.1 Detect restart loops
```bash
# View task history
docker service ps n8n_n8n
```
If you see many recent `Shutdown` or `Failed` entries, the container is crashing at startup.

### 2.2 Analyze error logs
```bash
# Logs from the last 10 minutes
docker service logs --since 10m n8n_n8n
```
Look for critical errors such as:
- "Connection refused" (can't reach Postgres).
- "Permission denied" (FS or DB issues).
- "Clean exit code: 0" (OOM killed, insufficient memory).

---

## 3. Recovery (Common Fixes)
**Goal:** Return to a healthy state when error X appears.

### Case A: Error "Permission denied for schema public" (Postgres)
**Symptom:** Logs show a DB error when trying to create tables/migrations.
**Cause:** The `n8n` user exists in Postgres but does not own the public schema.
**Fix:**
1. Connect to Postgres (from the manager):
   ```bash
   # Get the Postgres container ID
   PG_TASK=$(docker ps --filter name=postgres_postgres -q | head -n1)
   
   # Run the permissions fix
   docker exec -it $PG_TASK psql -U postgres -d n8n -c "GRANT ALL ON SCHEMA public TO n8n;"
   ```
2. Restart n8n to retry migrations:
   ```bash
   docker service update --force n8n_n8n
   ```

### Case B: Filesystem permission error (`EACCES`)
**Symptom:** Logs say `EACCES: permission denied, mkdir '/home/node/.n8n/...'`
**Cause:** The `/srv/fastdata/n8n` folder on master2 is owned by `root`, but the container runs as user `node` (1000).
**Fix:**
1. SSH to master2.
2. Adjust permissions:
   ```bash
   chown -R 1000:1000 /srv/fastdata/n8n
   ```
3. Restart the service.

---

## 4. Deployment Verification
**Goal:** Confirm that code/infra are in sync.

### 4.1 Validate clean repo
```bash
# On master1 (inside ~/lab-infra-ia-bigdata)
git status -sb
```
_Expected result:_ `## main...` (clean or with intentional changes).

### 4.2 Validate latest commit applied
```bash
git log -1 --oneline
```
_Example:_ `fa52b61 docs(runbook): add minimal n8n runbook`

---

## Appendix: Useful Commands

**Enter the container (debug shell):**
```bash
# Find which node it's running on
NODE=$(docker service ps n8n_n8n --filter "desired-state=running" --format "{{.Node}}")

# Find the container ID on that node (SSH required if it's master2)
ssh $NODE "docker ps --filter name=n8n_n8n -q"
# docker exec -it <ID> /bin/sh
```
