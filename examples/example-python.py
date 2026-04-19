import os, json, boto3
from datetime import datetime
from botocore.client import Config

s3 = boto3.client(
    "s3",
    endpoint_url=os.getenv("S3_ENDPOINT", "http://YOUR_AZURE_VM_IP:9000"),
    aws_access_key_id=os.getenv("S3_ACCESS_KEY", "YOUR_MINIO_USER"),
    aws_secret_access_key=os.getenv("S3_SECRET_KEY", "YOUR_MINIO_PASSWORD"),
    config=Config(signature_version="s3v4"),
    region_name="us-east-1",
)

BUCKET = "uploads"

def main():
    # List buckets
    buckets = s3.list_buckets()
    print("Buckets:", [b["Name"] for b in buckets["Buckets"]])

    # Upload JSON
    s3.put_object(Bucket=BUCKET, Key="demo/test.json",
        Body=json.dumps({"message": "Hello from Personal Cloud!", "ts": datetime.now().isoformat()}),
        ContentType="application/json")
    print("Uploaded demo/test.json")

    # List objects
    objects = s3.list_objects_v2(Bucket=BUCKET, Prefix="demo/")
    print("Objects:", [o["Key"] for o in objects.get("Contents", [])])

    # Presigned URL
    url = s3.generate_presigned_url("get_object", Params={"Bucket": BUCKET, "Key": "demo/test.json"}, ExpiresIn=3600)
    print("Presigned URL:", url)

    # Cleanup
    s3.delete_object(Bucket=BUCKET, Key="demo/test.json")
    print("Deleted demo/test.json")

if __name__ == "__main__":
    main()
