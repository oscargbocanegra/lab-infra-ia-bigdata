# Current architecture

> Source of truth: `stacks/**/stack.yml`. Reviewed 2026-08-22.

## Topology

The lab is a private two-node Docker Swarm. `master1` is the manager/leader and `master2` is the worker, labeled `tier=compute`, `storage=primary`, and `gpu=nvidia`.

```text
master1 (control)
  Traefik, Portainer, JupyterHub, Qdrant, RAG API, Agent, Open WebUI,
  Airflow (Redis/web/scheduler/flower), Spark master/history, OpenMetadata,
  OpenSearch Dashboards, Prometheus, Grafana and Fluent Bit.

master2 (compute/data/GPU)
  PostgreSQL/pgvector, n8n, Ollama, MinIO, OpenSearch, Spark worker,
  Airflow worker, dynamic JupyterHub single-user sessions and Fluent Bit.
```

The exact placement constraints are defined in each stack's `deploy.placement.constraints`.

## Data flow

```text
LAN --HTTPS--> Traefik
RAG API / Agent --> Ollama + Qdrant + PostgreSQL/pgvector + MinIO
Airflow --> Redis/Celery --> Spark --> MinIO (Bronze/Silver/Gold)
Fluent Bit (global) --> OpenSearch --> Dashboards
Prometheus --> node-exporter/cAdvisor/NVIDIA exporter --> Grafana
```

## Networks

- `public`: Traefik and HTTP-routed backends.
- `internal`: Private service-to-service traffic.
- `ingress`: Swarm native routing.
- `jupyterhub-user`: external network for dynamic sessions.

External networks must exist before deployment. Isolation is reinforced by TLS, BasicAuth, the LAN allowlist, and Swarm Secrets.

## Persistence and security

`master2` NVMe: PostgreSQL, OpenSearch, n8n, Airflow, temporary Spark data and JupyterHub user data. `master2` HDD: MinIO and Ollama models. `master1` stores control-plane data, Prometheus/Grafana, and the Hub.

OpenSearch runs as a single node with its security plugin disabled; Traefik protects external access. ADRs preserve historical context, but executable configuration always takes precedence.
