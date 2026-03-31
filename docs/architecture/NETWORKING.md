# Networking — Redes, Dominios y Flujo de Tráfico

> Actualizado: 2026-03-30

---

## Topología de red

```
                         INTERNET
                            ✗  (sin exposición pública)
                            │
                   ┌────────┴────────┐
                   │   Router LAN    │
                   │ 192.168.80.1    │
                   └────────┬────────┘
                            │ Ethernet (cableado)
              ┌─────────────┴──────────────┐
              │                            │
    ┌─────────▼──────────┐      ┌──────────▼──────────┐
    │    master1         │      │    master2          │
    │ 192.168.80.100     │      │ 192.168.80.X        │
    │ Swarm Manager      │      │ Swarm Worker        │
    └─────────┬──────────┘      └──────────┬──────────┘
              │                            │
              └──────────┬─────────────────┘
                         │
              Docker Swarm Overlay Networks
              ┌──────────┴──────────────┐
              │                         │
         ┌────▼─────┐           ┌───────▼──────┐
         │  public  │           │   internal   │
         │ overlay  │           │   overlay    │
         │ (ingress)│           │  (backend)   │
         └──────────┘           └──────────────┘
```

---

## Redes Docker Swarm

### Red `public` (overlay, attachable)

**Propósito**: Comunicación entre Traefik y los backends de cada servicio.

```bash
# Creación inicial
docker network create --driver overlay --attachable public
```

| Parámetro | Valor |
|-----------|-------|
| Driver | overlay |
| Scope | swarm |
| Attachable | sí |
| Cifrado | sí (overlay automático) |

**Servicios conectados**:
- traefik (bidireccional: recibe requests LAN, enruta a backends)
- portainer
- n8n
- jupyter-ogiovanni / jupyter-odavid
- ollama
- opensearch / dashboards

### Red `internal` (overlay, attachable)

**Propósito**: Comunicación privada service-to-service. Sin exposición a Traefik ni LAN directa.

```bash
# Creación inicial
docker network create --driver overlay --attachable internal
```

| Parámetro | Valor |
|-----------|-------|
| Driver | overlay |
| Scope | swarm |
| Attachable | sí |
| Cifrado | sí |

**Servicios conectados**:
- postgres (accedido por n8n, airflow)
- n8n (accede a postgres, opensearch)
- traefik (necesita conocer la IP de backends)
- ollama (accedido por jupyter internamente)
- opensearch (accedido por dashboards, jupyter, n8n)
- portainer-agent

---

## Dominio interno: `*.sexydad`

Todos los servicios se publican bajo el dominio `.sexydad` (dominio interno de la LAN).

**Resolución**: No hay DNS formal. Se configura por `/etc/hosts` en cada cliente:

```
# /etc/hosts (Windows/Linux/Mac del usuario)
192.168.80.100  traefik.sexydad
192.168.80.100  portainer.sexydad
192.168.80.100  n8n.sexydad
192.168.80.100  opensearch.sexydad
192.168.80.100  dashboards.sexydad
192.168.80.100  ollama.sexydad
192.168.80.100  jupyter-ogiovanni.sexydad
192.168.80.100  jupyter-odavid.sexydad
```

> Todos apuntan a `192.168.80.100` (master1) porque **Traefik actúa como único ingress**.

**Próximo paso recomendado (mejora)**: Configurar un DNS local en el router para wildcard `*.sexydad → 192.168.80.100` y eliminar la necesidad de editar `/etc/hosts` en cada cliente.

---

## Mapa de puertos

### master1 — Puertos publicados

| Puerto | Protocolo | Servicio | Mode |
|--------|-----------|---------|------|
| 80 | TCP | Traefik (→ redirect HTTPS) | host |
| 443 | TCP | Traefik (HTTPS/TLS) | host |

> Traefik usa `mode: host` para garantizar que los puertos se abran directamente en master1, NO en el routing mesh de Swarm.

### master2 — Puertos publicados

| Puerto | Protocolo | Servicio | Mode |
|--------|-----------|---------|------|
| 5432 | TCP | PostgreSQL | host |

> Postgres usa `mode: host` para acceso directo desde DBeaver/clientes SQL en la LAN.

### Puertos internos (solo overlay `internal`)

| Puerto | Servicio | Accedido por |
|--------|---------|--------------|
| 5678 | n8n | Traefik (via public) |
| 9200 | OpenSearch | Traefik, Jupyter, n8n |
| 5601 | OpenSearch Dashboards | Traefik |
| 11434 | Ollama | Traefik, Jupyter |
| 8888 | JupyterLab (por usuario) | Traefik |
| 9000 | Portainer | Traefik |
| 9001 | Portainer Agent | Portainer server |

---

## Flujo de un request HTTP (ejemplo: n8n)

```
Cliente LAN (192.168.80.50)
  │
  │  GET https://n8n.sexydad
  │  → DNS lookup: n8n.sexydad → 192.168.80.100 (por /etc/hosts)
  │  → TCP connect to 192.168.80.100:443
  ▼
Traefik (master1:443, mode: host)
  │
  │  1. TLS handshake (self-signed cert de secret traefik_tls_cert)
  │  2. Middleware: lan-whitelist.check(192.168.80.50) → ✅ en 192.168.80.0/24
  │  3. Router match: Host(`n8n.sexydad`) → servicio n8n
  │  4. Load balance hacia n8n container (vía overlay public)
  ▼
n8n container (master2, overlay public)
  │
  │  Response HTTP 200
  ▼
Cliente LAN
```

---

## Comunicación interna (service-to-service)

```
n8n → postgres (overlay internal)
  Service DNS: postgres_postgres → IP del container de Postgres
  Puerto: 5432
  Sin autenticación de red (password via secret)

opensearch-dashboards → opensearch (overlay internal)
  Service DNS: opensearch_opensearch (o hostname "opensearch")
  Puerto: 9200
  Sin auth (plugin de seguridad disabled)

jupyter → ollama (overlay internal)
  URL: http://ollama:11434
  Sin auth (solo red interna — no expuesto a LAN sin Traefik)
  
jupyter → opensearch (overlay internal)  
  URL: http://opensearch:9200
  Sin auth (solo red interna)
```

---

## Consideraciones de firewall

**Estado actual**: No hay firewall explícito configurado (UFW/iptables) más allá del routing por Traefik.

**Recomendación pendiente** (ver ROADMAP):
```bash
# master1: solo permitir entrada en :80, :443 y SSH
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from 192.168.80.0/24   # LAN completa para Swarm internals
ufw enable

# master2: solo SSH + Swarm + postgres LAN
ufw allow 22/tcp
ufw allow from 192.168.80.0/24   # LAN para Swarm + Postgres :5432
ufw enable
```
