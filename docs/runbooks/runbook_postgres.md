# Runbook de Operación: Postgres (Core DB)

## Datos de referencia
- **Stack**: `postgres` (servicio `postgres_postgres`)
- **Node**: `master2` (tier=compute, storage=primary)
- **Port**: 5432 (Host Mode: expuesto SOLO en LAN)
- **Persistencia**: `/srv/fastdata/postgres` con permisos estrictos (UID 999)
- **Databases principales**: `n8n`, `postgres`, `airflow` (futuro)

---

## 1. Operación diaria (Healthcheck)
**Objetivo:** Verificar que la base de datos acepta conexiones.

### 1.1 Verificar servicio en Swarm
Ejecutar en **master1**:
```bash
# Vista rápida (replicas)
docker service ls | egrep 'postgres_postgres|n8n_n8n|traefik_traefik|portainer_'

# Ver tasks con formato útil (estado detallado)
docker service ps postgres_postgres --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'
```

### 1.2 Access Check (vía red interna)
Crear un contenedor efímero para probar conexión real (evita usar psql del host si no está):
```bash
docker run --rm --network internal postgres:16 psql -h postgres -U postgres -c "SELECT 1;"
```
_Resultado esperado:_ `1`.

### 1.3 Access Check (vía puerto host LAN)
Desde **master1** (u otro equipo LAN), apuntando a **master2**:
```bash
# nc o telnet al puerto 5432 de master2 (asumiendo IP 192.168.80.x)
nc -zv master2 5432
```

---

## 2. Diagnóstico rápido (Incidente)
**Síntoma:** "n8n no conecta" / "Connection refused".

### 2.1 Logs del motor
```bash
docker service logs --tail 100 postgres_postgres
```
- Buscar: "FATAL: password authentication failed" (bad password).
- Buscar: "PANIC" o fallos de filesystem.

### 2.2 Verificar Persistencia
Si el servicio reinicia constantemente ("CrashLoopBackOff"), verifica el montaje en **master2**:
1. SSH a master2.
2. Verificar permisos de carpeta:
   ```bash
   ls -ld /srv/fastdata/postgres
   ```
   _Esperado:_ `drwx------ ... 999:999` (o root pero accesible por 999).
3. Verificar espacio en disco:
   ```bash
   df -h /srv/fastdata
   ```

---

## 3. Recuperación
### Caso: Reset de contraseña de superusuario
Si perdiste la clave de `postgres`:
1. Generar nuevo secret:
   ```bash
   printf "nueva_pass" | docker secret create pg_super_pass_v2 -
   ```
2. Actualizar stack (`core/02-postgres/stack.yml`) para usar `pg_super_pass_v2` y actualizar `POSTGRES_PASSWORD_FILE`.
3. Redesplegar:
   ```bash
   docker stack deploy -c stacks/core/02-postgres/stack.yml postgres
   ```
   *Nota: Esto puede requerir reiniciar el contenedor para que tome el nuevo archivo.*

### Caso: "Database is locked" / Conexiones muertas
Si hay bloqueos o demasiadas conexiones:
1. Entrar al contenedor (vía SSH a master2):
   ```bash
   CID=$(docker ps -qf name=postgres_postgres)
   docker exec -it $CID psql -U postgres
   ```
2. Matar queries bloqueantes:
   ```sql
   SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle';
   ```

---

## 4. Anexo: Gestión de Backups
(Si tienes un script de backup configurado)

### Backup manual (pg_dumpall)
Ejecutar desde **master2** (donde corre el contenedor):
```bash
CID=$(docker ps -qf name=postgres_postgres)
# Dump comprimido
docker exec $CID pg_dumpall -U postgres -c | gzip > /srv/datalake/backups/postgres_full_$(date +%F).sql.gz
```

### Restore (pg_restore)
```bash
# Descomprimir y pipear a psql
zcat backup.sql.gz | docker exec -i $CID psql -U postgres
```
