#!/usr/bin/env bash
#
# update.sh - Download the latest version of the app from GitHub, update
#             /opt/pwr-bc250-client, and restart the systemd service.
#
# Usage:  sudo ./deploy/update.sh [branch-or-tag]
#         (defaults to the repo's default branch, e.g. main)
#
set -euo pipefail

APP_NAME="pwr-bc250-client"
INSTALL_DIR="/opt/${APP_NAME}"
REF="${1:-}"   # optional branch/tag/commit; empty = repo default branch

log() { echo ">>> $*"; }

# --------------------------------------------------------------------------
# 0. Sanity checks
# --------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must be run as root: sudo ./deploy/update.sh" >&2
    exit 1
fi

if [[ ! -f "/etc/systemd/system/${APP_NAME}.service" ]]; then
    echo "Service '${APP_NAME}' is not installed. Run deploy/install.sh first." >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "curl not found. Please install curl first." >&2
    exit 1
fi

# --------------------------------------------------------------------------
# 1. Resolve the GitHub repo from the origin remote (fallback: known repo)
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SLUG=""

if command -v git >/dev/null 2>&1 && git -C "${SCRIPT_DIR}/.." rev-parse >/dev/null 2>&1; then
    origin_url="$(git -C "${SCRIPT_DIR}/.." config --get remote.origin.url || true)"
    # Handles https://github.com/owner/repo(.git) and git@github.com:owner/repo(.git)
    REPO_SLUG="$(printf '%s' "${origin_url}" | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
fi
REPO_SLUG="${REPO_SLUG:-igorpiedade/BC250_PWM_client}"

if [[ -z "${REF}" ]]; then
    log "Resolving default branch for ${REPO_SLUG} ..."
    REF="$(curl -fsSL "https://api.github.com/repos/${REPO_SLUG}" \
        | sed -n 's/.*"default_branch": *"\([^"]*\)".*/\1/p')"
    REF="${REF:-main}"
fi
log "Updating ${APP_NAME} from github.com/${REPO_SLUG} (ref: ${REF})"

# --------------------------------------------------------------------------
# 2. Download the tarball and extract it
# --------------------------------------------------------------------------
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

log "Downloading latest sources ..."
curl -fsSL -o "${TMP_DIR}/app.tar.gz" \
    "https://codeload.github.com/${REPO_SLUG}/tar.gz/${REF}"
tar -xzf "${TMP_DIR}/app.tar.gz" -C "${TMP_DIR}"
SRC_DIR="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

# --------------------------------------------------------------------------
# 3. Update files, dependencies, service, then restart
# --------------------------------------------------------------------------
log "Updating files in ${INSTALL_DIR} ..."
mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}/app"
cp -r "${SRC_DIR}/app" "${SRC_DIR}/requirements.txt" "${INSTALL_DIR}/"

log "Updating Python dependencies ..."
"${INSTALL_DIR}/.venv/bin/pip" install --quiet --upgrade pip
"${INSTALL_DIR}/.venv/bin/pip" install --quiet -r "${INSTALL_DIR}/requirements.txt"

log "Updating systemd unit ..."
cp "${SRC_DIR}/deploy/${APP_NAME}.service" "/etc/systemd/system/${APP_NAME}.service"
systemctl daemon-reload

log "Restarting service '${APP_NAME}' ..."
systemctl restart "${APP_NAME}"

log "Update complete."
systemctl --no-pager --full status "${APP_NAME}" || true
