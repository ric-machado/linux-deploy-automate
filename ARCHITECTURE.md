# Architecture

This repo has two distinct flows: the **target-machine flow** (what happens
when a server boots against the kit) and the **maintainer flow** (how the
kit itself is prepared, signed, and published). Both are summarized below;
`provisioning-kit/docs/ARCHITECTURE.md` covers the target-machine flow in
full detail.

## 1. Target-machine flow (boot → ready server)

```
Boot ISO with autoinstall cmdline
  (ds=nocloud-net;s=https://<server>/profiles/dev/)
        │
        ▼
Subiquity/curtin fetches user-data + meta-data over HTTPS
  (cert already validated by the boot environment — the trust root)
        │
        ▼
curtin partitions the disk per `storage:` in user-data
  (GPT, ESP + /boot outside LVM, single VG, percentage-sized LVs)
        │
        ▼
Target installed; cloud-init's embedded user-data: block
  (write_files + runcmd) is staged for first real boot
        │
        ▼
First boot: cloud-init writes 00-bootstrap.sh and runs it via
  `systemd-run --unit=provisioning-bootstrap --collect`
        │
        ▼
00-bootstrap.sh imports its pinned GPG public key, downloads +
  verifies manifest.json/.asc, then downloads + verifies (SHA-256)
  every stage script before running it
        │
        ▼
Stages run in order (05 → 90), each idempotent and separately logged;
  pipeline aborts on first failure
        │
        ▼
mark_done "ALL" — success banner, server ready
```

**Trust model, short version**: HTTPS protects transport, not against a
compromised web server or an altered file. `user-data` (and the
`00-bootstrap.sh` embedded in it) is the only file trusted on arrival — it
reaches the target through the already certificate-validated autoinstall
boot channel and carries a pinned GPG public key. Every other file
(`manifest.json` itself, `common.sh`, `pipeline.conf`, each stage script) is
verified — signature for the manifest, SHA-256 against the manifest for
everything else — **before** it is executed. Full detail, including why
this runs at first-boot rather than in `late-commands`, in
[`provisioning-kit/docs/ARCHITECTURE.md`](provisioning-kit/docs/ARCHITECTURE.md).

## 2. Maintainer flow (preparing and publishing a kit)

This is the half not covered by the target-machine doc: how `manifest.json`,
its signature, and the embedded GPG key in `00-bootstrap.sh` actually get
produced, and how the kit ends up on a web server in the first place.

```
provisioning-kit/tools/setup-production.sh   (run once per deployment, idempotent)
        │
        ├─ 1. generate a random admin password + SHA-512 hash
        │       → /opt/autodeploy/secrets/<profile>-admin-password.txt
        │
        ├─ 2. generate (or reuse) a production GPG keypair
        │       → /opt/autodeploy/GPG  (private key — never web-served)
        │
        ├─ 3. splice KIT_BASE_URL / PROFILE / the new GPG public key
        │       into scripts/00-bootstrap.sh
        │
        ├─ 4. re-embed the updated 00-bootstrap.sh into
        │       profiles/<profile>/user-data, and update
        │       identity.hostname/username/password there too
        │
        ├─ 5. tools/build-manifest.sh → manifest.json
        │       gpg --detach-sign       → manifest.json.asc
        │       (verified locally before proceeding)
        │
        └─ 6. rsync the kit (excluding .git/ and tools/) to
                /var/www/html/autodeploy  (or --deploy-dir)
```

Two roots of trust never overlap: the GPG **private** key lives only in
`--gpg-home` (default `/opt/autodeploy/GPG`), structurally outside the
directory that gets `rsync`'d to the web root, so it can never accidentally
become web-servable. The **public** key only ever reaches a target machine
embedded in `00-bootstrap.sh`, via the certificate-validated boot channel —
never fetched from the same server it's meant to verify.

Re-running `setup-production.sh` is safe: it reuses the existing GPG key by
default (`--rotate-key` to force a new one) and regenerates everything else
deterministically from the current `scripts/` and profile content. See
[USAGE.md](USAGE.md) for the full flag reference and
[RELEASE.md](RELEASE.md) for what's included in this version.

## Repository layout

```
.
├── README.md / ARCHITECTURE.md / USAGE.md / RELEASE.md   this repo's top-level docs
└── provisioning-kit/             the deployable kit (this is what you copy to a web root)
    ├── profiles/<name>/           one URL per profile: user-data + meta-data + pipeline.conf
    ├── scripts/                   first-boot pipeline + scripts/lib/common.sh
    ├── tools/                     maintainer-only: build-manifest.sh, setup-production.sh
    ├── manifest.json(.asc)        signed integrity manifest for the pipeline's fetchable files
    ├── keys/                      reference copy of the GPG public key (docs only)
    ├── configs/ packages/ templates/  placeholders reserved for future versions
    └── docs/                      deep-dive docs (architecture, deployment, storage, release, roadmap)
```
