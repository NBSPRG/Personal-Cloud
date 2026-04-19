#!/usr/bin/env bash
# Usage: sudo PROJECT_DIR=/opt/personal-cloud ./scripts/install-rclone-mount.sh drive3
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/personal-cloud}"
CONFIG_FILE="${PROJECT_DIR}/config/drives.json"
DRIVE_NAME="${1:-}"

if [ -z "${DRIVE_NAME}" ]; then
    echo "Usage: $0 DRIVE_NAME" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to install rclone mount services" >&2
    exit 1
fi

drive="$(jq -c --arg name "${DRIVE_NAME}" '.drives[] | select(.name == $name)' "${CONFIG_FILE}")"

if [ -z "${drive}" ]; then
    echo "Drive not found in ${CONFIG_FILE}: ${DRIVE_NAME}" >&2
    exit 1
fi

kind="$(jq -r '.kind // "local"' <<<"${drive}")"
if [ "${kind}" != "rclone" ]; then
    echo "Drive is not an rclone drive: ${DRIVE_NAME}" >&2
    exit 1
fi

rclone_remote="$(jq -r '.rclone_remote // empty' <<<"${drive}")"
host_path="$(jq -r '.host_path' <<<"${drive}")"
cache_size="$(jq -r '.vfs_cache_max_size // "5G"' <<<"${drive}")"

if [ -z "${rclone_remote}" ]; then
    echo "Missing rclone_remote for ${DRIVE_NAME}" >&2
    exit 1
fi

if ! rclone listremotes --config /root/.config/rclone/rclone.conf | grep -qx "${rclone_remote}:"; then
    echo "Missing rclone remote '${rclone_remote}' in /root/.config/rclone/rclone.conf" >&2
    echo "Run 'sudo rclone config' first to authorize the Google Drive account." >&2
    exit 1
fi

mkdir -p /etc/rclone-mounts "${host_path}"
cat > "/etc/rclone-mounts/${DRIVE_NAME}.env" <<EOF
RCLONE_REMOTE=${rclone_remote}:
MOUNT_DIR=${host_path}
VFS_CACHE_MAX_SIZE=${cache_size}
EOF

cp "${PROJECT_DIR}/systemd/rclone-drive@.service" /etc/systemd/system/rclone-drive@.service
systemctl daemon-reload
systemctl enable --now "rclone-drive@${DRIVE_NAME}.service"

echo "Installed and started rclone-drive@${DRIVE_NAME}.service"
echo "After confirming the mount, create the marker:"
echo "  sudo touch ${host_path}/.rclone-mounted"
