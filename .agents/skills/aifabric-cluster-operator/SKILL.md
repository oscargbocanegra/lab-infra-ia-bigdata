---
name: aifabric-cluster-operator
description: Execute authorized, non-destructive runtime label repairs, immutable image upgrades, and Git synchronization for the AiFabric Docker Swarm cluster. Use only for requested changes; use the auditor skill for read-only diagnosis.
---

# AiFabric Cluster Operator

Apply a confirmed AiFabric finding with the smallest safe mutation, validate the result, and reconcile runtime with the repository.

## Authorization and scope

- Skill invocation is not blanket authorization. Execute only the concrete services, stacks, files, and external actions requested by the user.
- Start from an auditor finding when available. Otherwise run only the targeted read-only preflight needed to resolve exact service names, current labels, images, mounts, replicas, nodes, and endpoints.
- Before every mutation, resolve the exact target and capture the prior value needed for rollback.
- Never broaden a label repair into an image upgrade, restart, stack deployment, volume change, or cluster-wide cleanup.
- Do not expose secret values. Inspect secret names and metadata only.
- Never run destructive cleanup, volume removal, `docker stack rm`, `docker system prune`, `git reset --hard`, or an unsupported database downgrade.

## Invariants

### Persistent data

- Preserve existing bind mounts, named volumes, placement constraints, networks, secrets, configs, and replica topology unless the user explicitly requests a reviewed change.
- Treat PostgreSQL, MySQL, Qdrant, MinIO, OpenSearch, OpenMetadata, Airflow, n8n, JupyterHub, and Open WebUI as stateful when they use persistent storage.
- Before a stateful image change, capture a service-specific consistent backup or snapshot and prove it is readable. Record baseline object, collection, index, or row counts when available.
- Never declare success if data counts, IDs, or integrity checks regress. Stop further rollout, preserve the pre-upgrade artifact, and recover data through the supported restore path.
- Do not downgrade a stateful service after schema or storage migration unless its vendor explicitly supports it. Restore a compatible backup instead.

### Images

- Deploy only a GA release with a versioned tag and immutable digest: `image:version@sha256:...`.
- Never deploy `latest`, including `latest@sha256:...`.
- Resolve the target for `linux/amd64` and record the exact platform digest. Confirm the tag and digest using the authoritative registry.
- Review vendor upgrade requirements for skipped versions. Use required intermediate versions rather than forcing an unsupported jump.
- Pre-pull the pinned image on the node that can run the task when this reduces downtime.

### Traefik

- This cluster uses the Swarm provider. Reference global middlewares with `@swarm`, including `lan-whitelist@swarm`, `llmfit-auth@swarm`, and service-specific auth middlewares.
- Preserve router rule, entrypoints, TLS, service port, and the external `public` overlay unless the finding requires one of them to change.
- Confirm the middleware is actually declared by the active Traefik service before referencing it.

## Operation selection

### Label-only runtime repair

Prefer a service-spec label update over `docker stack deploy`, especially for volume-bound services. A service-level label change should not replace the task:

```bash
docker service inspect <service> --format '{{json .Spec.Labels}}' | jq .
docker service ps --no-trunc <service>
docker service update --detach=true \
  --label-add 'traefik.http.routers.<router>.middlewares=lan-whitelist@swarm' \
  <service>
```

When multiple labels are needed, apply them in one `docker service update`. Afterward:

1. verify the effective labels;
2. verify the current task ID did not change unexpectedly;
3. test the exact endpoint once;
4. update the corresponding `stack.yml` with identical values;
5. validate the rendered manifest;
6. do not redeploy the stack merely to persist a label-only repair.

Use `docker stack deploy` for a label repair only when runtime repair cannot express the required change and the user has authorized the restart risk.

### Immutable image upgrade

For an image change:

1. Record current image/digest, task node, replicas, update policy, mounts, healthcheck, and service-specific data baseline.
2. Verify compatibility and create the required backup or snapshot.
3. Resolve and pre-pull the versioned target digest.
4. Update only the intended manifest fields. Keep data mounts and operational settings byte-for-byte unchanged unless explicitly required.
5. Render with `docker stack config -c <stack.yml>` and run `git diff --check`.
6. Deploy only the named stack:

```bash
docker stack deploy --with-registry-auth -c <stack.yml> <stack>
```

7. Wait only for normal convergence. Inspect the new task and bounded logs; do not start indefinite retry loops.
8. Run service-specific health, integration, and data-integrity checks.
9. If acceptance fails, stop the rollout. Roll back stateless services to the previous digest. For stateful migrations, follow the backup-based recovery plan rather than forcing a downgrade.

Do not use `docker service update --image` as the final workflow when a managed stack manifest exists; it creates repository/runtime drift.

## Validation

Always verify:

- nodes required by the service remain `Ready/Active`;
- expected replicas converge and the update is not paused;
- runtime image exactly matches the intended digest;
- mounts, networks, secrets, configs, and placement remain unchanged;
- Traefik labels use `@swarm` and the service remains on `public`;
- the application health endpoint returns its expected status;
- one relevant integration works, such as Ollama discovery or Open WebUI model listing;
- stateful data counts and canonical identifiers match the baseline.

Interpret `200`, expected redirects, and intended `401` challenges according to the application. Treat Traefik `404`, `502`, `503`, and `504` as failures. Report when curl uses `-k`.

## Git synchronization

- Inspect `git status --short --branch` before editing. Preserve unrelated user changes.
- Modify the canonical stack manifest that owns the runtime service. Do not stage unrelated paths and never use `git add .`.
- Validate the diff, rendered stack, and runtime before committing.
- Stage only the changed manifest and directly related documentation.
- Commit only when the user requested repository synchronization or a commit is an explicit part of the operation.
- Push only when the user explicitly requests `git push`. Confirm branch and remote state first.
- If on detached HEAD, do not strand the commit: switch to the intended available branch before committing, or apply the commit there with a user-authorized cherry-pick.

## Stop conditions

Stop without further mutation when:

- the exact target cannot be resolved;
- the target digest or platform is unavailable;
- the required backup cannot be created or read;
- the worktree has overlapping unrelated changes;
- a stateful service loses objects, points, rows, indexes, or collection integrity;
- the update pauses, repeatedly restarts, or introduces sustained errors;
- rollback requires an unsupported downgrade or destructive action.

Preserve evidence and report the blocker plus the safest recovery option.

## Output

Lead with the result and return compact tables:

1. changed service, old image/labels, new image/labels;
2. preserved mounts, networks, and data evidence;
3. health and integration results;
4. rollback artifact and status;
5. files changed, commit hash, and push status;
6. unresolved risks or stopped conditions.

Do not report success until runtime, data integrity, and repository state agree.
