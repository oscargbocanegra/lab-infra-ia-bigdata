# Línea base verificable: Repositorio – Runtime – Arquitectura objetivo

Fecha de evidencia: 2026-07-15
Repositorio base: `main` — `12a9e6f85a2b8068a898d2b45bd9575c3be41754`

## Arquitectura objetivo

- `master1`: manager Swarm, plano de control, Traefik y JupyterHub.
- `master2`: cómputo, GPU, persistencia, PostgreSQL/pgvector, servidores
  single-user, OpenSearch y Fluent Bit.
- Logs: Fluent Bit global hacia OpenSearch.
- Autenticación: NativeAuthenticator; SSO fuera del alcance actual.

## Matriz de conformidad

| Componente | Configuración declarada | Runtime verificado | Evidencia funcional | Estado |
|---|---|---|---|---|
| Traefik | `stacks/core/00-traefik` | `1/1` en master1 | Enrutamiento JupyterHub | Conforme |
| JupyterHub | Hub en master1; usuarios en master2 | Hub `1/1`; dos servidores single-user saludables | `/hub/health` HTTP 200 | Conforme |
| PostgreSQL/pgvector | Persistencia y placement en master2 | `1/1` en master2 | Contenedor activo | Conforme |
| OpenSearch | `2.19.4`; NVMe `/srv/fastdata/opensearch`; master2 | `1/1` en master2 | API interna HTTP 200; clúster green | Conforme |
| Fluent Bit | Global; salida OpenSearch | `2/2`, un task por nodo | `docker-logs-*` con documentos indexados | Conforme |
| GPU | Placement `gpu=nvidia` para cómputo IA | RTX 2080 Ti en master2 | Ollama activo en master2 | Conforme |

## Evidencia principal

- `master1:~/lab-reports/baseline-repository-runtime-architecture-master1-20260715_005452.txt`
- `master1:~/lab-reports/baseline-gap-repo-jupyterhub-master1-20260715_005946.txt`
- `master2:~/lab-reports/baseline-runtime-master2-direct-20260715_010008.txt`
- `master1:~/lab-reports/fluentbit-opensearch-current-path-master1-20260715_010855.txt`
- `master2:~/lab-reports/opensearch-internal-api-close-master2-20260715_011416.txt`

## Decisiones y pendientes

1. El acceso externo no autenticado a OpenSearch responde `403`; conservar la
   política actual hasta definir el acceso administrativo.
2. Normalizar documentación histórica: ADR-006 y referencias legacy
   `/srv/fastdata/jupyter/...`.
3. Evaluar `rag-api_rag-api`, actualmente en estado `0/1`.
4. Recuperar SSH no interactivo `master1 → master2` para auditorías automáticas.
