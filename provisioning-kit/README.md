# Provisioning Kit

A static file tree that, served over HTTPS from any Apache (or other) web
server, drives a fully automated Ubuntu Server 24.04 LTS install via
[autoinstall](https://canonical-subiquity.readthedocs-hosted.com/en/latest/intro-to-autoinstall.html):
disk partitioning (GPT + UEFI + LVM, percentage-sized volumes), then a
first-boot pipeline that installs and configures a profile-specific software
stack — with every downloaded script verified against a GPG-signed manifest
before it is ever executed.

Current version: see `VERSION`. Only the **`dev`** profile is implemented;
`web-server` and `local-server` are stubs (see `docs/ROADMAP.md`).

## Quick start

1. Copy this entire `provisioning-kit/` directory to your Apache web root,
   e.g. `https://your-server/provisioning-kit/`. See `docs/DEPLOYMENT.md` for
   required file permissions and `Content-Type` handling for extensionless
   files (`user-data`, `meta-data`).
2. Edit `profiles/dev/user-data`: set a real password hash (`openssl passwd -6`)
   and review the storage `match:` block for your target disk(s).
3. Edit `scripts/00-bootstrap.sh`: set `KIT_BASE_URL` to your server's URL.
   Since this file is embedded inside `profiles/dev/user-data`, re-run
   `tools/build-manifest.sh` afterwards is **not** needed for this file (it's
   never fetched/verified — see `docs/ARCHITECTURE.md`), but you do need to
   re-embed it: copy the edited script back into the `write_files` block.
4. Boot the Ubuntu Server 24.04 LTS ISO with the autoinstall cmdline from
   `docs/BOOTING.md`, pointed at `profiles/dev/`.
5. Watch progress: `journalctl -u provisioning-bootstrap -f` on the target
   machine once cloud-init has handed off, or inspect
   `/opt/provisioning/logs/` after boot completes.

## Layout

```
provisioning-kit/
├── VERSION                  kit version (also embedded in manifest.json)
├── manifest.json             sha256 of every fetchable file + version/build/commit
├── manifest.json.asc         detached GPG signature of manifest.json
├── keys/                     reference copy of the GPG public key (docs only)
├── tools/                    maintainer-only scripts (not served/fetched by targets)
├── profiles/<name>/          one URL per profile: user-data + meta-data + pipeline.conf
├── scripts/                  first-boot pipeline scripts, lib/common.sh
├── configs/ packages/ templates/   placeholders for future versions
└── docs/                      see docs/README.md for the full index
```

## Integrity model (short version)

`00-bootstrap.sh` is the only file never fetched over the network — it's
embedded directly in `user-data`, which itself only reaches the target
machine via the already certificate-validated autoinstall boot channel. It
carries a pinned GPG public key, verifies `manifest.json` against
`manifest.json.asc`, and then checks every other downloaded file's SHA-256
against that signed manifest before executing it. Full details in
`docs/ARCHITECTURE.md`; release process (regenerating the manifest +
signature) in `docs/RELEASING.md`.

**The GPG key shipped in this repo is a DEMO key for testing the signing
mechanism. Generate your own keypair and replace the embedded public key in
`scripts/00-bootstrap.sh` (and `keys/provisioning-kit-public.asc`) before any
real deployment** — see `docs/RELEASING.md`.

## Documentation

See `docs/README.md` for the full documentation index (architecture,
deployment, boot procedure, storage layout, release process, roadmap,
verification checklist).
