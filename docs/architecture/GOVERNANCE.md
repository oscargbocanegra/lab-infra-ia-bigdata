# Data governance

> Reviewed 2026-08-22. Describes declared components; it does not guarantee that every connector is configured at runtime.

## Current components

- OpenMetadata (`stacks/data/13-openmetadata`) with dedicated server, MySQL, and OpenSearch services on `master1`.
- Airflow (`stacks/automation/03-airflow`) with validation and promotion DAGs.
- MinIO for objects and Bronze/Silver/Gold data layers.
- Primary OpenSearch for logs and operational search on `master2`.

OpenMetadata YAML connectors cover PostgreSQL, MinIO, and Airflow. Great Expectations is not deployed as an independent service; any validation must run inside a DAG or image that includes it.

## Data convention

```text
bronze/<source>/<date>/raw.*
silver/<domain>/<table>/<date>/part-*.parquet
gold/<product>/<date>/part-*.parquet
```

The convention is operational and must include ownership, schema, retention, and quality evidence.

## Verification

```bash
docker stack services openmetadata
docker service logs openmetadata_openmetadata-server --tail 100
# verify connectors through the UI/API before declaring lineage
```

Related: [`MEDALLION.md`](MEDALLION.md), [`DATABASES.md`](DATABASES.md), [`DATABASES.md`](DATABASES.md), and ADR-007.
