#!/usr/bin/env bash
# Maintainer tool — NOT part of the first-boot pipeline, NOT fetched by any
# target machine. Run this locally before publishing a new kit version:
#
#   tools/build-manifest.sh
#   gpg --armor --detach-sign --output manifest.json.asc manifest.json
#
# See docs/RELEASING.md for the full release process.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$KIT_ROOT"

command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "ERROR: sha256sum is required" >&2; exit 1; }

VERSION="$(tr -d '[:space:]' < "${KIT_ROOT}/VERSION")"
CREATED="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
GIT_COMMIT="unknown"
if git -C "$KIT_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    GIT_COMMIT="$(git -C "$KIT_ROOT" rev-parse HEAD)"
fi
BUILD="${VERSION}+${CREATED//[-:TZ]/}"

# Every file 00-bootstrap.sh's fetch_verified() may download at runtime.
# 00-bootstrap.sh itself is intentionally excluded: it is never fetched over
# the network (it is embedded in user-data), so it has no manifest entry.
FILES=()
FILES+=("scripts/lib/common.sh")
for f in "${KIT_ROOT}"/scripts/*.sh; do
    name="$(basename "$f")"
    [[ "$name" == "00-bootstrap.sh" ]] && continue
    FILES+=("scripts/${name}")
done
for f in "${KIT_ROOT}"/profiles/*/pipeline.conf; do
    [[ -f "$f" ]] || continue
    profile="$(basename "$(dirname "$f")")"
    FILES+=("profiles/${profile}/pipeline.conf")
done

echo "Building manifest.json (version ${VERSION}, commit ${GIT_COMMIT})" >&2

json="$(jq -n \
    --arg version "$VERSION" \
    --arg build "$BUILD" \
    --arg created "$CREATED" \
    --arg git_commit "$GIT_COMMIT" \
    '{version: $version, build: $build, created: $created, git_commit: $git_commit, files: {}}')"

for rel in "${FILES[@]}"; do
    path="${KIT_ROOT}/${rel}"
    if [[ ! -f "$path" ]]; then
        echo "ERROR: listed file missing: ${rel}" >&2
        exit 1
    fi
    hash="sha256:$(sha256sum "$path" | awk '{print $1}')"
    echo "  ${rel} -> ${hash}" >&2
    json="$(jq --arg f "$rel" --arg h "$hash" '.files[$f] = $h' <<<"$json")"
done

echo "$json" | jq '.' > "${KIT_ROOT}/manifest.json"
echo "Wrote ${KIT_ROOT}/manifest.json" >&2
