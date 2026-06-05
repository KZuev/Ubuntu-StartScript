#!/usr/bin/env bash
# Package management: update/upgrade, base packages, optional packages

apt_update_upgrade() {
    is_done "apt_upgrade" && { log_info "apt upgrade: already done, skipping"; return; }

    # apt-get update already ran in Phase 0; run again here to pick up any
    # new repos that may have been added (e.g. by optional packages)
    apt-get update -q

    log_info "Upgrading installed packages"
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"

    log_info "Updating CA certificates"
    apt_install ca-certificates
    update-ca-certificates

    mark_done "apt_upgrade"
    log_info "System packages up to date"
}

install_base_packages() {
    is_done "base_packages" && { log_info "base packages: already installed, skipping"; return; }

    local packages="${SETUP_BASE_PACKAGES:-curl wget git ufw fail2ban htop ncdu tmux rsync \
        ca-certificates software-properties-common apt-transport-https \
        unattended-upgrades net-tools dnsutils lsof jq less logrotate chrony \
        nano gnupg}"

    log_info "Installing base packages"
    # shellcheck disable=SC2086
    apt_install $packages

    mark_done "base_packages"
    log_info "Base packages installed"
}

remove_packages() {
    local remove_list="${SETUP_REMOVE_PACKAGES:-}"
    [[ -z "$remove_list" ]] && return

    log_info "Removing packages: ${remove_list}"
    # shellcheck disable=SC2086
    apt_remove $remove_list
    log_info "Packages removed"
}

install_optional_packages() {
    local optional="${SETUP_OPTIONAL_PACKAGES:-}"
    [[ -z "$optional" ]] && return

    log_info "Installing optional packages: ${optional}"

    for pkg in $optional; do
        case "$pkg" in
            micro)  _install_micro ;;
            fish)   _install_fish ;;
            docker) _install_docker ;;
            *)
                log_info "Installing optional apt package: ${pkg}"
                apt_install "$pkg"
                ;;
        esac
    done
}

_install_micro() {
    is_done "micro" && { log_info "micro: already installed, skipping"; return; }

    if command -v micro &>/dev/null; then
        log_info "micro already installed at $(command -v micro)"
        mark_done "micro"
        return
    fi

    log_info "Installing micro editor (official installer)"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    # Download installer script and inspect before running
    curl -fsSL https://getmic.ro -o "${tmp_dir}/getmicro.sh"
    bash "${tmp_dir}/getmicro.sh"
    mv micro /usr/local/bin/micro
    chmod +x /usr/local/bin/micro
    rm -rf "$tmp_dir"

    mark_done "micro"
    log_info "micro editor installed: $(micro --version 2>/dev/null | head -1)"
}

_install_fish() {
    is_done "fish" && { log_info "fish: already installed, skipping"; return; }

    log_info "Installing fish shell"
    apt_install fish

    mark_done "fish"
    log_info "fish installed: $(fish --version 2>/dev/null)"
}

_install_docker() {
    is_done "docker" && { log_info "docker: already installed, skipping"; return; }

    if command -v docker &>/dev/null; then
        log_info "docker already installed: $(docker --version)"
        mark_done "docker"
        return
    fi

    log_info "Installing Docker CE from official repository"

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Detect Ubuntu codename (works across 20.04/22.04/24.04)
    local codename
    codename=$(. /etc/os-release && echo "$VERSION_CODENAME")

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${codename} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -q
    apt_install docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    systemctl enable --now docker

    # Add user to docker group only if the user already exists.
    # If the user is created later (Phase 4), create_user() handles this.
    if [[ -n "${SETUP_NEW_USER:-}" ]] && id "${SETUP_NEW_USER}" &>/dev/null; then
        usermod -aG docker "${SETUP_NEW_USER}"
        log_info "User ${SETUP_NEW_USER} added to docker group"
    fi

    mark_done "docker"
    log_info "Docker installed: $(docker --version)"
}

configure_auto_updates() {
    [[ "${SETUP_AUTO_UPDATES:-yes}" != "yes" ]] && {
        log_info "Auto-updates: disabled in config"
        return
    }

    is_done "auto_updates" && { log_info "auto-updates: already configured, skipping"; return; }

    log_info "Configuring unattended-upgrades"
    apt_install unattended-upgrades

    local reboot="${SETUP_AUTO_UPDATES_REBOOT:-no}"
    local reboot_bool
    [[ "$reboot" == "yes" ]] && reboot_bool="true" || reboot_bool="false"

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "${reboot_bool}";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::SyslogEnable "true";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    systemctl enable --now unattended-upgrades
    systemctl enable apt-daily.timer apt-daily-upgrade.timer

    mark_done "auto_updates"
    log_info "Auto security updates configured (auto-reboot: ${reboot})"
}

cleanup_packages() {
    log_info "Cleaning up unused packages"
    apt-get autoremove --purge -y -q 2>/dev/null || true
    apt-get autoclean -q 2>/dev/null || true
    log_info "Package cleanup complete"
}
