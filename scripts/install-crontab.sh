#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"
chmod +x "$BACKUP_SCRIPT"

CURRENT_CRON=$(crontab -l 2>/dev/null || true)

if ! echo "$CURRENT_CRON" | grep -qF "backup.sh daily"; then
    CURRENT_CRON="${CURRENT_CRON}
0 2 * * * ${BACKUP_SCRIPT} daily >> /var/log/cloud-backup-cron.log 2>&1"
fi

if ! echo "$CURRENT_CRON" | grep -qF "backup.sh weekly"; then
    CURRENT_CRON="${CURRENT_CRON}
0 3 * * 0 ${BACKUP_SCRIPT} weekly >> /var/log/cloud-backup-cron.log 2>&1"
fi

echo "$CURRENT_CRON" | crontab -
echo "Crontab updated:"
crontab -l
