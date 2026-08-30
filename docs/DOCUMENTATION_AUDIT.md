# Documentation audit — S2.5

> Reviewed 2026-08-30 against repository-declared configuration. This is a documentation audit, not a live-runtime audit.

## Findings and treatment

| Finding | Treatment in this documentation phase |
|---|---|
| Runtime health cannot be inferred from versioned stack files. | README and readiness assessment distinguish declared capabilities from live verification. |
| OpenSearch security is intentionally disabled for the private lab. | Retained as an explicit limitation, linked to ADR-004; no security configuration changed. |
| Stateful services use local paths and mostly single-node placement. | Documented as a resilience and availability boundary, not a production guarantee. |
| Alert routing is not declared as an active platform component. | Classified as Planned in the readiness assessment. |
| `envs/lab.env.example` still refers to the retired standalone Jupyter stack. | Recorded for a future configuration phase; it is not changed here because this branch is documentation-only. |
| `docs/ROADMAP.md` contains historical completion statements. | Retained as historical context; `docs/architecture/STATE.md` and the operational checklist remain the current source for verification. |
| Repository description, topics, and social preview are external GitHub settings. | Recommendations are supplied in `GITHUB_PRESENTATION.md`; no external setting was changed. |

## Checks completed

- Local Markdown links introduced or changed in this phase resolve to repository files.
- No secrets or credential values were added in the changed documentation.
- The README architecture claims are limited to components declared in stack files, architecture documents, ADRs, or runbooks.

## Follow-up outside this phase

- Reconcile environment templates with the current JupyterHub architecture.
- Decide whether and how to enable OpenSearch security for any broader exposure.
- Add Alertmanager and alert-routing policy if operational alerting is required.
- Capture runtime evidence after deployments rather than relying on documentation claims.
