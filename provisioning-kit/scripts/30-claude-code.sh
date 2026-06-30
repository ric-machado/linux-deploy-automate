#!/usr/bin/env bash
# Stage 30 — Claude Code CLI. Installs the binary only; authentication is done
# manually by the admin after first login (no credentials are embedded here).
set -euo pipefail

# shellcheck source=lib/common.sh
source /opt/provisioning/scripts/lib/common.sh

require_root
require_command npm

log "30-claude-code: npm install -g @anthropic-ai/claude-code"
retry 5 npm install -g @anthropic-ai/claude-code

require_command claude

log "30-claude-code: verifying install with 'claude --version'"
CLAUDE_VERSION="$(claude --version)"
log "30-claude-code: ${CLAUDE_VERSION}"
log "30-claude-code: done (run 'claude' as the admin user to authenticate)"
