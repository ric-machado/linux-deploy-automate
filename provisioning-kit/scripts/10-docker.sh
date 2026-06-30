#!/usr/bin/env bash
# Stage 10 — Docker Engine (official apt repo) + log-rotated daemon.json.
set -euo pipefail

# shellcheck source=lib/common.sh
source /opt/provisioning/scripts/lib/common.sh

require_root
require_command curl
require_command gpg

export DEBIAN_FRONTEND=noninteractive

DOCKER_KEYRING="/etc/apt/keyrings/docker.asc"
DOCKER_LIST="/etc/apt/sources.list.d/docker.list"

if [[ ! -f "$DOCKER_KEYRING" ]]; then
    log "10-docker: adding Docker apt repository"
    install -m 0755 -d /etc/apt/keyrings
    download "https://download.docker.com/linux/ubuntu/gpg" "$DOCKER_KEYRING"
    chmod a+r "$DOCKER_KEYRING"
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=${DOCKER_KEYRING}] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
        > "$DOCKER_LIST"
else
    log "10-docker: apt repository already configured, skipping"
fi

log "10-docker: apt-get update"
retry 5 apt-get update -qq

log "10-docker: installing docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
retry 5 apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

log "10-docker: writing /etc/docker/daemon.json (json-file log rotation)"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "20m",
        "max-file": "5"
    }
}
JSON

log "10-docker: enabling + starting docker"
systemctl enable docker.service containerd.service
systemctl restart docker.service

# The autoinstall identity user is the first (and only, in v1) interactive account, UID 1000.
ADMIN_USER="$(getent passwd 1000 | cut -d: -f1)"
if [[ -n "$ADMIN_USER" ]]; then
    log "10-docker: adding ${ADMIN_USER} to docker group"
    usermod -aG docker "$ADMIN_USER"
else
    log "WARN: 10-docker: no UID 1000 user found, skipping docker group membership"
fi

log "10-docker: done"
