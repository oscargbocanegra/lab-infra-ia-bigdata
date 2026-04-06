# OpenSearch + Dashboards — Search and Analytics Engine

## Overview

OpenSearch is an open-source search and analytics engine (Elasticsearch fork) for log analytics, full-text search, and data visualization. Includes **OpenSearch Dashboards** (web UI similar to Kibana) for visualization and management.

**Hardware:** HDD fastdata on master1 (control plane)  
**API Endpoint:** `https://opensearch.sexydad`  
**UI Endpoint:** `https://dashboards.sexydad`  
**Security:** BasicAuth + LAN Whitelist (Security plugin disabled for lab simplicity)

> **Note:** To access from your local machine:
>
> 1. **Add to your hosts file:**
>    ```
>    <master1-ip>  opensearch.sexydad dashboards.sexydad
>    ```
>
> 2. **Disable SSL verification** (self-signed certificate):
>    - **Postman:** Settings → General → SSL certificate verification (OFF)
>    - **cURL:** Use flag `-k`
>    - **Browser:** Accept the self-signed certificate warning on first visit to `https://dashboards.sexydad`

## Prerequisites

- ✅ Networks: `internal` and `public`
- ✅ Directory: `/srv/fastdata/opensearch` on **master1** (control plane)
- ✅ Secrets: `opensearch_basicauth` and `dashboards_basicauth` created
- ✅ Traefik middlewares: `opensearch-auth@docker` and `dashboards-auth@docker`
- ✅ System config: `vm.max_map_count=262144` on master1

## Deployment

### 1. Prepare data directory

```bash
# On master1 (control plane)
ssh <admin-user>@<master1-ip>
sudo mkdir -p /srv/fastdata/opensearch
sudo chown -R 1000:1000 /srv/fastdata/opensearch
sudo chmod 755 /srv/fastdata/opensearch
```

> OpenSearch runs as UID 1000, hence the specific chown.

### 2. Configure system settings (one-time on master1)

```bash
# Increase virtual memory (required by OpenSearch)
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### 3. Create BasicAuth secrets

```bash
# Reuse the same credentials as Jupyter
docker secret create opensearch_basicauth secrets/jupyter_basicauth
docker secret create dashboards_basicauth secrets/jupyter_basicauth
```

### 4. Add Traefik middlewares

Add labels in [stacks/core/00-traefik/stack.yml](../../core/00-traefik/stack.yml):

```yaml
# OpenSearch API
- traefik.http.middlewares.opensearch-auth.basicauth.usersfile=/run/secrets/opensearch_basicauth

# OpenSearch Dashboards UI
- traefik.http.middlewares.dashboards-auth.basicauth.usersfile=/run/secrets/dashboards_basicauth
```

Then redeploy Traefik:

```bash
docker stack deploy -c stacks/core/00-traefik/stack.yml traefik
```

### 5. Deploy OpenSearch + Dashboards

```bash
docker stack deploy -c stacks/data/11-opensearch/stack.yml opensearch
```

### 6. Verify deployment

```bash
# Check services
docker service ls | grep opensearch

# Check OpenSearch
docker service ps opensearch_opensearch
docker service logs opensearch_opensearch -f

# Check Dashboards
docker service ps opensearch_dashboards
docker service logs opensearch_dashboards -f
```

---

## OpenSearch Dashboards Web UI

**URL:** `https://dashboards.sexydad`

### Features

- **Discover:** Explore and search your data in real time
- **Visualize:** Create charts, tables, maps and visualizations
- **Dashboards:** Combine multiple visualizations into interactive dashboards
- **Dev Tools:** Console for running queries directly
- **Management:** Manage indexes, index patterns, and configurations

### First Access

1. Open your browser at `https://dashboards.sexydad`
2. Accept the self-signed certificate warning
3. Enter BasicAuth credentials (`<admin-user>` / `<your-password>`)
4. On first access you will see the OpenSearch Dashboards welcome screen

### Quick Start Guide

1. **Create Index Pattern:**
   - Go to Management → Stack Management → Index Patterns
   - Create an index pattern for your data (e.g. `logs-*`)

2. **Explore Data:**
   - Go to Discover
   - Select your index pattern
   - Filter, search, and explore your documents

3. **Create Visualizations:**
   - Go to Visualize
   - Create line charts, bar charts, pie charts, etc.

4. **Build Dashboards:**
   - Go to Dashboards
   - Combine your visualizations into interactive dashboards

---

## Authentication

All requests require **BasicAuth** (enforced by Traefik):

- **Username:** `<admin-user>` or `<second-user>`
- **Password:** `<your-password>`

---

## API Reference

Base URL: `https://opensearch.sexydad`

### 1. Cluster Health

```bash
curl -k -u <admin-user>:<your-password> https://opensearch.sexydad/_cluster/health
```

**Response:**
```json
{
  "cluster_name": "lab-opensearch",
  "status": "green",
  "number_of_nodes": 1,
  "number_of_data_nodes": 1
}
```

### 2. Create Index

```bash
curl -k -u <admin-user>:<your-password> -X PUT https://opensearch.sexydad/my-index \
  -H "Content-Type: application/json"
```

### 3. Index Document

```bash
curl -k -u <admin-user>:<your-password> -X POST https://opensearch.sexydad/my-index/_doc \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Document",
    "content": "This is a test",
    "timestamp": "2026-02-04T00:00:00Z"
  }'
```

### 4. Search Documents

```bash
curl -k -u <admin-user>:<your-password> -X GET https://opensearch.sexydad/my-index/_search \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "match": {
        "content": "test"
      }
    }
  }'
```

### 5. List Indices

```bash
curl -k -u <admin-user>:<your-password> https://opensearch.sexydad/_cat/indices?v
```

### 6. Delete Index

```bash
curl -k -u <admin-user>:<your-password> -X DELETE https://opensearch.sexydad/my-index
```

---

## Usage from Python

### Basic Connection

```python
from opensearchpy import OpenSearch
import urllib3

# Disable SSL warnings (self-signed cert)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

client = OpenSearch(
    hosts=[{'host': 'opensearch.sexydad', 'port': 443}],
    http_auth=('<admin-user>', '<your-password>'),
    use_ssl=True,
    verify_certs=False,
    ssl_show_warn=False
)

# Test connection
print(client.info())
print(client.cluster.health())
```

### From Jupyter (Internal Network)

```python
from opensearchpy import OpenSearch

# No auth needed on internal network
client = OpenSearch(
    hosts=[{'host': 'opensearch', 'port': 9200}],
    use_ssl=False
)

# Create index
client.indices.create(index='logs', ignore=400)

# Index document
doc = {
    'timestamp': '2026-02-04T10:00:00',
    'level': 'INFO',
    'message': 'Application started'
}
client.index(index='logs', body=doc)

# Search
results = client.search(
    index='logs',
    body={
        'query': {
            'match': {'level': 'INFO'}
        }
    }
)
print(results['hits']['hits'])
```

### Bulk Indexing

```python
from opensearchpy import OpenSearch, helpers

client = OpenSearch(
    hosts=[{'host': 'opensearch', 'port': 9200}],
    use_ssl=False
)

# Prepare documents
docs = [
    {
        '_index': 'logs',
        '_source': {
            'timestamp': f'2026-02-04T10:0{i}:00',
            'level': 'INFO',
            'message': f'Message {i}'
        }
    }
    for i in range(10)
]

# Bulk index
helpers.bulk(client, docs)
```

---

## Postman Configuration

### Setup
1. Create new request
2. Set Auth Type: **Basic Auth**
   - Username: `<admin-user>`
   - Password: `<your-password>`
3. Base URL: `https://opensearch.sexydad`
4. Disable SSL verification

### Example Collections

**Collection 1: Cluster Health**
```
GET https://opensearch.sexydad/_cluster/health
```

**Collection 2: Create Index**
```
PUT https://opensearch.sexydad/test-index
Content-Type: application/json
```

**Collection 3: Search**
```
POST https://opensearch.sexydad/test-index/_search
Content-Type: application/json

Body:
{
  "query": {
    "match_all": {}
  }
}
```

---

## Configuration

### OpenSearch (Engine)
- **CPUs:** 1.0 reserved, 3.0 limit
- **Memory:** 2GB reserved, 6GB limit
- **JVM Heap:** 1GB (-Xms1g -Xmx1g)

### Dashboards (UI)
- **CPUs:** 0.5 reserved, 2.0 limit
- **Memory:** 1GB reserved, 3GB limit

### Storage
- **Location:** `/srv/fastdata/opensearch` (HDD on master1)
- **Type:** Bind mount
- **Owner:** UID 1000 (opensearch user)
- **Node:** master1 (control plane)

### Security
- **Plugin:** Disabled (DISABLE_SECURITY_PLUGIN=true)
- **External Auth:** BasicAuth via Traefik
- **Network:** LAN Whitelist + BasicAuth

---

## Integration Examples

### With Python (pandas)

```python
import pandas as pd
from opensearchpy import OpenSearch, helpers

client = OpenSearch([{'host': 'opensearch', 'port': 9200}], use_ssl=False)

# Read data from OpenSearch
results = client.search(index='logs', body={'query': {'match_all': {}}}, size=1000)
df = pd.DataFrame([hit['_source'] for hit in results['hits']['hits']])
print(df.head())

# Write DataFrame to OpenSearch
data = [
    {'_index': 'metrics', '_source': row.to_dict()}
    for _, row in df.iterrows()
]
helpers.bulk(client, data)
```

### With n8n Workflows

Use HTTP Request node:
- URL: `http://opensearch:9200/my-index/_search`
- Method: POST
- Authentication: None (internal network)
- Body: JSON query

### With Airflow DAGs

```python
from opensearchpy import OpenSearch

def index_to_opensearch(**context):
    client = OpenSearch([{'host': 'opensearch', 'port': 9200}], use_ssl=False)

    doc = {
        'dag_id': context['dag'].dag_id,
        'execution_date': str(context['execution_date']),
        'status': 'success'
    }

    client.index(index='airflow-logs', body=doc)
```

---

## Monitoring

### Check cluster status
```bash
curl -k -u <admin-user>:<your-password> https://opensearch.sexydad/_cluster/health?pretty
```

### View node stats
```bash
curl -k -u <admin-user>:<your-password> https://opensearch.sexydad/_nodes/stats?pretty
```

### Check indices
```bash
curl -k -u <admin-user>:<your-password> https://opensearch.sexydad/_cat/indices?v
```

---

## Troubleshooting

### Dashboards not loading

```bash
# Check Dashboards service
docker service ps opensearch_dashboards --no-trunc
docker service logs opensearch_dashboards -f

# Common issue: Waiting for OpenSearch
# Solution: Ensure OpenSearch is running first
docker service ps opensearch_opensearch
curl -k -u <admin-user>:<your-password> https://opensearch.sexydad/_cluster/health
```

### Service not starting

```bash
# Check logs
docker service logs opensearch_opensearch -f

# Common issues:
# 1. vm.max_map_count too low
ssh <master1-ip> "sysctl vm.max_map_count"

# 2. Permissions on data directory
ssh <master1-ip> "ls -la /srv/fastdata/opensearch"

# 3. Memory issues
docker service ps opensearch_opensearch --no-trunc
```

### Memory errors

If you see memory errors, reduce JVM heap in stack.yml:
```yaml
- "OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g"  # Reduce to 1GB
```

### Reset data

```bash
sudo rm -rf /srv/fastdata/opensearch/*
docker service update --force opensearch_opensearch
```

---

## Notes

- **Single-node:** Configured as single-node (`discovery.type=single-node`)
- **Security Plugin:** Disabled to simplify the internal lab
- **Dashboards:** Includes full graphical interface (similar to Kibana)
- **Deployment:** Running on master1 (control plane) due to resource availability
- **HDD Storage:** Sufficient for lab/learning environment
- **Production:** For production, enable the security plugin, configure a multi-node cluster, and use NVMe
- **Backups:** Consider regular snapshots if data is critical
