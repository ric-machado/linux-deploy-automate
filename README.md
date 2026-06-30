# linux-deploy-automate

Zero-touch provisioning for Ubuntu Server 24.04 LTS. A static kit of
autoinstall/cloud-init configuration plus a first-boot script pipeline turns
a stock Ubuntu Server ISO boot into a fully configured host — disk
partitioning, Docker, Node.js, Python, GitHub CLI, Claude Code — with no
manual steps beyond pointing the installer at a URL, and every downloaded
script verified against a GPG-signed manifest before it ever runs.

## What's in this repo

```
provisioning-kit/        the kit itself — see provisioning-kit/README.md
├── profiles/dev/         autoinstall user-data/meta-data for the `dev` profile (implemented)
├── profiles/web-server/  stub, not implemented yet
├── profiles/local-server/ stub, not implemented yet
├── scripts/               first-boot pipeline (Docker, Node, Python, gh, Claude Code, ...)
├── tools/                 maintainer tooling (manifest builder, production setup automation)
└── docs/                  detailed architecture/deployment/storage/release docs
```

Only the `dev` profile is implemented in this version. See
`provisioning-kit/docs/ROADMAP.md` for what's deferred.

## Start here

| I want to... | Read |
|---|---|
| Understand how it works end to end | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Deploy and boot a server against this kit | [USAGE.md](USAGE.md) |
| See what's in this version | [RELEASE.md](RELEASE.md) |
| Go deep on a specific topic (storage layout, integrity model, boot cmdline...) | [provisioning-kit/docs/](provisioning-kit/docs/README.md) |

## Quick start

```sh
sudo provisioning-kit/tools/setup-production.sh \
    --kit-base-url https://your-server/autodeploy

# boot the Ubuntu Server 24.04 ISO with:
autoinstall ds=nocloud-net;s=https://your-server/autodeploy/profiles/dev/
```

`setup-production.sh` generates a real admin password, a real production GPG
signing key, splices both into the kit, re-signs the manifest, and deploys
the result to your Apache web root in one run. See [USAGE.md](USAGE.md) for
the full walkthrough and every flag.

## License

See [LICENSE](LICENSE).
