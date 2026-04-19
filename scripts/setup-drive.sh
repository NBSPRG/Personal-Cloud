#!/usr/bin/env bash
# Usage: sudo PROJECT_DIR=/opt/personal-cloud ./scripts/setup-drive.sh drive3
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/personal-cloud}"
CONFIG_FILE="${PROJECT_DIR}/config/drives.json"
DRIVE_NAME="${1:-}"
RCLONE_CONFIG="/root/.config/rclone/rclone.conf"

if [ -z "${DRIVE_NAME}" ]; then
    echo "Usage: $0 DRIVE_NAME" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to set up drives" >&2
    exit 1
fi

drive="$(jq -c --arg name "${DRIVE_NAME}" '.drives[] | select(.name == $name)' "${CONFIG_FILE}")"

if [ -z "${drive}" ]; then
    echo "Drive not found in ${CONFIG_FILE}: ${DRIVE_NAME}" >&2
    exit 1
fi

kind="$(jq -r '.kind // "local"' <<<"${drive}")"
host_path="$(jq -r '.host_path' <<<"${drive}")"
marker="$(jq -r '.marker // ""' <<<"${drive}")"
rclone_remote="$(jq -r '.rclone_remote // ""' <<<"${drive}")"

mkdir -p "${host_path}"

if [ "${kind}" != "rclone" ]; then
    echo "Prepared local drive '${DRIVE_NAME}' at ${host_path}"
    exit 0
fi

if [ -z "${rclone_remote}" ]; then
    echo "Missing rclone_remote for ${DRIVE_NAME}" >&2
    exit 1
fi

mkdir -p "$(dirname "${RCLONE_CONFIG}")"

rclone_type="$(jq -r '.rclone_type // "drive"' <<<"${drive}")"

if ! rclone listremotes --config "${RCLONE_CONFIG}" | grep -qx "${rclone_remote}:"; then
    echo ""
    echo "Authorizing remote '${rclone_remote}' (type: ${rclone_type})."
    echo "Rclone will print an authorization URL. Open it, approve access, and paste the result if asked."
    echo ""

    case "${rclone_type}" in
        drive)
            rclone config create "${rclone_remote}" drive \
                scope drive \
                --config "${RCLONE_CONFIG}" || FALLBACK=true
            ;;
        onedrive)
            rclone config create "${rclone_remote}" onedrive \
                --config "${RCLONE_CONFIG}" || FALLBACK=true
            ;;
        *)
            echo "Unknown rclone_type '${rclone_type}'. Run 'sudo rclone config' manually." >&2
            exit 1
            ;;
    esac

    if [ "${FALLBACK:-false}" = "true" ]; then
        echo ""
        echo "Automatic config failed. Run 'sudo rclone config' and create a remote named '${rclone_remote}', then rerun this command."
        exit 1
    fi
fi

sudo PROJECT_DIR="${PROJECT_DIR}" bash "${PROJECT_DIR}/scripts/install-rclone-mount.sh" "${DRIVE_NAME}"
sleep 5

if ! findmnt "${host_path}" >/dev/null 2>&1; then
    echo "Drive '${DRIVE_NAME}' did not mount at ${host_path}" >&2
    echo "Check: systemctl status rclone-drive@${DRIVE_NAME}.service" >&2
    exit 1
fi

if [ -n "${marker}" ]; then
    touch "${marker}"
fi

PROJECT_DIR="${PROJECT_DIR}" bash "${PROJECT_DIR}/scripts/prepare-drives.sh"
PROJECT_DIR="${PROJECT_DIR}" bash "${PROJECT_DIR}/scripts/generate-drive-compose.sh"

if command -v docker >/dev/null 2>&1; then
    cd "${PROJECT_DIR}"
    docker compose -f docker-compose.yml -f docker-compose.generated-drives.yml up -d filebrowser
fi

echo "Drive '${DRIVE_NAME}' is ready."
