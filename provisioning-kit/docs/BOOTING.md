# Booting the `dev` profile

Boot the standard Ubuntu Server 24.04 LTS ISO and append the following to the
kernel command line (at the GRUB boot menu, press `e` to edit, or pass via
your hypervisor's kernel-args field):

```
autoinstall ds=nocloud-net;s=https://SEU-SERVIDOR/provisioning-kit/profiles/dev/
```

Replace `SEU-SERVIDOR` with your actual Apache host. Note the trailing
slash — the NoCloud datasource fetches `<s>/user-data` and `<s>/meta-data`
from that exact base.

## What happens after boot

1. Subiquity runs the autoinstall flow non-interactively using
   `profiles/dev/user-data` (no prompts, since `interactive-sections` is not
   set and every required section is present).
2. curtin partitions the disk per `storage:` (see `docs/STORAGE.md`).
3. The installed system reboots into cloud-init's first-boot run, which
   executes the embedded `00-bootstrap.sh` via
   `systemd-run --unit=provisioning-bootstrap --collect`.
4. Progress can be watched directly on the console (login is available once
   cloud-init's first-boot stage completes, even while the provisioning
   pipeline is still running in the background unit) or via:
   ```
   journalctl -u provisioning-bootstrap -f
   ```
5. On success, `/etc/issue` and `/etc/motd.d/90-provisioning-kit` show a
   completion banner with the kit version. On failure, `/etc/issue` shows the
   failed stage and the log path; re-run with
   `sudo /opt/provisioning/scripts/00-bootstrap.sh` (idempotent — completed
   stages are skipped).
