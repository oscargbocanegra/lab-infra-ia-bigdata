# Traefik — Reverse Proxy & TLS Gateway

## Overview

Traefik v2.11 is the entry point for all HTTPS traffic in the cluster. It handles TLS termination, LAN-only access enforcement, BasicAuth middleware execution, and routing to every service.

| Property | Value |
|----------|-------|
| Image | `traefik:v2.11` |
| Node | master1 (`tier=control`) |
| Ports | `80` (redirect → 443), `443` (TLS, host mode), `8082` (metrics, overlay only) |
| URL | https://traefik.sexydad/dashboard/ |
| Auth | BasicAuth (`traefik_basic_auth` secret) |

## Architecture

```
Internet / LAN
      │
   :80 (HTTP) ──→ redirect to HTTPS
      │
   :443 (HTTPS, host mode) ──→ TLS termination
      │
   Traefik router matching (Host rules)
      │
   ┌──┴────────────────────────────┐
   │  Middlewares                  │
   │  - lan-whitelist (<lan-cidr>) │
   │  - basicauth (per service)    │
   └──┬────────────────────────────┘
      │
   Overlay network (public) ──→ backend containers
```

## Why Traefik holds ALL BasicAuth secrets

Traefik executes the `@docker` middlewares for every service. Even though the auth challenge protects, say, Jupyter — it is **Traefik** that validates the password file. Therefore all `*_basicauth` secrets must be mounted into Traefik, not into the individual services.

## Networks

| Network | Purpose |
|---------|---------|
| `public` | Overlay network for all Traefik-routed services |
| `internal` | Overlay network for service-to-service communication |

## Prometheus Metrics

The metrics endpoint is on `:8082` (entrypoint `metrics`). It is **not** published to the host — only reachable from within the `internal` overlay. Prometheus scrapes it at `traefik:8082`.

## Secrets Required

| Secret | Purpose |
|--------|---------|
| `traefik_basic_auth` | htpasswd file for Traefik dashboard |
| `traefik_tls_cert` | Self-signed TLS certificate (PEM) |
| `traefik_tls_key` | Self-signed TLS private key (PEM) |
| `jupyter_basicauth_v2` | htpasswd for Jupyter instances |
| `ollama_basicauth` | htpasswd for Ollama |
| `opensearch_basicauth` | htpasswd for OpenSearch |
| `dashboards_basicauth` | htpasswd for OpenSearch Dashboards |
| `prometheus_basicauth` | htpasswd for Prometheus |
| `grafana_admin_user` | Grafana admin username |
| `grafana_admin_password` | Grafana admin password |

## Configs

| Config | Mounted at | Purpose |
|--------|------------|---------|
| `traefik_dynamic` | `/etc/traefik/dynamic.yml` | TLS config, cert/key references |

## Deploy

```bash
docker stack deploy -c stacks/core/00-traefik/stack.yml traefik
```

## Persistence

Traefik is stateless — no volumes needed. TLS cert and key are stored as Swarm Secrets.

## Logs → OpenSearch

Logs are collected automatically by Fluent Bit via the default `json-file` driver.
Index: `docker-logs-YYYY.MM.DD` | Field: `container_name = traefik_traefik`
