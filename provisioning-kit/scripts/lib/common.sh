#!/usr/bin/env bash
# Shared helpers for the provisioning-kit pipeline.
# Sourced by 00-bootstrap.sh (embedded in autoinstall user-data) and every numbered stage script.
set -euo pipefail

PROV_ROOT="/opt/provisioning"
PROV_LOG_DIR="${PROV_ROOT}/logs"
PROV_STATE_DIR="${PROV_ROOT}/state"
BOOTSTRAP_LOG="${PROV_LOG_DIR}/bootstrap.log"

mkdir -p "$PROV_LOG_DIR" "$PROV_STATE_DIR"

log() {
    local msg="$1"
    local ts
    ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo "[${ts}] ${msg}" | tee -a "$BOOTSTRAP_LOG" >&2
}

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log "ERROR: must run as root"
        exit 1
    fi
}

require_network() {
    local probe="${1:-https://archive.ubuntu.com}"
    if ! curl -fsSL --max-time 10 -o /dev/null "$probe"; then
        log "ERROR: network check failed against ${probe}"
        exit 1
    fi
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "ERROR: required command not found: ${cmd}"
        exit 1
    fi
}

# retry <attempts> <command...> — exponential backoff starting at 2s
retry() {
    local attempts="$1"; shift
    local delay=2
    local n=1
    until "$@"; do
        if (( n >= attempts )); then
            log "ERROR: command failed after ${attempts} attempts: $*"
            return 1
        fi
        log "WARN: attempt ${n}/${attempts} failed, retrying in ${delay}s: $*"
        sleep "$delay"
        delay=$(( delay * 2 ))
        n=$(( n + 1 ))
    done
}

# download <url> <dest> — curl wrapped in retry()
download() {
    local url="$1"
    local dest="$2"
    retry 5 curl -fsSL --max-time 60 -o "$dest" "$url"
}

# verify_hash <file> <expected-sha256> — accepts a bare hex digest or a "sha256:<hex>" prefixed value
verify_hash() {
    local file="$1"
    local expected="$2"
    local actual
    actual="$(sha256sum "$file" | awk '{print $1}')"
    expected="${expected#sha256:}"
    if [[ "$actual" != "$expected" ]]; then
        log "ERROR: hash mismatch for ${file} (expected ${expected}, got ${actual})"
        return 1
    fi
}

# Stage state sentinels: <name>.running / <name>.done / <name>.failed under PROV_STATE_DIR
mark_running() { : > "${PROV_STATE_DIR}/${1}.running"; }
mark_done()    { rm -f "${PROV_STATE_DIR}/${1}.running" "${PROV_STATE_DIR}/${1}.failed"; : > "${PROV_STATE_DIR}/${1}.done"; }
mark_failed()  { rm -f "${PROV_STATE_DIR}/${1}.running"; : > "${PROV_STATE_DIR}/${1}.failed"; }
is_done()      { [[ -f "${PROV_STATE_DIR}/${1}.done" ]]; }
