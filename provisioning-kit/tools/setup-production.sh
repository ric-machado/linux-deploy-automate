#!/usr/bin/env bash
# Maintainer tool — NOT part of the first-boot pipeline, NOT fetched by any
# target machine. Run this ONCE (per environment) on the machine that builds
# and publishes the kit (typically the Apache host itself, or wherever you
# stage releases from) to go from "kit with placeholders" to "kit ready to
# serve a real autoinstall". It is destructive to live state (writes a real
# admin password hash into a git-tracked file, generates a production GPG
# signing key, deploys to the web root) — read docs/RELEASING.md and
# docs/DEPLOYMENT.md before running this against anything that matters.
#
# What it does, in order:
#   1. Generates a random admin password + SHA-512 crypt hash (openssl passwd -6)
#   2. Generates (or reuses) a production GPG signing keypair under
#      /opt/autodeploy/GPG (never copied into the served kit)
#   3. Writes the new password hash + GPG public key + KIT_BASE_URL into
#      scripts/00-bootstrap.sh and re-embeds it into profiles/<profile>/user-data
#   4. Rebuilds manifest.json and re-signs it with the new production key
#   5. Deploys the kit (provisioning-kit/) into /var/www/html/autodeploy
#
# Usage:
#   sudo tools/setup-production.sh --kit-base-url https://example.org/autodeploy
#
# All paths/values below have defaults but can be overridden — run with -h.
set -euo pipefail

# --- defaults (override via flags) ------------------------------------------
PROFILE="dev"
DEPLOY_DIR="/var/www/html/autodeploy"
GPG_HOME="/opt/autodeploy/GPG"
SECRETS_DIR="/opt/autodeploy/secrets"
KIT_BASE_URL=""
ADMIN_HOSTNAME=""
ADMIN_USERNAME=""
PASSWORD_LENGTH=24
GPG_NAME="Provisioning Kit (PRODUCTION)"
GPG_EMAIL=""
ROTATE_KEY=false
PROTECT_KEY_WITH_PASSPHRASE=false
DRY_RUN=false
FORCE=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_SRC="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    cat <<USAGE
Usage: $(basename "$0") [options]

  --kit-base-url URL       Base URL the kit will be served from
                            (default: https://\$(hostname -f)/autodeploy)
  --profile NAME            Profile to provision (default: ${PROFILE})
  --hostname NAME            identity.hostname for the profile (default: dev-server)
  --username NAME            identity.username for the profile (default: admin)
  --deploy-dir DIR           Web deploy target (default: ${DEPLOY_DIR})
  --gpg-home DIR             Production GPG keyring home (default: ${GPG_HOME})
  --secrets-dir DIR          Where generated secrets are written (default: ${SECRETS_DIR})
  --password-length N        Random password length in bytes before base64 (default: ${PASSWORD_LENGTH})
  --gpg-name "Name"          GPG key real name (default: "${GPG_NAME}")
  --gpg-email EMAIL          GPG key email (default: provisioning-kit@<hostname>)
  --rotate-key                Generate a brand new GPG key even if one already
                              exists in --gpg-home (default: reuse existing key)
  --protect-key-with-passphrase
                              Passphrase-protect the new GPG private key
                              (passphrase is generated and stored alongside it
                              in --secrets-dir; default: no passphrase, see
                              the warning printed at the end of this script)
  --dry-run                  Print what would happen, change nothing
  --force                    Skip confirmation prompts
  -h, --help                  Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kit-base-url) KIT_BASE_URL="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --hostname) ADMIN_HOSTNAME="$2"; shift 2 ;;
        --username) ADMIN_USERNAME="$2"; shift 2 ;;
        --deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
        --gpg-home) GPG_HOME="$2"; shift 2 ;;
        --secrets-dir) SECRETS_DIR="$2"; shift 2 ;;
        --password-length) PASSWORD_LENGTH="$2"; shift 2 ;;
        --gpg-name) GPG_NAME="$2"; shift 2 ;;
        --gpg-email) GPG_EMAIL="$2"; shift 2 ;;
        --rotate-key) ROTATE_KEY=true; shift ;;
        --protect-key-with-passphrase) PROTECT_KEY_WITH_PASSPHRASE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $1" >&2; }
die() { echo "ERROR: $1" >&2; exit 1; }
run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] $*" >&2
    else
        "$@"
    fi
}

[[ "$(id -u)" -eq 0 ]] || die "must run as root (writes to ${DEPLOY_DIR%/*} and ${GPG_HOME%/*})"

for cmd in gpg jq openssl rsync awk sed; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: ${cmd}"
done

PROFILE_USER_DATA="${KIT_SRC}/profiles/${PROFILE}/user-data"
[[ -f "$PROFILE_USER_DATA" ]] || die "no such profile: profiles/${PROFILE}/user-data not found under ${KIT_SRC}"

HOST_FQDN="$(hostname -f 2>/dev/null || hostname)"
[[ -n "$KIT_BASE_URL" ]] || KIT_BASE_URL="https://${HOST_FQDN}/autodeploy"
[[ -n "$ADMIN_HOSTNAME" ]] || ADMIN_HOSTNAME="dev-server"
[[ -n "$ADMIN_USERNAME" ]] || ADMIN_USERNAME="admin"
[[ -n "$GPG_EMAIL" ]] || GPG_EMAIL="provisioning-kit@${HOST_FQDN}"

log "kit source:    ${KIT_SRC}"
log "profile:        ${PROFILE}"
log "kit base URL:    ${KIT_BASE_URL}"
log "deploy dir:      ${DEPLOY_DIR}"
log "gpg home:        ${GPG_HOME}"
log "secrets dir:     ${SECRETS_DIR}"

if [[ "$FORCE" != true && "$DRY_RUN" != true ]]; then
    read -r -p "This will generate REAL production secrets and may overwrite ${DEPLOY_DIR}. Continue? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || die "aborted by user"
fi

run mkdir -p "$SECRETS_DIR"
run chmod 700 "$SECRETS_DIR"
run mkdir -p "$GPG_HOME"
run chmod 700 "$GPG_HOME"

# --- 1. random admin password + SHA-512 crypt hash --------------------------
log "generating random admin password"
ADMIN_PASSWORD="$(openssl rand -base64 "$PASSWORD_LENGTH")"
PASSWORD_HASH="$(openssl passwd -6 "$ADMIN_PASSWORD")"

PASSWORD_FILE="${SECRETS_DIR}/${PROFILE}-admin-password.txt"
if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] would write admin password to ${PASSWORD_FILE}"
else
    umask 077
    cat > "$PASSWORD_FILE" <<EOF
profile:  ${PROFILE}
username: ${ADMIN_USERNAME}
hostname: ${ADMIN_HOSTNAME}
password: ${ADMIN_PASSWORD}
generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')

Retrieve this, store it in your password manager, then delete this file.
EOF
    chmod 600 "$PASSWORD_FILE"
fi

# --- 2. production GPG keypair (generate or reuse) ---------------------------
mkdir -p /run/user/0 2>/dev/null && chmod 700 /run/user/0 2>/dev/null || true

EXISTING_FPR=""
if [[ -d "$GPG_HOME" ]]; then
    EXISTING_FPR="$(gpg --homedir "$GPG_HOME" --batch --with-colons --list-secret-keys 2>/dev/null \
        | awk -F: '/^fpr:/ {print $10; exit}')"
fi

GPG_PASSPHRASE=""
if [[ -n "$EXISTING_FPR" && "$ROTATE_KEY" != true ]]; then
    log "reusing existing production GPG key: ${EXISTING_FPR}"
    FPR="$EXISTING_FPR"
    PASSPHRASE_FILE="${SECRETS_DIR}/gpg-key-passphrase.txt"
    [[ -f "$PASSPHRASE_FILE" ]] && GPG_PASSPHRASE="$(cat "$PASSPHRASE_FILE")"
else
    [[ -z "$EXISTING_FPR" || "$ROTATE_KEY" == true ]] || die "unexpected state"
    log "generating new production GPG key (this can take a minute — needs entropy)"

    GEN_CONF="$(mktemp)"
    trap 'rm -f "$GEN_CONF"' EXIT

    if [[ "$PROTECT_KEY_WITH_PASSPHRASE" == true ]]; then
        GPG_PASSPHRASE="$(openssl rand -base64 32)"
        if [[ "$DRY_RUN" != true ]]; then
            umask 077
            echo "$GPG_PASSPHRASE" > "${SECRETS_DIR}/gpg-key-passphrase.txt"
            chmod 600 "${SECRETS_DIR}/gpg-key-passphrase.txt"
        fi
        cat > "$GEN_CONF" <<EOF
%echo Generating production signing key
Key-Type: RSA
Key-Length: 4096
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Name-Comment: provisioning-kit signing key
Expire-Date: 2y
Passphrase: ${GPG_PASSPHRASE}
%commit
%echo done
EOF
    else
        cat > "$GEN_CONF" <<EOF
%echo Generating production signing key
Key-Type: RSA
Key-Length: 4096
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Name-Comment: provisioning-kit signing key
Expire-Date: 2y
%no-protection
%commit
%echo done
EOF
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] would generate GPG key in ${GPG_HOME} (Name-Real=${GPG_NAME}, Name-Email=${GPG_EMAIL})"
        FPR="0000000000000000000000000000000000000000"
    else
        gpg --homedir "$GPG_HOME" --batch --pinentry-mode loopback --gen-key "$GEN_CONF" 2>&1 | tee -a "${SECRETS_DIR}/gpg-gen.log" >&2
        FPR="$(gpg --homedir "$GPG_HOME" --batch --with-colons --list-secret-keys \
            | awk -F: '/^fpr:/ {print $10; exit}')"
        [[ -n "$FPR" ]] || die "GPG key generation appears to have failed — see ${SECRETS_DIR}/gpg-gen.log"
    fi
    rm -f "$GEN_CONF"
    trap - EXIT
fi

log "production GPG fingerprint: ${FPR}"

GPG_VERIFY_OPTS=(--homedir "$GPG_HOME" --batch --yes --pinentry-mode loopback --local-user "$FPR")
[[ -n "$GPG_PASSPHRASE" ]] && GPG_VERIFY_OPTS+=(--passphrase "$GPG_PASSPHRASE")

NEW_PUBKEY_FILE="${GPG_HOME}/provisioning-kit-public.asc"
NEW_PRIVKEY_FILE="${GPG_HOME}/provisioning-kit-private.asc"
if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] would export public/private key to ${GPG_HOME}"
else
    gpg --homedir "$GPG_HOME" --batch --yes --armor --export "$FPR" > "$NEW_PUBKEY_FILE"
    umask 077
    gpg "${GPG_VERIFY_OPTS[@]}" --armor --export-secret-keys "$FPR" > "$NEW_PRIVKEY_FILE"
    chmod 600 "$NEW_PRIVKEY_FILE"
fi

# --- 3. write new values into scripts/00-bootstrap.sh ------------------------
BOOTSTRAP="${KIT_SRC}/scripts/00-bootstrap.sh"

if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] would update KIT_BASE_URL/PROFILE/GPG key in ${BOOTSTRAP}"
else
    log "updating KIT_BASE_URL and PROFILE in ${BOOTSTRAP}"
    # NOTE: delimiter is a control char (not '#') because the replacement text
    # itself contains literal '#' comment characters, which would otherwise be
    # mistaken for the closing delimiter.
    SEP=$'\x01'
    sed -i -E "s${SEP}^KIT_BASE_URL=\"[^\"]*\".*${SEP}KIT_BASE_URL=\"${KIT_BASE_URL}\"   # EDIT: base URL where the kit is served${SEP}" "$BOOTSTRAP"
    sed -i -E "s${SEP}^PROFILE=\"[^\"]*\".*${SEP}PROFILE=\"${PROFILE}\"                                           # EDIT: profile name (matches profiles/<name>/)${SEP}" "$BOOTSTRAP"

    log "splicing production GPG public key into ${BOOTSTRAP}"
    awk -v keyfile="$NEW_PUBKEY_FILE" '
        BEGIN { in_block = 0 }
        /<<.GPGKEY.$/ {
            print
            while ((getline line < keyfile) > 0) print line
            close(keyfile)
            in_block = 1
            next
        }
        in_block && /^GPGKEY$/ { in_block = 0; print; next }
        in_block { next }
        { print }
    ' "$BOOTSTRAP" > "${BOOTSTRAP}.new"
    mv "${BOOTSTRAP}.new" "$BOOTSTRAP"
    chmod +x "$BOOTSTRAP"
fi

cp "$NEW_PUBKEY_FILE" "${KIT_SRC}/keys/provisioning-kit-public.asc" 2>/dev/null || \
    run cp "$NEW_PUBKEY_FILE" "${KIT_SRC}/keys/provisioning-kit-public.asc"

# --- 4. re-embed 00-bootstrap.sh into profiles/<profile>/user-data -----------
if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] would re-embed ${BOOTSTRAP} into ${PROFILE_USER_DATA}"
    log "[DRY-RUN] would set identity.hostname=${ADMIN_HOSTNAME} identity.username=${ADMIN_USERNAME} identity.password=<hash>"
else
    log "re-embedding 00-bootstrap.sh into profiles/${PROFILE}/user-data"
    CONTENT_LINE="$(grep -n -F -- "        content: |" "$PROFILE_USER_DATA" | head -1 | cut -d: -f1)"
    RUNCMD_LINE="$(grep -n -F -- "    runcmd:" "$PROFILE_USER_DATA" | head -1 | cut -d: -f1)"
    [[ -n "$CONTENT_LINE" && -n "$RUNCMD_LINE" ]] || die "could not locate write_files/runcmd markers in ${PROFILE_USER_DATA} — re-embed manually"

    TMP_USER_DATA="$(mktemp)"
    head -n "$CONTENT_LINE" "$PROFILE_USER_DATA" > "$TMP_USER_DATA"
    sed 's/^/          /' "$BOOTSTRAP" >> "$TMP_USER_DATA"
    echo "" >> "$TMP_USER_DATA"
    tail -n "+${RUNCMD_LINE}" "$PROFILE_USER_DATA" >> "$TMP_USER_DATA"
    mv "$TMP_USER_DATA" "$PROFILE_USER_DATA"

    log "updating identity.hostname / identity.username / identity.password in profiles/${PROFILE}/user-data"
    sed -i -E "s#^(    hostname: ).*#\1${ADMIN_HOSTNAME}#" "$PROFILE_USER_DATA"
    sed -i -E "s#^(    username: ).*#\1${ADMIN_USERNAME}#" "$PROFILE_USER_DATA"
    sed -i -E "s#^(    password: ).*#\1\"${PASSWORD_HASH}\"#" "$PROFILE_USER_DATA"

    PYCHECK_OUTPUT="$(python3 - "$PROFILE_USER_DATA" "$BOOTSTRAP" <<'PYEOF' 2>&1
import sys, yaml
user_data_path, bootstrap_path = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(user_data_path))
embedded = d["autoinstall"]["user-data"]["write_files"][0]["content"]
original = open(bootstrap_path).read()
assert embedded == original, "embedded bootstrap content does not match scripts/00-bootstrap.sh"
print("user-data: YAML parses OK and embedded bootstrap matches scripts/00-bootstrap.sh")
PYEOF
)"
    PYCHECK_STATUS=$?
    if [[ $PYCHECK_STATUS -eq 0 ]]; then
        log "$PYCHECK_OUTPUT"
    elif ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import yaml' >/dev/null 2>&1; then
        log "WARN: skipped optional YAML/embed sanity check (python3/PyYAML not available)"
    else
        die "YAML/embed sanity check failed: ${PYCHECK_OUTPUT}"
    fi
fi

# --- 5. rebuild + sign manifest.json -----------------------------------------
if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] would run tools/build-manifest.sh and sign manifest.json with ${FPR}"
else
    log "rebuilding manifest.json"
    "${KIT_SRC}/tools/build-manifest.sh"

    log "signing manifest.json with production key ${FPR}"
    gpg "${GPG_VERIFY_OPTS[@]}" --armor --detach-sign --output "${KIT_SRC}/manifest.json.asc" "${KIT_SRC}/manifest.json"

    log "verifying signature against the freshly-exported public key"
    VERIFY_HOME="$(mktemp -d)"
    gpg --homedir "$VERIFY_HOME" --batch --quiet --import "$NEW_PUBKEY_FILE"
    gpg --homedir "$VERIFY_HOME" --batch --verify "${KIT_SRC}/manifest.json.asc" "${KIT_SRC}/manifest.json"
    rm -rf "$VERIFY_HOME"
fi

# --- 6. deploy to the web root ------------------------------------------------
run mkdir -p "$DEPLOY_DIR"
if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] would rsync ${KIT_SRC}/ to ${DEPLOY_DIR}/ (excluding .git, tools/)"
else
    log "deploying kit to ${DEPLOY_DIR}"
    rsync -a --exclude='.git' --exclude='tools' "${KIT_SRC}/" "${DEPLOY_DIR}/"
    if id www-data >/dev/null 2>&1; then
        chown -R www-data:www-data "$DEPLOY_DIR"
    else
        log "WARN: www-data user not found, leaving ownership as-is — adjust manually for your web server user"
    fi
    find "$DEPLOY_DIR" -type d -exec chmod 755 {} \;
    find "$DEPLOY_DIR" -type f -exec chmod 644 {} \;
fi

# --- summary -------------------------------------------------------------------
cat <<SUMMARY

*** Production setup complete (profile: ${PROFILE}) ***

  Kit base URL:        ${KIT_BASE_URL}
  Boot cmdline:         autoinstall ds=nocloud-net;s=${KIT_BASE_URL}/profiles/${PROFILE}/

  Deployed to:          ${DEPLOY_DIR}
  GPG fingerprint:       ${FPR}
  GPG keyring home:      ${GPG_HOME}  (private key — back this up, keep it OFF the web root)
  Admin password file:   ${PASSWORD_FILE}  (plaintext — retrieve and delete)
$( [[ "$PROTECT_KEY_WITH_PASSPHRASE" == true ]] && echo "  GPG key passphrase:    ${SECRETS_DIR}/gpg-key-passphrase.txt  (needed for future re-signing)" )

  scripts/00-bootstrap.sh and profiles/${PROFILE}/user-data in ${KIT_SRC}
  were modified in place (now contain a REAL password hash and a REAL GPG
  public key) — review with 'git diff' before committing, and decide
  whether this repo should hold the password hash or be kept private.

  Re-run this script any time you change scripts/ or pipeline.conf — it
  reuses the existing GPG key by default (pass --rotate-key to generate a
  new one) and re-signs the manifest.
SUMMARY
