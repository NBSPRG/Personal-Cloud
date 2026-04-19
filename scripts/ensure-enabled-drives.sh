#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/personal-cloud}"
CONFIG_FILE="${1:-${PROJECT_DIR}/config/drives.json}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to ensure enabled drives" >&2
    exit 1
fi

env_value() {
    local key="$1"
    local value=""

    value="$(printenv "${key}" || true)"

    if [ -z "${value}" ] && [ -f "${PROJECT_DIR}/.env" ]; then
        value="$(grep -E "^${key}=" "${PROJECT_DIR}/.env" | tail -n 1 | cut -d= -f2- || true)"
    fi

    printf '%s' "${value}"
}

is_listed_drive() {
    local name="$1"
    local enabled_drives=""

    enabled_drives="$(env_value "ENABLED_DRIVES")"
    enabled_drives="${enabled_drives// /}"

    if [ -z "${enabled_drives}" ]; then
        return 1
    fi

    case ",${enabled_drives}," in
        *",${name},"*) return 0 ;;
        *) return 1 ;;
    esac
}

is_enabled() {
    local name="$1"
    local enabled_env="$2"
    local default_enabled="$3"
    local value=""

    if is_listed_drive "${name}"; then
        return 0
    fi

    if [ -n "${enabled_env}" ]; then
        value="$(env_value "${enabled_env}")"
    fi

    if [ -z "${value}" ]; then
        value="${default_enabled}"
    fi

    [ "${value}" = "true" ]
}

while IFS= read -r drive; do
    name="$(jq -r '.name' <<<"${drive}")"
    kind="$(jq -r '.kind // "local"' <<<"${drive}")"
    host_path="$(jq -r '.host_path' <<<"${drive}")"
    enabled_env="$(jq -r '.enabled_env // ""' <<<"${drive}")"
    default_enabled="$(jq -r '.default_enabled // false' <<<"${drive}")"
    marker="$(jq -r '.marker // ""' <<<"${drive}")"
    rclone_remote="$(jq -r '.rclone_remote // ""' <<<"${drive}")"

    if ! is_enabled "${name}" "${enabled_env}" "${default_enabled}"; then
        continue
    fi

    mkdir -p "${host_path}"

    if [ "${kind}" != "rclone" ]; then
        continue
    fi

    if [ -n "${marker}" ] && [ -e "${marker}" ]; then
        continue
    fi

    if [ -z "${rclone_remote}" ]; then
        echo "Drive '${name}' is enabled but has no rclone_remote in ${CONFIG_FILE}" >&2
        exit 1
    fi

    if ! rclone listremotes --config /root/.config/rclone/rclone.conf | grep -qx "${rclone_remote}:"; then
        echo "" >&2
        echo "Drive '${name}' is enabled, but rclone remote '${rclone_remote}' is not authorized yet." >&2
        echo "Run this once on the VM, approve Google access, then push/redeploy:" >&2
        echo "  cd ${PROJECT_DIR}" >&2
        echo "  sudo PROJECT_DIR=${PROJECT_DIR} bash scripts/setup-drive.sh ${name}" >&2
        echo "" >&2
        exit 1
    fi

    PROJECT_DIR="${PROJECT_DIR}" bash "${PROJECT_DIR}/scripts/install-rclone-mount.sh" "${name}"
    sleep 5

    if ! findmnt "${host_path}" >/dev/null 2>&1; then
        echo "Drive '${name}' did not mount at ${host_path}" >&2
        echo "Check: systemctl status rclone-drive@${name}.service" >&2
        exit 1
    fi

    if [ -n "${marker}" ]; then
        touch "${marker}"
    fi
done < <(jq -c '.drives[]' "${CONFIG_FILE}")
