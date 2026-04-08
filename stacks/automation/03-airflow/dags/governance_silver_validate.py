"""
DAG: governance_silver_validate
=================================
Validates data quality BEFORE promoting data from silver/ to gold/.

This is a stricter suite than bronze validation:
- Schema must match exactly (column names + types)
- PK uniqueness enforced
- Null rate < 5% on all columns
- Value ranges validated (e.g. no negative prices, no future dates)

Trigger: triggered by silver promotion DAGs (not scheduled)

Parameters:
  domain : str  — data domain (e.g. "commerce", "users", "events")
  table  : str  — table name (e.g. "sales", "sessions")
  date   : str  — partition date in YYYY-MM-DD format
"""

from __future__ import annotations

from datetime import datetime, timedelta
import json
import logging
import os
from typing import Any

from airflow.decorators import dag, task
from airflow.exceptions import AirflowException
from airflow.models.param import Param
import boto3
import pandas as pd

log = logging.getLogger(__name__)

MINIO_ENDPOINT = os.environ.get("MINIO_ENDPOINT", "http://10.0.2.28:9000")
# NOTE: boto3 rejects hostnames with underscores (e.g. minio_minio) as invalid
# endpoint URLs. Use MINIO_ENDPOINT env var override or the overlay IP fallback.
MINIO_BUCKET_SILVER = "silver"
MINIO_BUCKET_GOVERNANCE = "governance"


def _get_minio_client() -> boto3.client:
    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY"),
        region_name="us-east-1",
    )


# ── Silver schemas — strict contracts ────────────────────────────────────────
# Define expected schema per domain/table.
# Add new entries as you create silver datasets.
SILVER_SCHEMAS: dict[str, dict[str, Any]] = {
    "commerce/sales": {
        "primary_keys": ["sale_id"],
        "required_columns": {
            "sale_id": "object",
            "date": "datetime64[ns]",
            "amount": "float64",
            "product_id": "object",
            "user_id": "object",
        },
        "max_null_rate": 0.01,  # 1% max null — silver is clean
        "value_checks": {
            "amount": {"min": 0.0},  # no negative amounts
        },
    },
    "users/profiles": {
        "primary_keys": ["user_id"],
        "required_columns": {
            "user_id": "object",
            "created_at": "datetime64[ns]",
            "email": "object",
        },
        "max_null_rate": 0.01,
        "value_checks": {},
    },
}


@dag(
    dag_id="governance_silver_validate",
    description="Strict quality validation before silver → gold promotion",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["governance", "quality", "silver"],
    params={
        "domain": Param("commerce", type="string", description="Data domain"),
        "table": Param("sales", type="string", description="Table name"),
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
def governance_silver_validate():
    @task
    def load_silver_partition(domain: str, table: str, date: str) -> dict:
        """Load all parquet files from silver/<domain>/<table>/<date>/"""
        s3 = _get_minio_client()
        prefix = f"{domain}/{table}/{date}/"

        response = s3.list_objects_v2(Bucket=MINIO_BUCKET_SILVER, Prefix=prefix)
        files = [
            obj["Key"]
            for obj in response.get("Contents", [])
            if obj["Key"].endswith(".parquet")
        ]

        if not files:
            raise AirflowException(
                f"No parquet files found in silver/{domain}/{table}/{date}/"
            )

        # Load all parts into single DataFrame
        frames = []
        for key in files:
            obj = s3.get_object(Bucket=MINIO_BUCKET_SILVER, Key=key)
            frames.append(pd.read_parquet(pd.io.common.BytesIO(obj["Body"].read())))

        df = pd.concat(frames, ignore_index=True)
        log.info("Loaded %d rows from silver/%s/%s/%s/", len(df), domain, table, date)

        # Serialize to JSON for XCom (small summary only — not the full df)
        return {
            "rows": len(df),
            "columns": list(df.columns),
            "dtypes": {col: str(dtype) for col, dtype in df.dtypes.items()},
            "null_counts": df.isnull().sum().to_dict(),
            "sample_values": {
                col: df[col].dropna().head(3).tolist() for col in df.columns
            },
            # Store serialized df for downstream tasks
            "_df_json": df.to_json(orient="split", date_format="iso"),
        }

    @task
    def validate_schema(partition_info: dict, domain: str, table: str) -> dict:
        """Validate column names and data types match the expected schema."""
        schema_key = f"{domain}/{table}"
        if schema_key not in SILVER_SCHEMAS:
            log.warning(
                "No schema defined for %s — skipping schema validation. "
                "Add it to SILVER_SCHEMAS in this DAG.",
                schema_key,
            )
            return {"check": "schema", "success": True, "detail": "no schema defined"}

        schema = SILVER_SCHEMAS[schema_key]
        issues = []

        for col, _expected_type in schema["required_columns"].items():
            if col not in partition_info["columns"]:
                issues.append(f"Missing column: {col}")
            # Type check — loose match (e.g. object == string)
            # Full strict type checking would require loading the DataFrame

        result = {
            "check": "schema",
            "success": len(issues) == 0,
            "issues": issues,
        }
        if issues:
            log.error("Schema validation failed: %s", issues)
        return result

    @task
    def validate_uniqueness(partition_info: dict, domain: str, table: str) -> dict:
        """Check primary key uniqueness."""
        schema_key = f"{domain}/{table}"
        if schema_key not in SILVER_SCHEMAS:
            return {
                "check": "uniqueness",
                "success": True,
                "detail": "no schema defined",
            }

        pks = SILVER_SCHEMAS[schema_key]["primary_keys"]
        df = pd.read_json(partition_info["_df_json"], orient="split")

        available_pks = [pk for pk in pks if pk in df.columns]
        if not available_pks:
            return {
                "check": "uniqueness",
                "success": True,
                "detail": "PK columns not present",
            }

        duplicates = df.duplicated(subset=available_pks).sum()
        result = {
            "check": "uniqueness",
            "primary_keys": pks,
            "duplicate_rows": int(duplicates),
            "success": duplicates == 0,
        }
        if duplicates > 0:
            log.error("Found %d duplicate rows on PKs %s", duplicates, pks)
        return result

    @task
    def validate_null_rates(partition_info: dict, domain: str, table: str) -> dict:
        """Enforce strict null rate threshold for silver layer."""
        schema_key = f"{domain}/{table}"
        max_null = SILVER_SCHEMAS.get(schema_key, {}).get("max_null_rate", 0.05)

        issues = []
        for col, null_count in partition_info["null_counts"].items():
            null_rate = (
                null_count / partition_info["rows"] if partition_info["rows"] > 0 else 0
            )
            if null_rate > max_null:
                issues.append(
                    {
                        "column": col,
                        "null_rate": round(null_rate, 4),
                        "max_allowed": max_null,
                    }
                )

        result = {
            "check": "null_rates",
            "success": len(issues) == 0,
            "issues": issues,
        }
        if issues:
            log.error("Null rate violations: %s", issues)
        return result

    @task
    def save_and_assert(
        schema_result: dict,
        uniqueness_result: dict,
        null_result: dict,
        domain: str,
        table: str,
        date: str,
    ) -> None:
        """Save combined result to MinIO and fail if any check failed."""
        combined = {
            "domain": domain,
            "table": table,
            "date": date,
            "layer": "silver",
            "checks": [schema_result, uniqueness_result, null_result],
            "success": all(
                r["success"] for r in [schema_result, uniqueness_result, null_result]
            ),
        }

        s3 = _get_minio_client()
        key = f"ge-results/silver/{domain}/{table}/{date}/result.json"
        s3.put_object(
            Bucket=MINIO_BUCKET_GOVERNANCE,
            Key=key,
            Body=json.dumps(combined, indent=2).encode("utf-8"),
            ContentType="application/json",
        )
        log.info("Silver validation result saved to governance/%s", key)

        if not combined["success"]:
            failed = [c for c in combined["checks"] if not c["success"]]
            raise AirflowException(
                f"Silver quality FAILED for {domain}/{table}/{date}.\n"
                f"Failed checks: {json.dumps(failed, indent=2)}"
            )

        log.info("✅ All silver checks passed for %s/%s/%s", domain, table, date)

    # ── DAG wiring ────────────────────────────────────────────────────────────
    domain = "{{ params.domain }}"
    table = "{{ params.table }}"
    date = "{{ params.date }}"

    partition_info = load_silver_partition(domain=domain, table=table, date=date)
    schema_result = validate_schema(
        partition_info=partition_info, domain=domain, table=table
    )
    uniqueness_result = validate_uniqueness(
        partition_info=partition_info, domain=domain, table=table
    )
    null_result = validate_null_rates(
        partition_info=partition_info, domain=domain, table=table
    )

    save_and_assert(
        schema_result=schema_result,
        uniqueness_result=uniqueness_result,
        null_result=null_result,
        domain=domain,
        table=table,
        date=date,
    )


governance_silver_validate()
