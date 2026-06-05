# Ubuntu-StartScript

Universal Ubuntu server initial setup script. Tested on Ubuntu 20.04, 22.04, 24.04.

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/kzuev/ubuntu-startscript
cd ubuntu-startscript

# 2. Generate config template
sudo ./setup.sh --init

# 3. Edit config — set hostname, user, SSH key, ports, optional packages
nano config.conf

# 4. Run setup (fully unattended)
sudo ./setup.sh
```

## What It Does

Runs in 8 phases, fully unattended after config is filled:

| Phase | Actions |
|-------|---------|
| 1 — System Identity | hostname, timezone, locale, NTP (chrony) |
| 2 — Resources | swap file, sysctl network hardening |
| 3 — Packages | apt update/upgrade, base packages, optional packages |
| 4 — User | create admin user, sudo group, SSH public key |
| 5 — Hardening | SSH config, disable root password, fail2ban |
| 6 — Firewall | UFW rules (SSH always first), enable |
| 7 — Maintenance | unattended-upgrades, package cleanup |
| 8 — Report | connection command, active warnings |

## Config Reference

Key settings in `config.conf`:

```bash
SETUP_HOSTNAME="myserver"
SETUP_TIMEZONE="Europe/Moscow"
SETUP_NEW_USER="admin"
SETUP_NEW_USER_SHELL="bash"            # bash or fish
SETUP_SSH_PUBLIC_KEY="ssh-ed25519 …"  # your public key
SETUP_SSH_PORT="22"
SETUP_SSH_PASSWORD_AUTH="no"           # requires public key above
SETUP_UFW_ALLOWED_PORTS="22 80 443"
SETUP_OPTIONAL_PACKAGES="micro docker" # micro, fish, docker, or any apt package
SETUP_SWAP_SIZE_GB="2"                 # 0 to skip
SETUP_AUTO_UPDATES="yes"
```

See `config.example.conf` for all options with documentation.

## Optional Packages

| Value | What happens |
|-------|-------------|
| `micro` | Installs micro editor from official installer (not outdated apt version) |
| `fish` | Installs fish shell, sets as default for new user |
| `docker` | Installs Docker CE from official Docker repository |
| anything else | Treated as an apt package name |

Example: `SETUP_OPTIONAL_PACKAGES="micro fish docker"`

## Safety Features

- **Lockout prevention** — refuses to disable password auth if no SSH key is set
- **UFW order** — rules are added before `ufw enable` (no accidental lockout)
- **SSH test gate** — runs `sshd -t` before restarting; reverts if config is invalid
- **SSH key first** — key is installed before password auth is disabled
- **Root preserved** — `passwd -l` locks root password but keeps account for rescue console access
- **Idempotent** — safe to re-run after interruption; completed phases are skipped

## Structure

```
setup.sh               Main script (--init or run)
config.example.conf    Config template with all options
lib/
  common.sh            Logging, error handling, validation
  system.sh            hostname, timezone, locale, NTP, swap, sysctl
  packages.sh          apt wrapper, base/optional packages, auto-updates
  user.sh              User creation, sudo, SSH key, shell
  ssh.sh               sshd hardening, fail2ban
  firewall.sh          UFW
```
