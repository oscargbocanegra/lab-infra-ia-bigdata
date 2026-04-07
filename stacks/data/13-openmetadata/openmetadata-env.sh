#!/bin/bash
# =============================================================================
# openmetadata-env.sh — Secret injection for OpenMetadata 1.4
# =============================================================================
# This script is sourced by openmetadata-server-start.sh BEFORE the JVM boots.
# It reads Docker Swarm secrets from /run/secrets/ and exports them as plain
# environment variables — required because OpenMetadata 1.4 does NOT support
# the Docker _FILE env var convention (e.g. DB_USER_PASSWORD_FILE is ignored).
#
# Mounted via Docker Config at:
#   /opt/openmetadata/conf/openmetadata-env.sh  (replaces the empty stub)
#
# WARNING: Do NOT mount a volume over /opt/openmetadata/conf/ — it overwrites
# the internal openmetadata.yaml bundled in the image and causes startup failure.
# =============================================================================

if [ -f /run/secrets/om_mysql_user_password ]; then
  export DB_USER_PASSWORD=$(cat /run/secrets/om_mysql_user_password)
fi

if [ -f /run/secrets/om_admin_password ]; then
  export ADMIN_PASSWORD=$(cat /run/secrets/om_admin_password)
fi

# Disable the Airflow pipeline service client health-check job.
# The standard apache/airflow image does NOT include the openmetadata-managed-apis
# plugin, so OM's PipelineServiceStatusJob throws "unsupported URI" on every poll.
# Setting NO_OP disables the polling entirely without losing ingestion functionality
# (ingestion still works via the OpenMetadata Python SDK inside Airflow DAGs).
export PIPELINE_SERVICE_CLIENT_CLASS_NAME=org.openmetadata.service.clients.pipeline.noop.NoopClient
