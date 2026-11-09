# Memory

2026-11-09. Favorites, progress and per-user settings are part 13 (`docs/manual/13-personal-state.md`) and `scripts/podman/state.sh`.

A container recreate already remounts `/srv/stream/<app>` and `/srv/gate/<app>`. A wipe of that directory does not. Snapshots are `/srv/storage/vault/personal-state` on the SGIN (off the Samba share) and `/srv/backups/personal-state` on the gate (not under `/srv/gate`). App scripts restore when the marker database is missing. `sgin/state-backup.sh` and `gate/state-backup.sh` also enable a 03:10 user timer.

Part 5.6 (PBS `stream.pxar` and the gate VM) already stores those bytes. It does not restore one app after its directory is wiped.

Do not edit manual section 5.4 for this. The music wall there allows `user:eels`, `user:rachel`, and `group:music`, then denies everyone else on `music.songofeo.com` and `mustang.songofeo.com`. Navidrome personal-state notes stay in part 13, not in `docs/music.md`.

Not in the part 13 snapshots: Paperless originals (`paperless/media`), nginx certs and site config, the forms inbox, Icecast's podman secrets. RomM and Paperless podman secrets are in their snapshots and are loaded only if that secret is missing.
