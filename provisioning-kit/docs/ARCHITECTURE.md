# Architecture

## Flow

```
1. Boot ISO with autoinstall cmdline
   (ds=nocloud-net;s=https://<server>/provisioning-kit/profiles/dev/)
        │
        ▼
2. Subiquity/curtin fetches user-data + meta-data over HTTPS
   (cert already validated by the boot environment — this is the trust root)
        │
        ▼
3. curtin partitions disk per the `storage:` config in user-data
   (GPT, ESP + /boot outside LVM, single VG, percentage-sized LVs)
        │
        ▼
4. Target system installed, autoinstall's embedded `user-data:` cloud-config
   block (write_files + runcmd) is staged for cloud-init on first real boot
        │
        ▼
5. First boot: cloud-init writes /opt/provisioning/scripts/00-bootstrap.sh
   and runs it via `systemd-run --unit=provisioning-bootstrap --collect`
        │
        ▼
6. 00-bootstrap.sh: apt-get install gnupg/jq/curl (verification tooling)
   → imports embedded GPG public key → downloads + verifies
   manifest.json/.asc → downloads + verifies (SHA-256) common.sh,
   pipeline.conf, and each stage script before running it
        │
        ▼
7. Stages run in order (05 → 90), each idempotent, each logged separately,
   pipeline aborts on first failure
        │
        ▼
8. mark_done "ALL" — success banner in /etc/issue + /etc/motd.d/
```

## Trust model

HTTPS protects the transport, but not against a compromised web server or a
script altered after publication. The chain of trust is:

1. **The boot cmdline itself** is the root of trust — the admin configuring
   `ds=nocloud-net;s=...` already trusts that URL/certificate.
2. `user-data` (and the `00-bootstrap.sh` embedded inside it via
   `write_files`) reaches the target machine through that same
   certificate-validated channel. **This is the only file ever trusted
   without a hash/signature check** — everything else is verified against it.
3. `00-bootstrap.sh` carries a **pinned GPG public key**, literally inline
   (not fetched from the kit's web root — fetching it from the same place
   being verified would be circular).
4. `manifest.json` + `manifest.json.asc` are downloaded and the detached
   signature is verified against that pinned key. Abort on any failure.
5. Every other file (`scripts/lib/common.sh`, `profiles/<p>/pipeline.conf`,
   each stage script) is downloaded and its SHA-256 checked against the
   signed manifest **before execution**. Abort the stage (no `.done`
   sentinel written) on any mismatch or missing manifest entry.

`00-bootstrap.sh` is therefore the **only** kit file that is never
fetched-and-verified at runtime; it's the integrity root, not subject to
self-verification.

## Idempotency & state

Every stage records its state as a sentinel file under
`/opt/provisioning/state/<stage>.{running,done,failed}`. `00-bootstrap.sh`
skips any stage already marked `.done`, so re-running
`sudo /opt/provisioning/scripts/00-bootstrap.sh` after a failure resumes from
the failed stage rather than starting over. Stage scripts are themselves
written to be safe to re-run manually (repo/package checks before
installing).

## Logging

- `/opt/provisioning/bootstrap-early.log` — pre-`common.sh` bootstrap output
  (key import, manifest fetch/verify)
- `/opt/provisioning/logs/bootstrap.log` — orchestration-level log (every
  `log()` call from `00-bootstrap.sh` and `common.sh`)
- `/opt/provisioning/logs/<stage>.log` — stdout/stderr of each individual
  stage script

## Why first-boot, not `late-commands`

`late-commands` run chrooted into the target filesystem from the live
installer environment: no real network stack, no systemd, no Docker daemon.
Installing Docker/Node/npm packages and running GPG verification with retry
logic needs all of those, so the entire pipeline runs from a genuine first
boot of the installed system instead, triggered by cloud-init's `user-data:`
block (`write_files` + `runcmd`).

`systemd-run --unit=provisioning-bootstrap --collect` decouples the pipeline
from cloud-init's `runcmd` watchdog (which can time out well before a
Docker + Node.js + npm install finishes) and gives one place to inspect
progress: `systemctl status provisioning-bootstrap` /
`journalctl -u provisioning-bootstrap`.
