# config_lib.sh - Shared helpers to manage the power controller config file.
#
# This file is meant to be *sourced* by deploy/install.sh and
# deploy/update.sh. Both scripts define a log() function and the
# INSTALL_DIR / APP_NAME variables before sourcing it.
#
# Provides:
#   is_valid_ipv4 <ip>
#   read_config_value <config-file> <key>
#   ask_power_controller_ip <current-ip>         # echoes the chosen IP
#   ask_power_controller_api_key <current-key>   # echoes the chosen key
#   write_power_controller_config <config-file> <ip> <api-key>
#   ensure_power_controller_config               # uses INSTALL_DIR / APP_NAME

is_valid_ipv4() {
    local ip="$1"
    [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local -a octets
    IFS='.' read -r -a octets <<< "${ip}"
    local octet
    for octet in "${octets[@]}"; do
        (( 10#${octet} <= 255 )) || return 1
    done
    return 0
}

# Print the value of <key> currently stored in the config file ("" if none).
read_config_value() {
    local config_file="$1"
    local key="$2"
    [[ -f "${config_file}" ]] || return 0
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "${config_file}" | tail -n 1
}

# Ask the user for the power controller IP (validated). Prints the result.
ask_power_controller_ip() {
    local current_ip="${1:-}"
    local ip=""

    if [[ ! -r /dev/tty ]]; then
        echo "No terminal available to ask for the power controller IP address." >&2
        echo "Create ${INSTALL_DIR}/config.cfg manually (see README) and re-run." >&2
        return 1
    fi

    while true; do
        if [[ -n "${current_ip}" ]]; then
            read -r -p "Power controller IP address [${current_ip}]: " ip </dev/tty
            ip="${ip:-${current_ip}}"
        else
            read -r -p "Power controller IP address: " ip </dev/tty
        fi
        if is_valid_ipv4 "${ip}"; then
            printf '%s\n' "${ip}"
            return 0
        fi
        echo "Invalid IPv4 address - please try again (e.g. 192.168.1.10)." >&2
    done
}

# Ask the user for the power controller API key (non-empty). Prints the result.
ask_power_controller_api_key() {
    local current_key="${1:-}"
    local key=""

    if [[ ! -r /dev/tty ]]; then
        echo "No terminal available to ask for the power controller API key." >&2
        echo "Create ${INSTALL_DIR}/config.cfg manually (see README) and re-run." >&2
        return 1
    fi

    while true; do
        if [[ -n "${current_key}" ]]; then
            read -r -p "Power controller API key [${current_key}]: " key </dev/tty
            key="${key:-${current_key}}"
        else
            read -r -p "Power controller API key: " key </dev/tty
        fi
        if [[ -n "${key}" ]]; then
            printf '%s\n' "${key}"
            return 0
        fi
        echo "API key cannot be empty." >&2
    done
}

# Write the config file with the given IP and API key (root-only read: the
# file contains a credential).
write_power_controller_config() {
    local config_file="$1"
    local ip="$2"
    local api_key="$3"

    cat > "${config_file}" <<EOF
# PWR BC250 client configuration.
# Created by the deploy scripts -- edit this file at any time, then run:
#   sudo systemctl restart ${APP_NAME}

[power-controller]
# IP address of the power controller this machine belongs to.
ip = ${ip}
# API key used to authenticate against the power controller API.
api-key = ${api_key}
EOF
    chmod 600 "${config_file}"
}

# Make sure ${INSTALL_DIR}/config.cfg exists and contains a valid IP and an
# API key. Only the missing/invalid values are asked for; a complete file is
# left untouched.
ensure_power_controller_config() {
    local config_file="${INSTALL_DIR}/config.cfg"
    local current_ip="" current_key=""

    current_ip="$(read_config_value "${config_file}" "ip")"
    current_key="$(read_config_value "${config_file}" "api-key")"

    if [[ -f "${config_file}" ]] && is_valid_ipv4 "${current_ip}" && [[ -n "${current_key}" ]]; then
        log "Power controller config already present in ${config_file} (IP ${current_ip})."
        return 0
    fi

    local ip api_key
    if is_valid_ipv4 "${current_ip}"; then
        ip="${current_ip}"
    else
        ip="$(ask_power_controller_ip "${current_ip}")"
    fi
    if [[ -n "${current_key}" ]]; then
        api_key="${current_key}"
    else
        api_key="$(ask_power_controller_api_key)"
    fi
    write_power_controller_config "${config_file}" "${ip}" "${api_key}"
    log "Power controller configuration saved to ${config_file}"
}
