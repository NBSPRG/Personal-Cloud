#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/opt/personal-cloud"
MOUNT_DRIVE1="/mnt/drive1"
MOUNT_DRIVE2="/mnt/drive2"

log() { echo "[SETUP] $*"; }

# 1. System packages
log "Updating system..."
apt update && apt upgrade -y
apt install -y git curl wget unzip fuse3 ca-certificates gnupg lsb-release ufw jq nginx

# 2. Docker
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    usermod -aG docker NBSPRG
fi

# 3. Rclone
if ! command -v rclone &>/dev/null; then
    log "Installing Rclone..."
    curl https://rclone.org/install.sh | bash
fi

# 4. Directories
mkdir -p "$MOUNT_DRIVE1" "$MOUNT_DRIVE2" /tmp/rclone-cache "$MOUNT_DRIVE1/minio-data" /var/lib/filebrowser

# 5. Systemd services
if [ -d "$PROJECT_DIR/systemd" ]; then
    cp "$PROJECT_DIR/systemd/"*.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable rclone-drive1 rclone-drive2
fi

# 6. MinIO env file
if [ ! -f /etc/default/minio ]; then
    cat > /etc/default/minio <<'EOF'
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=CHANGE_ME_TO_A_STRONG_PASSWORD
EOF
fi

# 7. Docker Compose .env
if [ -f "$PROJECT_DIR/.env.example" ] && [ ! -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
fi

# 8. Firewall
ufw allow 22/tcp
ufw allow 8080/tcp
ufw allow 9000/tcp
ufw allow 9001/tcp
ufw --force enable

# 9. Nginx configs
if [ -d "$PROJECT_DIR/nginx" ]; then
    cp "$PROJECT_DIR/nginx/"*.conf /etc/nginx/sites-available/
fi

# 10. Cron jobs
if [ -f "$PROJECT_DIR/scripts/install-crontab.sh" ]; then
    bash "$PROJECT_DIR/scripts/install-crontab.sh"
fi

echo ""
echo "Setup complete. Next steps:"
echo "  1. rclone config  (create gdrive1 and gdrive2 remotes)"
echo "  2. systemctl start rclone-drive1 rclone-drive2"
echo "  3. cd $PROJECT_DIR && nano .env && docker compose up -d"
