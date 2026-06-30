# Releasing a new kit version

Manual process, no CI/CD in v1 (see `docs/ROADMAP.md`). Run all of this
locally before copying the kit to your Apache server.

## 1. Bump `VERSION`

Edit `provisioning-kit/VERSION` (plain semver string, e.g. `1.1.0`).

## 2. Regenerate `manifest.json`

```
./tools/build-manifest.sh
```

This hashes (SHA-256) every file the pipeline fetches at runtime —
`scripts/lib/common.sh`, every `scripts/*.sh` except `00-bootstrap.sh`
(never fetched, see `docs/ARCHITECTURE.md`), and every
`profiles/*/pipeline.conf` — and writes `manifest.json` with
`version`/`build`/`created`/`git_commit` plus the `files` hash map.

## 3. Sign the manifest

```
gpg --armor --detach-sign --output manifest.json.asc manifest.json
```

Use your **own** GPG keypair for any real deployment — see "Replacing the
demo key" below. Verify locally before publishing:

```
gpg --verify manifest.json.asc manifest.json
```

## 4. Publish

Copy `provisioning-kit/` (including the regenerated `manifest.json` and
`manifest.json.asc`) to your Apache document root. **Never** copy the GPG
private key anywhere near the web root.

## Replacing the demo key

The keypair shipped with this repo (fingerprint embedded in
`scripts/00-bootstrap.sh` and mirrored in `keys/provisioning-kit-public.asc`)
is a **demo key**, generated only to exercise the signing mechanism
end-to-end. Before any real deployment:

1. Generate your own keypair:
   ```
   gpg --full-generate-key
   ```
2. Export the public key and replace **both**:
   - the heredoc block inside `scripts/00-bootstrap.sh` (between the
     `GPGKEY` markers)
   - `keys/provisioning-kit-public.asc` (reference copy only)
   - the identical `write_files` copy of `00-bootstrap.sh` embedded in
     every `profiles/*/user-data`
3. Keep the private key **out of this repository** entirely — store it in a
   password manager / HSM / secrets vault, not in `provisioning-kit/`.
4. Re-run steps 2-3 above (`build-manifest.sh` + `gpg --detach-sign`) using
   the new key.

## Why no CI/CD in v1

Deliberately deferred — see `docs/ROADMAP.md`. The release process above is
short enough to run by hand, and automating it would mean storing a signing
key in CI, which is a larger decision than this version takes on.
