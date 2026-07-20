# OpenSearch — Search, Analytics & ML Platform

## Overview

OpenSearch is an open-source, Apache 2.0-licensed search and analytics engine (Elasticsearch fork) used in this lab for **log analytics, full-text search, agent trace storage, and machine learning inference** via the ML Commons plugin.

| Component | Version | Placement |
|---|---|---|
| OpenSearch Engine | `2.19.4` | master2 (NVMe, compute tier) |
| OpenSearch Dashboards | `2.19.4` | master1 (control tier) |
| ML Commons plugin | `2.19.4.0` | bundled, enabled |

**API endpoint:** `https://opensearch.sexydad`  
**Dashboard UI:** `https://dashboards.sexydad`  
**Security model:** BasicAuth via Traefik + LAN whitelist. Security plugin disabled for lab simplicity.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Lab Cluster                          │
│                                                         │
│  master1                       master2                  │
│  ┌─────────────────────┐       ┌───────────────────┐    │
│  │ OpenSearch Dashboards│       │  OpenSearch Node  │    │
│  │   :5601 (internal)  │──────▶│  :9200 (internal) │    │
│  │   Traefik ingress   │       │  NVMe storage     │    │
│  │   ML Dashboard UI   │       │  ML Commons       │    │
│  └─────────────────────┘       │  k-NN + Neural    │    │
│                                │  Search plugins   │    │
│                                └───────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

**Data volumes (master2):**
- `/srv/fastdata/opensearch` — indices, cluster state, ML model cache (NVMe)

---

## ML Commons

OpenSearch 2.19.4 ships with `opensearch-ml 2.19.4.0` bundled. This lab has ML Commons fully enabled for local model inference and semantic search workflows.

### Enabled capabilities

| Capability | Status |
|---|---|
| Register models from OpenSearch Model Hub | ✅ |
| Register models from URL | ✅ |
| Register models from local file | ✅ |
| Deploy models on data nodes (no dedicated ml node) | ✅ |
| Text embedding inference | ✅ |
| k-NN / Neural Search integration | ✅ |
| ML Dashboard in OpenSearch Dashboards | ✅ |

### Active persistent cluster settings

```json
{
  "plugins.ml_commons.only_run_on_ml_node": false,
  "plugins.ml_commons.allow_registering_model_via_url": true,
  "plugins.ml_commons.allow_registering_model_via_local_file": true,
  "plugins.ml_commons.native_memory_threshold": 99,
  "plugins.ml_commons.jvm_heap_memory_threshold": 95
}
```

### Quickstart — register and deploy a text embedding model

```bash
# 1. Register from OpenSearch Model Hub (all-MiniLM-L6-v2, ~23 MB)
curl -sk -X POST "http://opensearch:9200/_plugins/_ml/models/_register" \
  --json '{
    "name": "huggingface/sentence-transformers/all-MiniLM-L6-v2",
    "version": "1.0.1",
    "model_format": "TORCH_SCRIPT"
  }'
# → returns { "task_id": "<id>" }

# 2. Poll task until COMPLETED
curl -sk "http://opensearch:9200/_plugins/_ml/tasks/<task_id>"
# → returns { "model_id": "<model_id>", "state": "COMPLETED" }

# 3. Deploy the model
curl -sk -X POST "http://opensearch:9200/_plugins/_ml/models/<model_id>/_deploy" --json '{}'
# → returns { "task_id": "<deploy_task_id>" }

# 4. Verify deployed
curl -sk "http://opensearch:9200/_plugins/_ml/stats"
# → "ml_deployed_model_count": 1
```

### Run inference (text embedding)

```bash
curl -sk -X POST "http://opensearch:9200/_plugins/_ml/models/<model_id>/_predict" \
  --json '{
    "parameters": {
      "texts": ["Lab Infra AI & Big Data Platform"]
    }
  }'
```

### ML Dashboard

Access via `https://dashboards.sexydad` → **Machine Learning** section in the left navigation:
- **Deployed Models** — manage deployed models and their status
- **Model Groups** — organize models by use case
- **Connectors** — integrate external model providers (optional)

---

## Prerequisites

- Networks: `internal` and `public` (external Swarm networks)
- Directory: `/srv/fastdata/opensearch` on master2 (UID 1000)
- Secrets: `opensearch_basicauth`, `dashboards_basicauth`
- System: `vm.max_map_count=262144` on master2

---

## Deployment

### First-time setup

```bash
# 1. Prepare data directory on master2
ssh <admin>@<master2-ip> "sudo mkdir -p /srv/fastdata/opensearch && sudo chown -R 1000:1000 /srv/fastdata/opensearch"

# 2. Set vm.max_map_count (required by OpenSearch)
ssh <admin>@<master2-ip> "sudo sysctl -w vm.max_map_count=262144 && echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf"

# 3. Deploy stack
docker stack deploy -c stacks/data/11-opensearch/stack.yml opensearch

# 4. Verify
docker service ls | grep opensearch
```

### Post-deploy: apply ML Commons cluster settings

After a fresh cluster deploy, apply the persistent ML settings (already set in production, required on fresh clusters):

```bash
curl -sk -X PUT "http://opensearch:9200/_cluster/settings" \
  --json '{
    "persistent": {
      "plugins.ml_commons.only_run_on_ml_node": false,
      "plugins.ml_commons.allow_registering_model_via_url": true,
      "plugins.ml_commons.allow_registering_model_via_local_file": true,
      "plugins.ml_commons.native_memory_threshold": 99,
      "plugins.ml_commons.jvm_heap_memory_threshold": 95
    }
  }'
```

> **Note:** These settings are stored in cluster state (persistent across restarts). The `stack.yml` also includes them as env vars for reproducibility on fresh deployments.

---

## Resource Allocation

| Service | CPU Reserved | CPU Limit | Memory Reserved | Memory Limit | JVM Heap |
|---|---|---|---|---|---|
| opensearch | 1.0 | 3.0 | 3 GB | 6 GB | 2 GB |
| dashboards | 0.5 | 2.0 | 1 GB | 3 GB | — |

The 2 GB JVM heap provides sufficient headroom for ML model loading alongside normal indexing workloads.

---

## Indices in production

| Index pattern | Purpose | Retention |
|---|---|---|
| `docker-logs-YYYY.MM.DD` | Container logs via Fluent Bit | 7 days (ISM) |
| `agent-traces-*` | LangGraph agent execution traces | — |
| `ragas-results-*` | RAGAS evaluation metrics | — |
| `model-benchmarks-*` | LLM benchmark leaderboard | — |

---

## API Reference

### Cluster health
```bash
curl -sk http://opensearch:9200/_cluster/health | jq .
```

### ML Commons stats
```bash
curl -sk http://opensearch:9200/_plugins/_ml/stats | jq .
```

### List deployed models
```bash
curl -sk http://opensearch:9200/_plugins/_ml/models/_search --json '{"query":{"term":{"model_state":"DEPLOYED"}}}'
```

### Common operations
```bash
# Create index
curl -sk -X PUT "http://opensearch:9200/my-index"

# Index document
curl -sk -X POST "http://opensearch:9200/my-index/_doc" \
  --json '{"title":"test","timestamp":"2026-07-20T00:00:00Z"}'

# Search
curl -sk -X POST "http://opensearch:9200/my-index/_search" \
  --json '{"query":{"match_all":{}}}'

# List indices
curl -sk "http://opensearch:9200/_cat/indices?v"
```

---

## Python SDK

```python
from opensearchpy import OpenSearch

# Internal network (from Jupyter, Airflow, n8n)
client = OpenSearch(
    hosts=[{"host": "opensearch", "port": 9200}],
    use_ssl=False
)

# Verify cluster
print(client.cluster.health())

# ML inference (requires deployed model)
model_id = "<deployed_model_id>"
response = client.transport.perform_request(
    "POST",
    f"/_plugins/_ml/models/{model_id}/_predict",
    body={"parameters": {"texts": ["example query"]}}
)
print(response)
```

---

## Troubleshooting

### ML Circuit Breaker opens on model deploy

If deploy fails with `Memory Circuit Breaker is open`:

```bash
# Check JVM heap usage
curl -sk "http://opensearch:9200/_nodes/stats/jvm" | jq '.nodes[].jvm.mem.heap_used_percent'

# If consistently >90%, increase JVM heap in stack.yml:
# OPENSEARCH_JAVA_OPTS=-Xms2g -Xmx2g  (current setting)

# Adjust threshold (persistent)
curl -sk -X PUT "http://opensearch:9200/_cluster/settings" \
  --json '{"persistent":{"plugins.ml_commons.jvm_heap_memory_threshold":95}}'
```

### Service not starting

```bash
# Verify vm.max_map_count on master2
ssh master2 "sysctl vm.max_map_count"   # must be 262144

# Check data directory permissions
ssh master2 "ls -la /srv/fastdata/opensearch"  # owner: 1000:1000

# View service logs
docker service logs opensearch_opensearch --tail 50
```

### Dashboards not connecting to OpenSearch

```bash
docker service logs opensearch_dashboards --tail 30
# Ensure OPENSEARCH_HOSTS points to internal hostname (not localhost)
```

---

## Rollback

```bash
# Redeploy previous stack definition from git history
git log --oneline stacks/data/11-opensearch/stack.yml
git show <sha>:stacks/data/11-opensearch/stack.yml | docker stack deploy -c - opensearch
```

---

## Security notes

- Security plugin is **disabled** (`DISABLE_SECURITY_PLUGIN=true`) for lab simplicity.
- All external access goes through Traefik with BasicAuth + LAN whitelist.
- Internal services communicate without authentication over the `internal` overlay network.
- For production: enable the security plugin, configure TLS between nodes, and use role-based access control.
