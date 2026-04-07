import boto3

s3 = boto3.client(
    "s3",
    endpoint_url="http://10.0.2.28:9000",
    aws_access_key_id="minioadmin",
    aws_secret_access_key="aCUJsixdVyStrPoizdfZlYukYllceAh5BzyJJF8oPXc=",
    region_name="us-east-1",
)
print("=== governance/ge-results/ ===")
objs = s3.list_objects_v2(Bucket="governance", Prefix="ge-results/")
for o in objs.get("Contents", []):
    print(f"  {o['Key']} ({o['Size']} bytes)")

# Print the content
for o in objs.get("Contents", []):
    resp = s3.get_object(Bucket="governance", Key=o["Key"])
    print("\n=== Content ===")
    print(resp["Body"].read().decode("utf-8")[:1000])
