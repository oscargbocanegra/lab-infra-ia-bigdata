# Runbook de Operación: Hosts Físicos (Setup & Reboot)

## Alcance
Este runbook asegura que el sistema operativo base de los nodos (especialmente `master2`) está configurado correctamente para soportar la capa de Docker Swarm.

---

## 1. Configuración Versionada (Fuente de Verdad)
La configuración del host **NO** debe vivir solo en `/etc/`. Debe coincidir con los archivos versionados en este repositorio:

| Archivo Real (Host) | Fuente de Verdad (Repo) | Propósito |
| :--- | :--- | :--- |
| `/etc/fstab` | `docs/hosts/master2/etc/fstab` | Montaje persistente de `/srv/fastdata` y `/srv/datalake` |
| `/etc/docker/daemon.json` | `docs/hosts/master2/etc/docker/daemon.json` | Rotación de logs, cgroup driver y optimizaciones de Docker |

---

## 2. Procedimiento Post-Reboot (Manual de Arranque)
**Objetivo:** Confirmar que el nodo recuperó su estado funcional tras un reinicio.

### 2.1 Verificar Almacenamiento (Crítico)
Si esto falla, los servicios de base de datos (Postgres, OpenSearch) **NO** deben arrancar.

1. **Comparar montajes activos con fstab versionado:**
   ```bash
   # En master2
   cat /etc/fstab
   # Comparar visualmente con docs/hosts/master2/etc/fstab
   ```

2. **Validar existencia de puntos de montaje:**
   ```bash
   df -h | grep /srv
   ```
   *Salida esperada:*
   ```text
   /dev/mapper/vg0-fastdata  ...  /srv/fastdata
   /dev/sdb1                 ...  /srv/datalake
   ```

3. **Prueba de escritura rápida:**
   ```bash
   touch /srv/fastdata/write_test && rm /srv/fastdata/write_test
   touch /srv/datalake/write_test && rm /srv/datalake/write_test
   ```
   *Si falla:* El disco está Read-Only o no montó. **STOP.**

### 2.2 Verificar Docker Engine
1. **Estado del servicio:**
   ```bash
   systemctl status docker
   ```
   *Esperado:* `Active: active (running)` y `enabled`.

2. **Validar configuración aplicada:**
   ```bash
   docker info | grep -i "logging driver"
   ```
   *Esperado:* `json-file` (coincide con `daemon.json`).

### 2.3 Verificar Red y Resolución
1. **Nombres internos:**
   ```bash
   ping -c 2 master1
   ping -c 2 master2
   ```

---

## 3. Diagnóstico y Reconstrucción
**Escenario:** El nodo reinició y `/srv/fastdata` no aparece.

### 3.1 Reconstrucción de fstab
1. Leer el archivo versionado:
   ```bash
   cat docs/hosts/master2/etc/fstab
   ```
2. Identificar UUIDs reales (si cambiaron discos):
   ```bash
   blkid
   ```
3. Editar `/etc/fstab` en el host para reflejar la intención del archivo versionado, actualizando los UUIDs si es hardware nuevo.
4. Aplicar:
   ```bash
   mount -a
   ```

### 3.2 Docker no inicia (daemon.json inválido)
1. Chequear errores:
   ```bash
   journalctl -u docker --no-pager | tail -n 20
   ```
2. Si el error es de sintaxis en config:
   - Restaurar desde repo:
     ```bash
     cp docs/hosts/master2/etc/docker/daemon.json /etc/docker/daemon.json
     systemctl restart docker
     ```

