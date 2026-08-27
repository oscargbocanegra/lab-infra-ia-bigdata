#!/bin/sh
set -eu

export ENGRAM_DATABASE_URL="postgres://engram:$(cat /run/secrets/pg_engram_pass)@postgres_postgres:5432/engram_cloud?sslmode=disable"
export ENGRAM_JWT_SECRET="$(cat /run/secrets/engram_jwt_secret)"
export ENGRAM_CLOUD_TOKEN_PEPPER="$(cat /run/secrets/engram_cloud_token_pepper)"
export ENGRAM_CLOUD_TOKEN="$(cat /run/secrets/engram_cloud_token_client)"
export ENGRAM_CLOUD_HOST=0.0.0.0
export ENGRAM_PORT=18080
export ENGRAM_CLOUD_ALLOWED_PROJECTS="lab-infra-ia-bigdata,boot-ia-as400-monitoring,datahub,oscarbocanegra.github.io,oscarbocanegra,dhub-fabric-ai-aidashboard-dev,friday_operational_support,app,fabric_microsoft_projects_training,operational_support_f.r.i.d.a.y,gentleman-guardian-angel,cluster-master1,revisa-en-que-trabaj-esta-semana,opencode,semantic-concept-extraction-pipeline,engram-pilot"

exec /usr/local/bin/engram cloud serve
