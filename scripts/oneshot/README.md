# One-shot scripts

Each one makes a single change to a running server: it backs up every file it touches, checks the
result (`nginx -t`, `authelia validate-config`, a health check) and puts the backups back if that
check fails. Running one a second time changes nothing.

| Script | Runs on | As | What it does |
|---|---|---|---|
| `sgin-music-one.sh` | SGIN | eels | One Navidrome (`:4533`) reading `dock1a/music/eels`, a library per person; retires `navidrome-rachel` and, with comedy and sessions moving to Audiobookshelf, `navidrome-comedy` and `navidrome-sessions` (data kept). Backs up the Quadlets and every Navidrome database, asks y/N. `TALK=navidrome` keeps comedy on `:4534` and moves sessions to `:4535` instead. Walkthrough: [`docs/music.md`](../../docs/music.md) |
| `gate-music-one.sh` | gate | podsvc | `music.` and `mustang.` → the one Navidrome, `comedy.` and `sessions.` → Audiobookshelf, and the music wall (only `MUSIC_USERS`, default `eels rachel`, may open `music.`/`mustang.`). Replaces the old N.A.V. walls for those names |
| `gate-signin.sh` | gate | podsvc | One sign-in for everyone, at home too: removes the floors' home bypass (so every Bay gets your username), one-month "Remember me", adds `vip.` to the floors if it's missing. Keeps the music wall (`gate-music-one.sh`) |
| `gate-apps.sh` | gate | podsvc | The phone apps get past the sign-in on their API paths only, and each app checks its own login: Navidrome's `/rest/` (Subsonic apps), Audiobookshelf's API, `/api/` on Kavita, RomM and Paperless. No Remote-User is passed on those paths, and paths with `..` are refused. Also passes the signed-in person's Remote-Name and Remote-Groups next to Remote-User (eo-art's `/whoami`) |
| `gate-sso-check.sh` | gate | podsvc | **Read-only.** Says which of the scripts above are on the live gate, runs `authelia validate-config` and `nginx -t`, and checks the sign-in, the phone apps' `/rest/` paths (and that a forged Remote-User is dropped) and Jellyfin on `tv.`. Walkthrough: `docs/gate-sso-tv-runbook.md` |
| `gate-eo-art.sh` | gate | eels | Installs a new `eo_art.py` (from Project-Eo `home/eo-art/`, put it next to this script) and `eo-art-folders.json` as `/srv/gate/eo-art/folders.json` (kept if one exists), and mounts dock1a read-only for the Comedy Bay's covers |

Getting one onto the gate, from the-box's PowerShell:

```powershell
scp .\gate-signin.sh eels@10.6.9.10:/tmp/
```

On the gate as eels, a script that runs as podsvc:

```bash
sudo install -o podsvc -m 755 /tmp/gate-signin.sh /home/podsvc/
```

```bash
sudo machinectl shell podsvc@ /bin/bash /home/podsvc/gate-signin.sh
```

Every script prints its backups' names (`*.bak-YYYYmmdd-HHMMSS`); copying one back over the file and
restarting the app undoes the change.
