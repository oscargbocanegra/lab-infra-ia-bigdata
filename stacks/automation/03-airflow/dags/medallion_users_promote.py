"""Minimal Bronze -> Silver -> Gold promotion for the lab users sample."""

from __future__ import annotations

from datetime import datetime
import io
import os

from airflow.decorators import dag, task
import boto3
import pandas as pd

MINIO_ENDPOINT = os.environ.get("MINIO_ENDPOINT", "http://10.0.2.28:9000")


def _s3():
    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        region_name="us-east-1",
    )


@dag(
    dag_id="medallion_users_promote",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    params={"date": "2026-07-17"},
    tags=["medallion", "bronze", "silver", "gold"],
)
def medallion_users_promote():
    @task
    def promote(date: str) -> dict:
        s3 = _s3()
        prefix = f"users/{date}/"
        objects = s3.list_objects_v2(Bucket="bronze", Prefix=prefix).get(
            "Contents", []
        )
        source = next(
            (item["Key"] for item in objects if item["Key"].endswith(".csv")),
            None,
        )
        if source is None:
            raise ValueError(f"No CSV found in bronze/{prefix}")

        frame = pd.read_csv(io.BytesIO(s3.get_object(Bucket="bronze", Key=source)["Body"].read()))
        frame.columns = [column.strip().lower() for column in frame.columns]
        frame = frame.drop_duplicates().reset_index(drop=True)
        frame["ingested_date"] = date

        silver_key = f"users/{date}/users.csv"
        silver_body = frame.to_csv(index=False).encode("utf-8")
        s3.put_object(Bucket="silver", Key=silver_key, Body=silver_body, ContentType="text/csv")

        summary = pd.DataFrame(
            [{"dataset": "users", "partition_date": date, "rows": len(frame), "columns": len(frame.columns)}]
        )
        gold_key = f"users/{date}/summary.csv"
        s3.put_object(
            Bucket="gold",
            Key=gold_key,
            Body=summary.to_csv(index=False).encode("utf-8"),
            ContentType="text/csv",
        )
        return {"source": source, "silver": silver_key, "gold": gold_key, "rows": len(frame)}

    promote("{{ params.date }}")


medallion_users_promote()
