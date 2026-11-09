# 13. Personal state (favorites, progress, settings)

**Result:** favorites, stars, playlists, watch and listen progress, bookmarks and per-user settings survive a container recreate (they already did) and a wipe of that app's data directory (they did not). One snapshot covers every person on that app. Navidrome is one database: Eels and Rachel are libraries in it, not two servers.

Part 5.6 already copies `/srv/stream` and the whole gate VM into Proxmox Backup Server. That keeps the bytes. It does not put one app back after you delete its directory and run its script. This part does.

The music wall in part 5.4 is not part of this. Nothing here edits who can sign in.

## 13.1 Recreate and wipe are different

Rerunning `jellyfin.sh` (or any other app script) does `podman rm` and `podman run` with the same mounts. The directory under `/srv/stream` or `/srv/gate` is still there, so favorites are still there.

Deleting that directory and running the script again used to start a blank server. The script now looks for a snapshot and puts the personal state back before the new container starts. `SKIP_STATE_RESTORE=1 ./jellyfin.sh` is how you start blank on purpose.

| | Container recreate, or rerunning the script | Wipe of that app's data directory |
|---|---|---|
| Jellyfin favorites, resume, users | kept in `/srv/stream/jellyfin/config` | gone, unless the snapshot is restored |
| Navidrome stars, playlists, who sees which library | kept in `/srv/stream/navidrome/navidrome.db` | gone with that file. The audio on `dock1a/music` is not in this directory |
| Audiobookshelf progress and bookmarks | kept in `/srv/stream/abs` | gone |
| Kavita progress and bookmarks | kept in `/srv/stream/kavita` | gone |
| RomM accounts, collections, saves | kept in `/srv/stream/romm` (database + `assets/`) | gone. ROM files on `dock1b/roms` are not |
| Everyone else's rows in the same database | same file | same file |

Podman secrets (RomM, Paperless, Icecast) are not in those directories. A wipe of the directory leaves the secrets. A new `podsvc` home, or `podman system reset`, deletes them. RomM and Paperless snapshots include the secret values and load them only when that secret is missing. An existing secret is never replaced.

## 13.2 Where the snapshots are

Not under `/srv/stream` or `/srv/gate`, and not under `/srv/storage/disks`. The `media` Samba share is `/srv/storage/disks`, so a snapshot there would be on `\\cobra-stream\media`. The vault is outside that share.

| Host | Snapshots | Why there |
|---|---|---|
| SGIN | `/srv/storage/vault/personal-state/<app>/` | On the Seagate, next to PBS, not in the share. Wiping `/srv/stream` does not touch it |
| Gate | `/srv/backups/personal-state/<app>/` | On the VM disk, outside `/srv/gate`. Wiping `/srv/gate/vaultwarden` does not touch it. The nightly VM backup (5.6) includes this path |

Each snapshot is a `tar.gz`, mode 600, with a `.sha256` beside it. `LATEST` names the newest. 14 are kept (`STATE_KEEP` changes that). A checksum that does not match refuses the restore. The script will not start that app empty over a snapshot it could not read.

One-time, as eels:

```bash
# SGIN. The vault must already be mounted (part 3.4 / 5.6).
sudo mkdir -p /srv/storage/vault/personal-state
sudo chown podsvc: /srv/storage/vault/personal-state

# Gate.
sudo mkdir -p /srv/backups/personal-state
sudo chown podsvc: /srv/backups /srv/backups/personal-state
```

Then as podsvc (`sudo machinectl shell podsvc@`), from the repo:

```bash
cd ~/cobra-server/scripts/podman/sgin    # gate/ on the gate
./state-backup.sh                        # snapshots whatever already has a database, and enables a daily timer
systemctl --user list-timers cobra-state-backup.timer
```

The timer is 03:10, as podsvc, with a few minutes of jitter. It is a user timer, not a root cron: the files and the podman secrets belong to podsvc. `STATE_NO_TIMER=1 ./state-backup.sh` snapshots once and does not install the timer.

Rerunning an app script also snapshots that app at the start (if its database is already there) and again after it is up. The timer is what covers the days you don't rerun the script. Anything changed after the last snapshot and before a wipe is not in the snapshot.

## 13.3 What is in a snapshot

SQLite copies use the backup API, so a running database is not copied mid-write. RomM uses `mariadb-dump --single-transaction`. Paperless uses `pg_dump`. The `notes:` line inside each tarball says the same thing as this table.

| App | Marker (missing ⇒ restore) | In the snapshot | Left out |
|---|---|---|---|
| Jellyfin | `config/data/jellyfin.db` (or `library.db` on an older server) | `config/data` (favorites, played, resume position, play count, per-user audio and subtitle choice, users, display preferences, the library rows those ids point at), `config/config` (server settings, including Known proxies), `config/root` (which folders are libraries), `config/plugins` | `config/metadata` (posters; Jellyfin fetches them again), `config/log`, the `/cache` mount |
| Navidrome | `navidrome.db` | That database. See 13.4 | `cache/` |
| Audiobookshelf | `config/absdatabase.sqlite` (or the older `audiobookshelf.sqlite`) | The database: users, which libraries they may see, `mediaProgress` (listen position, finished, ebook location), bookmarks stored on the user. `metadata/items` and `metadata/authors` (covers and edits keyed by those ids) | `metadata/cache`, logs, and Audiobookshelf's own zips in `metadata/backups`. Those zips live inside the instance directory, so a wipe deletes them too |
| Kavita | `kavita.db` | The database (reading progress, bookmarks, collections, ratings, preferences) and `appsettings.json`. The token in that file is what existing logins were signed with; the database without it still logs everyone out. Bookmark images | `covers/`, `cache/`, `logs/` |
| RomM | `db/ibdata1` | A MariaDB dump (accounts, collections, the per-user save records) and `assets/` (the save files and save states, under `assets/users/<id>/`). `config/config.yml`. The three RomM podman secrets, if they exist | `resources/` (cover art; a rescan downloads it again), `redis/`, the ROM files on `dock1b/roms` |
| ErsatzTV | any `.db` in `/srv/stream/ersatztv` | Channels, schedules, the Jellyfin API key | logs, cache. Who watched a channel is Jellyfin's database |
| Radio | `radio.liq` | That script | Icecast has no data directory. Its passwords stay podman secrets |
| cobra-breaks | any file in `/srv/stream/cobra-breaks` | `breaks.toml` and the Jellyfin API key | Watch progress is Jellyfin's. There is no podman script; restore with `state-restore.sh cobra-breaks`, then start the Quadlet |
| Vaultwarden | `db.sqlite3` | The vault: the database, `attachments/`, the RSA keys | `icon_cache/`, `tmp/` |
| Paperless | `postgres/PG_VERSION` | A `pg_dump` (users, saved views, tags, correspondents, the document index) and `paperless/data` (the search index). The Paperless podman secrets, if they exist | `paperless/media` (the originals). Copying them onto the same 64 GB VM disk can fill it. They stay in `/srv/gate/paperless/media` and in the VM backup. Redis is a queue |
| MeTube | any file under `/srv/gate/metube` except `tmp/` | Queue and download history | Finished videos on `wd2/youtube` |
| Homepage | `settings.yaml` | The dashboard yaml | — |
| Uptime Kuma | `kuma.db` | Monitors, notifications, the Kuma user | logs |
| hiscore | `hiscore.db` | The database, `raw/*.hi`, `keys.txt`, `titles.tsv` | The app code. `hiscore.sh` copies that from the repo |
| Authelia | `db.sqlite3` | `users.yml` (password hashes), `db.sqlite3` (TOTP devices), `configuration.yml` (the database is encrypted with the key in that file, so the two files stay together) | `notification.txt` (one-time codes). The files are copied as they are. This does not change access rules |
| eo-art | `eo_art.py` or `folders.json` | The script and `folders.json` | The pictures on `dock1a` |

RomM's dump is imported after MariaDB has initialised and before RomM itself starts, so RomM does not create a second empty schema on top of the dump. Paperless is the same with Postgres. If an import stops halfway, the script says so and leaves the dump in `<app>/.cobra-restore/`. Move the broken database directory aside (the message gives the `rm`) and run the app script again. The snapshot is still on the vault or in `/srv/backups`.

## 13.4 Navidrome: one database, a library per person

There is one `navidrome.db`.

| What you set in the UI | Where it lives |
|---|---|
| Star / loved, rating, play count, last played | `annotation`, one row per user and track (or album, or artist) |
| Playlists, including smart playlists | `playlist` and `playlist_tracks`. `owner_id` is the user |
| Position in a long track (Subsonic bookmark) | `bookmark` |
| Library **Eels** and library **Rachel** | `library`. The script only passes Eels (`ND_MUSICFOLDER=/media/dock1a/music/eels`). Rachel's path is a row you added under Settings → Libraries |
| Which person sees which library | `user_library`. Admins see all. Rachel's account sees Rachel |
| The songs themselves | `dock1a/music/eels` and `dock1a/music/rachel`. Not in the snapshot. A wipe of `/srv/stream/navidrome` does not delete them |

Adding the Rachel library again by hand after an empty database gives that library a new id. Stars and playlists point at the old id. Restore `navidrome.db`. Don't rebuild the libraries and expect the stars to line up.

Comedy and The Ward are Audiobookshelf libraries. Their progress is in `/srv/stream/abs`, in the same snapshot set, under the name `audiobookshelf`.

## 13.5 Restore

The usual case is: the directory is gone or empty, you run the app script, it restores, then it starts.

```bash
sudo machinectl shell podsvc@
cd ~/cobra-server/scripts/podman/sgin
rm -rf /srv/stream/navidrome          # the wipe
./navidrome.sh                        # restores from LATEST, then starts
```

Same on the gate with `gate/` and `/srv/gate/<app>`. RomM and Paperless need their database container to come up so the dump can be imported; that is part of `./romm.sh` and `./paperless.sh`, not a second command.

Restore without starting, or restore several emptied apps:

```bash
./state-restore.sh navidrome          # one app
./state-restore.sh                    # every app on this host whose marker file is missing
```

Then start the app with its own script so RomM or Paperless can import. cobra-breaks has no podman script: `./state-restore.sh cobra-breaks`, then start the Quadlet.

The marker file still exists and you want the snapshot anyway (this moves the current directory aside, it does not delete it):

```bash
FORCE_STATE_RESTORE=1 ./state-restore.sh navidrome
./navidrome.sh
```

The aside copy is named `<dir>.pre-restore-<timestamp>`. Paperless moves both `paperless/` and `postgres/`.

Start empty and keep the snapshot for later:

```bash
SKIP_STATE_RESTORE=1 ./jellyfin.sh
```

If `/srv/storage/vault` is not mounted, an emptied SGIN app refuses to start. Mount the Seagate, or pass `SKIP_STATE_RESTORE=1` if you mean to start blank. A first install with the vault mounted and no snapshot yet just starts empty.

## 13.6 What 5.6 already covered, and what is still open

Part 5.6, nightly:

- Proxmox copies the gate VM, which includes `/srv/gate` and `/srv/backups/personal-state`, into PBS.
- `proxmox-backup-client` copies `/srv/stream` (`stream.pxar`) and, separately, `dock1a`, `dock1b` and `wd1` into the vault datastore.

Use those when the SSD or the VM disk is what's gone. Use this part when one app's directory is what's gone and the snapshot disk is still there.

Still open:

- **Paperless originals** (`/srv/gate/paperless/media`) are not in the personal-state snapshot. They are on the VM disk, so the VM backup has them. A wipe of `paperless/media` alone is a PBS restore, not `./paperless.sh`.
- **nginx** certs and `songofeo.conf`, and **eo-art's pictures**, are not personal state. eo-art's `folders.json` is in the snapshot. nginx is not. Both are inside the VM backup.
- **Forms inbox** (`/srv/gate/forms`) is not in this set. It is on the VM disk.
- **Icecast passwords** are podman secrets only. A data-directory wipe does not remove them. A new `podsvc` home does. Copy them the way part 3's reinstall note already says, or accept new ones (`radio.sh` generates them when they're missing).
- **The gate cannot see `/srv/storage/vault`.** Gate snapshots sit on the gate disk. Losing that disk loses the live data and the snapshot together; the VM backup in PBS is the other copy, and pulling one app out of a VM image is the slow path 5.6 already had.
- **The Seagate holds both the SGIN snapshots and the PBS datastore.** Live data is on the SGIN's SSD until that directory is wiped. A dead Seagate loses the copies and leaves the live files. Fire, theft, and a surge through the hub are still the gap in 5.6: nothing here is an off-site copy.
- **cobra-breaks** is snapshotted by `state-backup.sh` on the SGIN, and restored only by `state-restore.sh`. Starting the Quadlet does not restore it.
- **Quadlet and these scripts still must not both own an app.** The restore hook is in the podman scripts. On a Quadlet host, run `state-restore.sh` yourself before you start the unit.

## 13.7 Notes for the next edit

- Hooks are `keep_personal_state` before the container is replaced and `snapshot_personal_state` after it is up. Both live in `scripts/podman/state.sh`, sourced from `lib.sh`.
- RomM's import runs after MariaDB is healthy and before `run_container romm`. Paperless's import runs after Postgres is ready and before `run_container paperless`.
- Don't point the snapshot root at `dock1a/backups` or anywhere under `/srv/storage/disks`. That tree is the Samba share.
- Navidrome's per-person notes stay in this part. Don't add them to the SSO writeup.
