# Runbook de Operación: Traefik (Core Proxy)

## Datos de referencia
- **Stack**: `traefik` (servicio `traefik_traefik`)
- **Node**: `master1` (tier=control)
- **Ports**: 80, 443 (Host Mode)
- **URL Dashboard**: `https://traefik.sexydad/dashboard/` (requiere BasicAuth)
- **Config**: `stacks/core/00-traefik/dynamic.yml` (se carga como Config `traefik_dynamic`)

---

## 1. Operación diaria (Healthcheck)
**Objetivo:** Verificar que el proxy recibe tráfico de internet/LAN.

### 1.1 Verificar servicio
Ejecutar en **master1**:
```bash
docker service ls --filter name=traefik_traefik
docker service ps traefik_traefik --no-trunc | head
```

### 1.2 Access Logs (Tiempo real)
Ver tráfico entrando:
```bash
docker service logs -f --tail 10 traefik_traefik
```
_Positivo:_ Ver líneas con métodos HTTP (GET/POST) y códigos de estado (200, 404, etc.).

### 1.3 Validar certificados TLS
```bash
# Verificar que sirva el certificado correcto (no te traefik default)
echo | openssl s_client -showcerts -servername traefik.sexydad -connect 192.168.80.100:443 2>/dev/null | openssl x509 -inform pem -noout -text | grep "Subject: CN"
```

---

## 2. Diagnóstico rápido (Incidente)
**Síntoma:** "No llego a ningún servicio" / "Error 404/502 Bad Gateway".

### 2.1 Verificar puertos en Host
Como usa `mode: host`, los puertos deben estar escuchando directo en master1:
```bash
sudo ss -lntp | grep -E ':(80|443|8080)'
```
_Si no aparecen:_ Traefik no está corriendo o falló el bind.

### 2.2 Error "404 Not Found" (general)
- El request llega a Traefik pero no matchea ningún Router.
- **Causa común:** El Host header no coincide (`curl -H "Host: servicio.lan" ...`) o etiqueta `traefik.http.routers...rule` mal definida en el servicio destino.
- **Fix:** Revisar logs buscando el dashboard para ver si el router aparece con errores.

### 2.3 Error "Internal Server Error / Bad Gateway"
- Traefik no puede conectar con el backend (contenedor destino).
- **Check rápido:** ¿El servicio destino y Traefik comparten la red `public` (o la que se use)?
  ```bash
  docker network inspect public
  ```

---

## 3. Recuperación
### Caso: Renovación de certificados / Cambio de dominio
Si actualizas `traefik_tls_cert` o `traefik_tls_key`, debes rotar el servicio (Swarm secrets son inmutables o requieren update).

1. Crear nuevos secrets con versión (v2):
   ```bash
   docker secret create traefik_tls_cert_v2 cert.pem
   docker secret create traefik_tls_key_v2 key.pem
   ```
2. Actualizar el stack (`stack.yml`) apuntando a los secrets `_v2`.
3. Redesplegar:
   ```bash
   docker stack deploy -c stacks/core/00-traefik/stack.yml traefik
   ```

### Caso: Dashboard inaccesible (401 Unauthorized interminable)
- Verificar el secret `traefik_basic_auth`.
- Regenerar el htpasswd (formato MD5/bcrypt/SHA1 ver doc de Traefik):
   ```bash
   htpasswd -nb admin PASSWORD
   ```

---

## 4. Anexo: Config dinámica
El archivo `dynamic.yml` maneja la configuración TLS global.
Si lo editas, debes actualizar la Config de Docker:
```bash
# Rotación de config
docker config create traefik_dynamic_v$(date +%s) stacks/core/00-traefik/dynamic.yml
# Actualizar stack apuntando a la nueva config
```
