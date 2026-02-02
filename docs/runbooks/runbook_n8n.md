## Alcance
Este runbook cubre:
1) Verificar estado del servicio n8n en Swarm
2) Ver logs recientes
3) Validar conectividad y privilegios mínimos con PostgreSQL (sin exponer secretos)

---

## Datos de referencia
- Stack: `n8n`
- Servicio: `n8n_n8n`
- URL: `https://n8n.sexydad`
- Nodo esperado (n8n): `master2` (por constraint)
- Persistencia (n8n): `/srv/fastdata/n8n` en `master2` (bind mount a `/home/node/.n8n`)
- Postgres service: `postgres_postgres`
- DB: `n8n`
- Rol/usuario: `n8n`

---

## 1) Verificar servicio (Swarm)

### 1.1 Estado y scheduling
Ejecutar EN [master1]:
```bash
docker stack ls | egrep '^n8n\s'
docker service ls | egrep 'n8n|postgres|traefik'
docker service ps n8n_n8n --no-trunc