# Nodos del clúster

> Revisado 2026-08-21. Los constraints de los stacks son la autoridad final.

## master1

| Atributo | Valor |
|---|---|
| Hostname | `master1` |
| Rol Swarm | manager / leader |
| Labels | `tier=control`, `node_role=manager`, `storage=backup`, `net=lan` |
| Función | gateway, control, UIs y servicios ligeros |
| Persistencia | `/srv/fastdata` para control, Prometheus/Grafana y Hub |

Servicios fijados al control: Traefik, Portainer, JupyterHub, Qdrant, RAG API, Agent, Open WebUI, Redis/Airflow control, Spark master/history, OpenMetadata, Dashboards, Prometheus y Grafana.

## master2

| Atributo | Valor |
|---|---|
| Hostname | `master2` |
| Rol Swarm | worker / ready |
| Labels | `tier=compute`, `node_role=worker`, `storage=primary`, `gpu=nvidia`, `net=lan` |
| Función | cómputo, datos, GPU y servicios stateful |
| Persistencia rápida | `/srv/fastdata` (PostgreSQL, OpenSearch, n8n, Airflow, Spark temporal, usuarios Hub) |
| Persistencia masiva | `/srv/datalake` (MinIO, modelos Ollama y datasets) |

Servicios fijados al compute: PostgreSQL, n8n, Ollama, MinIO, OpenSearch, Spark worker, Airflow worker y las sesiones `jupyterhub-user-*`.

## GPU

`master2` expone el recurso genérico `nvidia.com/gpu=1`, usa el runtime NVIDIA y la etiqueta `gpu=nvidia`. Ollama y el exporter NVIDIA requieren ese placement; JupyterHub puede consumir la GPU según la sesión.

## Comprobación

```bash
docker node ls
docker node inspect master1
docker node inspect master2
```

No se deben mover servicios stateful entre nodos sin actualizar el stack, las rutas y el runbook de rollback.
