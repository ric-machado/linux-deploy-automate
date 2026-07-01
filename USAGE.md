# Usage and implementation guide

How to take this repo from a clone to a server provisioned over the network,
end to end.

## 0. Prerequisites

- A Linux host to run the maintainer tooling on (root access), with `gpg`,
  `jq`, `openssl`, `rsync`, `awk`, `sed` installed.
- An Apache (or any static HTTP/HTTPS) web server with a **valid** TLS
  certificate already configured — the autoinstall boot channel's
  certificate validation is this kit's entire root of trust. Self-signed
  certs are not handled in v1.
- An Ubuntu Server 24.04 LTS installer ISO and a way to boot it (PXE,
  virtual media, USB) on the target machine.

## 1. Generate secrets and deploy the kit

`provisioning-kit/tools/setup-production.sh` does this in one run: generates
a random admin password (and its hash), generates (or reuses) a production
GPG signing key, splices both plus your kit URL into the kit's files,
re-signs the manifest, and deploys everything to your web root.

```sh
sudo provisioning-kit/tools/setup-production.sh \
    --kit-base-url https://your-server.example.com/autodeploy \
    --hostname dev-server \
    --username admin
```

Run with `--dry-run` first to preview every step without changing anything.
By default it asks for confirmation before making changes — pass `--force`
to skip the prompt (e.g. for unattended re-runs).

### Flags

| Flag | Default | Meaning |
|---|---|---|
| `--kit-base-url URL` | `https://$(hostname -f)/autodeploy` | Base URL the kit will be served from; embedded in `00-bootstrap.sh` and used to build the boot cmdline |
| `--profile NAME` | `dev` | Which `profiles/<name>/` to provision |
| `--hostname NAME` | `dev-server` | `identity.hostname` written into the profile's `user-data` |
| `--username NAME` | `admin` | `identity.username` written into the profile's `user-data` |
| `--deploy-dir DIR` | `/var/www/html/autodeploy` | Where the kit is `rsync`'d to (your web root) |
| `--gpg-home DIR` | `/opt/autodeploy/GPG` | Keyring holding the production GPG keypair — **never** under `--deploy-dir` |
| `--secrets-dir DIR` | `/opt/autodeploy/secrets` | Where the generated password (and optional GPG passphrase) are written |
| `--password-length N` | `24` | Random admin password length in bytes (before base64 encoding) |
| `--gpg-name "Name"` | `Provisioning Kit (PRODUCTION)` | GPG key real-name field |
| `--gpg-email EMAIL` | `provisioning-kit@<hostname>` | GPG key email field |
| `--rotate-key` | off | Force-generate a brand new GPG key even if `--gpg-home` already has one (default: reuse) |
| `--protect-key-with-passphrase` | off | Passphrase-protect the new private key (passphrase generated and saved in `--secrets-dir`); default is no passphrase, since the kit's release process is meant to run unattended |
| `--ssh-pubkey "KEY"` | none | Admin SSH public key to embed in `user-data` (e.g. `"$(cat ~/.ssh/id_ed25519.pub)"`). When set, `authorized-keys` is populated and `allow-pw` is set to `false`; `35-security.sh` will then disable password auth on the target. When omitted, password auth is kept (safe default when no key is available) |
| `--dry-run` | off | Print every step, change nothing |
| `--force` | off | Skip the confirmation prompt |
| `-h`, `--help` | | Show usage |

The script is idempotent: re-running it after editing a stage script or
`pipeline.conf` reuses the existing production key, regenerates the
manifest, re-signs it, and redeploys — safe to do as part of every release.

### What it touches

- **Generates, outside the repo:** the GPG keypair (`--gpg-home`) and the
  plaintext admin password file (`--secrets-dir`). Retrieve the password
  from `<secrets-dir>/<profile>-admin-password.txt` and delete the file
  once you've stored it somewhere safe — it's the only copy.
- **Modifies, inside the repo:** `scripts/00-bootstrap.sh` (URL, profile,
  embedded public key) and `profiles/<profile>/user-data` (the same
  embedded script, plus `identity.hostname/username/password`), then
  `manifest.json`/`manifest.json.asc`. Review with `git diff` — these now
  contain real secrets (a password hash and a public key tied to a real
  private key) and you decide whether that belongs in version control or
  should be kept out of it for your deployment.
- **Deploys:** an `rsync` copy of `provisioning-kit/` (excluding `.git/`
  and `tools/`) to `--deploy-dir`.

## 2. Boot the target machine

Boot the Ubuntu Server 24.04 LTS ISO and pass the autoinstall cmdline
printed at the end of `setup-production.sh`'s output:

```
autoinstall ds=nocloud-net;s=https://your-server.example.com/autodeploy/profiles/dev/
```

See `provisioning-kit/docs/BOOTING.md` for the exact mechanics of adding
this to your boot method (PXE/virtual media/etc).

## 3. Watch it provision

curtin partitions the disk per `profiles/dev/user-data`'s `storage:` block,
the installed system reboots, and cloud-init's first-boot `runcmd` starts
the pipeline. From the target machine:

```sh
journalctl -u provisioning-bootstrap -f
```

or after it finishes, inspect `/opt/provisioning/logs/` and
`/opt/provisioning/state/*.done`. A failure aborts the whole pipeline (no
partial continuation) and leaves a retry hint in `/etc/motd.d/`; re-running
`sudo /opt/provisioning/scripts/00-bootstrap.sh` resumes from the failed
stage since completed stages are skipped.

## 4. Verify

Log in as the admin user with the password retrieved in step 1, then:

```sh
docker run hello-world
node -v
python3 --version
gh --version
claude --version
git --version
```

The admin user should already be in the `docker` group without a fresh
login. Also verify the security hardening applied by `35-security.sh`:

```sh
sudo ufw status verbose          # should show: Status: active, 22/tcp ALLOW IN
sudo fail2ban-client status sshd # should show the sshd jail as active
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|maxauthtries|allowusers'
cat /etc/ssh/sshd_config.d/99-provisioning-hardening.conf
```

Full manual-verification checklist (including how to deliberately test the
integrity chain by tampering with a deployed file) in
`provisioning-kit/docs/VERIFICATION.md`.

## Updating an already-deployed kit

After editing anything under `provisioning-kit/scripts/` or
`profiles/*/pipeline.conf`, re-run `setup-production.sh` (same flags as
before) to regenerate the manifest, re-sign it, and redeploy. It reuses the
existing production GPG key automatically — pass `--rotate-key` only if you
specifically need to rotate the signing key itself.

## Customizing without `setup-production.sh`

For a fully manual process (e.g. CI that doesn't have access to the
production key) see `provisioning-kit/docs/RELEASING.md` and
`provisioning-kit/docs/DEPLOYMENT.md`, which document the same steps —
edit a hash by hand, run `tools/build-manifest.sh`, `gpg --detach-sign`,
`rsync` — broken out individually.
