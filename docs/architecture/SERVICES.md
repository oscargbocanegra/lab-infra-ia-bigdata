# Inventario de servicios vigente

> Derivado de los `stack.yml`; revisado 2026-08-21.

| Stack | Servicios | Placement / entrada |
|---|---:|---|
| traefik | 1 | master1 / `traefik.sexydad` |
| portainer | 2 | master1 + agent global / `portainer.sexydad` |
| postgres | 1 | master2 / `:5432` LAN |
| n8n | 1 | master2 / `n8n.sexydad` |
| jupyterhub | 1 + usuarios dinámicos | Hub master1, usuarios master2 / `jupyterhub.sexydad` |
| ollama | 1 | master2 + GPU / `ollama.sexydad`, `:11434` LAN |
| qdrant, rag-api, open-webui, agent | 4 | master1 / `qdrant`, `rag-api`, `chat`, `agent`.sexydad |
| airflow | 6 (init a 0) | control + worker master2 / `airflow`, `airflow-flower`.sexydad |
| opensearch | 2 | OpenSearch master2, Dashboards master1 |
| minio | 1 | master2 / `minio`, `minio-api`.sexydad |
| openmetadata | 3 | master1 / `openmetadata.sexydad` |
| spark | 3 | master1 + worker master2 / `spark-*.sexydad` |
| fluent-bit | 1 global | ambos nodos |
| prometheus | 5 | ambos nodos; UI master1 / `prometheus.sexydad` |
| grafana | 1 | master1 / `grafana.sexydad` |
| nvidia-exporter | 1 | master2 |

Total: **34 definiciones**; `airflow_init` no es un proceso permanente.

## Contratos

- JupyterHub crea `jupyterhub-user-*` mediante SwarmSpawner. No desplegar `jupyter_jupyter_*` legacy.
- RAG API integra Ollama, Qdrant, PostgreSQL/pgvector y MinIO.
- Airflow usa CeleryExecutor, Redis en master1 y un worker en master2.
- Fluent Bit se ejecuta globalmente y envía logs de Docker y reportes de salud a OpenSearch.
- Para versiones y digests, el valor de cada stack prevalece sobre cualquier tabla histórica.
