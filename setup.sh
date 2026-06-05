#!/usr/bin/env bash
# Ubuntu Server Initial Setup Script
# Usage:
#   sudo ./setup.sh --init         Generate config template → edit config.conf → run again
#   sudo ./setup.sh                Run setup with config.conf
#   sudo ./setup.sh /path/to.conf  Run setup with a specific config file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_EXAMPLE="${SCRIPT_DIR}/config.example.conf"
CONFIG_DEFAULT="${SCRIPT_DIR}/config.conf"

# ─── --init: generate config template ────────────────────────────────────────
if [[ "${1:-}" == "--init" ]]; then
    if [[ ! -f "$CONFIG_EXAMPLE" ]]; then
        echo "ERROR: config.example.conf not found in ${SCRIPT_DIR}" >&2
        exit 1
    fi
    if [[ -f "$CONFIG_DEFAULT" ]]; then
        echo "Config file already exists: ${CONFIG_DEFAULT}"
        echo "Delete it first if you want to regenerate."
        exit 1
    fi
    cp "$CONFIG_EXAMPLE" "$CONFIG_DEFAULT"
    echo ""
    echo "Config template created: ${CONFIG_DEFAULT}"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the config:  nano ${CONFIG_DEFAULT}"
    echo "  2. Run setup:        sudo ${SCRIPT_DIR}/setup.sh"
    echo ""
    exit 0
fi

# ─── Load library modules ─────────────────────────────────────────────────────
for lib in "${SCRIPT_DIR}/lib/"*.sh; do
    # shellcheck source=/dev/null
    source "$lib"
done

# ─── Root check ───────────────────────────────────────────────────────────────
require_root

# ─── Load config ──────────────────────────────────────────────────────────────
CONFIG_FILE="${1:-$CONFIG_DEFAULT}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo ""
    echo "ERROR: No config file found at: ${CONFIG_FILE}"
    echo ""
    echo "Generate one with:  sudo ./setup.sh --init"
    echo "Then edit:          nano ${CONFIG_DEFAULT}"
    echo "Then run:           sudo ./setup.sh"
    echo ""
    exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ─── Ensure log file is writable ──────────────────────────────────────────────
mkdir -p "$(dirname "${SETUP_LOG_FILE:-/var/log/server-setup.log}")"
touch "${SETUP_LOG_FILE:-/var/log/server-setup.log}"

log_info "========================================================"
log_info " Ubuntu Server Setup — started"
log_info " Config: ${CONFIG_FILE}"
log_info " Log:    ${SETUP_LOG_FILE:-/var/log/server-setup.log}"
log_info "========================================================"

# ─── Validate config ──────────────────────────────────────────────────────────
require_ubuntu
validate_config

# Phase 1 installs packages (chrony, locales) — package lists must be fresh first
phase "Phase 0: Package Lists"
if ! is_done "apt_update"; then
    log_info "Updating package lists"
    apt-get update -q
    mark_done "apt_update"
else
    log_info "Package lists: already updated, skipping"
fi

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 1 — System Identity
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 1: System Identity"
setup_hostname
setup_timezone
setup_locale
setup_ntp

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 2 — System Resources
#  Swap BEFORE apt upgrade — prevents OOM on small VPS during package installs
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 2: System Resources"
setup_swap
apply_sysctl

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 3 — Package Management
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 3: Package Management"
apt_update_upgrade
install_base_packages
remove_packages
install_optional_packages

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 4 — User Setup
#  SSH key is installed HERE — before SSH hardening.
#  This order ensures key access exists before password auth is disabled.
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 4: User Setup"
create_user
configure_user_shell
install_ssh_key

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 5 — Security Hardening
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 5: Security Hardening"
configure_ssh
harden_root
configure_fail2ban

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 6 — Firewall
#  Rules are added BEFORE ufw enable — enabling with no rules = lockout
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 6: Firewall"
configure_ufw

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 7 — Maintenance
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 7: Maintenance"
configure_auto_updates
cleanup_packages

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 8 — Completion Report
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 8: Complete"

SERVER_IP=$(hostname -I | awk '{print $1}')
SSH_PORT="${SETUP_SSH_PORT:-22}"
NEW_USER="${SETUP_NEW_USER:-admin}"

log_info "========================================================"
log_info " SETUP COMPLETE — $(date)"
log_info "========================================================"
log_info " Hostname:  ${SETUP_HOSTNAME}"
log_info " Timezone:  ${SETUP_TIMEZONE}"
log_info " User:      ${NEW_USER} (sudo)"
log_info " SSH port:  ${SSH_PORT}"
log_info " Log file:  ${SETUP_LOG_FILE:-/var/log/server-setup.log}"
log_info ""

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║            SERVER SETUP COMPLETE                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Hostname:     ${SETUP_HOSTNAME}"
echo "  New user:     ${NEW_USER} (with sudo)"
echo "  SSH port:     ${SSH_PORT}"
if [[ -n "${GENERATED_PASSWORD:-}" ]]; then
echo ""
echo "  Password:     ${GENERATED_PASSWORD}"
echo "  (auto-generated — save it now, it won't be shown again)"
fi
echo ""
echo "  Connect with:"
echo "    ssh -p ${SSH_PORT} ${NEW_USER}@${SERVER_IP}"
echo ""

# Warn about important security settings
WARNINGS=()

if [[ "${SETUP_DISABLE_ROOT_LOGIN:-yes}" == "yes" ]]; then
    WARNINGS+=("Root password is LOCKED — use '${NEW_USER}' account")
fi

if [[ "${SETUP_SSH_PASSWORD_AUTH:-yes}" == "no" ]]; then
    WARNINGS+=("Password SSH login is DISABLED — key auth only")
fi

if [[ "${SETUP_UFW_ENABLE:-yes}" == "yes" ]]; then
    WARNINGS+=("UFW firewall is ACTIVE — check 'ufw status' for open ports")
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "  Important:"
    for w in "${WARNINGS[@]}"; do
        echo "    • ${w}"
    done
    echo ""
fi

echo "  Log: ${SETUP_LOG_FILE:-/var/log/server-setup.log}"
echo ""

log_info "Setup finished successfully"
