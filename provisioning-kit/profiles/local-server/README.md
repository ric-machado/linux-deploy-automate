# profiles/local-server — not implemented in v1

This profile is a placeholder. It is not wired into the kit yet: there is no
`user-data`, `meta-data`, or `pipeline.conf` here, and no boot cmdline should
point at this directory.

See `docs/ROADMAP.md` for what this profile is expected to cover (LAN-only
services, no public exposure, relaxed firewall posture, etc.) and the
`profiles/dev/` profile for the reference implementation pattern to follow
once this is built out.
