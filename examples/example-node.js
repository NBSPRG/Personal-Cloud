import {
  S3Client, PutObjectCommand, GetObjectCommand,
  ListBucketsCommand, ListObjectsV2Command, DeleteObjectCommand,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const s3 = new S3Client({
  endpoint: process.env.S3_ENDPOINT || "http://YOUR_AZURE_VM_IP:9000",
  region: "us-east-1",
  credentials: {
    accessKeyId: process.env.S3_ACCESS_KEY || "YOUR_MINIO_USER",
    secretAccessKey: process.env.S3_SECRET_KEY || "YOUR_MINIO_PASSWORD",
  },
  forcePathStyle: true,
});

const BUCKET = "uploads";

async function main() {
  // List buckets
  const buckets = await s3.send(new ListBucketsCommand({}));
  console.log("Buckets:", buckets.Buckets?.map(b => b.Name));

  // Upload JSON
  await s3.send(new PutObjectCommand({
    Bucket: BUCKET, Key: "demo/test.json",
    Body: JSON.stringify({ message: "Hello from Personal Cloud!", ts: new Date() }),
    ContentType: "application/json",
  }));
  console.log("Uploaded demo/test.json");

  // List objects
  const objects = await s3.send(new ListObjectsV2Command({ Bucket: BUCKET, Prefix: "demo/" }));
  console.log("Objects:", objects.Contents?.map(o => o.Key));

  // Presigned URL
  const url = await getSignedUrl(s3, new GetObjectCommand({ Bucket: BUCKET, Key: "demo/test.json" }), { expiresIn: 3600 });
  console.log("Presigned URL:", url);

  // Cleanup
  await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: "demo/test.json" }));
  console.log("Deleted demo/test.json");
}

main().catch(console.error);
