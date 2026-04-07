# Runbook: CI/CD Pipeline

> Phase 10 — GitHub Actions CI + CD (self-hosted runner on master1)

---

## Overview

Two workflows handle the full automation pipeline:

| Workflow | File | Trigger | Runner |
|---|---|---|---|
| CI — Lint + Tests | `.github/workflows/ci.yml` | push / PR (any branch) | GitHub cloud (`ubuntu-latest`) |
| CD — Build + Deploy | `.github/workflows/deploy.yml` | push to `main` | self-hosted (`master1`) |

---

## Required GitHub Secrets

Go to: **GitHub repo → Settings → Secrets and variables → Actions → New repository secret**

| Secret name | Value |
|---|---|
| `DOCKER_USERNAME` | `giovannotti` |
| `DOCKER_TOKEN` | Docker Hub Personal Access Token (read/write) |

**How to create a Docker Hub token:**
1. Log in to [hub.docker.com](https://hub.docker.com)
2. Account Settings → Security → New Access Token
3. Permissions: Read & Write
4. Copy the token and save as `DOCKER_TOKEN` in GitHub Secrets

---

## Self-Hosted Runner Installation (master1)

The deploy workflow requires a self-hosted runner installed on **master1** (`192.168.80.100`).

### Step 1 — Get the registration token

1. Go to the GitHub repo
2. **Settings → Actions → Runners → New self-hosted runner**
3. Select **Linux** / **x64**
4. Copy the `--token` value shown (it expires in 1 hour)

### Step 2 — Install the runner on master1

```bash
ssh <user>@192.168.80.100

# Create runner directory
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download the runner (check https://github.com/actions/runner/releases for latest version)
curl -o actions-runner-linux-x64-2.322.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.322.0/actions-runner-linux-x64-2.322.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.322.0.tar.gz

# Configure (use the token from Step 1)
./config.sh \
  --url https://github.com/oscargbocanegra/lab-infra-ia-bigdata \
  --token <TOKEN_FROM_GITHUB> \
  --name master1 \
  --labels self-hosted,linux,x64 \
  --work _work

# Install and start as a systemd service
sudo ./svc.sh install
sudo ./svc.sh start
```

### Step 3 — Verify the runner is online

Back in GitHub: **Settings → Actions → Runners** — the runner should show **Idle** status.

### Runner management commands

```bash
# Check service status
sudo ./svc.sh status

# Stop runner
sudo ./svc.sh stop

# Start runner
sudo ./svc.sh start

# View runner logs
journalctl -u actions.runner.oscargbocanegra-lab-infra-ia-bigdata.master1 -f
```

---

## CI Workflow Details (ci.yml)

### Jobs

```
lint          → ruff check + ruff format --check
test-rag-api  → pytest tests/rag_api/ (Python 3.11)
test-agent    → pytest tests/agent/   (Python 3.12)
```

All jobs run in parallel. They do NOT need Docker, Qdrant, Postgres, or any running service — everything is mocked.

### Local equivalent

```bash
# Install tools
pip install ruff pytest pytest-asyncio httpx

# Run lint
ruff check .
ruff format --check .

# Run tests
pytest tests/rag_api/ -v
pytest tests/agent/ -v
```

---

## CD Workflow Details (deploy.yml)

### Steps

1. **Checkout** code on master1
2. **Compute tags** — `latest` + `sha-<git-short>` (e.g. `sha-a1b2c3d`)
3. **Build** `giovannotti/lab-rag-api` image (with `--cache-from` for speed)
4. **Build** `giovannotti/lab-agent` image
5. **Docker login** to Docker Hub with `DOCKER_USERNAME` + `DOCKER_TOKEN`
6. **Push** both images × 2 tags
7. **Deploy** `rag-api` stack: `docker stack deploy -c stacks/ai-ml/04-rag-api/stack.yml rag-api --with-registry-auth --prune`
8. **Deploy** `agent` stack: `docker stack deploy -c stacks/ai-ml/06-agent/stack.yml agent --with-registry-auth --prune`
9. **Wait** 20 seconds for containers to start
10. **Health check** both services via `curl --resolve` (handles self-signed TLS cert)
11. **Step Summary** — prints image tags and service URLs to GitHub Actions summary page

### Image tagging strategy

Every successful deploy produces two tags per image:
- `:latest` — always points to the newest build
- `:sha-XXXXXXX` — immutable, traceable to a specific commit (7-char Git SHA)

### Rollback

To roll back to a previous image version:

```bash
ssh <user>@192.168.80.100

# Find previous sha tag in Docker Hub or git log
# Then update the stack manually:
docker service update --image giovannotti/lab-rag-api:sha-<previous-sha> rag-api_rag-api
docker service update --image giovannotti/lab-agent:sha-<previous-sha>   agent_agent
```

---

## Troubleshooting

### CI fails: `ruff` lint error

```bash
# Fix locally before pushing
ruff check . --fix
ruff format .
```

### CI fails: `pytest` import error

Most likely a missing mock. Check `tests/rag_api/conftest.py` or `tests/agent/conftest.py`. The lifespan functions (`init_qdrant`, `init_postgres`, `init_minio`) MUST be patched before the app is imported.

### CD fails: Docker Hub push denied

1. Check that `DOCKER_TOKEN` secret is set and not expired
2. Verify the token has **Read & Write** permissions on Docker Hub
3. Verify Docker Hub repos exist: `giovannotti/lab-rag-api` and `giovannotti/lab-agent`

### CD fails: self-hosted runner offline

```bash
ssh <user>@192.168.80.100
cd ~/actions-runner
sudo ./svc.sh status
sudo ./svc.sh start
```

### CD fails: health check timeout

The health check uses `--resolve "hostname:443:127.0.0.1"` because the runner runs ON master1. If Traefik is not routing correctly:

```bash
# On master1, test directly
curl -k --resolve "rag-api.sexydad:443:127.0.0.1" https://rag-api.sexydad/health
curl -k --resolve "agent.sexydad:443:127.0.0.1"   https://agent.sexydad/health
```

### Check running services

```bash
docker stack services rag-api
docker stack services agent
docker service logs rag-api_rag-api --tail 50
docker service logs agent_agent     --tail 50
```

---

## Docker Hub Repositories

| Image | URL |
|---|---|
| `giovannotti/lab-rag-api` | https://hub.docker.com/r/giovannotti/lab-rag-api |
| `giovannotti/lab-agent` | https://hub.docker.com/r/giovannotti/lab-agent |

---

## Related Files

| File | Purpose |
|---|---|
| `.github/workflows/ci.yml` | Lint + test workflow (GitHub cloud) |
| `.github/workflows/deploy.yml` | Build + push + deploy workflow (self-hosted) |
| `pyproject.toml` | ruff + pytest configuration |
| `tests/rag_api/` | Unit tests for lab-rag-api |
| `tests/agent/` | Unit tests for lab-agent |
| `stacks/ai-ml/04-rag-api/stack.yml` | RAG API Swarm stack |
| `stacks/ai-ml/06-agent/stack.yml` | Agent Swarm stack |
