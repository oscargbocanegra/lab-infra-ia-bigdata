# Runbook: OpenSearch + Dashboards

## Reference Data

| Parameter | Value |
|-----------|-------|
| **Stack** | `opensearch` |
| **Services** | `opensearch_opensearch` + `opensearch_dashboards` |
| **Node** | master1 (`tier=control`) |
| **Version** | 2.19.4 |
| **Persistence** | `/srv/fastdata/opensearch` (master1) |
| **API URL** | `https://opensearch.sexydad` (BasicAuth) |
| **UI URL** | `https://dashboards.sexydad` (BasicAuth) |
| **Internal URL** | `http://opensearch:9200` (no auth, overlay internal) |

---

## 1. Daily Operations (Healthcheck)

### 1.1 Verify Swarm services

```bash
# On master1
docker service ls | grep opensearch

# Detailed state
docker service ps opensearch_opensearch --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'

docker service ps opensearch_dashboards --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'
```

### 1.2 Verify cluster health

```bash
# Health via Traefik (external, with auth)
curl -sk -u admin:PASSWORD https://opensearch.sexydad/_cluster/health | python3 -m json.tool

# Internal health (from master1, no auth)
curl -s http://localhost:9200/_cluster/health
# Expected: "status":"green"
```

### 1.3 View active indices

```bash
curl -s http://localhost:9200/_cat/indices?v
```

---

## 2. Quick Diagnostics (Incident)

### Symptom: Service won't start / keeps restarting

```bash
# View engine logs
docker service logs opensearch_opensearch --tail 50

# Common errors:
# "max virtual memory areas vm.max_map_count [65530] is too low"
# Fix: sudo sysctl -w vm.max_map_count=262144
#      echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# "BootstrapCheckException... heap size"
# Fix: verify that OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g is configured
```

### Symptom: Dashboards shows "OpenSearch is not available"

```bash
# 1. Verify the opensearch engine is running
docker service ps opensearch_opensearch

# 2. Verify dashboards can reach the engine
docker exec -it $(docker ps -q -f name=opensearch_dashboards) \
  curl -s http://opensearch:9200/_cluster/health
```

### Symptom: Permission denied on bind mount

```bash
# The container runs as UID 1000
# Fix on master1:
sudo chown -R 1000:1000 /srv/fastdata/opensearch
sudo chmod 750 /srv/fastdata/opensearch
docker service update --force opensearch_opensearch
```

---

## 3. Common Operations

### Create an index

```bash
curl -X PUT http://localhost:9200/my-index \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    }
  }'
```

### Index a document

```bash
curl -X POST http://localhost:9200/my-index/_doc \
  -H 'Content-Type: application/json' \
  -d '{"field": "value", "timestamp": "2026-03-30T00:00:00Z"}'
```

### Search

```bash
curl -X GET http://localhost:9200/my-index/_search \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match_all": {}}}'
```

### From Python (Jupyter)

```python
from opensearchpy import OpenSearch

client = OpenSearch(
    hosts=[{"host": "opensearch", "port": 9200}],
    use_ssl=False,
    verify_certs=False,
    http_auth=None
)

# Health
print(client.cluster.health())

# Index
client.index(index="test", body={"message": "hello"})

# Search
result = client.search(index="test", body={"query": {"match_all": {}}})
```

---

## 4. Backup / Restore

```bash
# Snapshot to a local directory (requires configuring a snapshot repository)
# See: https://opensearch.org/docs/latest/tuning-your-cluster/availability-and-recovery/snapshots/

# Simple backup: rsync the data directory
sudo rsync -av --progress /srv/fastdata/opensearch/ \
  /srv/datalake/backups/opensearch-$(date +%Y%m%d)/
```

---

## 5. Redeploy

```bash
# On master1, from the repository:
docker stack deploy -c stacks/data/11-opensearch/stack.yml opensearch

# Verify:
docker service ls | grep opensearch
curl -s http://localhost:9200/_cluster/health
```
