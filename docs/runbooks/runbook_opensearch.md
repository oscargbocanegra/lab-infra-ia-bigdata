# Runbook de Operación: OpenSearch + Dashboards

## Datos de referencia

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `opensearch` |
| **Servicios** | `opensearch_opensearch` + `opensearch_dashboards` |
| **Nodo** | master1 (`tier=control`) |
| **Versión** | 2.19.4 |
| **Persistencia** | `/srv/fastdata/opensearch` (HDD master1) |
| **URL API** | `https://opensearch.sexydad` (BasicAuth) |
| **URL UI** | `https://dashboards.sexydad` (BasicAuth) |
| **URL interna** | `http://opensearch:9200` (sin auth, overlay internal) |

---

## 1. Operación diaria (Healthcheck)

### 1.1 Verificar servicios Swarm

```bash
# En master1
docker service ls | grep opensearch

# Estado detallado
docker service ps opensearch_opensearch --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'

docker service ps opensearch_dashboards --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'
```

### 1.2 Verificar cluster health

```bash
# Health via Traefik (externo, con auth)
curl -sk -u admin:PASSWORD https://opensearch.sexydad/_cluster/health | python3 -m json.tool

# Health interno (desde master1, sin auth)
curl -s http://localhost:9200/_cluster/health
# Esperado: "status":"green"
```

### 1.3 Ver índices activos

```bash
curl -s http://localhost:9200/_cat/indices?v
```

---

## 2. Diagnóstico rápido (Incidente)

### Síntoma: Servicio no arranca / se reinicia

```bash
# Ver logs del motor
docker service logs opensearch_opensearch --tail 50

# Errores comunes:
# "max virtual memory areas vm.max_map_count [65530] is too low"
# Fix: sudo sysctl -w vm.max_map_count=262144
#      echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# "BootstrapCheckException... heap size"
# Fix: verificar que OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g esté configurado
```

### Síntoma: Dashboards muestra "OpenSearch is not available"

```bash
# 1. Verificar que opensearch (engine) está corriendo
docker service ps opensearch_opensearch

# 2. Verificar que dashboards puede llegar al engine
docker exec -it $(docker ps -q -f name=opensearch_dashboards) \
  curl -s http://opensearch:9200/_cluster/health
```

### Síntoma: Permiso denegado en bind mount

```bash
# El container corre como UID 1000
# Fix en master1:
sudo chown -R 1000:1000 /srv/fastdata/opensearch
sudo chmod 750 /srv/fastdata/opensearch
docker service update --force opensearch_opensearch
```

---

## 3. Operaciones comunes

### Crear un índice

```bash
curl -X PUT http://localhost:9200/mi-indice \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    }
  }'
```

### Indexar un documento

```bash
curl -X POST http://localhost:9200/mi-indice/_doc \
  -H 'Content-Type: application/json' \
  -d '{"campo": "valor", "timestamp": "2026-03-30T00:00:00Z"}'
```

### Buscar

```bash
curl -X GET http://localhost:9200/mi-indice/_search \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match_all": {}}}'
```

### Desde Python (Jupyter)

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

# Indexar
client.index(index="test", body={"mensaje": "hola"})

# Buscar
result = client.search(index="test", body={"query": {"match_all": {}}})
```

---

## 4. Backup / Restore

```bash
# Snapshot a directorio local (requiere configurar snapshot repository)
# Ver: https://opensearch.org/docs/latest/tuning-your-cluster/availability-and-recovery/snapshots/

# Backup simple: rsync del directorio de datos
sudo rsync -av --progress /srv/fastdata/opensearch/ \
  /srv/datalake/backups/opensearch-$(date +%Y%m%d)/
```

---

## 5. Redespliegue

```bash
# En master1, desde el repositorio:
docker stack deploy -c stacks/data/11-opensearch/stack.yml opensearch

# Verificar:
docker service ls | grep opensearch
curl -s http://localhost:9200/_cluster/health
```
