#!/usr/bin/env bash
# Firewall: UFW configuration and activation

configure_ufw() {
    [[ "${SETUP_UFW_ENABLE:-yes}" != "yes" ]] && {
        log_info "UFW: disabled in config, skipping"
        return
    }

    is_done "ufw" && { log_info "UFW: already configured, skipping"; return; }

    if ! command -v ufw &>/dev/null; then
        log_warn "ufw not found, installing"
        apt_install ufw
    fi

    log_info "Configuring UFW firewall"

    # Start from clean state
    ufw --force reset > /dev/null

    # Set default policies
    ufw default "${SETUP_UFW_DEFAULT_INCOMING:-deny}" incoming > /dev/null
    ufw default "${SETUP_UFW_DEFAULT_OUTGOING:-allow}" outgoing > /dev/null
    ufw default deny forward > /dev/null

    # CRITICAL: Allow SSH port FIRST — before enabling UFW
    local ssh_port="${SETUP_SSH_PORT:-22}"
    log_info "Opening SSH port: ${ssh_port}/tcp"
    ufw allow "${ssh_port}/tcp" comment "SSH" > /dev/null

    # Rate-limit SSH to supplement fail2ban (6 connections per 30s triggers block)
    ufw limit "${ssh_port}/tcp" > /dev/null

    # Open additional ports from config
    local ports="${SETUP_UFW_ALLOWED_PORTS:-}"
    for port in $ports; do
        # Skip SSH port — already added above
        [[ "$port" == "$ssh_port" ]] && continue
        log_info "Opening port: ${port}"
        ufw allow "$port" comment "user-configured" > /dev/null
    done

    # Enable logging
    ufw logging on > /dev/null

    # Enable UFW — must be LAST after all rules are added
    log_info "Enabling UFW"
    ufw --force enable

    mark_done "ufw"
    log_info "UFW enabled. Current status:"
    ufw status verbose | tee -a "${LOG_FILE:-/var/log/server-setup.log}"
}
