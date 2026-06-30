# Verification checklist

## Static checks (doable without a VM)

- [ ] `cloud-init schema --config-file=profiles/dev/user-data --annotate`
- [ ] `canonical/subiquity`'s `validate-autoinstall-user-data.py` against
      `profiles/dev/user-data`
- [ ] `yamllint` on `profiles/dev/user-data` and `profiles/dev/meta-data`
- [ ] `shellcheck` on every `scripts/*.sh` and `tools/build-manifest.sh`
- [ ] Every script listed in `profiles/dev/pipeline.conf` exists under
      `scripts/` and has a corresponding entry in `manifest.json`
- [ ] `manifest.json` is valid JSON (`jq '.' manifest.json`)
- [ ] `gpg --verify manifest.json.asc manifest.json` succeeds locally using
      `keys/provisioning-kit-public.asc`
- [ ] The `00-bootstrap.sh` content embedded in `profiles/dev/user-data`'s
      `write_files` block is byte-identical to `scripts/00-bootstrap.sh`
- [ ] No real password hash or GPG private key is committed anywhere in the
      repo (the shipped key is a labelled DEMO key, and
      `identity.password` in `user-data` is a non-functional placeholder)

## Manual checks (require a real VM/bare-metal boot)

- [ ] Boot the ISO with the `dev` profile's autoinstall cmdline
      (`virt-install`/QEMU-KVM or VirtualBox) against a kit served from a
      real Apache instance
- [ ] curtin partitions the disk as expected: `lsblk`, `vgs`, `lvdisplay`
      match the percentages in `docs/STORAGE.md`
- [ ] `swapon --show` confirms the swap LV is active
- [ ] `journalctl -u provisioning-bootstrap` shows the GPG key import,
      manifest signature verification, and each stage's hash verification
      succeeding
- [ ] **Tamper test**: modify one byte of a published stage script on the
      Apache server (without updating `manifest.json`) and confirm
      `00-bootstrap.sh` aborts that stage with a hash-mismatch error instead
      of executing the modified script
- [ ] **Signature tamper test**: modify `manifest.json` without re-signing
      and confirm `00-bootstrap.sh` aborts before downloading anything else
- [ ] `/etc/docker/daemon.json` applied; `docker info` shows the configured
      `json-file` log driver with `max-size`/`max-file`
- [ ] Final smoke test as the `admin` user (no new login required for the
      `docker` group to take effect — confirm this holds):
      ```
      docker run hello-world
      node -v
      python3 --version
      gh --version
      claude --version
      git --version
      ```
