# Engram Cloud

Engram Cloud is deployed as a single Swarm service on `master2`. It uses the
existing PostgreSQL service through the `internal` overlay and is reachable
only through Traefik at `https://aifabric.engram` from the LAN whitelist.

Engram is local-first: Codex launches the local stdio MCP process and each
Windows client keeps its SQLite database. Cloud provides project-scoped
replication and the dashboard; it is not a network MCP endpoint.

## One-time secrets (run on the Swarm manager)

Passwords must be URL-safe because the DSN is assembled by the container entrypoint.

```bash
openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32 | docker secret create pg_engram_pass -
openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48 | docker secret create engram_jwt_secret -
openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48 | docker secret create engram_cloud_token_pepper -
# Generate an individual client token and keep its copy in the approved secret store.
openssl rand -base64 72 | tr -dc 'A-Za-z0-9' | head -c 64 | docker secret create engram_cloud_token_client -
```

Create database `engram_cloud` and role `engram` in the existing PostgreSQL
instance, granting ownership only to that database. Use the value of
`pg_engram_pass` when setting the role password. Do not put credentials in Git.

## Deploy

```bash
docker stack deploy -c stacks/automation/04-engram/stack.yml engram
docker service ls --filter name=engram_engram-cloud
curl --fail --silent --show-error https://aifabric.engram/health
```

The piloto activo usa el token Bearer de `engram_cloud_token_client`, limitado por el
allowlist del servidor a `engram-pilot`. Para varios usuarios, emitir tokens
gestionados con grants por proyecto cuando se habilite el flujo de usuarios de la
versión instalada; no compartir el token entre proyectos.

## Windows client

Import the public laboratory CA once (the file is `clients/windows/aifabric-lab-root-ca-v2.crt`):

```powershell
Import-Certificate -FilePath .\aifabric-lab-root-ca-v2.crt -CertStoreLocation Cert:\CurrentUser\Root
```

Then run the installer for one or more explicitly authorized projects:

```powershell
.\engram-setup.ps1 -Project @("engram-pilot", "repo-a", "repo-b")
```

```text
ENGRAM_CLOUD_AUTOSYNC=1
ENGRAM_CLOUD_SERVER=https://aifabric.engram
ENGRAM_CLOUD_TOKEN=<contenido de /home/ogiovanni/.config/engram/client-token o del almacén seguro>
```

The script enrolls each project and stops on the first failed sync. To add a new repository, first add its exact normalized project name to `ENGRAM_CLOUD_ALLOWED_PROJECTS` on the server, redeploy, then rerun the script.

For each client, enroll and perform the first explicit sync manually if needed:

```text
engram cloud enroll engram-pilot
engram sync --cloud --project engram-pilot
```

Codex remains configured with local MCP stdio:

```toml
[mcp_servers.engram]
command = "engram"
args = ["mcp", "--tools=agent"]
```

## Backup and recovery

Run `scripts/hardening/engram-pg-backup.sh` on master2 before the existing
restic job; it creates a consistent logical dump under `/srv/fastdata/postgres-backups/engram`.
The restic job includes `/srv/fastdata/postgres-backups`; install the dump script as `/usr/local/bin/engram-pg-backup.sh` so it runs before restic. Test restoration periodically in an isolated database.
Back up the Swarm secrets and this stack through the approved protected
configuration store. Also retain local SQLite/export backups for critical
Windows clients because local SQLite remains authoritative.
