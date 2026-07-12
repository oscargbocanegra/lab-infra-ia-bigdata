# ADR-013: OpenSearch migration to master2

**Date**: 2026-07-12
**Status**: Accepted
**Supersedes**: ADR-006

## Context

ADR-006 ubicó OpenSearch en `master1` por la carga existente en `master2`.
Después del retiro de JupyterLab standalone y la adopción de servicios
single-user dinámicos, `master2` dispone de capacidad y almacenamiento NVMe.
Además, OpenSearch es stateful e intensivo en I/O.

## Decision

- OpenSearch se ejecuta en `master2`.
- Placement: `tier=compute` y `storage=primary`.
- Persistencia: `/srv/fastdata/opensearch` sobre NVMe.
- Dashboards y los despliegues Swarm permanecen en `master1`.
- El clúster continúa single-node con réplicas `0`.
- La retención de `docker-logs-*` se gestiona mediante ISM.

## Security

El Security Plugin continúa deshabilitado conforme a ADR-004. Se mantienen
Traefik, BasicAuth, whitelist LAN, redes overlay y ausencia de exposición
directa a Internet.

## Consequences

- Mejora el rendimiento de índices y reduce estado persistente en el control plane.
- Una caída de `master2` detiene OpenSearch y la ingesta.
- El rollback requiere preparar almacenamiento en `master1`, restaurar un backup
  válido y reconciliar el placement mediante Git.

## Evidence

OpenSearch `1/1` en `master2`, Dashboards `1/1` en `master1`, clúster `green`,
cero shards no asignados y Fluent Bit `2/2`.
