# ADR-007: Data Governance with OpenMetadata + Great Expectations

**Date:** 2026-04-06  
**Status:** Accepted  
**Deciders:** Lab architect  

---

## Context

As the lab evolves from a technical portfolio toward a production-ready platform,
data governance becomes essential. Without it:

- There is no catalog: nobody knows what datasets exist, their schemas, or their freshness.
- There is no lineage: it is impossible to trace where a dataset in `gold/` came from.
- There is no quality enforcement: data can silently corrupt as it moves bronze → silver → gold.
- Scaling to a real business context requires auditable, classified, and validated data.

The lab already has a Medallion architecture in MinIO (bronze/silver/gold), Airflow for
orchestration, Postgres for metadata, and OpenSearch for logs — all foundational pieces
for governance.

---

## Decision

Implement data governance in two layers:

### Layer 1 — Data Quality (Great Expectations inside Airflow)
- Run schema + quality validations as Airflow tasks before any bronze → silver promotion
- No new service required — Great Expectations is a Python library
- Validation results stored in MinIO (`governance/ge-results/`) and logged to OpenSearch

### Layer 2 — Data Catalog + Lineage (OpenMetadata)
- Deploy OpenMetadata as a new Docker Swarm stack (`stacks/data/13-openmetadata/`)
- Connect native connectors to: Postgres, MinIO, Airflow (OpenLineage)
- Provides: catalog, column-level lineage, PII classification, data profiling
- Uses its own MySQL backend (bundled in the stack)

---

## Naming Conventions (enforced by setup script)

MinIO bucket structure:

```
bronze/<source>/<YYYY-MM-DD>/<filename>
silver/<domain>/<table>/<YYYY-MM-DD>/part-*.parquet
gold/<report-name>/<YYYY-MM-DD>/part-*.parquet
governance/ge-results/<pipeline>/<YYYY-MM-DD>/result.json
governance/catalogs/                              ← OpenMetadata exports
```

---

## Alternatives Considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| **OpenMetadata** | Native Docker, connectors for all lab tools, lightweight (~1.5GB RAM), modern UI | Requires MySQL bundled | ✅ Selected |
| DataHub | Industry standard, LinkedIn-backed | Requires Kafka + ZooKeeper, heavy (~8GB RAM) | ❌ Too heavy for lab |
| Apache Atlas | Hadoop ecosystem standard | Complex deploy, no MinIO connector | ❌ Too complex |
| Custom Postgres catalog | Full control, no new service | High maintenance, no UI | ❌ Not scalable |
| Great Expectations only | Simple, no new service | No lineage, no catalog UI | ❌ Incomplete |

---

## Consequences

**Positive:**
- Full data observability: catalog + lineage + quality in one tool
- Airflow DAGs automatically report lineage to OpenMetadata via OpenLineage
- Governance layer is independent — can be disabled without affecting pipelines
- Portfolio-ready: OpenMetadata is used in production at many companies

**Negative:**
- ~1.5 GB additional RAM on master1 (acceptable — 25 GB available)
- MySQL bundled in OpenMetadata stack adds one more database engine
- OpenMetadata ingestion connectors require periodic refresh (scheduled via Airflow)

---

## Resources

- OpenMetadata docs: https://docs.open-metadata.org
- Great Expectations docs: https://docs.greatexpectations.io
- OpenLineage (Airflow integration): https://openlineage.io
