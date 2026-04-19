#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/personal-cloud}"
SKIP_MARKER_CHECK=false

if [ "${1:-}" = "--skip-marker-check" ]; then
    SKIP_MARKER_CHECK=true
    shift
fi

CONFIG_FILE="${1:-${PROJECT_DIR}/config/drives.json}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to prepare drive folders" >&2
    exit 1
fi

cloud_root="$(jq -r '.cloud_root' "${CONFIG_FILE}")"

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

mkdir -p "${cloud_root}"
chmod 555 "${cloud_root}"

while IFS= read -r drive; do
    name="$(jq -r '.name' <<<"${drive}")"
    host_path="$(jq -r '.host_path' <<<"${drive}")"
    enabled_env="$(jq -r '.enabled_env // ""' <<<"${drive}")"
    default_enabled="$(jq -r '.default_enabled // false' <<<"${drive}")"
    marker="$(jq -r '.marker // ""' <<<"${drive}")"
    browser_path="$(jq -r '.browser_path' <<<"${drive}")"
    cloud_name="${browser_path##*/}"

    if ! is_enabled "${name}" "${enabled_env}" "${default_enabled}"; then
        continue
    fi

    mkdir -p "${cloud_root}/${cloud_name}"
    chmod 555 "${cloud_root}/${cloud_name}"
    mkdir -p "${host_path}"

    if [ "${SKIP_MARKER_CHECK}" = "false" ] && [ -n "${marker}" ] && [ ! -e "${marker}" ]; then
        echo "Missing mount marker for ${name}: ${marker}" >&2
        echo "Create it only after ${host_path} is mounted and authorized." >&2
        exit 1
    fi
done < <(jq -c '.drives[]' "${CONFIG_FILE}")
