# Runbook: Host Nodes (Setup & Reboot)

## Scope
This runbook ensures that the base operating system on each node (especially `master2`) is correctly configured to support the Docker Swarm layer.

---

## 1. Versioned Configuration (Source of Truth)
Host configuration must NOT live only in `/etc/`. It must match the versioned files in this repository:

| Real File (Host) | Source of Truth (Repo) | Purpose |
| :--- | :--- | :--- |
| `/etc/fstab` | `docs/hosts/master2/etc/fstab` | Persistent mount of `/srv/fastdata` and `/srv/datalake` |
| `/etc/docker/daemon.json` | `docs/hosts/master2/etc/docker/daemon.json` | Log rotation, cgroup driver, and Docker optimizations |

---

## 2. Post-Reboot Procedure (Startup Checklist)
**Goal:** Confirm the node recovered its functional state after a reboot.

### 2.1 Verify Storage (Critical)
If this fails, database services (Postgres, OpenSearch) **must NOT** be started.

1. **Compare active mounts against versioned fstab:**
   ```bash
   # On master2
   cat /etc/fstab
   # Compare visually with docs/hosts/master2/etc/fstab
   ```

2. **Validate mount points exist:**
   ```bash
   df -h | grep /srv
   ```
   *Expected output:*
   ```text
   /dev/mapper/vg0-fastdata  ...  /srv/fastdata
   /dev/sdb1                 ...  /srv/datalake
   ```

3. **Quick write test:**
   ```bash
   touch /srv/fastdata/write_test && rm /srv/fastdata/write_test
   touch /srv/datalake/write_test && rm /srv/datalake/write_test
   ```
   *If it fails:* The disk is Read-Only or did not mount. **STOP.**

### 2.2 Verify Docker Engine
1. **Service status:**
   ```bash
   systemctl status docker
   ```
   *Expected:* `Active: active (running)` and `enabled`.

2. **Validate applied configuration:**
   ```bash
   docker info | grep -i "logging driver"
   ```
   *Expected:* `json-file` (matches `daemon.json`).

### 2.3 Verify Network and Resolution
1. **Internal name resolution:**
   ```bash
   ping -c 2 master1
   ping -c 2 master2
   ```

---

## 3. Diagnostics and Reconstruction
**Scenario:** The node rebooted and `/srv/fastdata` is not visible.

### 3.1 Reconstructing fstab
1. Read the versioned file:
   ```bash
   cat docs/hosts/master2/etc/fstab
   ```
2. Identify real UUIDs (if hardware changed):
   ```bash
   blkid
   ```
3. Edit `/etc/fstab` on the host to reflect the intent of the versioned file, updating UUIDs if new hardware is in use.
4. Apply:
   ```bash
   mount -a
   ```

### 3.2 Docker won't start (invalid daemon.json)
1. Check for errors:
   ```bash
   journalctl -u docker --no-pager | tail -n 20
   ```
2. If the error is a config syntax issue:
   - Restore from repo:
     ```bash
     cp docs/hosts/master2/etc/docker/daemon.json /etc/docker/daemon.json
     systemctl restart docker
     ```
