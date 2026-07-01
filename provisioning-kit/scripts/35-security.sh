#!/usr/bin/env bash
# Stage 35 — SSH hardening, UFW firewall, fail2ban.
#
# UFW + Docker note: Docker manages its own iptables rules and will bypass
# UFW for container published ports (docker run -p ...). UFW therefore does
# not restrict access to published container ports — only host-level services
# (SSH, and anything else listening on the host network directly) are
# protected by UFW rules. Manage container-port exposure via Docker networks
# or a separate iptables/nftables policy if tighter control is needed.
set -euo pipefail

# shellcheck source=lib/common.sh
source /opt/provisioning/scripts/lib/common.sh

require_root

# --admin-user <name>: explicit override; falls back to UID 1000 (the user
# created by autoinstall's identity: block, same approach as 10-docker.sh).
ADMIN_USER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --admin-user) ADMIN_USER="$2"; shift 2 ;;
        *) log "35-security: WARN unknown arg: $1"; shift ;;
    esac
done

if [[ -z "$ADMIN_USER" ]]; then
    ADMIN_USER="$(getent passwd 1000 | cut -d: -f1)"
fi

if [[ -z "$ADMIN_USER" ]]; then
    log "35-security: ERROR could not determine admin user (no UID 1000 and --admin-user not set)"
    exit 1
fi

log "35-security: admin user: ${ADMIN_USER}"

export DEBIAN_FRONTEND=noninteractive

# ── 1. UFW ───────────────────────────────────────────────────────────────────

if ! dpkg -l ufw 2>/dev/null | grep -q '^ii'; then
    log "35-security: installing ufw"
    retry 5 apt-get install -y -qq ufw
else
    log "35-security: ufw already installed"
fi

if ufw status | grep -q 'Status: active'; then
    log "35-security: UFW already active — skipping reset, ensuring SSH rule exists"
    ufw allow ssh comment "provisioning-kit" 2>/dev/null || true
else
    log "35-security: configuring UFW (default deny in, allow SSH, enable)"
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh comment "provisioning-kit"
    ufw --force enable
    log "35-security: UFW enabled"
fi

# ── 2. fail2ban ──────────────────────────────────────────────────────────────

if ! dpkg -l fail2ban 2>/dev/null | grep -q '^ii'; then
    log "35-security: installing fail2ban"
    retry 5 apt-get install -y -qq fail2ban
else
    log "35-security: fail2ban already installed"
fi

F2B_JAIL="/etc/fail2ban/jail.d/provisioning-sshd.conf"
if [[ ! -f "$F2B_JAIL" ]]; then
    log "35-security: writing fail2ban sshd jail config"
    cat > "$F2B_JAIL" <<'EOF'
# Written by provisioning-kit/scripts/35-security.sh
[sshd]
enabled  = true
port     = ssh
filter   = sshd
backend  = systemd
maxretry = 3
findtime = 600
bantime  = 3600
EOF
fi

systemctl enable fail2ban
if systemctl is-active --quiet fail2ban; then
    log "35-security: reloading fail2ban"
    systemctl reload fail2ban
else
    log "35-security: starting fail2ban"
    systemctl start fail2ban
fi

# ── 3. SSH hardening (drop-in, not touching /etc/ssh/sshd_config directly) ──

SSHD_DROP_IN="/etc/ssh/sshd_config.d/99-provisioning-hardening.conf"

if [[ ! -f "$SSHD_DROP_IN" ]]; then
    # Disable PasswordAuthentication only when the admin already has an
    # authorized_keys file — autoinstall populates this from user-data's
    # authorized-keys list. Without an SSH key on the machine, disabling
    # password auth would lock the admin out entirely.
    ADMIN_HOME="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
    ADMIN_KEYS="${ADMIN_HOME}/.ssh/authorized_keys"

    if [[ -s "$ADMIN_KEYS" ]]; then
        PASS_AUTH="no"
        log "35-security: SSH key found for ${ADMIN_USER} — disabling PasswordAuthentication"
    else
        PASS_AUTH="yes"
        log "35-security: WARN no SSH key found for ${ADMIN_USER} — keeping PasswordAuthentication yes"
        log "35-security: WARN add an SSH key and re-run this stage, or set authorized-keys in user-data"
    fi

    log "35-security: writing ${SSHD_DROP_IN}"
    cat > "$SSHD_DROP_IN" <<EOF
# Written by provisioning-kit/scripts/35-security.sh — do not edit by hand.
# Re-run the provisioning pipeline to update (idempotent once the file exists;
# delete this file first to force regeneration on the next run).
PermitRootLogin no
PasswordAuthentication ${PASS_AUTH}
MaxAuthTries 3
LoginGraceTime 30
AllowUsers ${ADMIN_USER}
X11Forwarding no
EOF

    log "35-security: validating sshd config"
    if ! sshd -t; then
        log "35-security: ERROR sshd config validation failed — removing drop-in"
        rm -f "$SSHD_DROP_IN"
        exit 1
    fi

    log "35-security: restarting ssh"
    systemctl restart ssh
else
    log "35-security: sshd drop-in already present — skipping (delete ${SSHD_DROP_IN} to regenerate)"
fi

log "35-security: done"
