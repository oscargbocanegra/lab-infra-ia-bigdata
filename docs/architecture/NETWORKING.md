# Redes, dominios y flujo de tráfico

> Revisado 2026-08-22.

## Topología

```text
LAN (sin exposición pública)
  -> master1:80/443 -> Traefik -> redes overlay
  -> master2:5432 (PostgreSQL) y :11434 (Ollama), solo clientes LAN autorizados
```

## Redes Swarm

| Red | Tipo | Uso |
|---|---|---|
| `public` | overlay externa, attachable | Traefik y servicios con router |
| `internal` | overlay externa, attachable | tráfico privado backend |
| `jupyterhub-user` | overlay externa | Hub y sesiones single-user |
| `ingress` | overlay nativa | routing mesh de Swarm |

Crear las redes externas antes de desplegar y no sustituirlas por nombres de proyecto.

## Dominios publicados

Todos resuelven al IP de `master1` mediante DNS local o `/etc/hosts`:

```text
traefik, portainer, jupyterhub, qdrant, rag-api, chat, agent, n8n, ollama,
opensearch, dashboards, minio, minio-api, openmetadata, spark-master,
spark-worker, spark-history, airflow, airflow-flower, prometheus y grafana
```

La convención de nombres es `aifabric.<servicio>`. Traefik termina TLS, aplica `lan-whitelist` y, cuando corresponde, BasicAuth.

## Puertos

| Puerto | Nodo | Servicio | Exposición |
|---:|---|---|---|
| 80/443 | master1 | Traefik | LAN, `mode: host` |
| 5432 | master2 | PostgreSQL | LAN directa controlada |
| 11434 | master2 | Ollama | LAN directa controlada |
| 9000/9001 | interno | MinIO API/console | overlay/Traefik |
| 9200/5601 | interno | OpenSearch/Dashboards | overlay/Traefik |
| 7077/8080/8081/18080 | interno | Spark master/worker/history | overlay/Traefik |

No se publican puertos de backend adicionales salvo los declarados explícitamente en los stacks.
