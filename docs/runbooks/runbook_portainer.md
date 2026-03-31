# Runbook de Operación: Portainer CE

## Datos de referencia

| Parámetro | Valor |
|-----------|-------|
| **Stack** | `portainer` |
| **Servicios** | `portainer_portainer` (server) + `portainer_agent` (global) |
| **Versión** | 2.39.1 |
| **Nodo server** | master1 (`tier=control`) |
| **Nodo agent** | global (master1 + master2) |
| **Persistencia** | `/srv/fastdata/portainer:/data` |
| **URL** | `https://portainer.sexydad` |
| **Auth** | Solo LAN whitelist via Traefik (auth propia de Portainer) |

---

## 1. Operación diaria

### 1.1 Verificar servicios

```bash
# En master1
docker service ls | grep portainer
docker service ps portainer_portainer
docker service ps portainer_agent
```

### 1.2 Verificar conectividad con agentes

En la UI de Portainer:
- `Environments` → debe mostrar el endpoint del Swarm
- Ambos nodos deben aparecer como `active` en `Cluster visualizer`

---

## 2. Actualizar Portainer

Al cambiar la versión en `stack.yml` (ej: 2.21.0 → 2.39.1):

```bash
# En master1, desde el repositorio:
docker stack deploy -c stacks/core/01-portainer/stack.yml portainer

# Los datos persisten en /srv/fastdata/portainer (bind mount)
# La UI mantiene configuración, usuarios, endpoints
```

> **Nota importante**: Portainer CE no tiene `--force` de upgrade automático.
> Redesplegar con la nueva imagen es suficiente (Swarm hace rolling update).

---

## 3. Diagnóstico (Incidente)

### Síntoma: UI inaccesible / 502

```bash
docker service logs portainer_portainer --tail 20

# Error común: agente no disponible
# "No active endpoints found"
# Fix: verificar que portainer_agent está corriendo en todos los nodos
docker service ps portainer_agent
```

### Síntoma: "Swarm cluster not found"

```bash
# Verificar que el agent está corriendo en el mismo nodo que el server
# El server se conecta via: tcp://tasks.agent:9001

# Ver si tasks.agent resuelve correctamente
docker exec -it $(docker ps -q -f name=portainer_portainer) \
  ping -c 2 tasks.agent
```

### Síntoma: Datos perdidos tras reinicio

```bash
# Verificar bind mount
ls -la /srv/fastdata/portainer/
# Debe contener: portainer.db, certs/, etc.

# Si el directorio está vacío → Portainer reinicia desde cero (primer setup)
# Crear el directorio si no existe:
sudo mkdir -p /srv/fastdata/portainer
sudo chown root:docker /srv/fastdata/portainer
sudo chmod 2775 /srv/fastdata/portainer
```

---

## 4. Primeras configuraciones post-upgrade

Tras un upgrade mayor de Portainer:

1. Iniciar sesión con credenciales existentes
2. Verificar en `Settings → Upgrade` que no hay migraciones pendientes
3. Revisar `Environments` → endpoint Swarm debe aparecer como `Up`
4. Revisar stacks gestionados — deben seguir visibles

---

## 5. Redespliegue completo

```bash
# En master1:
docker stack rm portainer   # ⚠️ Los datos persisten (bind mount), pero hay downtime

# Esperar 10 segundos y redesplegar:
sleep 10
docker stack deploy -c stacks/core/01-portainer/stack.yml portainer
```
