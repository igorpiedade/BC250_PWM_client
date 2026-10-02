#!/usr/bin/env bash
#
# install.sh - Install the PWR BC250 client API as a systemd service
#              and open its port in the local firewall.
#
# Usage:  sudo ./install.sh
#
set -euo pipefail

APP_NAME="pwr-bc250-client"
INSTALL_DIR="/opt/${APP_NAME}"
PORT="8765"

log() { echo ">>> $*"; }

# --------------------------------------------------------------------------
# 0. Sanity checks
# --------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must be run as root: sudo ./install.sh" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found. Please install python3 first." >&2
    exit 1
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
    echo "python3 venv module not available." >&2
    echo "  Debian/Ubuntu: sudo apt install python3-venv" >&2
    echo "  Fedora/RHEL:   sudo dnf install python3" >&2
    exit 1
fi

# --------------------------------------------------------------------------
# 1. Copy application files
# --------------------------------------------------------------------------
log "[1/5] Installing application files to ${INSTALL_DIR} ..."
mkdir -p "${INSTALL_DIR}"
cp -r "${SCRIPT_DIR}/app" "${SCRIPT_DIR}/requirements.txt" "${INSTALL_DIR}/"

# --------------------------------------------------------------------------
# 2. Virtual environment + dependencies
# --------------------------------------------------------------------------
log "[2/5] Creating virtual environment and installing dependencies ..."
python3 -m venv "${INSTALL_DIR}/.venv"
"${INSTALL_DIR}/.venv/bin/pip" install --quiet --upgrade pip
"${INSTALL_DIR}/.venv/bin/pip" install --quiet -r "${INSTALL_DIR}/requirements.txt"

# --------------------------------------------------------------------------
# 3. systemd service
# --------------------------------------------------------------------------
log "[3/5] Installing systemd service '${APP_NAME}' ..."
cp "${SCRIPT_DIR}/deploy/${APP_NAME}.service" "/etc/systemd/system/${APP_NAME}.service"
systemctl daemon-reload
systemctl enable "${APP_NAME}"
systemctl restart "${APP_NAME}"

# --------------------------------------------------------------------------
# 4. Firewall: open port 8765/tcp
# --------------------------------------------------------------------------
log "[4/5] Opening port ${PORT}/tcp in the firewall ..."
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    # Fedora / RHEL / openSUSE (firewalld)
    firewall-cmd --permanent --add-port="${PORT}/tcp"
    firewall-cmd --reload
    log "firewalld: ${PORT}/tcp allowed (permanent)."
elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    # Debian / Ubuntu (ufw)
    ufw allow "${PORT}/tcp" comment "PWR BC250 client API"
    log "ufw: ${PORT}/tcp allowed."
elif command -v iptables >/dev/null 2>&1 && \
     iptables -L INPUT -n >/dev/null 2>&1; then
    # Fallback: raw iptables (rule added only if not already present)
    if ! iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport "${PORT}" -j ACCEPT
    fi
    # Persist when a persistence helper is available
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save
    elif [[ -d /etc/iptables ]] && command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/iptables/rules.v4
    else
        log "iptables: rule added but NOT persisted across reboots."
    fi
    log "iptables: ${PORT}/tcp allowed."
else
    log "No active firewall detected - skipping firewall configuration."
fi

# --------------------------------------------------------------------------
# 5. Done
# --------------------------------------------------------------------------
log "[5/5] Installation complete."
systemctl --no-pager --full status "${APP_NAME}" || true
echo
echo "The API is listening on 0.0.0.0:${PORT}"
echo "  curl http://<machine-ip>:${PORT}/autodiscover"
echo "  journalctl -u ${APP_NAME} -f   # follow logs"
