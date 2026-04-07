"""
DAG: governance_bronze_validate
================================
Validates data quality on files landing in MinIO bronze/ bucket.

Trigger: triggered by upstream ingestion DAGs (not scheduled)
         Can also be triggered manually for a specific source+date.

Parameters:
  source : str  — data source name (e.g. "sales", "users", "events")
  date   : str  — partition date in YYYY-MM-DD format

Flow:
  1. Check file exists in bronze/<source>/<date>/
  2. Run Great Expectations suite: bronze_landing
  3. Save result to governance/ge-results/<source>/<date>/result.json
  4. If validation fails → raise AirflowException (stops downstream)
  5. If validation passes → set XCom flag for silver promotion DAG

Dependencies (pip install in Airflow image or via requirements.txt):
  great-expectations>=0.18
  boto3>=1.26
  pandas>=2.0
"""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timedelta

import boto3
import pandas as pd
from airflow.decorators import dag, task
from airflow.exceptions import AirflowException
from airflow.models.param import Param

log = logging.getLogger(__name__)

# ── MinIO connection (reads from Airflow Connections: minio_s3) ───────────────
# NOTE: boto3 rejects hostnames containing underscores (e.g. minio_minio) as
# invalid endpoint URLs. The MINIO_ENDPOINT env var is used as an override so
# the operator can inject the correct address at deploy time without touching
# DAG code. Fallback to the internal overlay IP (10.0.2.28) which is the
# address MinIO's overlay VIP resolves to on this Swarm cluster.
MINIO_ENDPOINT = os.environ.get("MINIO_ENDPOINT", "http://10.0.2.28:9000")
MINIO_BUCKET_BRONZE = "bronze"
MINIO_BUCKET_GOVERNANCE = "governance"


def _get_minio_client() -> boto3.client:
    """Build a boto3 S3 client pointing to the lab MinIO instance."""
    # Credentials from environment (injected by entrypoint.sh via Docker secrets)
    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY"),
        region_name="us-east-1",
    )


# ── Default expectations per source ──────────────────────────────────────────
# Each source can override these in a dedicated suite file.
# These are the minimum quality gates for bronze landing.
DEFAULT_EXPECTATIONS = {
    "min_rows": 1,
    "max_null_rate": 0.30,  # 30% nulls max on any column at bronze layer
    "required_columns": [],  # override per source
}

SOURCE_EXPECTATIONS: dict[str, dict] = {
    "sales": {
        "min_rows": 10,
        "max_null_rate": 0.05,
        "required_columns": ["date", "amount", "product_id"],
    },
    "users": {
        "min_rows": 1,
        "max_null_rate": 0.10,
        "required_columns": ["user_id", "created_at"],
    },
}


@dag(
    dag_id="governance_bronze_validate",
    description="Validate data quality on bronze landing — runs before silver promotion",
    schedule=None,  # triggered by upstream ingestion DAGs
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["governance", "quality", "bronze"],
    params={
        "source": Param("sales", type="string", description="Data source name"),
        "date": Param(
            default=datetime.now().strftime("%Y-%m-%d"),
            type="string",
            description="Partition date (YYYY-MM-DD)",
        ),
    },
    default_args={
        "owner": "governance",
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
        "email_on_failure": False,
    },
)
def governance_bronze_validate():
    @task
    def check_file_exists(source: str, date: str) -> dict:
        """Verify that at least one file exists in bronze/<source>/<date>/"""
        s3 = _get_minio_client()
        prefix = f"{source}/{date}/"

        response = s3.list_objects_v2(
            Bucket=MINIO_BUCKET_BRONZE,
            Prefix=prefix,
        )
        files = [obj["Key"] for obj in response.get("Contents", [])]

        if not files:
            raise AirflowException(
                f"No files found in bronze/{source}/{date}/ — "
                f"cannot validate empty partition"
            )

        log.info("Found %d file(s) in bronze/%s/%s/", len(files), source, date)
        return {"files": files, "count": len(files)}

    @task
    def run_quality_checks(file_info: dict, source: str, date: str) -> dict:
        """
        Run basic data quality checks.
        In a full GE setup, this would call context.run_checkpoint().
        Here we run lightweight pandas-based checks for portability.
        """
        s3 = _get_minio_client()
        expectations = SOURCE_EXPECTATIONS.get(source, DEFAULT_EXPECTATIONS)
        results = {
            "source": source,
            "date": date,
            "files_checked": file_info["count"],
            "checks": [],
            "success": True,
        }

        for file_key in file_info["files"]:
            log.info("Checking file: %s", file_key)

            # Download and parse
            obj = s3.get_object(Bucket=MINIO_BUCKET_BRONZE, Key=file_key)
            content = obj["Body"].read()

            try:
                if file_key.endswith(".csv"):
                    df = pd.read_csv(pd.io.common.BytesIO(content))
                elif file_key.endswith(".parquet"):
                    df = pd.read_parquet(pd.io.common.BytesIO(content))
                elif file_key.endswith(".json"):
                    df = pd.read_json(pd.io.common.BytesIO(content))
                else:
                    log.warning(
                        "Unknown file type: %s — skipping content checks", file_key
                    )
                    continue
            except Exception as e:
                results["checks"].append(
                    {
                        "file": file_key,
                        "check": "parseable",
                        "success": False,
                        "detail": str(e),
                    }
                )
                results["success"] = False
                continue

            # Check: minimum rows
            row_check = {
                "file": file_key,
                "check": "min_rows",
                "expected": expectations["min_rows"],
                "actual": len(df),
                "success": len(df) >= expectations["min_rows"],
            }
            results["checks"].append(row_check)
            if not row_check["success"]:
                results["success"] = False

            # Check: null rate per column
            for col in df.columns:
                null_rate = df[col].isnull().mean()
                null_check = {
                    "file": file_key,
                    "check": "null_rate",
                    "column": col,
                    "expected_max": expectations["max_null_rate"],
                    "actual": round(null_rate, 4),
                    "success": null_rate <= expectations["max_null_rate"],
                }
                results["checks"].append(null_check)
                if not null_check["success"]:
                    results["success"] = False
                    log.warning(
                        "High null rate in %s.%s: %.1f%% (max %.1f%%)",
                        file_key,
                        col,
                        null_rate * 100,
                        expectations["max_null_rate"] * 100,
                    )

            # Check: required columns
            for required_col in expectations.get("required_columns", []):
                col_check = {
                    "file": file_key,
                    "check": "required_column",
                    "column": required_col,
                    "success": required_col in df.columns,
                }
                results["checks"].append(col_check)
                if not col_check["success"]:
                    results["success"] = False
                    log.error(
                        "Required column '%s' missing in %s", required_col, file_key
                    )

        log.info(
            "Quality check result for %s/%s: %s (%d checks)",
            source,
            date,
            "PASS" if results["success"] else "FAIL",
            len(results["checks"]),
        )
        return results

    @task
    def save_result(validation_result: dict, source: str, date: str) -> None:
        """Persist validation result to MinIO governance/ge-results/<source>/<date>/"""
        s3 = _get_minio_client()
        key = f"ge-results/{source}/{date}/result.json"

        s3.put_object(
            Bucket=MINIO_BUCKET_GOVERNANCE,
            Key=key,
            Body=json.dumps(validation_result, indent=2).encode("utf-8"),
            ContentType="application/json",
        )
        log.info("Validation result saved to governance/%s", key)

    @task
    def assert_success(validation_result: dict) -> None:
        """Fail the DAG if quality checks did not pass — blocks silver promotion."""
        if not validation_result["success"]:
            failed = [c for c in validation_result["checks"] if not c["success"]]
            details = json.dumps(failed, indent=2)
            raise AirflowException(
                f"Data quality FAILED for {validation_result['source']}/{validation_result['date']}.\n"
                f"Failed checks:\n{details}"
            )
        log.info(
            "✅ All quality checks passed for %s/%s",
            validation_result["source"],
            validation_result["date"],
        )

    # ── DAG wiring ────────────────────────────────────────────────────────────
    source = "{{ params.source }}"
    date = "{{ params.date }}"

    file_info = check_file_exists(source=source, date=date)
    validation_result = run_quality_checks(
        file_info=file_info, source=source, date=date
    )
    save_result(validation_result=validation_result, source=source, date=date)
    assert_success(validation_result=validation_result)


governance_bronze_validate()
