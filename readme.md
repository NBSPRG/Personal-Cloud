# Personal Cloud Infrastructure — Build Prompt

## Project Overview

Build a personal cloud storage infrastructure using:
- **GitHub Codespaces** (development environment — write and test code)
- **Azure for Students** (compute server — always-on VM, $100 free credit/year)
- **GitHub Actions** (auto-deploy — push code, Azure updates automatically)
- **Rclone** (bridge between Azure VM and Google Drive)
- **MinIO** (S3-compatible API layer)
- **FileBrowser** (web UI for file management)
- **2x Google Drive accounts** (5TB each = 10TB total storage — free)

The goal is a fully functional, self-hosted, S3-compatible cloud storage system
that costs $0/month and serves as a personal alternative to AWS S3, Dropbox,
and similar paid services.

---

## Developer Workflow

```
GitHub Codespaces          ← Write and test code here
        ↓
   git push to GitHub      ← Push when ready
        ↓
  GitHub Actions           ← Auto-triggers on every push
        ↓
     Azure VM              ← Pulls latest code, restarts services
        ↓
  Live in ~30 seconds      ← No manual deployment needed
```

### Day-to-Day Usage

| Task | Where |
|---|---|
| Writing code | Codespaces |
| Testing locally | Codespaces terminal |
| Deploying | `git push` — that's it |
| Managing files | FileBrowser web UI |
| Using storage in apps | MinIO S3 API |
| Server management | Azure Portal |

---

## Full Architecture

```
You (browser / app / code)
         |
         |
   GitHub Codespaces        ← DEV: where you BUILD
   (GitHub Pro — free)
         |
      git push
         |
   GitHub Actions           ← CI/CD: auto-deploy on push
         |
      Azure VM              ← SERVER: runs 24/7
   (B2s — 2vCPU, 4GB RAM)
   ($100 Azure Student credit)
         |
       Rclone               ← BRIDGE: connects VM to Drive
         |
        MinIO               ← API: S3-compatible storage layer
       (port 9000/9001)
         |
     FileBrowser            ← UI: manage files via browser
       (port 8080)
         |
   Google Drive x2          ← STORAGE: 10TB free
   Account 1 (5TB hot)
   Account 2 (5TB cold)
```

---

## Server

- Provider: Microsoft Azure for Students
- Instance type: B2s — 2 vCPU, 4GB RAM
- Credit: $100 free per year (no credit card required — student email only)
- OS: Ubuntu 22.04 LTS
- Open ports: 9000 (MinIO API), 9001 (MinIO Console), 8080 (FileBrowser), 22 (SSH)

---

## What to Build — Step by Step

### Step 1 — Azure VM Setup
- Sign up at azure.microsoft.com/free/students using a student email
- Provision a B2s Ubuntu 22.04 VM
- Configure Network Security Group to open ports 9000, 9001, 8080
- Set up SSH access with a key pair
- Run system updates: `apt update && apt upgrade -y`
- Install Git: `apt install git -y`

### Step 2 — GitHub Repository Setup
- Create a new GitHub repository for this project
- Add a `.github/workflows/deploy.yml` file for auto-deployment
- Store secrets in GitHub Secrets:
  - `AZURE_VM_IP` → public IP of the Azure VM
  - `AZURE_SSH_KEY` → private SSH key to connect to Azure
  - `MINIO_ROOT_USER` → MinIO admin username
  - `MINIO_ROOT_PASSWORD` → MinIO admin password

### Step 3 — GitHub Actions Auto-Deploy Workflow
Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Azure

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Deploy to Azure VM
        uses: appleboy/ssh-action@v0.1.10
        with:
          host: ${{ secrets.AZURE_VM_IP }}
          username: azureuser
          key: ${{ secrets.AZURE_SSH_KEY }}
          script: |
            cd /opt/personal-cloud
            git pull origin main
            docker compose down
            docker compose up -d
            echo "Deployed successfully"
```

Every `git push` to main → Azure auto-pulls and restarts. No manual SSH needed.

### Step 4 — Install and Configure Rclone
- Install Rclone on the Azure VM
- Configure two Google Drive remotes:
  - `gdrive1` → Google Drive Account 1 (hot storage — active files)
  - `gdrive2` → Google Drive Account 2 (cold storage — backups and archives)
- Mount both remotes as local directories:
  - `gdrive1` → `/mnt/drive1`
  - `gdrive2` → `/mnt/drive2`
- Configure Rclone mounts to start automatically on server reboot using systemd
- Enable VFS caching for better performance (`/tmp/rclone-cache`)

### Step 5 — Install and Configure MinIO
- Download and install MinIO server (latest stable)
- Point MinIO data directory to `/mnt/drive1/minio-data`
- Set admin credentials via environment variables
- Configure MinIO to start as a systemd service
- Expose MinIO on:
  - Port 9000 → S3 API endpoint
  - Port 9001 → Web console
- Create initial buckets:
  - `uploads` — for app file uploads
  - `backups` — for database and server backups
  - `media` — for videos and large media files
  - `assets` — for static assets and documents

### Step 6 — Install FileBrowser
- Install FileBrowser
- Point root directory to `/mnt/drive1`
- Configure admin credentials
- Run FileBrowser on port 8080
- Configure as systemd service for auto-start

### Step 7 — Nginx Reverse Proxy (Optional but recommended)
- Install Nginx
- Configure reverse proxy:
  - `s3.yourdomain.com` → MinIO API (port 9000)
  - `console.yourdomain.com` → MinIO Console (port 9001)
  - `files.yourdomain.com` → FileBrowser (port 8080)
- Set up SSL with Certbot (Let's Encrypt) for HTTPS

### Step 8 — Automated Backup Pipeline
- Set up cron jobs to automatically sync important data:
  - Daily backup of server files → gdrive1:backups
  - Weekly sync of drive1 to drive2 (redundancy)
  - Database dump scripts piped to MinIO backups bucket

---

## Storage Layout

```
Google Drive Account 1 (Hot — /mnt/drive1)
├── minio-data/
│   ├── uploads/       ← user/app file uploads
│   ├── assets/        ← static files, documents
│   ├── media/         ← videos, large media
│   └── backups/       ← DB dumps, server backups
└── filebrowser/       ← direct file access via UI

Google Drive Account 2 (Cold — /mnt/drive2)
├── archive/           ← old projects, completed work
├── pc-backup/         ← full laptop/desktop backups
├── photos/            ← personal photo archive
└── redundancy/        ← mirror of drive1 critical data
```

### Pluggable Drives

FileBrowser drives are generated from:

```text
config/drives.json
```

Deployment writes `docker-compose.generated-drives.yml` from that config, then
starts Docker Compose with the generated file. The `/cloud` folder itself is a
read-only shell directory, so FileBrowser cannot upload to VM disk by accident.
Only enabled drive mount folders are writable.

Current flags:

```env
ENABLED_DRIVES=
DRIVE1_ENABLED=true
DRIVE2_NORMAL_MODE=false
VM_SPACE=
```

For new drives, prefer the scalable GitHub Actions secret:

```text
ENABLED_DRIVES=drive2,drive3,photos
```

GitHub Actions cannot automatically read brand-new secret names such as
`DRIVE3_ENABLED` unless the workflow is edited to mention them. `ENABLED_DRIVES`
keeps adding future drives plug-and-play.

With defaults, FileBrowser shows:

```text
drive1/
```

With `DRIVE2_NORMAL_MODE=true`, FileBrowser shows:

```text
drive1/
drive2/
```

When Drive 2 normal mode is enabled, the weekly Drive 1 to Drive 2 mirror is
skipped so normal Drive 2 files are not overwritten.

With `VM_SPACE=READ_ONLY`, FileBrowser also shows:

```text
vm-space/
```

That maps to `/mnt/vm-storage` as read-only. FileBrowser can download files
from it, but cannot upload into it.

With `VM_SPACE=READ_WRITE`, the same `vm-space/` folder is writable. Leave
`VM_SPACE` empty to hide VM disk space from FileBrowser.

#### Add A New Google Drive

1. Add a block to `config/drives.json`:

```json
{
  "name": "drive3",
  "host_path": "/mnt/drive3",
  "browser_path": "/cloud/drive3",
  "mode": "rw",
  "enabled_env": "DRIVE3_ENABLED",
  "default_enabled": false,
  "required": false,
  "marker": "/mnt/drive3/.rclone-mounted",
  "kind": "rclone",
  "rclone_remote": "gdrive3"
}
```

2. Commit the config and add the drive name to the `ENABLED_DRIVES` GitHub Actions secret:

```text
ENABLED_DRIVES=drive3
```

3. Push to `main`.

If the Google account has not been authorized yet, GitHub Actions will stop with
a command like this:

```bash
cd /opt/personal-cloud
sudo PROJECT_DIR=/opt/personal-cloud bash scripts/setup-drive.sh drive3
```

Run that command once on the VM. It starts rclone authorization, prints the
Google approval URL, installs the systemd mount, creates the mount marker, and
regenerates FileBrowser mounts.

The manual approval step is required because Google OAuth cannot be safely
completed inside a non-interactive GitHub Actions deploy job.

If you prefer doing the auth first, run:

```bash
sudo rclone config
```

Create the remote name used in config, for example:

```text
gdrive3
```

Then install and start the mount service:

```bash
cd /opt/personal-cloud
sudo PROJECT_DIR=/opt/personal-cloud bash scripts/install-rclone-mount.sh drive3
```

4. Confirm the mount is real, then create the marker:

```bash
findmnt /mnt/drive3
sudo touch /mnt/drive3/.rclone-mounted
```

---

## S3 API Usage (After Setup)

This setup is fully S3-compatible. Use it in any project exactly like AWS S3,
just change the endpoint:

### Node.js
```javascript
import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";

const s3 = new S3Client({
  endpoint: "http://YOUR_AZURE_VM_IP:9000",
  region: "us-east-1",         // required but ignored by MinIO
  credentials: {
    accessKeyId: "YOUR_MINIO_USER",
    secretAccessKey: "YOUR_MINIO_PASSWORD"
  },
  forcePathStyle: true          // required for MinIO
});

// Upload
await s3.send(new PutObjectCommand({
  Bucket: "uploads",
  Key: "images/photo.jpg",
  Body: fileBuffer,
  ContentType: "image/jpeg"
}));

// Download
const file = await s3.send(new GetObjectCommand({
  Bucket: "uploads",
  Key: "images/photo.jpg"
}));
```

### Python
```python
import boto3

s3 = boto3.client(
  's3',
  endpoint_url='http://YOUR_AZURE_VM_IP:9000',
  aws_access_key_id='YOUR_MINIO_USER',
  aws_secret_access_key='YOUR_MINIO_PASSWORD'
)

s3.upload_file('photo.jpg', 'uploads', 'images/photo.jpg')
```

---

## Key Limits to Know

| Limit | Value | Notes |
|---|---|---|
| Upload per day | 750 GB per Drive account | 1.5TB/day total across 2 accounts |
| Download bandwidth | ~10 TB/day | More than enough |
| Single file max size | 5 TB | No practical limit |
| API rate limit | 12,000 req / 100 sec | Fine for personal + small apps |
| Azure B2s credit | ~3 months at $34/month | Downsize to B1s after setup |
| Codespaces hours | 180 core hrs/month (Pro) | ~90 real hrs on 2-core machine |

---

## Cost Breakdown

| Tool | Cost |
|---|---|
| GitHub Codespaces | Free (GitHub Pro) |
| GitHub Actions | Free (GitHub Pro) |
| Azure VM (B2s) | From $100 student credit |
| Google Drive 10TB | Free (already have it) |
| MinIO | Free open source |
| FileBrowser | Free open source |
| Rclone | Free open source |
| **Total** | **$0** |

---

## What This Replaces

| Service | Replaced By | Monthly Saving |
|---|---|---|
| AWS S3 (100GB) | MinIO on Drive | ~$20 |
| Dropbox (2TB) | FileBrowser on Drive | ~$15 |
| DigitalOcean Droplet | Azure Student VM | ~$10 |
| Backblaze B2 | Rclone backups to Drive | ~$6 |
| **Total** | | **~$50/month** |

---

## What This is NOT Suitable For

- High traffic public CDN (millions of daily requests)
- HIPAA / SOC2 / compliance-heavy applications
- Sub-100ms latency requirements
- Replacing production AWS infrastructure for large scale apps

## What This is PERFECT For

- Side projects and personal apps
- Early stage SaaS applications
- Developer tooling and internal apps
- Database and server backups
- Personal media and photo vault
- File sharing and collaboration (small team)

---

## Deliverables Expected from This Prompt

1. Complete shell script to set up everything from scratch on a fresh Ubuntu 22.04 Azure VM
2. GitHub Actions workflow file (`deploy.yml`) for auto-deployment on every git push
3. Systemd service files for Rclone mounts, MinIO, and FileBrowser
4. Nginx config for reverse proxy with SSL
5. Cron job scripts for automated backups
6. Example app integration code (Node.js and Python)
7. Rclone config template for two Google Drive accounts
8. Docker Compose file to run MinIO + FileBrowser together

---

## Notes

- Develop everything in GitHub Codespaces — never write code directly on the Azure VM
- All services should auto-start on server reboot via systemd
- GitHub Actions deploys automatically on every push to `main` branch
- Rclone VFS cache should be configured to `/tmp/rclone-cache` to avoid filling the root disk
- MinIO should have a separate access key per application (not using root credentials in apps)
- FileBrowser password should be changed from default immediately after setup
- Google Drive OAuth tokens refresh automatically via Rclone
- After initial setup and testing, downsize Azure VM from B2s to B1s to extend the $100 credit
- Azure Student credit renews every year — re-verify student status before expiry
