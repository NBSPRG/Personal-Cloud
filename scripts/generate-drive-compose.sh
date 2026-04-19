#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/personal-cloud}"
CONFIG_FILE="${1:-${PROJECT_DIR}/config/drives.json}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to generate drive compose config" >&2
    exit 1
fi

cloud_root="$(jq -r '.cloud_root' "${CONFIG_FILE}")"
output_file="${PROJECT_DIR}/$(jq -r '.generated_compose' "${CONFIG_FILE}")"

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

enabled_count=0
marker_tests=""

{
    echo "services:"
    echo "  filebrowser:"
    echo "    volumes:"
    echo "      - ${cloud_root}:/cloud:ro"
} > "${output_file}"

while IFS= read -r drive; do
    name="$(jq -r '.name' <<<"${drive}")"
    host_path="$(jq -r '.host_path' <<<"${drive}")"
    browser_path="$(jq -r '.browser_path' <<<"${drive}")"
    mode="$(jq -r '.mode // "rw"' <<<"${drive}")"
    enabled_env="$(jq -r '.enabled_env // ""' <<<"${drive}")"
    default_enabled="$(jq -r '.default_enabled // false' <<<"${drive}")"
    marker="$(jq -r '.marker // ""' <<<"${drive}")"

    if ! is_enabled "${name}" "${enabled_env}" "${default_enabled}"; then
        continue
    fi

    enabled_count=$((enabled_count + 1))

    if [ "${mode}" = "ro" ]; then
        echo "      - ${host_path}:${browser_path}:ro" >> "${output_file}"
    else
        echo "      - ${host_path}:${browser_path}" >> "${output_file}"
    fi

    if [ -n "${marker}" ]; then
        marker_target="/mnt-check/${name}/.rclone-mounted"
        echo "      - ${marker}:${marker_target}:ro" >> "${output_file}"

        if [ -z "${marker_tests}" ]; then
            marker_tests="test -f ${marker_target}"
        else
            marker_tests="${marker_tests} && test -f ${marker_target}"
        fi
    fi
done < <(jq -c '.drives[]' "${CONFIG_FILE}")

if [ "${enabled_count}" -eq 0 ]; then
    echo "No drives are enabled. At least one drive must be enabled for FileBrowser." >&2
    exit 1
fi

if [ -z "${marker_tests}" ]; then
    marker_tests="true"
fi

{
    echo "    environment:"
    echo "      - FB_ROOT=/cloud"
    echo "    command:"
    echo "      - ${marker_tests} && filebrowser"
} >> "${output_file}"

echo "Generated ${output_file}"
