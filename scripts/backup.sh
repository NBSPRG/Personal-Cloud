#!/usr/bin/env bash
# Usage: ./backup.sh {daily|weekly|all}
set -euo pipefail

LOG_FILE="/var/log/cloud-backup.log"
DATE_STAMP=$(date "+%Y-%m-%d")
DRIVE1="gdrive1"
DRIVE2="gdrive2"
PROJECT_DIR="/opt/personal-cloud"
DRIVE2_NORMAL_MODE="${DRIVE2_NORMAL_MODE:-false}"

if [ -f "${PROJECT_DIR}/.env" ]; then
    # Load deployment flags such as DRIVE2_NORMAL_MODE for cron runs.
    set -a
    . "${PROJECT_DIR}/.env"
    set +a
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

daily_backup() {
    log "=== DAILY BACKUP ==="
    rclone copy /etc/default/minio "${DRIVE1}:backups/daily/${DATE_STAMP}/server-config/" --log-file "$LOG_FILE" --log-level INFO 2>&1 || true
    rclone copy "$PROJECT_DIR" "${DRIVE1}:backups/daily/${DATE_STAMP}/project/" --exclude ".git/**" --exclude ".env" --log-file "$LOG_FILE" --log-level INFO 2>&1 || true
    rclone copy /root/.config/rclone/rclone.conf "${DRIVE1}:backups/daily/${DATE_STAMP}/rclone-config/" --log-file "$LOG_FILE" --log-level INFO 2>&1 || true
    rclone delete "${DRIVE1}:backups/daily" --min-age 30d --log-file "$LOG_FILE" --log-level INFO 2>&1 || true
    log "=== DAILY BACKUP DONE ==="
}

weekly_sync() {
    if [ "${DRIVE2_NORMAL_MODE}" = "true" ]; then
        log "Skipping weekly drive2 sync because DRIVE2_NORMAL_MODE=true"
        return 0
    fi

    log "=== WEEKLY SYNC ==="
    rclone sync "${DRIVE1}:minio-data" "${DRIVE2}:redundancy/minio-mirror" --transfers 4 --checkers 8 --log-file "$LOG_FILE" --log-level INFO 2>&1 || true
    rclone sync "${DRIVE1}:backups" "${DRIVE2}:redundancy/backups-mirror" --transfers 4 --log-file "$LOG_FILE" --log-level INFO 2>&1 || true
    log "=== WEEKLY SYNC DONE ==="
}

case "${1:-all}" in
    daily)  daily_backup ;;
    weekly) weekly_sync ;;
    all)    daily_backup; weekly_sync ;;
    *)      echo "Usage: $0 {daily|weekly|all}"; exit 1 ;;
esac
