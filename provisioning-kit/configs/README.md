# configs/

Reference copies of host configuration files deployed by the first-boot
pipeline. These files are **not fetched directly** by any stage script —
they document what each script generates at runtime (scripts build the
actual target files with runtime values like the admin username substituted
in). See each file's header comment for the exact target path on the
provisioned machine.

## Contents (v1.1)

| File | Deployed to | Deployed by |
|---|---|---|
| `sshd_config.d/provisioning-hardening.conf` | `/etc/ssh/sshd_config.d/99-provisioning-hardening.conf` | `scripts/35-security.sh` |
| `fail2ban/jail.d/sshd.conf` | `/etc/fail2ban/jail.d/provisioning-sshd.conf` | `scripts/35-security.sh` |

## v2 placeholders

Still reserved for future versions (see `docs/ROADMAP.md`):
- `ufw/` — explicit UFW application profiles
- `sysctl.d/` — kernel tuning (`vm.swappiness`, `net.*` hardening)
- `journald.conf.d/` — log retention limits
