# ADR-006: OpenSearch on master1 (not master2)

**Date**: 2026-02-04  
**Status**: Accepted (revisable)

---

## Context

The original design placed OpenSearch on master2 (NVMe, better I/O). However, at deployment time, master2 had the following resources committed:

```
Reserved CPUs: ~14/16 (Jupyter x2: 8, Ollama: 6)
Reserved RAM:  ~28/32 GB (Jupyter x2: 16 GB, Ollama: 12 GB)
```

Adding OpenSearch to master2 with its requirements (2 GB RAM reserved, 6 GB limit, 1 GB JVM heap) risked OOM (Out of Memory) on the node.

---

## Decision

**OpenSearch runs on master1** (`tier=control`) instead of master2.

---

## Trade-offs

| Factor | master2 (original ideal) | master1 (current decision) |
|--------|--------------------------|---------------------------|
| Disk I/O | NVMe — excellent | HDD — sufficient for lab |
| Resources | Saturated (Jupyter + Ollama) | Abundant (~26 GB free) |
| OOM risk | High | Low |
| Index performance | Better | Acceptable (lab) |

---

## Reasons

1. **For lab/experimentation**: OpenSearch workloads in this lab are simple searches, some log indexes, and basic dashboards. There are no hundreds of shards or millions of real-time documents. HDD is sufficient.

2. **Stability > performance in lab**: OOM on master2 would also bring down Jupyter and Ollama (the most valuable services in the lab). Not worth the risk.

3. **master1 has plenty of CPU**: i7-6700T with ~25 GB free RAM and ~5 CPUs available — more than enough for OpenSearch + Dashboards with reduced resources (1 CPU reserved, 1 GB heap).

---

## Review Plan

Migrate OpenSearch to master2 if:
- master2 RAM is upgraded to >64 GB
- Jupyter/Ollama resources are reduced
- Real index performance is needed (>1M docs/day)

Migration: update the constraint in `stack.yml` from `tier=control` to `tier=compute` and create `/srv/fastdata/opensearch` on master2.

---

## Consequences

- ✅ master2 stability guaranteed
- ✅ master1 with balanced load
- ⚠️ OpenSearch I/O over HDD (accepted for lab)
- ⚠️ If master1 goes down, both Traefik and OpenSearch go down (single point of failure for both)
