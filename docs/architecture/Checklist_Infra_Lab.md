# Checklist operativo

> Revisado 2026-08-21. Este checklist verifica el estado del despliegue actual; no es un roadmap histórico.

## Preflight

- [ ] `docker node ls`: master1 manager/leader y master2 worker/ready.
- [ ] Labels `tier`, `storage`, `gpu` presentes según [`NODES.md`](NODES.md).
- [ ] Redes externas `public`, `internal` y `jupyterhub-user` creadas.
- [ ] Secrets requeridos creados fuera de Git.
- [ ] `/srv/fastdata` y `/srv/datalake` montados antes de iniciar Docker.

## Stacks

| Área | Stack | Verificación |
|---|---|---|
| Entrada | `traefik`, `portainer` | `docker stack services <stack>`; HTTPS por `aifabric.<servicio>` |
| Datos | `postgres`, `opensearch`, `minio`, `openmetadata` | health/API y volumen persistente |
| IA | `jupyterhub`, `ollama`, `qdrant`, `rag-api`, `open-webui`, `agent` | Hub health, `/api/tags`, endpoints `/health` |
| Automatización | `n8n`, `airflow` | webserver, scheduler, worker y Flower |
| Analítica | `spark` | worker registrado y history accesible |
| Observabilidad | `fluent-bit`, `prometheus`, `grafana`, `nvidia-exporter` | targets UP, dashboard y logs indexados |

## Comandos de aceptación

```bash
docker stack ls
docker stack services jupyterhub
docker service ps opensearch_opensearch
curl -k https://aifabric.jupyterhub/hub/health
curl -k https://aifabric.ollama/api/tags
```

Los estados `pending deploy` de la versión 2026-03-30 quedan obsoletos: MinIO, Spark y Airflow tienen stacks declarados y sus runbooks actuales deben usarse para validar la ejecución.
