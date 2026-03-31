# ADR-005: GPU vía Generic Resources en Docker Swarm

**Fecha**: 2026-01  
**Estado**: Aceptado

---

## Contexto

Docker Swarm NO tiene soporte nativo para `--gpus all` (eso es solo Docker Engine, no Swarm mode). Para usar la GPU RTX 2080 Ti de master2 desde contenedores Swarm se evaluaron:

1. **Generic Resources** — mecanismo de Swarm para recursos personalizados
2. **Node constraints custom** — solo placement, sin reserva real
3. **Sin gestión** — confiar en el runtime de NVIDIA directamente

---

## Decisión

**Usar Generic Resources** (`nvidia.com/gpu=1`) registrado en master2 + `default-runtime: nvidia` en `daemon.json`.

---

## Implementación

```json
// /etc/docker/daemon.json en master2
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
# En stack.yml de servicios con GPU:
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

## Motivos

1. **Placement correcto**: Sin Generic Resources, Swarm no sabe qué nodo tiene GPU y podría intentar correr Ollama o Jupyter en master1 (sin GPU). Con `node.labels.gpu=nvidia` + `generic_resources`, el scheduler de Swarm garantiza que el container va a master2.

2. **Reserva real**: Generic Resources hace que Swarm "reserve" la GPU — si ya está usada por un servicio, otro servicio que la requiera quedará en `Pending` en lugar de arrancar sin GPU.

3. **`default-runtime: nvidia`**: Al configurar nvidia como runtime por defecto, todos los containers en master2 tienen acceso al runtime NVIDIA sin necesidad de `--runtime=nvidia` explícito (Swarm no soporta esa opción en stack.yml).

---

## Limitaciones

- Solo funciona si `nvidia-container-toolkit` está instalado en master2 ✅
- El driver NVIDIA debe estar funcionando en el host ✅ (Driver 535.288.01)
- Solo UNA GPU registrada — si se agrega otra GPU, actualizar el valor a `2`
- `docker service inspect` muestra la reserva pero NO el uso real de VRAM (para eso: `nvidia-smi` en master2)

---

## Consecuencias

- ✅ Ollama y Jupyter tienen GPU garantizada
- ✅ Scheduler no permite conflictos de "doble asignación"
- ✅ `torch.cuda.is_available()` retorna `True` en Jupyter kernels
- ⚠️ Solo 1 GPU disponible — Ollama y Jupyter pueden competir por VRAM (11 GB total)
