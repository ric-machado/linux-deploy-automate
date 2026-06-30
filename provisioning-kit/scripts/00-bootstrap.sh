#!/usr/bin/env bash
# Provisioning Kit — first-boot bootstrap orchestrator.
#
# This is the ONE file that is never fetched over the network: it is embedded literally
# (via cloud-init `write_files`) inside profiles/<profile>/user-data, which itself only
# reaches the target machine through the already-certificate-validated autoinstall boot
# channel (ds=nocloud-net;s=https://...). Everything downloaded AFTER this point
# (manifest.json, common.sh, pipeline.conf, every stage script) is verified against the
# GPG-signed manifest before it is ever executed, so trust never has to be re-established
# from an untrusted HTTP response.
#
# KIT_BASE_URL / PROFILE / GPG_PUBLIC_KEY below are filled in per-deployment when this
# script is copied into profiles/<profile>/user-data — see docs/RELEASING.md.
set -euo pipefail

KIT_BASE_URL="https://SEU-SERVIDOR/provisioning-kit"   # EDIT: base URL where the kit is served
PROFILE="dev"                                           # EDIT: profile name (matches profiles/<name>/)

PROV_ROOT="/opt/provisioning"
GNUPG_HOME="${PROV_ROOT}/gnupg"
mkdir -p "$PROV_ROOT" "$GNUPG_HOME"
chmod 700 "$GNUPG_HOME"

# Minimal bootstrap-local logger — common.sh's richer log()/state helpers take over once sourced below.
boot_log() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [bootstrap] $1" | tee -a "${PROV_ROOT}/bootstrap-early.log" >&2
}

fail_banner() {
    local stage="$1"
    {
        echo ""
        echo "*** PROVISIONING FAILED at stage: ${stage} ***"
        echo "    See ${PROV_ROOT}/logs/${stage}.log (or ${PROV_ROOT}/bootstrap-early.log)"
        echo "    Re-run with: sudo ${PROV_ROOT}/scripts/00-bootstrap.sh"
        echo ""
    } | tee -a /etc/issue >/dev/null
}

boot_log "starting bootstrap for profile '${PROFILE}'"

# --- Verification tooling (platform prerequisite, not "kit content" — not subject to manifest verification) ---
boot_log "installing gnupg + jq (verification tooling)"
export DEBIAN_FRONTEND=noninteractive
for i in 1 2 3 4 5; do
    apt-get update -qq && apt-get install -y -qq gnupg jq curl ca-certificates && break
    boot_log "WARN: apt attempt ${i}/5 failed, retrying in $((i*2))s"
    sleep $((i*2))
done
command -v gpg >/dev/null || { boot_log "ERROR: gpg not available after install"; fail_banner "bootstrap"; exit 1; }
command -v jq  >/dev/null || { boot_log "ERROR: jq not available after install"; fail_banner "bootstrap"; exit 1; }

# --- Embedded GPG public key (pinned at deploy time; NOT fetched from KIT_BASE_URL) ---
cat > "${PROV_ROOT}/provisioning-kit-public.asc" <<'GPGKEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGpDmv4BEACeOYvtgyl94OpGyOFPa4ZIY169EKiuW8sDZPmaObRgt+NMdsb6
GWqbPWts46/+lrxZgqO03eveavs8IuHdsA3FmOW9UyLL+e82bmTa3e7ejAfd19vN
qB2/FR2cC1Tcm27pdXKDfbLvlxtwBcCNP2x9T8MErwqxsISaJq21PlTxChmkjtU0
QCbNgbp66B1ejw/1JaFOOwLhif6rgyzZJTMaYtCofbdMeC1KTJWZPExnHx4XCwAO
vtyj8g5Pqy/j0sMJsJm11yMZqp6XgxdZvS6VINzGQPFbqQKZPyBRqzvRL7nnjxqT
Q4Ug2vpMns4EF4xege0WHfDCfYt4KsPDBLhsqp3VfyLuq1beZ9qeaxJlBhp5TOdY
mqeRtJB7h9A0R8AhPScTwSZxPMEZGAW6cXVoIbx/viFEeEh3P4UUierJahrqE8rF
vXamIKTep6VsiuECkr3tHSPcLKxHfwWIVXDKiKLFJc+ZpSEDiq9cmAMX+6EKavFi
Ct7nTNFOyZa2n3A/Ee75sQEO7EGiAwJMqWqFiryDBsDKIGgy0tzObLqBlb6B4eSi
2U4DPXmbwdiS7Bc5k/iJCb34BBiLvUwFx9DO2WL7vRqLbZ1YakZ9foFeiSBZJT/g
JhQMUR1TVhlaMCixJorDU6o7qG8knLHlSnRJG36RQRTNm5neFceSqpub3QARAQAB
tFpQcm92aXNpb25pbmcgS2l0IChERU1PIGtleSAtIHJlcGxhY2UgYmVmb3JlIHBy
b2R1Y3Rpb24pIDxwcm92aXNpb25pbmcta2l0QGV4YW1wbGUuaW52YWxpZD6JAlIE
EwEKADwWIQQg8GHuAzDQ90rDRP002+U6P/rz5AUCakOa/gMbLwQFCwkIBwICIgIG
FQoJCAsCBBYCAwECHgcCF4AACgkQNNvlOj/68+TCgA/9EWWA7k0F1AFnbfCABEla
GR508SHodGtdWEYpL2FVTfGdtboW6oAPS4Nm7rfdkennTowP03WnViojVcFXS7vX
NkLCE/kf+RziaRZbiswGpVqSiufzZ/Mnw3fV9NSjJJk8D2/BaFkZEzpJnz8xkOJv
anyrppRXToJOv99U9ym7SUfHHhm7HokUTDZLiZVoxV3R5zsgUL9jHliCgRJsujTz
JQ66Y+mhIu5Di2xx0xVuV8NjAm9fHux2lSZXaBv9+7hFeGlgoMNaTxgU49zgLpRx
K4IZgqonsXBCcCelNHVlHVyKpkrKLGntCW1vCj12/10qQelK0lgJjZCm+G6vG45J
xOPH2qO6De0veueRUGO8Bb8tFxAc7MWux9A8fntFyC32PiWzmno9xH6Mvu/0EicD
Rtek3X2uh7owW8Bhns9AQDUrBZRzJt5THElVIN3gZ+WNF0Sk3lI0A7WOn/V6FbVY
/gsVmRIUmiPqbpoOA53DlBxw4slp142hN1tHW5S2H/QwdiSIriJtGFwLvlYaGUQq
dvY2Y2LqjtmaxyJcajrzUf9ybNZGTWcONUx0vZ9slDbEYiHvE0rRLD3JIUSPI5ns
jfCJVHJlQlByiVL3lqZkVprxiyBxesJAfOQsp5dcDuH67iNgzv4cL3ZB7b+Xnewt
vIQZy8Fp9sGM0SMDkVaTtEw=
=9aaW
-----END PGP PUBLIC KEY BLOCK-----
GPGKEY

boot_log "importing GPG public key into dedicated keyring"
gpg --homedir "$GNUPG_HOME" --batch --quiet --import "${PROV_ROOT}/provisioning-kit-public.asc" 2>>"${PROV_ROOT}/bootstrap-early.log"

# --- Fetch + verify manifest.json (the integrity root for everything else) ---
boot_log "downloading manifest.json + manifest.json.asc"
curl -fsSL --max-time 60 -o "${PROV_ROOT}/manifest.json" "${KIT_BASE_URL}/manifest.json"
curl -fsSL --max-time 60 -o "${PROV_ROOT}/manifest.json.asc" "${KIT_BASE_URL}/manifest.json.asc"

boot_log "verifying manifest.json signature"
if ! gpg --homedir "$GNUPG_HOME" --batch --verify "${PROV_ROOT}/manifest.json.asc" "${PROV_ROOT}/manifest.json" 2>>"${PROV_ROOT}/bootstrap-early.log"; then
    boot_log "ERROR: manifest.json signature verification FAILED — aborting, kit may be tampered or corrupted"
    fail_banner "manifest-verify"
    exit 1
fi
boot_log "manifest.json signature OK"

KIT_VERSION="$(jq -r '.version' "${PROV_ROOT}/manifest.json")"
boot_log "kit version: ${KIT_VERSION}"

# fetch_verified <relative-path-in-manifest> <dest> — downloads a file and checks its sha256
# against the entry of the same name in manifest.json["files"]. Aborts on any mismatch/missing entry.
fetch_verified() {
    local rel="$1"
    local dest="$2"
    local expected
    expected="$(jq -r --arg f "$rel" '.files[$f] // empty' "${PROV_ROOT}/manifest.json")"
    if [[ -z "$expected" ]]; then
        boot_log "ERROR: ${rel} has no entry in manifest.json — refusing to fetch"
        return 1
    fi
    mkdir -p "$(dirname "$dest")"
    curl -fsSL --max-time 60 -o "$dest" "${KIT_BASE_URL}/${rel}"
    local actual
    actual="$(sha256sum "$dest" | awk '{print $1}')"
    expected="${expected#sha256:}"
    if [[ "$actual" != "$expected" ]]; then
        boot_log "ERROR: hash mismatch for ${rel} (expected ${expected}, got ${actual})"
        return 1
    fi
    boot_log "verified ${rel}"
}

# --- common.sh: verified, then sourced — everything after this point uses its log()/mark_*()/etc. ---
mkdir -p "${PROV_ROOT}/scripts/lib"
if ! fetch_verified "scripts/lib/common.sh" "${PROV_ROOT}/scripts/lib/common.sh"; then
    fail_banner "common.sh"
    exit 1
fi
chmod +x "${PROV_ROOT}/scripts/lib/common.sh"
# shellcheck source=lib/common.sh
source "${PROV_ROOT}/scripts/lib/common.sh"

require_root

log "bootstrap: common.sh loaded, kit version ${KIT_VERSION}"

# --- pipeline.conf: verified, then parsed ---
if ! fetch_verified "profiles/${PROFILE}/pipeline.conf" "${PROV_ROOT}/pipeline.conf"; then
    fail_banner "pipeline.conf"
    exit 1
fi

# --- Run each stage in order. Each line in pipeline.conf is "<script-name> [args...]". ---
mkdir -p "${PROV_ROOT}/scripts" "${PROV_ROOT}/logs"

while IFS= read -r line || [[ -n "$line" ]]; do
    # skip blank lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # shellcheck disable=SC2206
    parts=($line)
    script_name="${parts[0]}"
    script_args=("${parts[@]:1}")
    stage_id="${script_name%.sh}"

    if is_done "$stage_id"; then
        log "stage ${stage_id}: already done, skipping"
        continue
    fi

    log "stage ${stage_id}: fetching scripts/${script_name}"
    if ! fetch_verified "scripts/${script_name}" "${PROV_ROOT}/scripts/${script_name}"; then
        mark_failed "$stage_id"
        fail_banner "$stage_id"
        exit 1
    fi
    chmod +x "${PROV_ROOT}/scripts/${script_name}"

    mark_running "$stage_id"
    log "stage ${stage_id}: running (args: ${script_args[*]:-none})"
    if "${PROV_ROOT}/scripts/${script_name}" "${script_args[@]:-}" 2>&1 | tee "${PROV_LOG_DIR}/${stage_id}.log" >&2; then
        mark_done "$stage_id"
        log "stage ${stage_id}: done"
    else
        mark_failed "$stage_id"
        log "stage ${stage_id}: FAILED — aborting pipeline, see ${PROV_LOG_DIR}/${stage_id}.log"
        fail_banner "$stage_id"
        exit 1
    fi
done < "${PROV_ROOT}/pipeline.conf"

mark_done "ALL"
{
    echo ""
    echo "*** Provisioning completed successfully (kit version ${KIT_VERSION}) ***"
    echo "    $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo ""
} | tee -a /etc/issue >/dev/null
log "all stages completed successfully — kit version ${KIT_VERSION}"
