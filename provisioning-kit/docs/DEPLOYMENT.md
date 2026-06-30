# Deployment

## Copying to Apache

Copy the entire `provisioning-kit/` directory tree as-is into your Apache
document root (or a subdirectory of it), preserving the directory structure.
Nothing needs to be built first — `manifest.json`/`manifest.json.asc` are
already generated and committed (see `docs/RELEASING.md` for how to
regenerate them after any edit).

```
rsync -av provisioning-kit/ your-server:/var/www/html/provisioning-kit/
```

## File permissions

Standard Apache static-file permissions are sufficient: readable by the
Apache user, no execute bit required (the target machine downloads these as
plain files, it doesn't execute them off the web server). Directory listing
is not required and can be left disabled.

## Content-Type for extensionless files

`profiles/dev/user-data` and `profiles/dev/meta-data` have no file extension.
Most Apache configs default extensionless files to
`application/octet-stream` or `text/plain`, which is fine for cloud-init's
NoCloud HTTP datasource — it does not require a specific `Content-Type`.
If you have strict MIME-type enforcement elsewhere in your Apache config,
explicitly allow/serve these two files as `text/plain` or `text/yaml`, e.g.:

```apache
<FilesMatch "^(user-data|meta-data)$">
    ForceType text/plain
</FilesMatch>
```

## Required manual edits before first deploy

1. **`profiles/dev/user-data` → `identity.password`** — replace the
   placeholder hash with a real one:
   ```
   openssl passwd -6
   ```
   The placeholder in the repo is intentionally not a usable hash; autoinstall
   will not produce a working login until this is replaced.

2. **`profiles/dev/user-data` → `storage.config[0].match`** — defaults to
   `size: largest`. For machines with multiple disks or SAN-attached storage,
   pin a specific disk via `serial:`, `wwn:`, or `path:` instead — see
   `docs/STORAGE.md`.

3. **`scripts/00-bootstrap.sh` → `KIT_BASE_URL`** — set to the actual base
   URL this kit is served from, then **copy the edited script's content back
   into the `write_files` block in `profiles/dev/user-data`** (the two must
   stay byte-identical — `00-bootstrap.sh` is never separately fetched, the
   embedded copy in `user-data` is what actually runs).

4. **GPG signing key** — the key shipped in `keys/` and embedded in
   `00-bootstrap.sh` is a **DEMO key**. Generate your own and re-sign before
   any real deployment — see `docs/RELEASING.md`.

After any edit to files under `scripts/` or `profiles/*/pipeline.conf`,
re-run `tools/build-manifest.sh` and re-sign `manifest.json` — stale hashes
will make `00-bootstrap.sh` abort with a hash-mismatch error on every
affected stage.
