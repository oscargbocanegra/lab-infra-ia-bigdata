# Verifiable baseline: repository, runtime, and target architecture

Evidence date: 2026-07-15
Baseline repository: `main` — inspect the current commit with `git rev-parse main`

## Target architecture

- `master1`: Swarm manager, control plane, Traefik, and JupyterHub.
- `master2`: compute, GPU, persistence, PostgreSQL/pgvector, single-user servers, OpenSearch, and Fluent Bit.
- Logs: Fluent Bit runs globally and forwards logs to OpenSearch.
- Authentication: NativeAuthenticator; SSO outside the current scope.

## Conformance matrix

| Component | Declared configuration | Verified runtime | Functional evidence | Status |
|---|---|---|---|---|
| Traefik | `stacks/core/00-traefik` | `1/1` on master1 | JupyterHub routing | Compliant |
| JupyterHub | Hub on master1; users on master2 | Hub `1/1`; two healthy single-user servers | `/hub/health` HTTP 200 | Compliant |
| PostgreSQL/pgvector | Persistence and placement on master2 | `1/1` on master2 | Active container | Compliant |
| OpenSearch | `2.19.4`; NVMe `/srv/fastdata/opensearch`; master2 | `1/1` on master2 | API HTTP 200; green cluster | Compliant |
| Fluent Bit | Global; OpenSearch output | `2/2`, one task per node | `docker-logs-*` with indexed documents | Compliant |
| GPU | `gpu=nvidia` placement for AI compute | RTX 2080 Ti on master2 | Ollama active on master2 | Compliant |

## Primary evidence

- `master1:~/lab-reports/baseline-repository-runtime-architecture-master1-20260715_005452.txt`
- `master1:~/lab-reports/baseline-gap-repo-jupyterhub-master1-20260715_005946.txt`
- `master2:~/lab-reports/baseline-runtime-master2-direct-20260715_010008.txt`
- `master1:~/lab-reports/fluentbit-opensearch-current-path-master1-20260715_010855.txt`
- `master2:~/lab-reports/opensearch-internal-api-close-master2-20260715_011416.txt`

## Decisions and open items

1. Unauthenticated external OpenSearch access returns `403`; retain the current policy until administrative access is defined.
2. ADR-006 and the paths `/srv/fastdata/jupyter/...` are historical; the current architecture uses OpenSearch on master2 and JupyterHub at `/srv/fastdata/jupyterhub`.
3. Verify `rag-api_rag-api` using the stack health check; do not infer state from historical evidence.
4. Restore non-interactive SSH `master1 → master2` for automated audits.
