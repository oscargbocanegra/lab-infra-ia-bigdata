#!/usr/bin/env bash
# Trigger Airflow DAGs via the internal REST API
# Usage: bash trigger_dags.sh
set -e

AIRFLOW_API="http://127.0.0.1:8080/api/v1"
CREDS="admin:Airflow2026!"
RUN_ID="manual_dns_fix_$(date +%s)"

trigger_dag() {
  local dag_id="$1"
  local run_id="${2:-$RUN_ID}"
  echo "Triggering DAG: $dag_id (run_id=$run_id)"
  curl -s -X POST \
    "${AIRFLOW_API}/dags/${dag_id}/dagRuns" \
    -H "Content-Type: application/json" \
    -u "${CREDS}" \
    -d "{\"dag_run_id\": \"${run_id}\"}"
  echo
}

trigger_dag "agent_synthetic_dataset"
trigger_dag "agent_model_benchmark"

echo "Done. Check status:"
echo "  curl -s ${AIRFLOW_API}/dags/agent_synthetic_dataset/dagRuns?limit=2 -u ${CREDS}"
