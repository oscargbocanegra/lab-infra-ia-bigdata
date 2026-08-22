# Arquitectura vigente

> Fuente de verdad: `stacks/**/stack.yml`. Revisada el 2026-08-21.

## Topología

El laboratorio es un Docker Swarm privado de dos nodos. `master1` es manager/leader y `master2` es worker con `tier=compute`, `storage=primary` y `gpu=nvidia`.

```text
master1 (control)
  Traefik, Portainer, JupyterHub, Qdrant, RAG API, Agent, Open WebUI,
  Airflow (Redis/web/scheduler/flower), Spark master/history, OpenMetadata,
  OpenSearch Dashboards, Prometheus, Grafana y Fluent Bit.

master2 (compute/data/GPU)
  PostgreSQL/pgvector, n8n, Ollama, MinIO, OpenSearch, Spark worker,
  Airflow worker, sesiones single-user dinámicas de JupyterHub y Fluent Bit.
```

Las restricciones exactas están en `deploy.placement.constraints` de cada stack.

## Flujo de datos

```text
LAN --HTTPS--> Traefik
RAG API / Agent --> Ollama + Qdrant + PostgreSQL/pgvector + MinIO
Airflow --> Redis/Celery --> Spark --> MinIO (Bronze/Silver/Gold)
Fluent Bit (global) --> OpenSearch --> Dashboards
Prometheus --> node-exporter/cAdvisor/NVIDIA exporter --> Grafana
```

## Redes

- `public`: Traefik y backends con routers HTTP.
- `internal`: tráfico privado entre servicios.
- `ingress`: publicación nativa de Swarm.
- `jupyterhub-user`: red externa para sesiones dinámicas.

Las redes externas deben existir antes del despliegue. El aislamiento se complementa con TLS, BasicAuth, whitelist LAN y Swarm Secrets.

## Persistencia y seguridad

NVMe de `master2`: PostgreSQL, OpenSearch, n8n, Airflow, Spark temporal y usuarios JupyterHub. HDD de `master2`: MinIO y modelos Ollama. `master1` guarda datos de control, Prometheus/Grafana y el Hub.

OpenSearch es single-node con el plugin de seguridad desactivado; el acceso externo está protegido por Traefik. Los ADR conservan el contexto histórico, pero la configuración ejecutable siempre prevalece.
