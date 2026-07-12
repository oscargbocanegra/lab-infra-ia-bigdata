# Runbook: OpenSearch + Dashboards

## Reference Data

| Parameter | Value |
|---|---|
| Stack | `opensearch` |
| Services | `opensearch_opensearch`, `opensearch_dashboards` |
| OpenSearch node | `master2` (`tier=compute`, `storage=primary`) |
| Dashboards node | `master1` (`tier=control`) |
| Version | `2.19.4` |
| Persistence | `/srv/fastdata/opensearch` on master2 NVMe |
| API URL | `https://opensearch.sexydad` |
| UI URL | `https://dashboards.sexydad` |
| Internal URL | `http://opensearch:9200` |

## 1. Daily verification

### Node: master1

```bash
docker service ls | grep opensearch

docker service ps opensearch_opensearch --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'

docker service ps opensearch_dashboards --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'

curl -sk -u '<user>:<password>' \
  https://opensearch.sexydad/_cluster/health?pretty
```

Expected:

```text
opensearch_opensearch  1/1 on master2
opensearch_dashboards  1/1 on master1
status                 green
unassigned_shards      0
```

### Node: master2

```bash
OS_CONTAINER="$(docker ps -q --filter name=opensearch_opensearch | head -1)"
test -n "${OS_CONTAINER}"

docker exec "${OS_CONTAINER}" \
  curl -s http://127.0.0.1:9200/_cluster/health?pretty

docker exec "${OS_CONTAINER}" \
  curl -s http://127.0.0.1:9200/_cat/indices?v
```

## 2. Diagnostics

### Node: master1

```bash
docker service logs opensearch_opensearch --tail 100
docker service logs opensearch_dashboards --tail 100
```

### Node: master2

```bash
sysctl vm.max_map_count
findmnt /srv/fastdata
df -h /srv/fastdata
sudo ls -ld /srv/fastdata/opensearch
```

Required value:

```text
vm.max_map_count = 262144
```

Do not change ownership, permissions, placement or data contents before
capturing a report and defining rollback.

## 3. Redeploy

### Node: master1

```bash
cd ~/lab-infra-ia-bigdata
docker stack config -c stacks/data/11-opensearch/stack.yml >/dev/null
docker stack deploy -c stacks/data/11-opensearch/stack.yml opensearch
```

Then repeat the daily verification.

## 4. Backup and restore

OpenSearch data is stateful. Before migration, reset, ownership changes or
restore, identify:

- source path and node;
- backup or snapshot;
- available capacity;
- UID/GID and permissions;
- restore procedure;
- rollback criteria.

The active path is:

```text
master2:/srv/fastdata/opensearch
```

Never copy the live data directory as the primary backup mechanism while
OpenSearch is writing. Prefer a tested OpenSearch snapshot repository.

Resetting or deleting data requires the literal authorization:

```text
CONFIRMO BORRADO
```

## 5. Architecture

- ADR-013 supersedes ADR-006.
- OpenSearch remains single-node.
- Indices use zero replicas.
- Docker log retention uses OpenSearch ISM.
- Security controls remain governed by ADR-004.
