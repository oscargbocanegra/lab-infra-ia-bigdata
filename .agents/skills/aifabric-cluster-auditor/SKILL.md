---
name: aifabric-cluster-auditor
description: Perform strictly read-only health, replica, domain availability, and Traefik routing audits for the AiFabric Docker Swarm cluster. Use for status checks and diagnosis; never use it to deploy, update, restart, or repair services.
---

# AiFabric Cluster Auditor

Audit the live AiFabric cluster without changing cluster, host, repository, or application state.

## Safety boundary

- Execute only read-only inspection commands such as `docker node ls`, `docker service ls`, `docker service ps`, `docker service inspect`, bounded `docker service logs`, `docker network inspect`, `curl`, `getent`, `jq`, `awk`, `rg`, and `git status`.
- Never execute mutations, including `docker service update`, `docker stack deploy`, `docker stack rm`, `docker node update`, `docker restart`, `docker scale`, `docker exec`, `docker system prune`, package operations, file edits, Git staging/commits, or writes through HTTP methods other than GET/HEAD.
- Do not create temporary files or redirect command output to disk. Keep transformations in pipelines.
- Do not print secret values, environment values, config contents, authentication headers, or credentials. Inspect only metadata needed for diagnosis.
- If remediation is requested, report the exact diagnosis and a proposed command separately, marked `NO EJECUTADO`; do not run it while this skill is active.
- Use bounded commands: no observation loops, streaming logs, or unbounded waits. Default to `--tail 50` and `--since 10m` for logs.

## Diagnostic protocol

### 1. Nodes and replicas

Run:

```bash
docker node ls
docker service ls --format '{{.Name}}\t{{.Mode}}\t{{.Replicas}}\t{{.Image}}'
docker service ls --format '{{.Name}}\t{{.Replicas}}' | awk -F '\t' 'split($2,r,"/") == 2 && r[1] != r[2]'
```

Treat any node not `Ready/Active`, replica mismatch, rejected task, repeated restart, or paused update as a finding. A completed one-shot service at `0/0` is not automatically a failure; confirm its desired mode and task history.

For each affected service, inspect only that service:

```bash
docker service ps --no-trunc <service>
docker service inspect <service> --format '{{json .UpdateStatus}}'
docker service logs --since 10m --tail 50 <service>
```

### 2. Traefik routing

Identify the active Traefik service rather than assuming its stack name:

```bash
docker service ls --format '{{.Name}}\t{{.Image}}' | awk 'tolower($0) ~ /traefik/'
docker service inspect <traefik-service> --format '{{json .Spec.TaskTemplate.ContainerSpec.Args}}' | jq .
docker service inspect <traefik-service> --format '{{json .Spec.Labels}}' | jq .
```

Confirm the provider (`swarm` versus `docker`), entrypoint names, shared overlay network, and globally declared middleware names. Discover application routers dynamically:

```bash
docker service ls -q | xargs docker service inspect --format '{{.Spec.Annotations.Name}}\t{{json .Spec.Labels}}'
```

Report:

- router name and `Host(...)` rule;
- entrypoints and TLS state;
- service port and selected network;
- middleware references and provider namespace;
- missing middleware, mixed `@docker`/`@swarm`, missing port, or absent shared network.

Use `docker network inspect <network>` only to verify membership. Do not attach or detach services.

### 3. Domain availability

Derive hosts and paths from live router labels and repository verification scripts when available. Prefer HTTPS GET requests because some applications reject HEAD. Bypass proxy variables for laboratory domains:

```bash
getent ahostsv4 <host>
curl --noproxy '*' -ksS --max-time 15 -o /dev/null -w '%{http_code}\t%{content_type}\t%{redirect_url}\n' https://<host>/<path>
```

Classify results:

- `PASS`: `200` or an expected application redirect (`301`, `302`, `307`, `308`).
- `AUTH`: expected `401` authentication challenge.
- `DENIED`: `403`; routing exists, but source allowlisting or authorization blocked the request.
- `ROUTING FAIL`: Traefik-style `404`, missing router, invalid middleware, or wrong entrypoint.
- `UPSTREAM FAIL`: `502`, `503`, or `504`.
- `UNREACHABLE`: DNS, TLS, connection, or timeout failure.

Do not use `-k` silently in the report: state that certificate verification was bypassed. When TLS trust is part of the audit, repeat without `-k` and report the certificate result separately.

### 4. Focused diagnosis

Correlate failures in this order:

1. Node readiness and service replica convergence.
2. Current task state and bounded service logs.
3. Traefik router rule, middleware namespace, entrypoint, service port, and overlay membership.
4. DNS resolution and HTTP status.
5. Application health endpoint, using a read-only GET only.

Distinguish pre-existing failed task history from the current running task. Never mark a service failed solely because old shutdown tasks appear in `docker service ps`.

## Output

Omit conversational preamble. Return compact tables in this order:

1. `Resumen`: overall `PASS`, `DEGRADED`, or `FAIL`, with counts.
2. `Nodos`: hostname, status, availability, manager role, engine version.
3. `Servicios con hallazgos`: service, replicas, current task, image, finding.
4. `Dominios`: endpoint, HTTP result, classification, evidence.
5. `Traefik`: router, entrypoint, middleware, network/port, finding.
6. `Diagnóstico`: root cause, affected scope, and read-only evidence.
7. `Acciones sugeridas (NO EJECUTADAS)`: only when findings require remediation.

State the commands that were not run because of the read-only boundary when the user requested a mutation.
