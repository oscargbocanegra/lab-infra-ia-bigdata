# OpenMetadata 1.4 — Data Catalog & Governance

Part of **Phase 9A — Data Governance**.

OpenMetadata provides centralized metadata management, data lineage tracking, and data quality
integration for all data assets in this lab (MinIO, Postgres, Airflow).

---

## Architecture

```
MinIO (s3://)      ──┐
Postgres           ──┼──► OpenMetadata Server ──► OpenSearch (search index)
Airflow Pipelines  ──┘         │
                               │
                          MySQL (metadata store)
```

- **Metadata store**: MySQL 8 (dedicated container, local to stack)
- **Search index**: shared OpenSearch instance on `lab-network`
- **UI**: `https://openmetadata.sexydad` via Traefik
- **Node**: master1 (`node.labels.role == manager`)
- **Persistence**: `/srv/fastdata/openmetadata/{mysql,server}`

---

## Prerequisites

1. OpenSearch stack running: `docker stack ls | grep opensearch`
2. Docker Swarm secrets created (see below)
3. Persistence directories created on master1

---

## Deploy

### 1. Run the setup script (first time only, via SSH on master1)

```bash
sudo bash scripts/governance/setup-governance.sh
```

This script:
- Creates 3 Docker Swarm secrets interactively (`om_admin_password`, `om_mysql_root_password`, `om_mysql_user_password`)
- Creates `/srv/fastdata/openmetadata/mysql` on master1
- Creates MinIO governance bucket structure (`bronze/`, `silver/`, `gold/`, `governance/`)
- Writes a base Great Expectations config under `/srv/fastdata/airflow/great_expectations/`

> The `openmetadata-env.sh` file in this directory is bundled as a Docker Config
> automatically by Docker Swarm when the stack is deployed — no manual `docker config create` needed.

### 2. Deploy from Portainer

In the Portainer UI:

```
Stacks → Add Stack → Repository
  Repository URL : https://github.com/<org>/lab-infra-ia-bigdata
  Compose path   : stacks/data/13-openmetadata/stack.yml
  Branch         : main
```

Or from CLI on master1:

```bash
docker stack deploy -c stacks/data/13-openmetadata/stack.yml openmetadata
```

### 3. Bootstrap the database (FIRST TIME ONLY)

Run in a `screen` session — takes 3-5 minutes:

```bash
screen -S om-bootstrap
docker run --rm --network internal \
  -e DB_HOST=openmetadata-mysql \
  -e DB_PORT=3306 \
  -e DB_SCHEME=mysql \
  -e DB_USER=openmetadata \
  -e DB_USER_PASSWORD=<om_mysql_user_password> \
  -e OM_DATABASE=openmetadata_db \
  -e DB_DRIVER_CLASS=com.mysql.cj.jdbc.Driver \
  openmetadata/server:1.4.7 \
  ./bootstrap/bootstrap_storage.sh migrate-all
```

After bootstrap completes, force-restart the server:

```bash
docker service update --force openmetadata_openmetadata-server
```

### 4. Verify

```bash
docker stack services openmetadata
docker service logs openmetadata_openmetadata-server --tail 50
curl -sk https://openmetadata.sexydad/api/v1/system/config
```

### 5. Access

- **URL**: `https://openmetadata.sexydad`
- **Default credentials**: `admin` / `<the password you set in step 1>`

---

## Connectors (configure via UI after deploy)

| Service | Type | Connection |
|---------|------|------------|
| Postgres (lab) | Database | `postgres:5432` (internal Swarm DNS) |
| MinIO | Object Storage | `http://minio:9000` (internal Swarm DNS) |
| Airflow | Pipeline | `http://airflow-webserver:8080` |

Navigate to **Settings → Services** to add each connector.

---

## Secrets

| Secret name | Used by |
|-------------|---------|
| `om_admin_password` | OpenMetadata initial admin user |
| `om_mysql_root_password` | MySQL root account |
| `om_mysql_user_password` | MySQL `openmetadata` app user |

---

## Data Quality Integration

Great Expectations DAGs in Airflow publish quality results back to OpenMetadata
via the OM Python SDK. This enables quality scores to appear inline on dataset pages.

DAGs:
- `governance_bronze_validate` — validates raw files on ingestion
- `governance_silver_validate` — validates curated tables before gold promotion

---

## Persistence

| Path | Contents |
|------|----------|
| `/srv/fastdata/openmetadata/mysql` | MySQL 8 data directory |
| `/srv/fastdata/openmetadata/server` | OpenMetadata server state |

Both paths are on master1's NVMe (`/srv/fastdata`).

---

## Troubleshooting

**Server doesn't start (exits immediately):**
```bash
docker service logs openmetadata_openmetadata-server --tail 100
# Common cause: MySQL not ready yet — wait 60 s and re-deploy
docker service update --force openmetadata_openmetadata-server
```

**OpenSearch connection refused:**
```bash
# Verify OpenSearch is reachable from the same network
docker run --rm --network lab-network alpine sh -c 'nc -zv opensearch 9200'
```

**MySQL auth error:**
```bash
# Secret may be wrong — remove and recreate
docker secret rm om_mysql_user_password
echo -n "newpassword" | docker secret create om_mysql_user_password -
docker service update --force openmetadata_openmetadata-server
```
