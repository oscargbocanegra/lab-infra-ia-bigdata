# Gobierno de datos

> Revisado 2026-08-21. Describe componentes declarados, no una garantía de que cada conector esté configurado en runtime.

## Componentes actuales

- OpenMetadata (`stacks/data/13-openmetadata`) con servidor, MySQL y OpenSearch dedicados en `master1`.
- Airflow (`stacks/automation/03-airflow`) con DAGs de validación y promoción.
- MinIO para objetos y capas Bronze/Silver/Gold.
- OpenSearch principal para logs y búsquedas operativas en `master2`.

Los conectores YAML de OpenMetadata cubren PostgreSQL, MinIO y Airflow. Great Expectations no está desplegado como servicio independiente; cualquier validación debe ejecutarse dentro de un DAG o imagen que la incluya.

## Convención de datos

```text
bronze/<fuente>/<fecha>/raw.*
silver/<dominio>/<tabla>/<fecha>/part-*.parquet
gold/<producto>/<fecha>/part-*.parquet
```

La convención es operativa y debe acompañarse de propietarios, esquema, retención y evidencia de calidad.

## Verificación

```bash
docker stack services openmetadata
docker service logs openmetadata_openmetadata-server --tail 100
# comprobar conectores desde la UI/API antes de declarar lineage
```

Relacionado: [`MEDALLION.md`](MEDALLION.md), [`DATABASES.md`](DATABASES.md) y ADR-007.
