# Runbook: Traefik (Core Proxy)

## Reference Data
- **Stack**: `traefik` (service `traefik_traefik`)
- **Node**: `master1` (tier=control)
- **Ports**: 80, 443 (Host Mode)
- **Dashboard URL**: `https://traefik.sexydad/dashboard/` (requires BasicAuth)
- **Config**: `stacks/core/00-traefik/dynamic.yml` (loaded as Docker Config `traefik_dynamic`)

---

## 1. Daily Operations (Healthcheck)
**Goal:** Verify that the proxy is receiving traffic.

### 1.1 Verify service
Run on **master1**:
```bash
# Quick view (replicas)
docker service ls | egrep 'postgres_postgres|n8n_n8n|traefik_traefik|portainer_'

# Tasks with useful format (detailed state)
docker service ps traefik_traefik --no-trunc \
  --format 'table {{.ID}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'
```

### 1.2 Access Logs (Real-time)
Watch incoming traffic:
```bash
docker service logs -f --tail 10 traefik_traefik
```
_Positive sign:_ Lines with HTTP methods (GET/POST) and status codes (200, 404, etc.).

### 1.3 Validate TLS certificates
```bash
# Verify the correct certificate is served (not the Traefik default)
echo | openssl s_client -showcerts -servername traefik.sexydad -connect <master1-ip>:443 2>/dev/null | openssl x509 -inform pem -noout -text | grep "Subject: CN"
```

---

## 2. Quick Diagnostics (Incident)
**Symptom:** "Can't reach any service" / "Error 404/502 Bad Gateway".

### 2.1 Verify ports on Host
Since it uses `mode: host`, ports must be listening directly on master1:
```bash
sudo ss -lntp | grep -E ':(80|443|8080)'
```
_If not visible:_ Traefik is not running or the bind failed.

### 2.2 Error "404 Not Found" (generic)
- The request reaches Traefik but doesn't match any Router.
- **Common cause:** The Host header doesn't match (`curl -H "Host: service.lan" ...`) or the `traefik.http.routers...rule` label is misconfigured on the target service.
- **Fix:** Check logs and the dashboard to see if the router appears with errors.

### 2.3 Error "Internal Server Error / Bad Gateway"
- Traefik can't connect to the backend (target container).
- **Quick check:** Are the target service and Traefik on the same `public` network?
  ```bash
  docker network inspect public
  ```

---

## 3. Recovery
### Case: Certificate renewal / Domain change
If you update `traefik_tls_cert` or `traefik_tls_key`, the service must be rotated (Swarm secrets are immutable or require an update).

1. Create new secrets with a version suffix (v2):
   ```bash
   docker secret create traefik_tls_cert_v2 cert.pem
   docker secret create traefik_tls_key_v2 key.pem
   ```
2. Update the stack (`stack.yml`) to point to the `_v2` secrets.
3. Redeploy:
   ```bash
   docker stack deploy -c stacks/core/00-traefik/stack.yml traefik
   ```

### Case: Dashboard inaccessible (401 Unauthorized loop)
- Verify the `traefik_basic_auth` secret.
- Regenerate the htpasswd (MD5/bcrypt/SHA1 format — see Traefik docs):
   ```bash
   htpasswd -nb admin PASSWORD
   ```

---

## 4. Appendix: Dynamic Config
The `dynamic.yml` file manages global TLS configuration.
If you edit it, you must update the Docker Config:
```bash
# Config rotation
docker config create traefik_dynamic_v$(date +%s) stacks/core/00-traefik/dynamic.yml
# Update the stack to point to the new config
```
