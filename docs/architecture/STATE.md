# Estado actual verificable

> Actualizado: 2026-07-18

## Resumen

- `master1`: control plane, Traefik, Portainer, OpenSearch Dashboards,
  Spark Master/History, Airflow Hub y diagnósticos del nodo.
- `master2`: compute/data/GPU, PostgreSQL, n8n, OpenSearch, MinIO, Spark
  Worker, JupyterHub single-user y Ollama.
- La ruta canónica del laboratorio sigue siendo `main` en Git y el runtime
  verificado se mantiene alineado con el repo.

## Evidencia reciente

- JupyterHub reconciliado con `giovannotti/lab-jupyter:sha-1269366`.
- Smoke distribuido PySpark validado desde una sesión real de JupyterHub.
- `master1` dejó el reporte de arranque fuera del camino crítico mediante
  `lab-report-boot.timer`.

## Servicios críticos

| Servicio | Estado |
|---|---|
| Traefik | operativo |
| Portainer | operativo |
| OpenSearch / Dashboards | operativo |
| PostgreSQL | operativo |
| n8n | operativo |
| Spark | operativo |
| Airflow | operativo |
| MinIO | operativo |
| JupyterHub | operativo |
| Ollama | operativo |

## Rutas canónicas

- `/srv/fastdata/jupyterhub/hub`
- `/srv/fastdata/jupyterhub/users/<username>`
- `/srv/fastdata/opensearch`
- `/srv/fastdata/postgres`
- `/srv/fastdata/airflow`
- `/srv/fastdata/spark-tmp`
- `/srv/datalake/minio`
- `/srv/datalake/models/ollama`

## Red

- `public`: ingreso LAN por Traefik.
- `internal`: tráfico de backend entre servicios.
- Dominio interno: `*.sexydad`.

## Notas

- Seguridad mantenida en modo simple y funcional para laboratorio.
- El rollback principal sigue siendo volver a la imagen o stack anterior y
  redeplegar.
