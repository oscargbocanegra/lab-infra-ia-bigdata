# Fluent Bit — Centralized Log Collection

> Stack: `stacks/monitoring/00-fluent-bit/stack.yml`
> Phase: 6.1 — Observability (Logs)

---

## What this does

Deploys **Fluent Bit** in **global mode** (1 instance per Swarm node) to collect all Docker container logs from `master1` and `master2` and ship them to the existing **OpenSearch** instance for centralized log management via **OpenSearch Dashboards**.

```
master1 containers ──┐
                     ├── Fluent Bit (global) ──► OpenSearch ──► Dashboards
master2 containers ──┘
```

---

## Index Strategy

| Index name | Pattern | Created by |
|------------|---------|------------|
| `docker-logs-2026.04.02` | `docker-logs-*` | Fluent Bit (daily rollover) |
| `docker-logs-2026.04.03` | `docker-logs-*` | Fluent Bit (auto next day) |

- **One index per day** — makes deletion surgical and clean
- **Auto-delete after 7 days** via OpenSearch ISM policy
- **No manual cleanup needed** — the policy runs nightly

---

## Deploy Instructions

### Step 1 — Configure OpenSearch (run once)

```bash
# From master1, with OpenSearch running
bash scripts/observability/setup-opensearch-logs.sh
```

This creates:
- ISM policy `docker-logs-retention-7d` → deletes indices older than 7 days
- Index template `docker-logs-template` → correct field mappings

### Step 2 — Create state directory on BOTH nodes

```bash
# master1 (Swarm manager)
mkdir -p /srv/fastdata/fluent-bit

# master2 (compute node) — run via SSH
ssh <user>@<master2-ip> "mkdir -p /srv/fastdata/fluent-bit"
```

### Step 3 — Deploy

```bash
docker stack deploy -c stacks/monitoring/00-fluent-bit/stack.yml fluent-bit
```

### Step 4 — Verify

```bash
# Check both replicas are running (one per node)
docker service ls | grep fluent

# Wait ~30s then check indices are being created
curl http://localhost:9200/_cat/indices/docker-logs-* | sort

# Check Fluent Bit health endpoint (from master1)
docker service ps fluent-bit_fluent-bit --no-trunc
```

---

## Dashboards Setup (one-time)

1. Go to OpenSearch Dashboards (via your internal domain)
2. **Management** → **Index Patterns** → **Create index pattern**
3. Index pattern: `docker-logs-*`
4. Time field: `@timestamp`
5. Create pattern

**Useful Discover filters:**
- Filter by node: `node: node1` or `node: node2`
- Filter by stack: `com.docker.stack.namespace: jupyter`
- Filter by stream: `stream: stderr` (errors only)
- Search: `log: ERROR` or `log: exception`

---

## Retention Policy

| Setting | Value |
|---------|-------|
| Index rollover | Daily (`docker-logs-YYYY.MM.DD`) |
| Retention | 7 days |
| Mechanism | OpenSearch ISM policy (server-side cron) |
| Action | Hard delete of the entire daily index |

To change retention (e.g. to 14 days), update the ISM policy:
```bash
curl -X PUT http://localhost:9200/_plugins/_ism/policies/docker-logs-retention-7d \
  -H 'Content-Type: application/json' \
  -d '{ ... "min_index_age": "14d" ... }'
```

> Run from master1 (Swarm manager node), where OpenSearch is reachable on port 9200.

---

## Resource Impact

| Component | CPU | RAM | Node |
|-----------|-----|-----|------|
| Fluent Bit (master1) | 0.05 reserved / 0.25 max | 32MB reserved / 128MB max | master1 |
| Fluent Bit (master2) | 0.05 reserved / 0.25 max | 32MB reserved / 128MB max | master2 |
| OpenSearch extra load | ~0.1 avg write | ~200MB heap | master1 |

Fluent Bit is extremely lightweight — **~5MB RAM** typical usage.

---

## Troubleshooting

```bash
# View Fluent Bit logs (replace task ID)
docker service logs fluent-bit_fluent-bit --tail 50 --follow

# Check if indices exist
curl http://localhost:9200/_cat/indices/docker-logs-* -v

# Manually verify ISM policy is applied
curl http://localhost:9200/_plugins/_ism/explain/docker-logs-$(date +%Y.%m.%d)

# Force ISM policy check (don't wait for cron)
curl -X POST http://localhost:9200/_plugins/_ism/add/docker-logs-* \
  -H 'Content-Type: application/json' \
  -d '{"policy_id": "docker-logs-retention-7d"}'
```
