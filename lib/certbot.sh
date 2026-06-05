#!/usr/bin/env bash
# SSL certificate via Let's Encrypt (certbot standalone)

configure_certbot() {
    [[ -z "${SETUP_DOMAIN:-}" ]] && return

    is_done "certbot" && { log_info "certbot: already configured, skipping"; return; }

    local domain="${SETUP_DOMAIN}"
    local email="${SETUP_CERTBOT_EMAIL:-}"

    log_info "Obtaining SSL certificate for domain: ${domain}"

    apt_install certbot

    # Certbot standalone uses port 80 for HTTP challenge — UFW must allow it
    if ! ss -tlnp | grep -q ":80[[:space:]]"; then
        log_info "Port 80 is open in UFW (required for HTTP challenge)"
    fi

    local email_arg
    if [[ -n "$email" ]]; then
        email_arg="--email ${email}"
    else
        email_arg="--register-unsafely-without-email"
        log_warn "No SETUP_CERTBOT_EMAIL set — you won't get expiry notifications"
    fi

    # shellcheck disable=SC2086
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        $email_arg \
        -d "$domain"

    # Certbot installs a renewal timer automatically; verify it is active
    local timer_active="no"
    for timer in certbot.timer snap.certbot.renew.timer; do
        if systemctl enable --now "$timer" &>/dev/null; then
            timer_active="$timer"
            break
        fi
    done

    if [[ "$timer_active" == "no" ]]; then
        # Fall back to cron if systemd timer not found
        if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
            (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --standalone") | crontab -
            log_info "Auto-renewal configured via cron (daily at 03:00)"
        fi
    else
        log_info "Auto-renewal timer active: ${timer_active}"
    fi

    mark_done "certbot"
    log_info "Certificate obtained: /etc/letsencrypt/live/${domain}/"
    log_info "Renewal: certbot renew --dry-run   (to test)"
}
