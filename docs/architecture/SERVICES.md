# Inventario de servicios vigente

> Derivado de los `stack.yml`; revisado 2026-08-21.

| Stack | Servicios | Placement / entrada |
|---|---:|---|
| traefik | 1 | master1 / `aifabric.traefik` |
| portainer | 2 | master1 + agent global / `aifabric.portainer` |
| postgres | 1 | master2 / `:5432` LAN |
| n8n | 1 | master2 / `aifabric.n8n` |
| jupyterhub | 1 + usuarios dinámicos | Hub master1, usuarios master2 / `aifabric.jupyterhub` |
| ollama | 1 | master2 + GPU / `aifabric.ollama`, `:11434` LAN |
| llmfit + dashboards + Swagger UI | 4 | advisor master2 + docs master1 / `aifabric.llmfit`, `aifabric.llmfit-mobile`, `aifabric.llmfit-docs` |
| qdrant, rag-api, open-webui, agent | 4 | master1 / `aifabric.qdrant`, `aifabric.rag-api`, `aifabric.chat`, `aifabric.agent` |
| airflow | 6 (init a 0) | control + worker master2 / `aifabric.airflow`, `aifabric.airflow-flower` |
| opensearch | 2 | OpenSearch master2 / `aifabric.opensearch`; Dashboards master1 / `aifabric.dashboards` |
| minio | 1 | master2 / `aifabric.minio`, `aifabric.minio-api` |
| openmetadata | 3 | master1 / `aifabric.openmetadata` |
| spark | 3 | master1 + worker master2 / `aifabric.spark-master`, `aifabric.spark-worker`, `aifabric.spark-history` |
| fluent-bit | 1 global | ambos nodos |
| prometheus | 5 | ambos nodos; UI master1 / `aifabric.prometheus` |
| grafana | 1 | master1 / `aifabric.grafana` |
| nvidia-exporter | 1 | master2 |

Total: **38 definiciones**; `airflow_init` no es un proceso permanente.

## Contratos

- JupyterHub crea `jupyterhub-user-*` mediante SwarmSpawner. No desplegar `jupyter_jupyter_*` legacy.
- RAG API integra Ollama, Qdrant, PostgreSQL/pgvector y MinIO.
- Airflow usa CeleryExecutor, Redis en master1 y un worker en master2.
- Fluent Bit se ejecuta globalmente y envía logs de Docker y reportes de salud a OpenSearch.
- Para versiones y digests, el valor de cada stack prevalece sobre cualquier tabla histórica.
