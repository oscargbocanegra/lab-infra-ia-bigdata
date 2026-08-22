# Arquitectura Medallion

> Revisado 2026-08-21. Patrón objetivo implementado sobre MinIO y Spark; las tablas y DAGs concretos se versionan por proyecto.

## Capas

```text
fuentes -> Bronze (raw) -> Spark/validación -> Silver (curado) -> Gold (consumo)
                         Airflow orquesta y Jupyter explora
```

- **Bronze**: datos recibidos sin transformar.
- **Silver**: datos tipados, deduplicados y enriquecidos, preferentemente Delta/Parquet.
- **Gold**: agregados, KPIs y features consumibles.

MinIO vive en `master2` (`/srv/datalake/minio`). Spark declara las extensiones Delta y usa el worker de `master2`; Airflow ejecuta DAGs de gobierno, promoción y evaluación.

## Buckets y responsabilidades

| Bucket/prefijo | Uso |
|---|---|
| `bronze/` | aterrizaje raw |
| `silver/` | datasets curados |
| `gold/` | productos analíticos y ML |
| `governance/` | resultados de validación/catálogo si se habilitan |
| `airflow-logs/` | reservado para logs remotos (Airflow está configurado con logging local por defecto) |
| `spark-warehouse/` | warehouse y eventos según configuración |

No asumir que un bucket existe solo por aparecer en un ejemplo: comprobarlo en MinIO antes de ejecutar un DAG.
