#!/usr/bin/env bash
# Usage: ./backup.sh {daily|weekly|all}
set -euo pipefail

LOG_FILE="/var/log/cloud-backup.log"
DATE_STAMP=$(date "+%Y-%m-%d")
DRIVE1="gdrive1"
DRIVE2="gdrive2"
ONEDRIVE="onedrive1"
PROJECT_DIR="/opt/personal-cloud"
DRIVE2_NORMAL_MODE="${DRIVE2_NORMAL_MODE:-false}"

if [ -f "${PROJECT_DIR}/.env" ]; then
    DRIVE2_NORMAL_MODE="$(grep -E "^DRIVE2_NORMAL_MODE=" "${PROJECT_DIR}/.env" | tail -n 1 | cut -d= -f2- || echo "${DRIVE2_NORMAL_MODE}")"
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

is_onedrive_available() {
    rclone listremotes --config /root/.config/rclone/rclone.conf | grep -qx "${ONEDRIVE}:"
}

daily_backup() {
    log "=== DAILY BACKUP ==="

    rclone copy /etc/default/minio "${DRIVE1}:backups/daily/${DATE_STAMP}/server-config/" \
        --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

    rclone copy "$PROJECT_DIR" "${DRIVE1}:backups/daily/${DATE_STAMP}/project/" \
        --exclude ".git/**" --exclude ".env" \
        --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

    rclone copy /root/.config/rclone/rclone.conf "${DRIVE1}:backups/daily/${DATE_STAMP}/rclone-config/" \
        --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

    rclone delete "${DRIVE1}:backups/daily" --min-age 30d \
        --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

    # ── Offsite copy to OneDrive ──────────────────────────────────────────────
    if is_onedrive_available; then
        log "Syncing daily backup to OneDrive..."

        rclone sync "${DRIVE1}:backups/daily/${DATE_STAMP}" \
            "${ONEDRIVE}:backups/daily/${DATE_STAMP}" \
            --transfers 4 \
            --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

        # Keep only last 30 days on OneDrive too
        rclone delete "${ONEDRIVE}:backups/daily" --min-age 30d \
            --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

        log "OneDrive daily backup done."
    else
        log "OneDrive not available — skipping offsite daily backup."
    fi

    log "=== DAILY BACKUP DONE ==="
}

weekly_sync() {
    if [ "${DRIVE2_NORMAL_MODE}" = "true" ]; then
        log "Skipping weekly drive2 sync because DRIVE2_NORMAL_MODE=true"
    else
        log "=== WEEKLY SYNC — drive1 → drive2 ==="

        rclone sync "${DRIVE1}:minio-data" "${DRIVE2}:redundancy/minio-mirror" \
            --transfers 4 --checkers 8 \
            --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

        rclone sync "${DRIVE1}:backups" "${DRIVE2}:redundancy/backups-mirror" \
            --transfers 4 \
            --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

        log "=== WEEKLY SYNC drive1 → drive2 DONE ==="
    fi

    # ── Offsite sync to OneDrive ──────────────────────────────────────────────
    if is_onedrive_available; then
        log "=== WEEKLY SYNC — drive1 → OneDrive ==="

        # Full MinIO data backup to OneDrive
        rclone sync "${DRIVE1}:minio-data" "${ONEDRIVE}:minio-backup" \
            --transfers 4 --checkers 8 \
            --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

        # Full backups archive to OneDrive
        rclone sync "${DRIVE1}:backups" "${ONEDRIVE}:backups" \
            --transfers 4 \
            --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

        # Project files to OneDrive
        rclone sync "$PROJECT_DIR" "${ONEDRIVE}:personal-cloud-project" \
            --exclude ".git/**" --exclude ".env" \
            --transfers 4 \
            --log-file "$LOG_FILE" --log-level INFO 2>&1 || true

        log "=== WEEKLY SYNC drive1 → OneDrive DONE ==="
    else
        log "OneDrive not available — skipping offsite weekly sync."
    fi
}

case "${1:-all}" in
    daily)  daily_backup ;;
    weekly) weekly_sync ;;
    all)    daily_backup; weekly_sync ;;
    *)      echo "Usage: $0 {daily|weekly|all}"; exit 1 ;;
esac