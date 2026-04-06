#!/usr/bin/env bash
# =============================================================================
# setup-governance.sh — One-time governance bootstrap
# =============================================================================
# Run from master1 BEFORE deploying the openmetadata stack.
#
# What this script does:
#   1. Creates OpenMetadata Docker Swarm secrets (passwords)
#   2. Creates persistence directories on master1 (/srv/fastdata/openmetadata/)
#   3. Creates governance MinIO buckets (governance, bronze, silver, gold)
#   4. Creates Docker Config 'openmetadata-env' for secret injection into JVM
#   5. Creates Great Expectations base config for Airflow DAGs
#
# Usage:
#   bash scripts/governance/setup-governance.sh
# =============================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Prerequisites ────────────────────────────────────────────────────────────
[[ $(id -u) -ne 0 ]] && error "Run as root or with sudo"
command -v docker >/dev/null || error "docker not found"
command -v mc >/dev/null    || warn "mc (MinIO client) not found — skipping MinIO setup"

echo ""
echo "============================================================"
echo "  Lab Data Governance — Bootstrap Setup"
echo "============================================================"
echo ""

# ── Step 1: Docker Swarm Secrets ─────────────────────────────────────────────
info "Step 1: Creating Docker Swarm secrets for OpenMetadata..."

create_secret() {
    local name="$1"
    local prompt="$2"
    if docker secret inspect "$name" &>/dev/null; then
        warn "Secret '$name' already exists — skipping"
    else
        read -rsp "  Enter $prompt: " value; echo ""
        [[ -z "$value" ]] && error "$prompt cannot be empty"
        echo -n "$value" | docker secret create "$name" -
        success "Secret '$name' created"
    fi
}

create_secret "om_mysql_root_password" "OpenMetadata MySQL root password"
create_secret "om_mysql_user_password" "OpenMetadata MySQL user (openmetadata) password"
create_secret "om_admin_password"      "OpenMetadata admin UI password"

# ── Step 2: Persistence directories on master1 ───────────────────────────────
info "Step 2: Creating persistence directories on master1..."

mkdir -p /srv/fastdata/openmetadata/mysql
mkdir -p /srv/fastdata/openmetadata/server
success "Directories created: /srv/fastdata/openmetadata/{mysql,server}"

# ── Step 3: MinIO bucket structure ───────────────────────────────────────────
if command -v mc &>/dev/null; then
    info "Step 3: Configuring MinIO governance bucket structure..."

    # Read MinIO credentials from running container
    MINIO_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i 'minio_minio' | head -1)
    if [[ -z "$MINIO_CONTAINER" ]]; then
        warn "MinIO container not found — skipping bucket setup"
        warn "Run manually: mc mb minio/governance && mc mb minio/bronze && ..."
    else
        MINIO_ACCESS=$(docker exec "$MINIO_CONTAINER" cat /run/secrets/minio_access_key)
        MINIO_SECRET=$(docker exec "$MINIO_CONTAINER" cat /run/secrets/minio_secret_key)

        # Configure mc alias
        mc alias set labminio http://localhost:9000 "$MINIO_ACCESS" "$MINIO_SECRET" --api S3v4 2>/dev/null || \
        mc alias set labminio https://minio-api.sexydad "$MINIO_ACCESS" "$MINIO_SECRET" --api S3v4

        # Create governance structure
        for bucket in governance bronze silver gold; do
            mc mb --ignore-existing "labminio/$bucket"
            success "Bucket: $bucket"
        done

        # Create governance subfolders (via placeholder objects)
        for folder in ge-results catalogs; do
            echo "# placeholder" | mc pipe "labminio/governance/$folder/.keep"
        done

        success "MinIO governance structure ready"
    fi
else
    warn "Step 3: mc not found — create buckets manually:"
    echo "    mc mb minio/governance"
    echo "    mc mb minio/bronze"
    echo "    mc mb minio/silver"
    echo "    mc mb minio/gold"
fi

# ── Step 4: Docker Config — openmetadata-env ─────────────────────────────────
info "Step 4: Creating Docker Config 'openmetadata-env' for secret injection..."

# OpenMetadata 1.4 does NOT support Docker's _FILE env var convention.
# Instead, we mount a shell script over the empty /opt/openmetadata/conf/openmetadata-env.sh
# which the start script sources before the JVM boots.  This script reads the
# Docker secrets from /run/secrets/ and exports them as plain env vars.

OM_ENV_SCRIPT=$(cat << 'OMENV'
#!/bin/bash
# OpenMetadata secret injection — sourced by openmetadata-server-start.sh
# DO NOT mount a volume over /opt/openmetadata/conf — it overwrites openmetadata.yaml
if [ -f /run/secrets/om_mysql_user_password ]; then
  export DB_USER_PASSWORD=$(cat /run/secrets/om_mysql_user_password)
fi
if [ -f /run/secrets/om_admin_password ]; then
  export ADMIN_PASSWORD=$(cat /run/secrets/om_admin_password)
fi
OMENV
)

if docker config inspect openmetadata-env &>/dev/null; then
    warn "Docker Config 'openmetadata-env' already exists — skipping"
    warn "To recreate: docker config rm openmetadata-env && re-run this script"
else
    echo "$OM_ENV_SCRIPT" | docker config create openmetadata-env -
    success "Docker Config 'openmetadata-env' created"
fi

# ── Step 5: Great Expectations base config ───────────────────────────────────
info "Step 5: Creating Great Expectations base config for Airflow DAGs..."

GE_DIR="/srv/fastdata/airflow/great_expectations"
mkdir -p "$GE_DIR/expectations"
mkdir -p "$GE_DIR/checkpoints"
mkdir -p "$GE_DIR/plugins/custom_data_docs"

# great_expectations.yml — base config
cat > "$GE_DIR/great_expectations.yml" << 'GEYAML'
# Great Expectations config for Lab Airflow
# Docs: https://docs.greatexpectations.io

config_version: 3.0

datasources:
  minio_bronze:
    class_name: Datasource
    execution_engine:
      class_name: PandasExecutionEngine
    data_connectors:
      default_inferred_data_connector_name:
        class_name: InferredAssetS3DataConnector
        bucket_or_container: bronze
        default_regex:
          pattern: (.+)/(.+)/(.+)
          group_names:
            - source
            - date
            - filename

stores:
  expectations_store:
    class_name: ExpectationsStore
    store_backend:
      class_name: TupleFilesystemStoreBackend
      base_directory: /opt/airflow/great_expectations/expectations/

  validations_store:
    class_name: ValidationsStore
    store_backend:
      class_name: TupleFilesystemStoreBackend
      base_directory: /opt/airflow/great_expectations/validations/

  evaluation_parameter_store:
    class_name: EvaluationParameterStore

expectations_store_name: expectations_store
validations_store_name: validations_store
evaluation_parameter_store_name: evaluation_parameter_store

data_docs_sites:
  local_site:
    class_name: SiteBuilder
    store_backend:
      class_name: TupleFilesystemStoreBackend
      base_directory: /opt/airflow/great_expectations/data_docs/local_site/
    site_index_builder:
      class_name: DefaultSiteIndexBuilder

anonymous_usage_statistics:
  enabled: false
GEYAML

chown -R 50000:50000 "$GE_DIR" 2>/dev/null || true
success "Great Expectations config created at $GE_DIR"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Setup complete! Next steps:"
echo "============================================================"
echo ""
echo "  1. Deploy OpenMetadata stack:"
echo "     docker stack deploy -c stacks/data/13-openmetadata/stack.yml openmetadata"
echo ""
echo "  2. Bootstrap the database (FIRST TIME ONLY — takes 3-5 min):"
echo "     # Run in a screen/tmux session to avoid timeout:"
echo "     screen -S om-bootstrap"
echo "     docker run --rm --network internal \\"
echo "       -e DB_HOST=openmetadata-mysql -e DB_PORT=3306 \\"
echo "       -e DB_SCHEME=mysql -e DB_USER=openmetadata \\"
echo "       -e DB_USER_PASSWORD=\$(docker secret inspect om_mysql_user_password --format '{{.Spec.Name}}' 2>/dev/null || echo '<om_mysql_user_password>') \\"
echo "       -e OM_DATABASE=openmetadata_db \\"
echo "       -e DB_DRIVER_CLASS=com.mysql.cj.jdbc.Driver \\"
echo "       openmetadata/server:1.4.7 \\"
echo "       ./bootstrap/bootstrap_storage.sh migrate-all"
echo "     # NOTE: Pass the actual MySQL user password you set during secret creation."
echo "     # After bootstrap, force restart the server service:"
echo "     docker service update --force openmetadata_openmetadata-server"
echo ""
echo "  3. Wait ~2 min after bootstrap, then open:"
echo "     https://openmetadata.sexydad"
echo ""
echo "  4. Login: admin / <om_admin_password>"
echo ""
echo "  5. Configure connectors via UI:"
echo "     Settings → Services → Add Service"
echo "     - Database: Postgres (<master2-ip>:5432)"
echo "     - Storage:  MinIO (https://minio-api.sexydad)"
echo "     - Pipeline: Airflow (http://airflow_airflow_webserver:8080)"
echo ""
echo "  6. Governance DAGs are auto-loaded from /srv/fastdata/airflow/dags/"
echo ""
