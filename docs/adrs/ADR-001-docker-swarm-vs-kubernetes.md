# ADR-001: Docker Swarm over Kubernetes

**Date**: 2025-12 (initial design)  
**Status**: Accepted  
**Authors**: `<admin-user>`, `<second-user>`

---

## Context

The lab has 2 physical nodes intended to run AI/Big Data workloads. A container orchestrator is needed to manage services declaratively and reproducibly.

The options evaluated were:
1. **Docker Swarm** — Docker-native orchestrator, simple
2. **Kubernetes (K8s)** — industry standard, complex
3. **K3s** — lightweight Kubernetes for edge/lab environments

---

## Decision

**Docker Swarm was chosen.**

---

## Reasons

1. **Unnecessary operational complexity**: K8s with 2 nodes requires managing etcd, control-plane, CNI, CSI, Ingress Controller, CRDs... Swarm has all of this integrated and works out of the box.

2. **Resource overhead**: K8s consumes ~2–4 GB of RAM just for its control-plane (kube-apiserver, etcd, scheduler, controller-manager). With 32 GB per node that is wasted resources on orchestrator infrastructure rather than workloads.

3. **Sufficient for the goal**: The lab is a learning/experimentation environment, not production with SLAs. Swarm provides: HA (when more nodes are added), service discovery, overlay networks, secrets, rolling updates — everything needed.

4. **Docker Compose compatibility**: Swarm `stack.yml` files are supersets of `docker-compose.yml`. The learning curve is minimal.

5. **Simple GitOps**: `docker stack deploy -c stack.yml name` — no need to learn kubectl, Helm, kustomize, or operators.

---

## Consequences

- ✅ Initial setup in < 30 min (vs days for K8s)
- ✅ Simple operation (1 command to deploy/update)
- ✅ Simple runbooks
- ⚠️ If the lab grows to >5 nodes, evaluate migration to K3s
- ⚠️ No automatic auto-scaling (not needed in lab)
- ⚠️ No native zero-downtime rolling updates for stateful services (workaround: drain + update)
