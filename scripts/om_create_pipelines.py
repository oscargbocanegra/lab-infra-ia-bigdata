#!/usr/bin/env python3
"""
Phase 9A: Create and trigger ingestion pipelines for lab-postgres and lab-minio.
Run inside Docker on master1 with --network internal.
"""

import requests
import json
import sys
import time

BASE = "http://openmetadata_openmetadata-server:8585/api/v1"

# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------
r = requests.post(
    BASE + "/users/login",
    json={"email": "admin@lab.local", "password": "T3Blbk1ldGFkYXRhMjAyNiE="},
)
r.raise_for_status()
token = r.json()["accessToken"]
print("LOGIN OK", file=sys.stderr)

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json",
}


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
def api(method, path, **kwargs):
    resp = getattr(requests, method)(BASE + path, headers=headers, **kwargs)
    return resp


def jprint(data):
    print(json.dumps(data, indent=2))


# ---------------------------------------------------------------------------
# 1. List existing ingestion pipelines
# ---------------------------------------------------------------------------
print("\n=== Existing Ingestion Pipelines ===")
r = api("get", "/services/ingestionPipelines?limit=50")
data = r.json()
pipelines = data.get("data", [])
print(f"Total: {len(pipelines)}")
for p in pipelines:
    print(
        f"  - {p['name']} | service={p.get('service', {}).get('name')} | status={p.get('pipelineStatuses', {}).get('pipelineState', '?')}"
    )

# ---------------------------------------------------------------------------
# 2. Create Postgres metadata ingestion pipeline
# ---------------------------------------------------------------------------
PG_PIPELINE_NAME = "lab-postgres-metadata-ingestion"
existing_names = [p["name"] for p in pipelines]

if PG_PIPELINE_NAME not in existing_names:
    print(f"\n=== Creating Postgres ingestion pipeline ===")
    pg_pipeline = {
        "name": PG_PIPELINE_NAME,
        "displayName": "Lab Postgres - Metadata Ingestion",
        "pipelineType": "metadata",
        "service": {
            "id": "25c90e90-a19b-418a-8f88-83cc72baeee8",
            "type": "databaseService",
        },
        "sourceConfig": {
            "config": {
                "type": "DatabaseMetadata",
                "markDeletedTables": True,
                "includeTables": True,
                "includeViews": True,
                "includeTags": True,
                "includeStoredProcedures": True,
                "queryLogDuration": 1,
                "queryParsingTimeoutLimit": 300,
                "useFqnForFiltering": False,
                "schemaFilterPattern": {"excludes": []},
                "tableFilterPattern": {"excludes": []},
            }
        },
        "airflowConfig": {
            "scheduleInterval": "0 */6 * * *",
            "startDate": "2024-01-01T00:00:00.000Z",
            "retries": 3,
        },
    }
    r_pg = api("post", "/services/ingestionPipelines", json=pg_pipeline)
    print(f"HTTP {r_pg.status_code}")
    jprint(r_pg.json())
    if r_pg.status_code in (200, 201):
        pg_pipeline_id = r_pg.json()["id"]
        print(f"✅ Postgres pipeline created: {pg_pipeline_id}")
    else:
        print("❌ Failed to create Postgres pipeline")
        pg_pipeline_id = None
else:
    print(f"\n⏭  Postgres pipeline already exists")
    pg_pipeline_id = next(
        (p["id"] for p in pipelines if p["name"] == PG_PIPELINE_NAME), None
    )

# ---------------------------------------------------------------------------
# 3. Create MinIO / S3 metadata ingestion pipeline
# ---------------------------------------------------------------------------
MINIO_PIPELINE_NAME = "lab-minio-metadata-ingestion"

if MINIO_PIPELINE_NAME not in existing_names:
    print(f"\n=== Creating MinIO ingestion pipeline ===")
    minio_pipeline = {
        "name": MINIO_PIPELINE_NAME,
        "displayName": "Lab MinIO - Metadata Ingestion",
        "pipelineType": "metadata",
        "service": {
            "id": "a9170343-10a4-46bd-aa3b-ea7b4cc9beed",
            "type": "storageService",
        },
        "sourceConfig": {
            "config": {
                "type": "StorageMetadata",
            }
        },
        "airflowConfig": {
            "scheduleInterval": "0 */6 * * *",
            "startDate": "2024-01-01T00:00:00.000Z",
            "retries": 3,
        },
    }
    r_minio = api("post", "/services/ingestionPipelines", json=minio_pipeline)
    print(f"HTTP {r_minio.status_code}")
    jprint(r_minio.json())
    if r_minio.status_code in (200, 201):
        minio_pipeline_id = r_minio.json()["id"]
        print(f"✅ MinIO pipeline created: {minio_pipeline_id}")
    else:
        print("❌ Failed to create MinIO pipeline")
        minio_pipeline_id = None
else:
    print(f"\n⏭  MinIO pipeline already exists")
    minio_pipeline_id = next(
        (p["id"] for p in pipelines if p["name"] == MINIO_PIPELINE_NAME), None
    )

# ---------------------------------------------------------------------------
# 4. Trigger both pipelines
# ---------------------------------------------------------------------------
for pipeline_id, name in [(pg_pipeline_id, "Postgres"), (minio_pipeline_id, "MinIO")]:
    if not pipeline_id:
        print(f"\n⚠  Skipping trigger for {name} — no pipeline ID")
        continue
    print(f"\n=== Triggering {name} ingestion pipeline ({pipeline_id}) ===")
    r_trigger = api("post", f"/services/ingestionPipelines/trigger/{pipeline_id}")
    print(f"HTTP {r_trigger.status_code}")
    print(r_trigger.text[:500])
    if r_trigger.status_code in (200, 201):
        print(f"✅ {name} pipeline triggered successfully")
    else:
        print(f"❌ Failed to trigger {name} pipeline")

print("\n=== Done ===")
