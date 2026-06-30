# Documentation index

| Doc | Covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Full boot-to-ready flow, trust model |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Copying the kit to Apache, permissions, Content-Type |
| [BOOTING.md](BOOTING.md) | Exact autoinstall boot cmdline for the `dev` profile |
| [STORAGE.md](STORAGE.md) | LVM percentage layout, swap rationale, disk matching |
| [RELEASING.md](RELEASING.md) | Manual release process: manifest + GPG signature |
| [ROADMAP.md](ROADMAP.md) | Explicitly deferred items (v2+) |
| [VERIFICATION.md](VERIFICATION.md) | Validation checklist, static + manual-VM |

## What's implemented in v1

| Area | Status |
|---|---|
| `dev` profile (storage, packages, bootstrap) | ✅ implemented |
| `web-server` / `local-server` profiles | ⬜ stub only, see ROADMAP.md |
| GPG-signed manifest integrity | ✅ implemented |
| Per-stage logs + idempotent sentinels | ✅ implemented |
| Docker log rotation (`daemon.json`) | ✅ implemented |
| Extra users / SSH hardening / firewall / monitoring | ⬜ deferred, see ROADMAP.md |
| CI/CD (lint/validate/build automation) | ⬜ deferred, see ROADMAP.md |
| Profile inheritance (`profiles/base/`) | ⬜ deferred, see ROADMAP.md |
