#!/usr/bin/env bash
# Stage 20 — Python 3 toolchain.
set -euo pipefail

# shellcheck source=lib/common.sh
source /opt/provisioning/scripts/lib/common.sh

require_root

export DEBIAN_FRONTEND=noninteractive

log "20-python: apt-get update"
retry 5 apt-get update -qq

log "20-python: installing python3 python3-pip python3-venv"
retry 5 apt-get install -y -qq python3 python3-pip python3-venv

log "20-python: python $(python3 --version)"
log "20-python: done"
