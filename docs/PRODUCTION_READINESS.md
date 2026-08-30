# Production-readiness assessment

> This assessment describes repository-declared controls as of 2026-08-30. It is not evidence that a specific Swarm runtime is healthy or that the platform meets a production SLA.

## Status legend

- **Implemented:** declared in executable configuration or supported by maintained operational artifacts.
- **Partial:** present with material scope limits, manual dependencies, or environment-specific verification required.
- **Planned:** explicitly identified as future work; no complete implementation is claimed.
- **Not assessed:** insufficient repository evidence for a reliable classification.

| Area | Status | Repository evidence | Boundary or next verification |
|---|---|---|---|
| Configuration management | Partial | Versioned stacks, host references, and non-secret templates under `envs/`. | Validate the active host environment against the repository before deployment. |
| Secrets management | Implemented | `.gitignore` excludes secrets; stacks reference external Docker Swarm Secrets. | Confirm required secret names on the Swarm manager; values remain outside Git. |
| Networking | Implemented | External overlays, Traefik routing, LAN allowlisting, and published-port documentation. | Confirm firewall and DNS/hosts rules in the target environment. |
| Persistent storage | Implemented | Bind-mount paths and node placement are documented. | Storage is host-local; confirm mounts and ownership before Docker starts. |
| Backup and recovery | Partial | Restic and service backup scripts/runbooks are present. | Restore drills and runtime backup freshness require environment evidence. |
| Authentication and authorization | Partial | Traefik BasicAuth and service-specific credentials/secrets are declared. | No claim of centralized identity, multi-tenant RBAC, or unified authorization. |
| Logging | Implemented | Fluent Bit and OpenSearch/Dashboards stacks and runbooks are present. | Verify index ingestion and retention in the target runtime. |
| Metrics | Implemented | Prometheus, Grafana, node/cAdvisor/NVIDIA exporters, and dashboards are declared. | Verify scrape target health and dashboard provisioning at runtime. |
| Alerting | Planned | Prometheus configuration identifies Alertmanager as a future addition. | Design and deploy alert routing before claiming active alerting. |
| Health checks | Partial | Health endpoints and service-specific validation commands are documented. | Coverage and actual task convergence must be validated per stack. |
| Scalability | Partial | Swarm placement, overlays, and worker roles provide a scaling foundation. | Stateful services and the two-node topology constrain practical scale and availability. |
| Upgrade strategy | Partial | Docker Engine and service runbooks include upgrade and rollback guidance. | Verify image pinning, compatibility, and rollback on each change. |
| Security hardening | Partial | UFW, SSH hardening, TLS rotation, Docker Secrets, and LAN controls are documented. | Self-signed TLS and the disabled OpenSearch security plugin are deliberate lab trade-offs. |

## Declared limitations that affect a production claim

- Stateful services are primarily single-node and rely on local persistent disks.
- The default certificate model is internal/self-signed unless replaced by the operator.
- OpenSearch runs with `DISABLE_SECURITY_PLUGIN=true`; see [ADR-004](adrs/ADR-004-opensearch-security-plugin-disabled.md).
- Prometheus alert routing is not declared as an active service.
- Runtime evidence is not stored as a substitute for current Swarm verification.

## Validation baseline

Run the [operational checklist](architecture/Checklist_Infra_Lab.md) and the relevant service runbook before claiming runtime readiness. The stack files remain the executable source of truth.
