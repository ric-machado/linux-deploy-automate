# Release notes

## v1.1.0 — Security hardening sprint

SSH hardening, UFW firewall, and fail2ban brute-force protection for the
`dev` profile. SSH key injection into `user-data` via `setup-production.sh
--ssh-pubkey`. No breaking changes to v1.0 user-data format or GPG key
material — re-running `setup-production.sh` on an existing deployment
is the upgrade path.

### New in v1.1

**`scripts/35-security.sh`** — new first-boot pipeline stage:
- **UFW**: `default deny incoming / allow outgoing`, SSH (port 22) explicitly
  whitelisted. See the Docker+UFW interaction note inside the script —
  Docker's published ports bypass UFW by design (iptables-managed).
- **fail2ban**: sshd jail blocking IPs for 1 hour after 3 failed SSH
  attempts in any 10-minute window (systemd/journald backend, Ubuntu 24.04
  default).
- **SSH hardening** via drop-in `/etc/ssh/sshd_config.d/99-provisioning-hardening.conf`:
  `PermitRootLogin no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `AllowUsers
  <admin>`, `X11Forwarding no`. `PasswordAuthentication` is set to `no` only
  when the admin already has a populated `authorized_keys` — avoids lockout
  when no SSH key was provided.

**`configs/`** — no longer a placeholder: `configs/sshd_config.d/` and
`configs/fail2ban/jail.d/` contain reference copies of the configs the
pipeline deploys.

**`tools/setup-production.sh --ssh-pubkey "KEY"`** — injects an SSH public
key into `profiles/<profile>/user-data`'s `authorized-keys` and sets
`allow-pw: false`, so both autoinstall and the hardening stage agree on
disabling password auth.

### Upgrade path from v1.0

1. Pull the latest changes.
2. Re-run `setup-production.sh` with the same flags as before (add
   `--ssh-pubkey "$(cat ~/.ssh/id_ed25519.pub)"` if you now want key-only
   auth). The existing GPG key is reused; `35-security.sh` is automatically
   included in the rebuilt manifest.
3. Boot a new target machine, or re-provision an existing one by deleting the
   `/opt/provisioning/state/` sentinels and re-running
   `sudo /opt/provisioning/scripts/00-bootstrap.sh`.

---

## v1.0.0 — Provisioning Kit, `dev` profile

First shippable version. Zero-touch Ubuntu Server 24.04 LTS provisioning via
autoinstall + a GPG-verified first-boot script pipeline, for a single
profile (`dev`), plus a maintainer tool that automates everything needed to
take it from "demo key in git" to "deployed with real secrets."

### Included

**`profiles/dev/`** — autoinstall `user-data`/`meta-data` for the `dev`
profile:
- GPT + UEFI disk layout: ESP and `/boot` outside LVM, a single VG with
  percentage-sized LVs (`lv-root` 25%, `lv-var` 15%, `lv-docker` 20%,
  `lv-tmp` 5%, fixed 4G swap LV) — see `provisioning-kit/docs/STORAGE.md`
- Single admin user via `identity:`, password-only login (no SSH key in v1)
- `00-bootstrap.sh` embedded directly in `user-data` (the only file trusted
  on arrival, via the certificate-validated boot channel)

**`scripts/`** — first-boot pipeline, numbered with gaps for future stages:
`05-base-packages`, `10-docker` (with log-rotated `daemon.json`), `15-node`,
`20-python`, `25-github-cli`, `30-claude-code`, `90-cleanup`. Shared
`lib/common.sh` provides logging, retry, idempotency sentinels, and hash
verification.

**Integrity chain** — `manifest.json` (SHA-256 of every fetchable file) +
detached GPG signature (`manifest.json.asc`), verified against a GPG public
key pinned inside `00-bootstrap.sh` before any stage script is downloaded or
run. A corrupted manifest or a corrupted staged file both abort the
pipeline before execution — verified in this release by deliberately
tampering with both (see "Validation performed" below).

**`tools/build-manifest.sh`** — hashes every fetchable file and writes
`manifest.json`.

**`tools/setup-production.sh`** *(new in this release)* — automates the
entire path from a freshly cloned repo (demo GPG key, placeholder
password/hostname) to a deployed, production-signed kit: generates a random
admin password + hash, generates (or reuses) a production GPG keypair,
splices both plus the target URL into the kit, rebuilds and re-signs the
manifest, and `rsync`s the result to a web root — one command, idempotent,
safe to re-run on every release. See [USAGE.md](USAGE.md) for the full flag
reference.

**Top-level docs** *(new in this release)*: this file, `README.md`,
`ARCHITECTURE.md`, `USAGE.md` — a repo-wide overview layered on top of the
existing `provisioning-kit/docs/` deep-dive set (architecture, deployment,
boot cmdline, storage layout, manual release process, verification
checklist).

### Validation performed

- `shellcheck -S warning` clean across every script.
- `yamllint` clean (only pre-existing line-length style warnings).
- `setup-production.sh` executed for real (not just `--dry-run`) in a
  sandboxed root environment: generated a real GPG keypair and admin
  password, spliced them into the kit, rebuilt and signed the manifest, and
  deployed to a web root.
- The resulting trust chain was independently re-verified: extracted the
  GPG public key from the *deployed* `00-bootstrap.sh` only, imported it
  into a throwaway keyring, and confirmed `manifest.json.asc` verifies
  against it — the same check a real target machine performs at first boot.
- Confirmed every file's SHA-256 in `manifest.json` matches the deployed
  copy.
- Tamper tests: corrupting a staged script is caught by the hash check;
  corrupting `manifest.json` itself is caught by signature verification.
  Both correctly abort.
- Two bugs found during that live run were fixed in `setup-production.sh`:
  a `sed` delimiter collision that broke the `KIT_BASE_URL`/`PROFILE`
  substitution, and a sanity-check step that silently swallowed its own
  success/failure output. Both fixes are included in this release.

### Known limitations / explicitly deferred

See `provisioning-kit/docs/ROADMAP.md` for the full list. Highlights: only
the `dev` profile is implemented (`web-server`/`local-server` are stubs);
no SSH key login, SSH hardening, firewall, or fail2ban; no CI/CD,
Makefile, or automated tests; no automatic rollback of a partially-applied
pipeline stage.

### Upgrading from the demo key

The GPG keypair and password hash shipped in this repo by default are
**demo values**, meant only to exercise the integrity mechanism. Run
`tools/setup-production.sh` (see [USAGE.md](USAGE.md)) before any real
deployment — it replaces both with generated, real values.
