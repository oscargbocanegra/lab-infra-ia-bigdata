# ADR-004: OpenSearch Security Plugin Disabled

**Date**: 2026-01  
**Status**: Accepted (revisable if the lab is opened to the internet)

---

## Context

OpenSearch includes a security plugin that provides:
- TLS between cluster nodes
- Internal basic authentication (users/roles in its own DB)
- RBAC at the index level
- Auditing

In a single-node environment, most of these features are overhead with no real value.

---

## Decision

**`DISABLE_SECURITY_PLUGIN=true`** in the OpenSearch stack.

---

## Reasons

1. **No real value in single-node**: TLS between nodes is irrelevant with 1 node. Index RBAC is configuration overhead for a learning lab.

2. **High complexity**: The plugin requires generating internal certificates for the admin API, configuring `opensearch.yml` with cert paths, generating password hashes with a specific tool... All of this on top of Traefik (which already has TLS) and BasicAuth (which already provides auth).

3. **Sufficient defense in depth for lab**:
   - Layer 1: LAN-only (not exposed to the internet)
   - Layer 2: Traefik `lan-whitelist` (`<lan-cidr>` only)
   - Layer 3: BasicAuth on Traefik for the external endpoint
   - Layer 4: `internal` overlay network for service-to-service access (no network auth but no LAN exposure)

4. **Consistent with lab philosophy**: Reduce setup friction to maximize learning time.

---

## Accepted Risk

- If someone on the LAN has direct access to master1:9200 (bypassing Traefik), they have unauthenticated access to OpenSearch.
- Mitigation: direct access requires being on the LAN + knowing the port + Traefik is the only published endpoint.

---

## When to Review This Decision

- If the lab is exposed to a broader corporate network
- If indexes with real sensitive data are added
- If OpenSearch is connected to a production pipeline
