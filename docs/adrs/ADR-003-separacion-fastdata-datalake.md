# ADR-003: Separation of fastdata/datalake on master2

**Date**: 2025-12  
**Status**: Accepted

---

## Context

master2 has two disks with very different characteristics:
- **NVMe Samsung 970 EVO 1TB**: Very high IOPS (~3500 MB/s read, ~2300 MB/s write), limited capacity vs HDD
- **HDD Seagate 2TB**: Low IOPS (rotational), massive capacity, ideal for sequential/bulk data

The key decision: what goes on each?

---

## Decision

**Two mount points with well-defined purposes**:

- `/srv/fastdata` (NVMe, LVM 600 GB): "hot" data — I/O intensive
- `/srv/datalake` (HDD 2TB): massive data — bulk storage

---

## Classification Criteria

| Data | Mount | Reason |
|------|-------|--------|
| PostgreSQL data | `/srv/fastdata` | Transactions: random I/O → NVMe essential |
| n8n state | `/srv/fastdata` | Metadata and credentials: frequent reads |
| Jupyter home + .venv | `/srv/fastdata` | Massive `pip install` → heavy random I/O |
| OpenSearch index | `/srv/fastdata` | Queries: random I/O on inverted indexes |
| .gguf models | `/srv/datalake` | 4–30 GB files: sequential read on load |
| ML datasets | `/srv/datalake` | Sequential bulk read (pandas, spark): HDD ok |
| Artifacts/outputs | `/srv/datalake` | Write once, read rarely |
| Backups | `/srv/datalake` | Bulk write, cold storage |

---

## Technical Reasons

**PostgreSQL on HDD** would degrade query performance by >10x with B-Tree lookups (random I/O). With NVMe, PostgreSQL can sustain thousands of IOPS; with rotational HDD, it drops to ~100–200 IOPS.

**LLM models on HDD** is acceptable because: (1) Ollama loads the model into VRAM once, (2) the read is sequential and linear (one large file), (3) HDD can do 120–150 MB/s sequential read — sufficient to load a 4 GB model in ~30 seconds.

---

## Implementation

```bash
# LVM on NVMe
pvcreate /dev/nvme0n1
vgcreate vg0 /dev/nvme0n1
lvcreate -L 600G -n fastdata vg0
mkfs.ext4 /dev/vg0/fastdata
mount /dev/vg0/fastdata /srv/fastdata

# HDD direct
mkfs.ext4 /dev/sda  # (or use the existing partition)
mount /dev/sda /srv/datalake
```

---

## Consequences

- ✅ PostgreSQL, Jupyter and OpenSearch have NVMe: optimal performance
- ✅ Datasets and models on HDD: massive capacity without wasting NVMe
- ✅ Clear structure for knowing where each type of data goes
- ⚠️ 600 GB of NVMe committed to fastdata (~330 GB unpartitioned for expansion)
- ⚠️ If "hot" data grows, expand the LV: `lvextend -L +200G /dev/vg0/fastdata && resize2fs /dev/vg0/fastdata`
