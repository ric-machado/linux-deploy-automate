# Roadmap (explicitly deferred from v1)

These were raised during design (either in the original spec or the
follow-up technical review) and deliberately scoped out of v1 to keep the
first version shippable. Listed here so they aren't silently dropped.

## Profiles
- `profiles/web-server/` — reverse proxy / TLS termination / public-facing
  firewall posture (currently a stub README only)
- `profiles/local-server/` — LAN-only services, relaxed firewall posture
  (currently a stub README only)
- `profiles/base/` with inheritance shared across profiles — only worth
  extracting once a second real profile exists; until then it's speculative
  abstraction over a single implementation

## Security hardening
- Extra non-root users beyond the single `identity:` admin (e.g. a dedicated
  `dockeradmin`/`devops` account)

**Delivered in v1.1** (no longer deferred):
- SSH hardening: `PermitRootLogin no`, `MaxAuthTries 3`, `LoginGraceTime 30`,
  `AllowUsers <admin>`, `X11Forwarding no` — via drop-in
  `/etc/ssh/sshd_config.d/99-provisioning-hardening.conf`
- SSH key-based login: `tools/setup-production.sh --ssh-pubkey` injects an
  SSH public key into `user-data`'s `authorized-keys` and sets `allow-pw:
  false`; `35-security.sh` sets `PasswordAuthentication no` on the target
  only when a key is actually present (avoids lockout if no key was set)
- UFW firewall: default deny incoming, allow outgoing, port 22 explicitly
  allowed; see the Docker+UFW note in `scripts/35-security.sh`
- fail2ban: sshd jail (3 attempts / 10 min / 1 h ban, systemd backend)

## Observability
- Netdata / Prometheus node exporter
- sysctl / journald hardening and log-retention tuning

## Automation
- GitHub Actions: YAML lint, `cloud-init schema --annotate` /
  `validate-autoinstall-user-data.py` validation, shellcheck, automated ISO
  build — all currently run manually, see `docs/VERIFICATION.md`
- Makefile wrapping the manual verification/release commands
- `tests/` directory (e.g. automated VM boot tests)
- Automated ISO building/repackaging (`iso-builder/`)

## Pipeline robustness
- Automatic rollback of a partially-applied stage (e.g. a Docker install that
  fails halfway) — reverting safely is a feature in its own right, not an
  incremental tweak; for now, fix the underlying issue and re-run
  `00-bootstrap.sh` manually (idempotent, skips `.done` stages)

## Docker
- Example `docker-compose.dev.yml` / `Dockerfile.dev` under a `docker/`
  directory — v1 only creates the `/var/lib/docker` mount point + LV; no
  example application/compose file is shipped
