# Networking, domains, and traffic flow

> Reviewed 2026-08-22.

## Topology

```text
LAN (no public exposure)
  -> master1:80/443 -> Traefik -> overlay networks
  -> master2:5432 (PostgreSQL) and :11434 (Ollama), authorized LAN clients only
```

## Swarm networks

| Network | Type | Purpose |
|---|---|---|
| `public` | external, attachable overlay | Traefik and routed services |
| `internal` | external, attachable overlay | private backend traffic |
| `jupyterhub-user` | external overlay | Hub and single-user sessions |
| `ingress` | native overlay | Swarm routing mesh |

Create external networks before deployment; do not replace them with project-scoped names.

## Published domains

All names resolve to the `master1` IP through local DNS or `/etc/hosts`:

```text
traefik, portainer, jupyterhub, qdrant, rag-api, chat, agent, n8n, ollama,
opensearch, dashboards, minio, minio-api, llmfit, llmfit-docs, openmetadata, spark-master,
spark-worker, spark-history, airflow, airflow-flower, prometheus and grafana
```

Names follow the `aifabric.<service>`. Traefik terminates TLS, applies `lan-whitelist`, and uses BasicAuth where required.

## Ports

| Port | Node | Service | Exposure |
|---:|---|---|---|
| 80/443 | master1 | Traefik | LAN, `mode: host` |
| 5432 | master2 | PostgreSQL | controlled direct LAN access |
| 11434 | master2 | Ollama | controlled direct LAN access |
| 9000/9001 | internal | MinIO API/console | overlay/Traefik |
| 9200/5601 | internal | OpenSearch/Dashboards | overlay/Traefik |
| 7077/8080/8081/18080 | internal | Spark master/worker/history | overlay/Traefik |

No additional backend ports are published unless explicitly declared in the stacks.
