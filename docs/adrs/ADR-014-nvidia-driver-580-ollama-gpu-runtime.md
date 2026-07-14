# ADR-014: NVIDIA driver 580 for Ollama GPU runtime

- **Status:** Accepted
- **Date:** 2026-07-14
- **Scope:** `master2`, Ollama, NVIDIA Exporter and Prometheus GPU telemetry

## Context

`master2` used NVIDIA driver `535.309.01`. Containers could see the RTX 2080 Ti,
but Ollama `0.32.0` rejected the driver because its CUDA libraries required
driver `550` or newer. Inference fell back to CPU and `/api/ps` reported
`size_vram=0`.

## Decision

Use Ubuntu package `nvidia-driver-580-server`, version `580.159.03`, preserving
NVIDIA Container Toolkit `1.19.0` and Docker's `nvidia` default runtime.

## Consequences

- Ollama offloads validated model layers to the RTX 2080 Ti.
- `/api/ps` reports non-zero `size_vram`.
- NVIDIA Exporter runs `1/1`.
- Prometheus reports `up{job="nvidia_gpu"} = 1` and ingests `nvidia_smi_*`.
- Future driver upgrades require a maintenance window and reboot of `master2`.
- Driver and Ollama compatibility must be validated together.

## Validation evidence

- Active driver: `580.159.03`.
- Ollama test model: `qwen3.5:4b`.
- Validated VRAM allocation: greater than zero.
- Prometheus NVIDIA metric series: greater than zero.

## Rollback

```bash
sudo apt-get install -y nvidia-driver-535-server
sudo reboot
```

After rollback, restore Ollama and NVIDIA Exporter from IaC. GPU inference for
the current Ollama version will remain unavailable until a compatible driver is
installed.
