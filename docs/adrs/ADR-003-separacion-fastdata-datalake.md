# ADR-003: Separación fastdata/datalake en master2

**Fecha**: 2025-12  
**Estado**: Aceptado

---

## Contexto

master2 tiene dos discos con características muy distintas:
- **NVMe Samsung 970 EVO 1TB**: IOPS altísimos (~3500 MB/s read, ~2300 MB/s write), capacidad limitada vs HDD
- **HDD Seagate 2TB**: IOPS bajos (rotativo), capacidad masiva, ideal para datos secuenciales/bulk

La decisión clave: ¿qué va en cada uno?

---

## Decisión

**Dos puntos de montaje con propósitos bien definidos**:

- `/srv/fastdata` (NVMe, LVM 600 GB): datos "calientes" — I/O intensivo
- `/srv/datalake` (HDD 2TB): datos masivos — bulk storage

---

## Criterio de clasificación

| Dato | Mount | Motivo |
|------|-------|--------|
| PostgreSQL data | `/srv/fastdata` | Transacciones: random I/O → NVMe imprescindible |
| n8n state | `/srv/fastdata` | Metadata y credenciales: lectura frecuente |
| Jupyter home + .venv | `/srv/fastdata` | `pip install` masivo → mucho I/O random |
| OpenSearch index | `/srv/fastdata` | Queries: random I/O en índices invertidos |
| Modelos .gguf | `/srv/datalake` | Archivos de 4–30 GB: lectura secuencial al cargar |
| Datasets ML | `/srv/datalake` | Bulk read secuencial (pandas, spark): HDD ok |
| Artifacts/outputs | `/srv/datalake` | Write once, read rarely |
| Backups | `/srv/datalake` | Bulk write, cold storage |

---

## Motivos técnicos

**PostgreSQL en HDD** degradaría >10x el rendimiento de queries con B-Tree lookups (random I/O). Con NVMe, PostgreSQL puede sostener miles de IOPS; con HDD rotativo, cae a ~100–200 IOPS.

**Modelos LLM en HDD** es aceptable porque: (1) Ollama carga el modelo en VRAM una vez, (2) la lectura es secuencial lineal (un archivo grande), (3) HDD puede hacer 120–150 MB/s en lectura secuencial — suficiente para cargar un modelo de 4 GB en ~30 segundos.

---

## Implementación

```bash
# LVM sobre NVMe
pvcreate /dev/nvme0n1
vgcreate vg0 /dev/nvme0n1
lvcreate -L 600G -n fastdata vg0
mkfs.ext4 /dev/vg0/fastdata
mount /dev/vg0/fastdata /srv/fastdata

# HDD directo
mkfs.ext4 /dev/sda  # (o usar la partición existente)
mount /dev/sda /srv/datalake
```

---

## Consecuencias

- ✅ PostgreSQL, Jupyter y OpenSearch tienen NVMe: rendimiento óptimo
- ✅ Datasets y modelos en HDD: capacidad masiva sin desperdiciar NVMe
- ✅ Estructura clara para saber dónde va cada tipo de dato
- ⚠️ 600 GB de NVMe comprometido para fastdata (quedan ~330 GB sin particionar para expansión)
- ⚠️ Si los datos "calientes" crecen, expandir el LV: `lvextend -L +200G /dev/vg0/fastdata && resize2fs /dev/vg0/fastdata`
