# Estado verificable del repositorio

> Revisado 2026-08-21. Describe la configuración declarada en `main`; el estado de tareas se confirma en el Swarm.

- `main` es la rama de despliegue.
- `master1`: manager/leader, `tier=control`; `master2`: worker con GPU.
- JupyterHub reemplaza al stack standalone JupyterLab.
- OpenSearch corre en `master2`; Dashboards en `master1`.
- OpenMetadata, observabilidad, RAG API, Agent y Open WebUI están declarados en stacks propios.

```bash
docker node ls
docker stack ls
docker stack services jupyterhub
docker stack services opensearch
docker stack services prometheus
```

La documentación no afirma “100% operativo” sin una captura reciente de estas comprobaciones. Rutas persistentes: [`STORAGE.md`](STORAGE.md). Redes: [`NETWORKING.md`](NETWORKING.md).
