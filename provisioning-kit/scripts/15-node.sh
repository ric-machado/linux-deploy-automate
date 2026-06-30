#!/usr/bin/env bash
# Stage 15 — Node.js LTS (NodeSource).
set -euo pipefail

# shellcheck source=lib/common.sh
source /opt/provisioning/scripts/lib/common.sh

require_root
require_command curl

export DEBIAN_FRONTEND=noninteractive

if command -v node >/dev/null 2>&1; then
    log "15-node: node already installed ($(node --version)), skipping"
else
    log "15-node: running NodeSource setup_lts.x"
    retry 5 bash -c 'curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -'

    log "15-node: apt-get install nodejs"
    retry 5 apt-get install -y -qq nodejs
fi

log "15-node: node $(node --version), npm $(npm --version)"
log "15-node: done"
