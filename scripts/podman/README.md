# Podman run scripts

One bash script per app, using plain `podman run`. They build the same two pods as the manual's Quadlet files (parts 3.8, 5.4, 7, 8): same images, ports, folders and users. Use them instead of the Quadlets, or to rebuild a single app quickly.

| Host | Folder | Pod | Scripts |
|---|---|---|---|
| SGIN, `cobra-stream` (10.6.9.20) | [`sgin/`](sgin/) | `stream` | `jellyfin.sh` (Quick Sync), `ersatztv.sh` (live TV channels + guide), `navidrome.sh` (one library per person), `audiobookshelf.sh`, `kavita.sh`, `romm.sh` (RomM + EmulatorJS + MariaDB), `radio.sh` (Icecast + Liquidsoap, part 8) |
| Gate VM, `cobra-gate` (10.6.9.10) | [`gate/`](gate/) | `gate` | `vaultwarden.sh`, `paperless.sh` (Paperless + Postgres + Redis), `metube.sh`, `homepage.sh`, `hiscore.sh` (part 7), plus the pieces the gate needs to be reachable: `nginx.sh`, `authelia.sh`, `uptime-kuma.sh` |

Each folder also has `up-all.sh`, which runs every script on that host in order.

## Before you run them

The host part of the manual must be done first, because the scripts don't use sudo:

- **SGIN:** parts 3.3 to 3.7 (Intel driver and HuC firmware, the mergerfs pool at `/srv/storage/pool` with its folders, user `podsvc` in groups `media`, `render`, `video` with linger on, `/srv/stream` owned by podsvc, Samba, nftables).
- **Gate:** part 5.2 (podsvc with linger, `/srv/gate` owned by podsvc, ports 80/443 allowed for rootless, the CIFS mount of the pool). nginx also needs the certificate from 5.3 and the site config from 5.5; Authelia needs its config from 5.5.

## Run

Get the scripts onto the host, either `git clone https://github.com/agent61636/cobra-server` as podsvc, or the ZIP plus `scp -r`. Then:

```bash
sudo machinectl shell podsvc@        # a real login session; sudo su / sudo -u won't work
cd ~/cobra-server/scripts/podman/sgin     # gate/ on the gate
./up-all.sh                          # or one app: ./jellyfin.sh
podman ps --pod
```

Every script is safe to run again. It removes that app's container and starts a fresh one. The app's data lives in the mounted folders, so nothing is lost. Each one ends by printing the app's URL and the setup steps you do once in its web page.

| To... | Run |
|---|---|
| Update one app to its newest image | `UPDATE=1 ./jellyfin.sh` |
| Update everything on the host | `UPDATE=1 ./up-all.sh` (read the release notes for Authelia, Paperless and RomM first) |
| See logs | `podman logs -f jellyfin` |
| Restart one app | `podman restart jellyfin` |
| Add another person's music library | `MUSIC_USERS="eels rachel sam" ./navidrome.sh` (it makes `music/sam` on the pool and prints the steps) |
| Give one app extra settings | put `KEY=value` lines in `~/.config/cobra/<container>.env` and rerun its script, e.g. RomM's metadata keys in `romm.env` |
| Change a pod's ports | edit `sgin/pod.sh` or `gate/pod.sh`, then `RECREATE_POD=1 ./up-all.sh` |
| Read a generated password | `podman secret ls`, then `podman secret inspect --showsecret --format '{{.SecretData}}' romm-db-password` |

## How they work

- **Pods.** `sgin/pod.sh` and `gate/pod.sh` hold the published ports. The SGIN publishes each app's port to the LAN (nftables keeps it LAN and WireGuard only). The gate publishes only 80/443, and every app there is reached through nginx on `127.0.0.1`.
- **Start at boot.** Containers are made with `--restart always`, and the first script run enables `podman-restart.service` for podsvc, which starts them at boot (linger keeps it running without a login). On the gate, Paperless and MeTube keep restarting until the SGIN's share is back.
- **Passwords.** The RomM, Paperless and Icecast passwords are generated once and stored as podman secrets, never in the scripts. They don't show up in `podman inspect`.
- **Quick Sync.** Jellyfin and ErsatzTV get `/dev/dri` and `--group-add keep-groups`, so they keep podsvc's `render` group inside the container. `jellyfin.sh` checks afterwards that ffmpeg in the container sees the GPU's HEVC profiles.
- **Folders.** Same paths as the manual: app data under `/srv/stream/<app>` and `/srv/gate/<app>` with `:Z`, and the library pool mounted read-only at `/media` without `:Z`, because Samba shares it. RomM writes to `roms` and MeTube to `youtube`; Paperless reads `scans`.

## Coming from the manual's Quadlet files

One app can't be run both ways. If a script finds a matching `.container` or `.pod` file in `~/.config/containers/systemd/`, it stops and prints how to switch. To move a whole host at once:

```bash
systemctl --user stop stream-pod                 # gate-pod on the gate
mkdir -p ~/quadlet-old && mv ~/.config/containers/systemd/* ~/quadlet-old/
systemctl --user daemon-reload
```

RomM and Paperless already have a database with the password the manual generated. Hand it over on the first script run, or the app can't log in to its own database. The old values are in the moved files:

```bash
grep -h -o 'DB_PASSWD=[^ ]*\|ROMM_AUTH_SECRET_KEY=[^ ]*' ~/quadlet-old/romm.container                  # SGIN
ROMM_DB_PASSWORD=<DB_PASSWD value> ROMM_AUTH_SECRET=<ROMM_AUTH_SECRET_KEY value> ./romm.sh

grep -h -o 'PAPERLESS_DBPASS=[^ ]*\|PAPERLESS_SECRET_KEY=[^ ]*' ~/quadlet-old/paperless.container       # gate
PAPERLESS_DB_PASSWORD=<DBPASS value> PAPERLESS_SECRET=<SECRET_KEY value> ./paperless.sh
```

The radio's Icecast passwords are new on every setup anyway, so `radio.sh` simply makes its own.

## Checking the scripts

```bash
shellcheck scripts/podman/lib.sh scripts/podman/sgin/*.sh scripts/podman/gate/*.sh
```

`COBRA_POOL` and `COBRA_DATA` move the pool and data folders for a test run on another machine. Leave them unset on the real hosts.
