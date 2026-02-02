# Runbook de Operación: n8n (Automation)

## Datos de referencia
- **Stack**: `automation` (servicio `n8n_n8n`)
- **URL**: `https://n8n.sexydad`
- **Nodo ejecución**: `master2` (tier=compute)
- **Persistencia**: `/srv/fastdata/n8n` (en master2) → `/home/node/.n8n`
- **Dependencia**: Postgres (`postgres_postgres` en internal net)

---

## 1. Operación diaria (Healthcheck)
**Objetivo:** “¿Está vivo n8n?” en menos de 5 minutos.

### 1.1 Verificar tarea de Swarm
Ejecutar en **master1** (manager):
```bash
# Debe mostrar REPLICAS 1/1
docker service ls --filter name=n8n_n8n

# Debe mostrar CURRENT STATE: Running (hace X tiempo)
docker service ps n8n_n8n --no-trunc | head -n 5
```

### 1.2 Verificar endpoint (desde LAN)
```bash
# Debe responder 200/401 (si pide auth) o redirigir
curl -I https://n8n.sexydad
```

### 1.3 Verificar Logs recientes (Señales de vida)
```bash
# Últimas 50 líneas para ver actividad reciente
docker service logs --tail 50 n8n_n8n
```
_Resultado esperado:_ "n8n ready on 0.0.0.0, port 5678" / "Editor is now accessible".

---

## 2. Diagnóstico rápido (Incidente)
**Síntoma:** No carga la UI / el servicio se está reiniciando.

### 2.1 Detectar bucles de reinicio
```bash
# Ver historial de tareas fallidas
docker service ps n8n_n8n
```
Si ves muchos `Shutdown` o `Failed` recientes, el contenedor está crasheando al inicio.

### 2.2 Analizar logs del error
```bash
# Ver logs desde hace 10 minutos
docker service logs --since 10m n8n_n8n
```
Busca errores críticos como:
- "Connection refused" (no llega a Postgres).
- "Permission denied" (problemas de FS o DB).
- "Clean exit code: 0" (OOM killed, memoria insuficiente).

---

## 3. Recuperación (Fixes comunes)
**Objetivo:** Volver a estado sano si aparece X error.

### Caso A: Error "Permission denied for schema public" (Postgres)
**Síntoma:** Logs muestran error de DB al intentar crear tablas/migraciones.
**Causa:** El usuario `n8n` existe en Postgres pero no es dueño del esquema público.
**Fix:**
1. Conectarse a Postgres (desde manager):
   ```bash
   # Obtener ID del contenedor Postgres
   PG_TASK=$(docker ps --filter name=postgres_postgres -q | head -n1)
   
   # Ejecutar fix de permisos
   docker exec -it $PG_TASK psql -U postgres -d n8n -c "GRANT ALL ON SCHEMA public TO n8n;"
   ```
2. Reiniciar n8n para reintentar migraciones:
   ```bash
   docker service update --force n8n_n8n
   ```

### Caso B: Error de permisos en sistema de archivos (`EACCES`)
**Síntoma:** logs dicen `EACCES: permission denied, mkdir '/home/node/.n8n/...'`
**Causa:** La carpeta `/srv/fastdata/n8n` en master2 tiene owner `root` pero el contenedor corre como usuario `node` (1000).
**Fix:**
1. SSH a master2.
2. Ajustar permisos:
   ```bash
   chown -R 1000:1000 /srv/fastdata/n8n
   ```
3. Reiniciar servicio.

---

## 4. Verificación de despliegue
**Objetivo:** Confirmar que el código/infra está sincronizado.

### 4.1 Validar repo limpio
```bash
# En master1 (dentro de ~/lab-infra-ia-bigdata)
git status -sb
```
_Resultado esperado:_ `## main...` (limpio o con cambios intencionales).

### 4.2 Validar último commit aplicado
```bash
git log -1 --oneline
```
_Ejemplo:_ `fa52b61 docs(runbook): add minimal n8n runbook`

---

## Anexo: Comandos útiles

**Entrar al contenedor (debug shell):**
```bash
# Buscar en qué nodo corre
NODE=$(docker service ps n8n_n8n --filter "desired-state=running" --format "{{.Node}}")

# Buscar ID del contenedor en ese nodo (SSH requerido si es master2)
ssh $NODE "docker ps --filter name=n8n_n8n -q"
# docker exec -it <ID> /bin/sh
```
