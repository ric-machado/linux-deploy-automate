#!/usr/bin/env bash
# Stage 25 — GitHub CLI (official apt repo).
set -euo pipefail

# shellcheck source=lib/common.sh
source /opt/provisioning/scripts/lib/common.sh

require_root
require_command curl

export DEBIAN_FRONTEND=noninteractive

GH_KEYRING="/etc/apt/keyrings/githubcli.asc"
GH_LIST="/etc/apt/sources.list.d/github-cli.list"

if [[ ! -f "$GH_KEYRING" ]]; then
    log "25-github-cli: adding GitHub CLI apt repository"
    install -m 0755 -d /etc/apt/keyrings
    download "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "$GH_KEYRING"
    chmod a+r "$GH_KEYRING"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=${GH_KEYRING}] https://cli.github.com/packages stable main" \
        > "$GH_LIST"
else
    log "25-github-cli: apt repository already configured, skipping"
fi

log "25-github-cli: apt-get update"
retry 5 apt-get update -qq

log "25-github-cli: installing gh"
retry 5 apt-get install -y -qq gh

log "25-github-cli: $(gh --version | head -n1)"
log "25-github-cli: done"
