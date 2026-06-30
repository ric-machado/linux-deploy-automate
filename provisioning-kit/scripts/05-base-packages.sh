#!/usr/bin/env bash
# Stage 05 — base packages common to every dev workstation/server.
set -euo pipefail

# shellcheck source=lib/common.sh
source /opt/provisioning/scripts/lib/common.sh

require_root

PACKAGES=(
    vim
    openssl
    ca-certificates
    curl
    gnupg
    lsb-release
    git
    jq
    unzip
    build-essential
)

log "05-base-packages: apt-get update"
export DEBIAN_FRONTEND=noninteractive
retry 5 apt-get update -qq

log "05-base-packages: installing ${PACKAGES[*]}"
retry 5 apt-get install -y -qq "${PACKAGES[@]}"

log "05-base-packages: done"
