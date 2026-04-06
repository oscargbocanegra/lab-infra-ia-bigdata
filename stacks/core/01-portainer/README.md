# Portainer CE — Docker Swarm Management UI

## Overview

Portainer CE provides a web UI to manage the Docker Swarm cluster, inspect services, view logs, and manage stacks, secrets, and configs.

| Property | Value |
|----------|-------|
| Image | `portainer/portainer-ce:2.39.1` |
| Agent Image | `portainer/agent:2.39.1` |
| Node (server) | master1 (`tier=control`) |
| Node (agent) | **global** — runs on ALL nodes (master1 + master2) |
| URL | https://portainer.sexydad |
| Auth | Portainer's own user management (no BasicAuth middleware) |

## Architecture

```
Browser ──→ traefik (port 443) ──→ portainer-ce (port 9000)
                                         │
                              tcp://tasks.agent:9001 (TLS skip)
                                         │
                              portainer-agent (global, all nodes)
                                    │             │
                               master1:docker  master2:docker
```

The `agent` service runs in **global mode** — one instance per node — giving Portainer visibility into both cluster members.

## Persistence

| Path (host) | Container | Purpose |
|-------------|-----------|---------|
| `/srv/fastdata/portainer` | `/data` | Portainer database, users, settings (master1) |

## Networks

| Network | Used by |
|---------|---------|
| `public` | portainer-ce (Traefik routing) |
| `internal` | portainer-ce ↔ agent communication |

## Deploy

```bash
docker stack deploy -c stacks/core/01-portainer/stack.yml portainer
```

## Pre-requisites

```bash
mkdir -p /srv/fastdata/portainer
```

## First Login

On first access, Portainer will prompt to create an admin user. Set credentials to `<admin-user> / <your-password>` for consistency with the rest of the lab.

## Logs → OpenSearch

Logs are collected automatically by Fluent Bit via the default `json-file` driver.
Index: `docker-logs-YYYY.MM.DD` | Fields: `portainer_portainer`, `portainer_agent`
