# Operational checklist

> Reviewed 2026-08-22. This checklist verifies the current deployment state; it is not a historical roadmap.

## Preflight checks

- [ ] `docker node ls`: master1 manager/leader and master2 worker/ready.
- [ ] Labels `tier`, `storage`, `gpu` present as defined in [`NODES.md`](NODES.md).
- [ ] external networks `public`, `internal`, and `jupyterhub-user` created.
- [ ] required secrets created outside Git.
- [ ] `/srv/fastdata` and `/srv/datalake` mounted before Docker starts.

## Stacks

| Area | Stack | Verification |
|---|---|---|
| Ingress | `traefik`, `portainer` | `docker stack services <stack>`; HTTPS through `aifabric.<service>` |
| Data | `postgres`, `opensearch`, `minio`, `openmetadata` | health/API and persistent volume |
| AI | `jupyterhub`, `ollama`, `qdrant`, `rag-api`, `open-webui`, `agent` | Hub health, `/api/tags`, endpoints `/health` |
| Automation | `n8n`, `airflow` | webserver, scheduler, worker, and Flower |
| Analytics | `spark` | registered worker and accessible history server |
| Observability | `fluent-bit`, `prometheus`, `grafana`, `nvidia-exporter` | UP targets, dashboard, and indexed logs |

## Acceptance commands

```bash
docker stack ls
docker stack services jupyterhub
docker service ps opensearch_opensearch
curl -k https://aifabric.jupyterhub/hub/health
curl -k https://aifabric.ollama/api/tags
```

The `pending deploy` states from the 2026-03-30 version are obsolete: MinIO, Spark, and Airflow have declared stacks, and their current runbooks must be used to validate execution.
