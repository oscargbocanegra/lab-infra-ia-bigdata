#!/usr/bin/env python3
"""
Upload sample test data to MinIO bronze bucket for governance DAG validation.
Run inside Docker on master1 with --network internal.
"""

import io
import json
import boto3

# minio_minio resolves to 10.0.2.28 on the internal overlay network.
# boto3 rejects hostnames with underscores as invalid URLs — use IP directly.
MINIO_ENDPOINT = "http://10.0.2.28:9000"
MINIO_ACCESS = "minioadmin"
MINIO_SECRET = "aCUJsixdVyStrPoizdfZlYukYllceAh5BzyJJF8oPXc="

s3 = boto3.client(
    "s3",
    endpoint_url=MINIO_ENDPOINT,
    aws_access_key_id=MINIO_ACCESS,
    aws_secret_access_key=MINIO_SECRET,
    region_name="us-east-1",
)

# List buckets
print("=== Buckets ===")
buckets = s3.list_buckets()
for b in buckets.get("Buckets", []):
    print(f"  {b['Name']}")

# Create governance bucket if not exists
existing_buckets = [b["Name"] for b in buckets.get("Buckets", [])]
for bucket_name in ["bronze", "silver", "gold", "governance"]:
    if bucket_name not in existing_buckets:
        print(f"\nCreating bucket: {bucket_name}")
        s3.create_bucket(Bucket=bucket_name)
        print(f"  ✅ Created {bucket_name}")
    else:
        print(f"\n  ✅ Bucket {bucket_name} already exists")

# Upload sample sales CSV to bronze/sales/2026-04-06/
sample_csv = """date,amount,product_id,customer_id,region
2026-04-06,150.50,PROD-001,CUST-101,LATAM
2026-04-06,89.99,PROD-002,CUST-102,LATAM
2026-04-06,210.00,PROD-003,CUST-103,US
2026-04-06,45.00,PROD-001,CUST-104,US
2026-04-06,320.75,PROD-004,CUST-105,EU
2026-04-06,67.50,PROD-002,CUST-106,EU
2026-04-06,195.00,PROD-005,CUST-107,LATAM
2026-04-06,88.25,PROD-003,CUST-108,US
2026-04-06,412.00,PROD-006,CUST-109,LATAM
2026-04-06,55.00,PROD-001,CUST-110,EU
"""

key = "sales/2026-04-06/sales_20260406.csv"
s3.put_object(
    Bucket="bronze",
    Key=key,
    Body=sample_csv.encode("utf-8"),
    ContentType="text/csv",
)
print(f"\n✅ Uploaded sample data: bronze/{key}")

# Verify
objs = s3.list_objects_v2(Bucket="bronze", Prefix="sales/2026-04-06/")
for obj in objs.get("Contents", []):
    print(f"  📄 {obj['Key']} ({obj['Size']} bytes)")

print("\nDone!")
