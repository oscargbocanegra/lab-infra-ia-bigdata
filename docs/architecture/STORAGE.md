# Almacenamiento y rutas canónicas

> Revisado 2026-08-21. Las rutas se derivan de los bind mounts de los stacks.

## `master1` (HDD, control)

- `/srv/fastdata/jupyterhub/hub`: estado del Hub.
- `/srv/fastdata/prometheus`, `/srv/fastdata/grafana`: métricas y dashboards.
- `/srv/fastdata/portainer`: configuración de Portainer.
- `/srv/fastdata/spark-history`: eventos de Spark e historial.
- `/srv/fastdata/fluent-bit`: offsets de Fluent Bit.

## `master2` (NVMe + HDD, compute)

NVMe `/srv/fastdata`: `postgres`, `opensearch`, `n8n`, `airflow`, `spark-tmp` y `jupyterhub/users/<username>`.

HDD `/srv/datalake`: `minio`, `models/ollama`, `datasets`, `notebooks`, `artifacts` y `backups`.

## Servicios y persistencia

| Servicio | Ruta | Nodo |
|---|---|---|
| PostgreSQL/pgvector | `/srv/fastdata/postgres` | master2 |
| OpenSearch | `/srv/fastdata/opensearch` | master2 |
| n8n | `/srv/fastdata/n8n` | master2 |
| MinIO | `/srv/datalake/minio` | master2 |
| Ollama | `/srv/datalake/models/ollama` | master2 |
| JupyterHub Hub | `/srv/fastdata/jupyterhub/hub` | master1 |
| JupyterHub users | `/srv/fastdata/jupyterhub/users/<username>` | master2 |
| Airflow | `/srv/fastdata/airflow` | ambos según componente |
| Spark temporal | `/srv/fastdata/spark-tmp` | master2 |

Las rutas `/srv/fastdata/jupyter/<username>` pertenecen al runtime standalone retirado y no son rutas activas del Hub.

## Operación segura

Montar ambos discos antes de iniciar Docker (`RequiresMountsFor`). Verificar propietarios según UID de la imagen y no borrar datos para “recrear” un servicio sin backup. Las copias de seguridad son responsabilidad de los runbooks de hardening; el stack no implementa replicación automática.

```bash
df -h /srv/fastdata /srv/datalake
findmnt /srv/fastdata /srv/datalake
```
