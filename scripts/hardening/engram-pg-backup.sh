#!/usr/bin/env bash
# Logical backup of Engram Cloud PostgreSQL database on master2.
set -euo pipefail
BACKUP_DIR="${ENGRAM_BACKUP_DIR:-/srv/fastdata/postgres-backups/engram}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP_DIR"
container="$(docker ps --filter label=com.docker.swarm.service.name=postgres_postgres --format '{{.ID}}' | head -1)"
[[ -n "$container" ]] || { echo "postgres_postgres container not found" >&2; exit 1; }
docker exec "$container" sh -c 'export PGPASSWORD="$(cat /run/secrets/pg_super_pass)"; pg_dump --format=custom --no-owner --dbname=engram_cloud --username=postgres' > "$BACKUP_DIR/engram_cloud-$STAMP.dump"
chmod 0600 "$BACKUP_DIR/engram_cloud-$STAMP.dump"
find "$BACKUP_DIR" -type f -name 'engram_cloud-*.dump' -mtime +30 -delete
printf 'Created %s\n' "$BACKUP_DIR/engram_cloud-$STAMP.dump"
