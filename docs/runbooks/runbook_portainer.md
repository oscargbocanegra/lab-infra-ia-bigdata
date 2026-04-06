# Runbook: Portainer CE

## Reference Data

| Parameter | Value |
|-----------|-------|
| **Stack** | `portainer` |
| **Services** | `portainer_portainer` (server) + `portainer_agent` (global) |
| **Version** | 2.39.1 |
| **Server node** | master1 (`tier=control`) |
| **Agent nodes** | global (master1 + master2) |
| **Persistence** | `/srv/fastdata/portainer:/data` |
| **URL** | `https://portainer.sexydad` |
| **Auth** | LAN-only whitelist via Traefik (Portainer's own auth) |

---

## 1. Daily Operations

### 1.1 Verify services

```bash
# On master1
docker service ls | grep portainer
docker service ps portainer_portainer
docker service ps portainer_agent
```

### 1.2 Verify agent connectivity

In the Portainer UI:
- `Environments` → should show the Swarm endpoint
- Both nodes should appear as `active` in `Cluster visualizer`

---

## 2. Update Portainer

When changing the version in `stack.yml` (e.g. 2.21.0 → 2.39.1):

```bash
# On master1, from the repository:
docker stack deploy -c stacks/core/01-portainer/stack.yml portainer

# Data persists in /srv/fastdata/portainer (bind mount)
# UI retains configuration, users, endpoints
```

> **Important note**: Portainer CE does not auto-upgrade with `--force`.
> Redeploying with the new image is sufficient (Swarm performs a rolling update).

---

## 3. Diagnostics (Incident)

### Symptom: UI inaccessible / 502

```bash
docker service logs portainer_portainer --tail 20

# Common error: agent not available
# "No active endpoints found"
# Fix: verify portainer_agent is running on all nodes
docker service ps portainer_agent
```

### Symptom: "Swarm cluster not found"

```bash
# Verify the agent is running on the same node as the server
# The server connects via: tcp://tasks.agent:9001

# Check if tasks.agent resolves correctly
docker exec -it $(docker ps -q -f name=portainer_portainer) \
  ping -c 2 tasks.agent
```

### Symptom: Data lost after reboot

```bash
# Verify bind mount
ls -la /srv/fastdata/portainer/
# Should contain: portainer.db, certs/, etc.

# If the directory is empty → Portainer restarts from scratch (first-time setup)
# Create the directory if it doesn't exist:
sudo mkdir -p /srv/fastdata/portainer
sudo chown root:docker /srv/fastdata/portainer
sudo chmod 2775 /srv/fastdata/portainer
```

---

## 4. Post-Upgrade Initial Configuration

After a major Portainer upgrade:

1. Log in with existing credentials
2. Check `Settings → Upgrade` for any pending migrations
3. Review `Environments` → the Swarm endpoint should appear as `Up`
4. Review managed stacks — they should still be visible

---

## 5. Full Redeploy

```bash
# On master1:
docker stack rm portainer   # ⚠️ Data persists (bind mount), but there is downtime

# Wait 10 seconds and redeploy:
sleep 10
docker stack deploy -c stacks/core/01-portainer/stack.yml portainer
```
