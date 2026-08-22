# Runbook: LLMfit capacity advisor

## Purpose

LLMfit is a node-local advisor. It detects the hardware of `master2`, scores models and reports recommendations. It does not replace Ollama and it does not serve completions.

| Interface | URL | Access |
|---|---|---|
| LLMfit dashboard | `https://aifabric.llmfit` | LAN allowlist + `llmfit_basicauth` |
| REST/OpenAPI UI | `https://aifabric.llmfit-docs` | LAN allowlist + `llmfit_basicauth` |
| Modern responsive dashboard | `https://aifabric.llmfit-mobile` | LAN allowlist + `llmfit_basicauth` |

The stack does not publish port `8787` on the host. Traefik on `master1` is the only LAN entry point. LLMfit uses the `ollama` DNS alias on the shared overlay and pins `--memory 11G` for the documented RTX 2080 Ti.

The dashboard is the upstream `llmfit-web` frontend, built from the pinned upstream commit recorded in `stacks/ai-ml/07-llmfit/build-web.sh` and served by a small Nginx service. Requests under `/api` are routed to the LLMfit process on `master2`; the browser therefore uses the same origin and does not need a separate API URL.

## Prerequisites

Create the BasicAuth secret on the Swarm manager before deploying. The value must be an htpasswd line:

```bash
htpasswd -nb <user> '<password>' | docker secret create llmfit_basicauth -
```

Confirm the external networks and node labels:

```bash
docker network inspect public internal >/dev/null
docker node inspect master2 --format '{{ index .Spec.Labels "tier" }} {{ index .Spec.Labels "gpu" }}'
```

The expected output includes `compute nvidia`.

## Deploy

Deploy Traefik first so its middleware and secret are loaded, then LLMfit:

```bash
docker stack config -c stacks/core/00-traefik/stack.yml >/dev/null
docker stack config -c stacks/ai-ml/07-llmfit/stack.yml >/dev/null
docker stack deploy -c stacks/core/00-traefik/stack.yml traefik
docker stack deploy -c stacks/ai-ml/07-llmfit/stack.yml llmfit
```

Add these names to the LAN DNS or `/etc/hosts`, pointing to the `master1` address:

```text
aifabric.llmfit
aifabric.llmfit-docs
aifabric.llmfit-mobile
```

### Certificado del laboratorio

Traefik sirve un certificado para los nombres `aifabric.*` firmado por la CA interna del laboratorio. Para que el navegador lo muestre como confiable, importa el certificado público `/srv/fastdata/traefik/aifabric-lab-root-ca.crt` en el almacén de **Entidades de certificación raíz de confianza** de cada equipo cliente.

## Validation

Run from an authorized LAN client with the BasicAuth credentials:

```bash
curl -sk -u "$LLMFIT_USER:$LLMFIT_PASSWORD" https://aifabric.llmfit/health
curl -sk -u "$LLMFIT_USER:$LLMFIT_PASSWORD" https://aifabric.llmfit/api/v1/system
curl -sk -u "$LLMFIT_USER:$LLMFIT_PASSWORD" \
  'https://aifabric.llmfit/api/v1/models/top?limit=5&min_fit=good&use_case=coding'
curl -sk -u "$LLMFIT_USER:$LLMFIT_PASSWORD" https://aifabric.llmfit-docs/openapi.yaml
```

En Swagger UI pulsa **Authorize** y usa las mismas credenciales BasicAuth. El esquema OpenAPI ya declara `basicAuth`, por lo que Swagger enviará el encabezado `Authorization` al ejecutar cada operación.

The `/api/v1/system` response must show the expected RAM, CPU and GPU for `master2`. The deployed validation reports 31.26 GB RAM, 16 CPU cores, CUDA and 11.0 GB VRAM on the RTX 2080 Ti. If a future hardware change produces different values, update the `--memory` override before using recommendations for placement decisions.

## API boundary

The public contract intentionally exposes read-only capacity and inventory endpoints. The upstream server restricts model downloads and hardware planning to localhost, so `/api/v1/download*` and `/api/v1/plan` are not advertised through the external Swagger document. Use the local CLI on `master2` for those administrative operations until a separately authenticated controller is designed.

## Operations

```bash
docker stack services llmfit
docker service logs --tail 100 llmfit_llmfit
docker service ps llmfit_llmfit --no-trunc
```

Treat `estimated_tps` as an estimate. Prefer `measured_tps` after benchmarking a model on the actual node.

## Rebuild del dashboard

Si se actualiza LLMfit, reconstruye los activos oficiales y vuelve a copiarlos al volumen del servicio:

```bash
stacks/ai-ml/07-llmfit/build-web.sh
docker stack deploy -c stacks/ai-ml/07-llmfit/stack.yml llmfit
```

La variante moderna usa el mismo código funcional de LLMfit, pero añade una barra lateral plegable y controles para mostrar u ocultar Hardware, Filters e Inspector. El rebuild se realiza desde `stacks/ai-ml/07-llmfit/web-responsive/`.
