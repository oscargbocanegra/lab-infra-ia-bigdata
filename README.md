# Lab Infra — AI & Big Data Platform

Plataforma autoalojada sobre un clúster de dos nodos Docker Swarm. Los `stack.yml` son la fuente de verdad del despliegue; esta página resume la arquitectura vigente (revisada 2026-08-21).

## Estado y alcance

- `main` es la rama canónica.
- Hay 18 stacks y 34 definiciones de servicio. `airflow_init` tiene `replicas: 0` y solo se usa para inicialización.
- Traefik en `master1` es el único punto de entrada HTTPS desde la LAN (`*.sexydad`).
- JupyterHub es el único acceso Jupyter soportado; el stack standalone `stacks/ai-ml/01-jupyter` no se despliega.
- `master2` concentra GPU, almacenamiento y servicios stateful.

## Arquitectura resumida

```text
LAN -> Traefik (master1)
       -> JupyterHub, RAG API, Agent, Open WebUI, Qdrant, Airflow, Spark UI,
          OpenMetadata y observabilidad
master2 (worker + GPU) -> PostgreSQL/pgvector, n8n, Ollama, MinIO, OpenSearch,
                          Spark worker, Airflow worker y sesiones JupyterHub
```

Las redes overlay externas `public` e `internal` separan ingreso y tráfico de backend. Ollama (`11434`) y PostgreSQL (`5432`) conservan publicación LAN directa para clientes autorizados.

## Navegación

- [`docs/architecture/ARCHITECTURE.md`](docs/architecture/ARCHITECTURE.md) — diseño y flujos
- [`docs/architecture/SERVICES.md`](docs/architecture/SERVICES.md) — inventario derivado de stacks
- [`docs/architecture/NETWORKING.md`](docs/architecture/NETWORKING.md) — redes, dominios y puertos
- [`docs/architecture/NODES.md`](docs/architecture/NODES.md) — placement y almacenamiento
- [`docs/architecture/STATE.md`](docs/architecture/STATE.md) — comprobaciones operativas
- [`docs/runbooks/`](docs/runbooks/) — operación
- [`stacks/`](stacks/) — configuración desplegable

No se versionan credenciales: los stacks requieren Docker Swarm Secrets creados fuera de Git.
