# ADR-005: GPU via Generic Resources in Docker Swarm

**Date**: 2026-01  
**Status**: Accepted

---

## Context

Docker Swarm does NOT have native support for `--gpus all` (that is Docker Engine only, not Swarm mode). To use the RTX 2080 Ti GPU on master2 from Swarm containers, the following options were evaluated:

1. **Generic Resources** — Swarm mechanism for custom resources
2. **Custom node constraints** — placement only, no real reservation
3. **No management** — rely on the NVIDIA runtime directly

---

## Decision

**Use Generic Resources** (`nvidia.com/gpu=1`) registered on master2 + `default-runtime: nvidia` in `daemon.json`.

---

## Implementation

```json
// /etc/docker/daemon.json on master2
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "node-generic-resources": ["nvidia.com/gpu=1"]
}
```

```yaml
# In stack.yml for GPU-enabled services:
deploy:
  placement:
    constraints:
      - node.labels.gpu == nvidia
  resources:
    reservations:
      generic_resources:
        - discrete_resource_spec:
            kind: 'nvidia.com/gpu'
            value: 1
```

---

## Reasons

1. **Correct placement**: Without Generic Resources, Swarm does not know which node has a GPU and might try to run Ollama or Jupyter on master1 (no GPU). With `node.labels.gpu=nvidia` + `generic_resources`, the Swarm scheduler guarantees the container goes to master2.

2. **Real reservation**: Generic Resources causes Swarm to "reserve" the GPU — if it is already in use by one service, another service requiring it will remain in `Pending` instead of starting without a GPU.

3. **`default-runtime: nvidia`**: By configuring nvidia as the default runtime, all containers on master2 have access to the NVIDIA runtime without needing explicit `--runtime=nvidia` (Swarm does not support that option in `stack.yml`).

---

## Limitations

- Only works if `nvidia-container-toolkit` is installed on master2 ✅
- The NVIDIA driver must be running on the host ✅ (Driver 535.288.01)
- Only ONE GPU registered — if another GPU is added, update the value to `2`
- `docker service inspect` shows the reservation but NOT the actual VRAM usage (for that: `nvidia-smi` on master2)

---

## Consequences

- ✅ Ollama and Jupyter have guaranteed GPU
- ✅ Scheduler prevents double-assignment conflicts
- ✅ `torch.cuda.is_available()` returns `True` in Jupyter kernels
- ⚠️ Only 1 GPU available — Ollama and Jupyter may compete for VRAM (11 GB total)
