#!/usr/bin/env python3
"""Trigger Airflow DAG runs via the internal REST API from inside a container."""

import urllib.request
import base64
import json
import sys

AIRFLOW_URL = "http://localhost:8080/api/v1"
CREDS = base64.b64encode(b"admin:Airflow2026!").decode()

DAGS_TO_TRIGGER = [
    "agent_ragas_eval",
]

RUN_ID = "manual_timeout_fix_v1"


def trigger_dag(dag_id, run_id=RUN_ID):
    url = f"{AIRFLOW_URL}/dags/{dag_id}/dagRuns"
    payload = json.dumps({"dag_run_id": run_id}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        method="POST",
    )
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"Basic {CREDS}")
    try:
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read().decode())
            print(
                f"OK  {dag_id}: state={result.get('state')} run_id={result.get('dag_run_id')}"
            )
            return result
    except Exception as e:
        print(f"ERR {dag_id}: {e}")
        return None


def list_runs(dag_id):
    url = f"{AIRFLOW_URL}/dags/{dag_id}/dagRuns?order_by=-start_date&limit=3"
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Basic {CREDS}")
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read().decode())
        print(f"\n=== Recent runs for {dag_id} ===")
        for run in result.get("dag_runs", []):
            print(
                f"  {run['dag_run_id']:55s}  {run['state']:12s}  {run.get('start_date', '?')}"
            )


if __name__ == "__main__":
    print("Triggering DAGs...")
    for dag_id in DAGS_TO_TRIGGER:
        trigger_dag(dag_id)

    print("\nChecking run status...")
    for dag_id in DAGS_TO_TRIGGER:
        list_runs(dag_id)
