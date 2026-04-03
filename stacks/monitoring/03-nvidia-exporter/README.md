# NVIDIA GPU Exporter Stack

> Phase 6.2 — Observability | Lab Infra AI + Big Data

## Overview

Exposes NVIDIA GPU metrics in Prometheus format for the RTX 2080 Ti on the compute node (master2).  
This is a separate stack from the main Prometheus stack to isolate the GPU device access requirements.

**Services:**

| Service | Image | Node | Purpose |
|---|---|---|---|
| `nvidia-exporter` | `utkuozdemir/nvidia_gpu_exporter:1.4.1` | compute (master2) | GPU metrics exporter |

---

## Metrics Exposed

The exporter runs `nvidia-smi` on a configurable interval and exposes:

| Metric | Description |
|---|---|
| `nvidia_smi_utilization_gpu_ratio` | GPU compute utilization (0–1) |
| `nvidia_smi_memory_used_bytes` | VRAM used (bytes) |
| `nvidia_smi_memory_free_bytes` | VRAM free (bytes) |
| `nvidia_smi_memory_total_bytes` | VRAM total (bytes) |
| `nvidia_smi_temperature_gpu` | GPU temperature (°C) |
| `nvidia_smi_power_draw_watts` | Power draw (W) |
| `nvidia_smi_fan_speed_ratio` | Fan speed (0–1) |
| `nvidia_smi_clocks_current_graphics_clock_hz` | Current GPU clock (Hz) |

**Prometheus scrape target:** `nvidia-exporter:9835` (via Docker overlay DNS)

---

## Hardware

| Component | Details |
|---|---|
| GPU | NVIDIA GeForce RTX 2080 Ti |
| VRAM | 11 GB GDDR6 |
| CUDA | 12.2 |
| Driver | 535.x |
| Node | compute (master2) |

---

## Pre-requisites

The following must be in place on master2 **before** deploying this stack:

1. **NVIDIA drivers** — driver 535.x (already confirmed installed)
2. **nvidia-container-toolkit** — required for Docker GPU device access

   ```bash
   # Verify on master2:
   nvidia-smi
   # Should show GPU info and driver version

   # Verify container toolkit:
   nvidia-container-cli --version
   ```

3. **Swarm node label** — `gpu=nvidia` (already set on master2)

   ```bash
   # Verify:
   docker node inspect master2 --format '{{ .Spec.Labels }}'
   # Should include: map[gpu:nvidia tier:compute]
   ```

4. **Docker daemon GPU resource config** on master2 — `/etc/docker/daemon.json` must include:

   ```json
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

   After editing, restart Docker: `sudo systemctl restart docker`  
   Then rejoin the Swarm or wait for Swarm to re-register the node resources.

---

## Deploy

```bash
# From the Swarm manager node (master1), with the repo cloned/updated:
docker stack deploy -c stacks/monitoring/03-nvidia-exporter/stack.yml nvidia-exporter
```

Verify:

```bash
docker stack services nvidia-exporter
# Expected: 1/1 running on the compute node

# Confirm it's on master2:
docker service ps nvidia-exporter_nvidia-exporter
```

Test the metrics endpoint from inside the cluster:

```bash
# From any container on the internal overlay network:
curl http://nvidia-exporter:9835/metrics | head -20
```

---

## Useful Commands

```bash
# Check service status
docker stack services nvidia-exporter

# View logs
docker service logs -f nvidia-exporter_nvidia-exporter

# Remove stack
docker stack rm nvidia-exporter
```

---

## Why a Separate Stack?

The container needs access to GPU device files (`/dev/nvidia0`, `/dev/nvidiactl`, etc.) via the `nvidia-container-runtime`. Bundling this into the main Prometheus stack would require giving **all** services in that stack elevated device access. By isolating it in its own stack, only this one container carries the GPU resource requirement — cleaner and more secure.

---

## Resource Usage (approximate)

| Service | CPU reservation | RAM reservation |
|---|---|---|
| nvidia-exporter | 0.05 CPU | 32 MiB |
