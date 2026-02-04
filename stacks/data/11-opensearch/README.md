# OpenSearch + Dashboards - Search and Analytics Engine

## Overview

OpenSearch is an open-source search and analytics engine (Elasticsearch fork) for log analytics, full-text search, and data visualization. Includes **OpenSearch Dashboards** (web UI similar to Kibana) for visualization and management.

**Hardware:** HDD fastdata on master1 (control plane)  
**API Endpoint:** `https://opensearch.sexydad`  
**UI Endpoint:** `https://dashboards.sexydad` ⭐ **Interfaz Gráfica**  
**Security:** BasicAuth + LAN Whitelist (Security plugin disabled for lab simplicity)

> **⚠️ Importante:** Para acceder desde tu máquina local:
> 
> 1. **Agregar en tu archivo hosts:**
>    ```
>    192.168.80.100 opensearch.sexydad dashboards.sexydad
>    ```
> 
> 2. **Desactivar verificación SSL** (certificado autofirmado):
>    - **Postman:** Settings → General → SSL certificate verification (OFF)
>    - **cURL:** Usar flag `-k`
>    - **Browser:** Aceptar certificado autofirmado al acceder a `https://dashboards.sexydad`

## Prerequisites

- ✅ Networks: `internal` and `public`
- ✅ Directory: `/srv/fastdata/opensearch` on **master1** (control plane)
- ✅ Secrets: `opensearch_basicauth` and `dashboards_basicauth` created
- ✅ Traefik middlewares: `opensearch-auth@docker` and `dashboards-auth@docker`
- ✅ System config: `vm.max_map_count=262144` on master1

## Deployment

### 1. Prepare data directory

```bash
# En master1 (control plane)
ssh master1
sudo mkdir -p /srv/fastdata/opensearch
sudo chown -R 1000:1000 /srv/fastdata/opensearch
sudo chmod 755 /srv/fastdata/opensearch
```

> **Nota:** OpenSearch corre como UID 1000, por eso el chown específico.

### 2. Configure system settings (one-time on master1)

```bash
ssh master1
# Increase virtual memory (required by OpenSearch)
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### 3. Create BasicAuth secrets

```bash
# Reutilizar las mismas credenciales de Jupyter
docker secret create opensearch_basicauth secrets/jupyter_basicauth
docker secret create dashboards_basicauth secrets/jupyter_basicauth
```

### 4. Add Traefik middlewares

Agregar labels en [stacks/core/00-traefik/stack.yml](../../core/00-traefik/stack.yml):

```yaml
# OpenSearch API
- traefik.http.middlewares.opensearch-auth.basicauth.usersfile=/run/secrets/opensearch_basicauth

# OpenSearch Dashboards UI
- traefik.http.middlewares.dashboards-auth.basicauth.usersfile=/run/secrets/dashboards_basicauth
```

Luego redesplegar Traefik:

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

## 🌐 OpenSearch Dashboards Web UI

**URL:** `https://dashboards.sexydad`

### Features

- 📊 **Discover:** Explora y busca tus datos en tiempo real
- 📈 **Visualize:** Crea gráficos, tablas, mapas y visualizaciones
- 📱 **Dashboards:** Combina múltiples visualizaciones en dashboards interactivos
- 🔍 **Dev Tools:** Consola para ejecutar queries directamente
- ⚙️ **Management:** Administra índices, index patterns y configuraciones

### First Access

1. Abre tu navegador en `https://dashboards.sexydad`
2. Acepta el certificado autofirmado (aviso de seguridad)
3. Ingresa credenciales BasicAuth:
   - **Username:** `ogiovanni` o `odavid`
   - **Password:** Mismo que Jupyter
4. En el primer acceso, verás la pantalla de bienvenida de OpenSearch Dashboards

### Quick Start Guide

1. **Create Index Pattern:**
   - Ve a Management → Stack Management → Index Patterns
   - Crea un index pattern para tus datos (ej: `logs-*`)

2. **Explore Data:**
   - Ve a Discover
   - Selecciona tu index pattern
   - Filtra, busca y explora tus documentos

3. **Create Visualizations:**
   - Ve a Visualize
   - Crea gráficos de líneas, barras, pie charts, etc.

4. **Build Dashboards:**
   - Ve a Dashboards
   - Combina tus visualizaciones en dashboards interactivos

---

## 🔐 Authentication

Todas las peticiones requieren **BasicAuth**:

- **Username:** `ogiovanni` o `odavid`
- **Password:** Mismo que Jupyter

---

## 📚 API Reference

Base URL: `https://opensearch.sexydad`

### 1. Cluster Health

```bash
curl -k -u ogiovanni:password https://opensearch.sexydad/_cluster/health
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
curl -k -u ogiovanni:password -X PUT https://opensearch.sexydad/my-index \
  -H "Content-Type: application/json"
```

### 3. Index Document

```bash
curl -k -u ogiovanni:password -X POST https://opensearch.sexydad/my-index/_doc \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Document",
    "content": "This is a test",
    "timestamp": "2026-02-04T00:00:00Z"
  }'
```

### 4. Search Documents

```bash
curl -k -u ogiovanni:password -X GET https://opensearch.sexydad/my-index/_search \
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
curl -k -u ogiovanni:password https://opensearch.sexydad/_cat/indices?v
```

### 6. Delete Index

```bash
curl -k -u ogiovanni:password -X DELETE https://opensearch.sexydad/my-index
```

---

## 🐍 Usage from Python

### Basic Connection

```python
from opensearchpy import OpenSearch
import urllib3

# Disable SSL warnings (self-signed cert)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

client = OpenSearch(
    hosts=[{'host': 'opensearch.sexydad', 'port': 443}],
    http_auth=('ogiovanni', 'your-password'),
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

## 🧪 Postman Configuration

### Setup
1. Create new request
2. Set Auth Type: **Basic Auth**
   - Username: `ogiovanni`
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

## 🔧 Configuration

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

## 🔗 Integration Examples

### With Python (pandas)

```python
import pandas as pd
from opensearchpy import OpenSearch

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

## 📊 Monitoring

### Check cluster status
```bash
curl -k -u ogiovanni:password https://opensearch.sexydad/_cluster/health?pretty
```

### View node stats
```bash
curl -k -u ogiovanni:password https://opensearch.sexydad/_nodes/stats?pretty
```

### Check indices
```bash
curl -k -u ogiovanni:password https://opensearch.sexydad/_cat/indices?v
```

---

## 🔧 Troubleshooting

### Dashboards not loading

```bash
# Check Dashboards service
docker service ps opensearch_dashboards --no-trunc
docker service logs opensearch_dashboards -f

# Common issue: Waiting for OpenSearch
# Solution: Ensure OpenSearch is running first
docker service ps opensearch_opensearch
curl -k -u ogiovanni:password https://opensearch.sexydad/_cluster/health
```

### Service not starting

```bash
# Check logs
docker service logs opensearch_opensearch -f

# Common issues:
# 1. vm.max_map_count too low
ssh master1 "sysctl vm.max_map_count"

# 2. Permissions on data directory
ssh master1 "ls -la /srv/fastdata/opensearch"

# 3. Memory issues
docker service ps opensearch_opensearch --no-trunc
```

### Memory errors

Si ves errores de memoria, ajusta JVM heap en stack.yml:
```yaml
- "OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g"  # Reducir a 1GB
```

### Reset data

```bash
ssh master1
sudo rm -rf /srv/fastdata/opensearch/*
docker service update --force opensearch_opensearch
```

---

## 📝 Notes

- **Single-node:** Configurado como nodo único (discovery.type=single-node)
- **Security Plugin:** Deshabilitado para simplificar lab interno
- **Dashboards:** Incluye interfaz gráfica completa (similar a Kibana)
- **Deployment:** Corriendo en master1 (control plane) por disponibilidad de recursos
- **HDD Storage:** Suficiente para ambiente de lab/aprendizaje
- **Production:** Para producción, habilitar security plugin, configurar cluster multi-nodo y usar NVMe
- **Backups:** Considerar snapshots regulares si datos son críticos
