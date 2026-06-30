# scripts/

First-boot pipeline scripts, fetched and integrity-verified one at a time by
`00-bootstrap.sh` (see `docs/ARCHITECTURE.md`). Every script in this directory
is listed by name in `manifest.json` with its SHA-256 hash, and only scripts
named in a profile's `pipeline.conf` are ever fetched/executed.

## Numbering convention

Stages are numbered in increments of 5 so that new stages can be inserted
without renumbering existing ones:

| Range | Purpose |
|---|---|
| `00` | bootstrap orchestrator (embedded in `user-data`, never fetched) |
| `05` | base OS packages |
| `10` | Docker |
| `15` | Node.js |
| `20` | Python |
| `25` | GitHub CLI |
| `30` | Claude Code CLI |
| `35`-`85` | reserved for v2 (extra users, SSH hardening, UFW, fail2ban, monitoring — see `docs/ROADMAP.md`) |
| `90` | cleanup / final banner |

## Adding a new stage

1. Create `scripts/NN-name.sh`:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   # shellcheck source=lib/common.sh
   source /opt/provisioning/scripts/lib/common.sh
   require_root
   log "NN-name: ..."
   ```
2. Use `log()`, `retry()`, `download()`, `require_root`/`require_network`/`require_command`
   from `lib/common.sh` instead of re-implementing them.
3. Make the script idempotent — it may be re-run manually after a failed
   pipeline (stages with a `.done` sentinel in `/opt/provisioning/state/` are
   skipped automatically, but a stage script can itself be invoked again).
4. Add the script's filename (with optional arguments) as a new line in the
   relevant profile's `pipeline.conf`, e.g. `profiles/dev/pipeline.conf`.
5. Re-run `tools/build-manifest.sh` and re-sign `manifest.json` before
   publishing (see `docs/RELEASING.md`) — an unlisted or hash-mismatched
   script is refused by `fetch_verified()` in `00-bootstrap.sh`.

## `lib/common.sh`

Shared helpers sourced by every script above:

- `log(msg)` — timestamped line to `logs/bootstrap.log` and stderr
- `require_root` / `require_network [url]` / `require_command <cmd>`
- `retry <attempts> <command...>` — exponential backoff starting at 2s
- `download <url> <dest>` — `curl` wrapped in `retry`
- `verify_hash <file> <sha256>` — accepts bare hex or `sha256:`-prefixed
- `mark_running` / `mark_done` / `mark_failed` / `is_done` — stage sentinels
  under `/opt/provisioning/state/`
