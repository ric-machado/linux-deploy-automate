#!/usr/bin/env bash
# Stage 90 — apt cleanup + final success banner in /etc/motd.
set -euo pipefail

# shellcheck source=lib/common.sh
source /opt/provisioning/scripts/lib/common.sh

require_root

export DEBIAN_FRONTEND=noninteractive

log "90-cleanup: apt-get autoremove --purge"
apt-get autoremove -y -qq --purge

log "90-cleanup: apt-get clean"
apt-get clean

KIT_VERSION="unknown"
if [[ -f "${PROV_ROOT}/manifest.json" ]] && command -v jq >/dev/null 2>&1; then
    KIT_VERSION="$(jq -r '.version' "${PROV_ROOT}/manifest.json")"
fi

log "90-cleanup: writing success banner to /etc/motd (kit version ${KIT_VERSION})"
mkdir -p /etc/motd.d
cat > /etc/motd.d/90-provisioning-kit <<MOTD

*** Provisioning Kit ${KIT_VERSION}: all stages completed successfully ***
    Logs:  ${PROV_LOG_DIR}
    State: ${PROV_STATE_DIR}

MOTD

log "90-cleanup: done"
