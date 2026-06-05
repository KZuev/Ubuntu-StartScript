#!/usr/bin/env bash
# Common utilities: logging, error handling, validation, idempotency

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_FILE="${SETUP_LOG_FILE:-/var/log/server-setup.log}"

_log() {
    local level="$1"; shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

log_info()  { _log "INFO " "$@"; }
log_warn()  { _log "WARN " "$@" >&2; }
log_error() { _log "ERROR" "$@" >&2; }

phase() {
    echo "" | tee -a "$LOG_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
    echo "  $*" | tee -a "$LOG_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------
set -euo pipefail
trap '_on_error $LINENO $?' ERR

_on_error() {
    log_error "Script failed at line $1 (exit code: $2)"
    log_error "Check log: ${LOG_FILE}"
    exit 1
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run as root (use sudo)" >&2
        exit 1
    fi
}

require_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        log_error "This script is designed for Ubuntu only. Detected: ${ID:-unknown}"
        exit 1
    fi
    log_info "Detected Ubuntu ${VERSION_ID:-?}"
}

# ---------------------------------------------------------------------------
# Config validation — prevents common lockout scenarios
# ---------------------------------------------------------------------------
validate_config() {
    local errors=0

    # Hostname
    if [[ -z "${SETUP_HOSTNAME:-}" ]]; then
        log_error "SETUP_HOSTNAME is required"
        (( errors++ )) || true
    fi

    # Timezone
    if [[ -z "${SETUP_TIMEZONE:-}" ]]; then
        log_error "SETUP_TIMEZONE is required"
        (( errors++ )) || true
    elif ! timedatectl list-timezones 2>/dev/null | grep -qx "${SETUP_TIMEZONE}"; then
        log_warn "SETUP_TIMEZONE '${SETUP_TIMEZONE}' may not be valid — proceeding anyway"
    fi

    # New user — must match Linux username rules (lowercase, no spaces)
    if [[ -z "${SETUP_NEW_USER:-}" ]]; then
        log_error "SETUP_NEW_USER is required"
        (( errors++ )) || true
    elif [[ ! "${SETUP_NEW_USER}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        log_error "SETUP_NEW_USER='${SETUP_NEW_USER}' is invalid. Use lowercase letters, digits, _ or - only (e.g. 'kirill')"
        (( errors++ )) || true
    fi

    # SSH lockout prevention: disabling password auth without a key = lockout
    local key="${SETUP_SSH_PUBLIC_KEY:-}"
    if [[ "${SETUP_SSH_PASSWORD_AUTH:-yes}" == "no" ]]; then
        if [[ -z "$key" || "$key" == "ssh-ed25519 AAAA..." || "$key" == "YOUR_PUBLIC_KEY_HERE" ]]; then
            log_error "FATAL: SETUP_SSH_PASSWORD_AUTH=no but no valid SSH public key provided."
            log_error "You will be permanently locked out. Set SETUP_SSH_PUBLIC_KEY first."
            (( errors++ )) || true
        fi
    fi

    # SSH port must be in UFW allowed ports
    local ssh_port="${SETUP_SSH_PORT:-22}"
    local ufw_ports="${SETUP_UFW_ALLOWED_PORTS:-}"
    if [[ "${SETUP_UFW_ENABLE:-yes}" == "yes" ]]; then
        if ! echo "$ufw_ports" | grep -qw "$ssh_port"; then
            log_warn "SSH port ${ssh_port} not in SETUP_UFW_ALLOWED_PORTS — adding automatically"
            SETUP_UFW_ALLOWED_PORTS="${ssh_port} ${ufw_ports}"
            export SETUP_UFW_ALLOWED_PORTS
        fi
    fi

    # Fish as root shell: fish is not POSIX, breaks system scripts
    if [[ "${SETUP_NEW_USER_SHELL:-bash}" == "fish" && "${SETUP_NEW_USER:-}" == "root" ]]; then
        log_error "Cannot set fish as shell for root — fish is not POSIX compatible"
        (( errors++ )) || true
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Config validation failed with ${errors} error(s). Aborting."
        exit 1
    fi

    log_info "Config validation passed"
}

# ---------------------------------------------------------------------------
# Idempotency markers — safe to re-run after interruption
# ---------------------------------------------------------------------------
MARKER_DIR="/var/log/server-setup.markers"

is_done() {
    [[ -f "${MARKER_DIR}/$1" ]]
}

mark_done() {
    mkdir -p "$MARKER_DIR"
    date > "${MARKER_DIR}/$1"
}

# ---------------------------------------------------------------------------
# Apt helper — always noninteractive, no interactive prompts
# ---------------------------------------------------------------------------
apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "$@"
}

apt_remove() {
    DEBIAN_FRONTEND=noninteractive apt-get purge -y -q "$@" 2>/dev/null || true
}
