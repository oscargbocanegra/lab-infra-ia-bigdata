# ADR-006: OpenSearch en master1 (no master2)

**Fecha**: 2026-02-04  
**Estado**: Aceptado (revisable)

---

## Contexto

El diseño original planteaba OpenSearch en master2 (NVMe, mejor I/O). Sin embargo, al momento del despliegue, master2 tenía los siguientes recursos comprometidos:

```
CPUs reservadas: ~14/16 (Jupyter x2: 8, Ollama: 6)
RAM reservada:   ~28/32 GB (Jupyter x2: 16 GB, Ollama: 12 GB)
```

Agregar OpenSearch en master2 con sus requerimientos (2 GB RAM reservados, 6 GB límite, 1 GB JVM heap) arriesgaba OOM (Out of Memory) en el nodo.

---

## Decisión

**OpenSearch corre en master1** (`tier=control`) en lugar de master2.

---

## Trade-offs

| Factor | master2 (ideal original) | master1 (decisión actual) |
|--------|--------------------------|---------------------------|
| I/O disco | NVMe — excelente | HDD — suficiente para lab |
| Recursos | Saturado (Jupyter + Ollama) | Abundante (~26 GB libre) |
| Riesgo OOM | Alto | Bajo |
| Performance índices | Mejor | Aceptable (lab) |

---

## Motivos

1. **Para lab/experimentación**: Los workloads de OpenSearch en este lab son búsquedas simples, algunos índices de logs y dashboards básicos. No hay cientos de shards ni millones de documentos en tiempo real. HDD es suficiente.

2. **Estabilidad > performance en lab**: OOM en master2 derribaría también Jupyter y Ollama (los servicios más valiosos del lab). No vale el riesgo.

3. **master1 tiene CPU de sobra**: i7-6700T con ~25 GB RAM libre y ~5 CPUs disponibles — más que suficiente para OpenSearch + Dashboards con recursos reducidos (1 CPU reservado, 1 GB heap).

---

## Plan de revisión

Migrar OpenSearch a master2 si:
- Se actualiza la RAM de master2 a >64 GB
- Se reducen los recursos de Jupyter/Ollama
- Se necesita performance de índices real (>1M docs/día)

Migración: actualizar constraint en `stack.yml` de `tier=control` a `tier=compute` y crear `/srv/fastdata/opensearch` en master2.

---

## Consecuencias

- ✅ Estabilidad de master2 garantizada
- ✅ master1 con carga balanceada
- ⚠️ I/O de OpenSearch sobre HDD (aceptado para lab)
- ⚠️ Si master1 cae, tanto Traefik como OpenSearch caen (único punto de fallo para ambos)
