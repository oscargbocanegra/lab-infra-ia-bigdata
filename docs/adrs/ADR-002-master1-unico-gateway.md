# ADR-002: master1 as the Sole LAN Gateway

**Date**: 2025-12  
**Status**: Accepted

---

## Context

With 2 nodes, we need to decide where the reverse proxy (Traefik) runs to expose services to the LAN. Options:

1. Traefik on master1 only
2. Traefik on master2 only
3. Traefik on both nodes (HA with keepalived/VIP)

---

## Decision

**Traefik runs only on master1** with `mode: host` on ports :80 and :443.

---

## Reasons

1. **Certificate simplicity**: A single entry point → a single cert/key pair to manage. No need to synchronize certs between nodes.

2. **master2 free for workloads**: master2 has the GPU, the NVMe, and RAM committed to Jupyter + Ollama. Adding gateway load would take resources away from the real workloads.

3. **LAN-only does not need HA**: There is no production SLA. If master1 goes down, the lab goes into maintenance. Acceptable for a lab environment.

4. **`mode: host` on master1**: Guarantees that :443 is available directly on the master1 IP (`<master1-ip>`), without Swarm's routing mesh that can interfere with TLS certificates.

5. **A single hostname for all `/etc/hosts`**: All `*.sexydad` entries point to `<master1-ip>`. Simple.

---

## Consequences

- ✅ Simple setup, one certificate, one entry point
- ✅ master2 without proxy overhead
- ⚠️ If master1 goes down, all services are inaccessible from the LAN (accepted for lab)
- ⚠️ If HA is needed in the future, add keepalived + VIP between nodes
