# One-shot scripts

Each one makes a single change to a running server: it backs up every file it touches, checks the
result (`nginx -t`, `authelia validate-config`, a health check) and puts the backups back if that
check fails. Running one a second time changes nothing.

| Script | Runs on | As | What it does |
|---|---|---|---|
| `sgin-navidromes.sh` | SGIN | eels | The four Navidromes (music :4533, comedy :4534, mustang :4535, sessions :4536): folders, firewall, Quadlets, restart of the stream pod |
| `gate-navidromes.sh` | gate | podsvc | Points the gate's nginx and Authelia at those four Navidromes |
| `gate-signin.sh` | gate | podsvc | One sign-in for everyone, at home too: removes the floors' home bypass (so every Bay gets your username), one-month "Remember me", adds `vip.` to the floors if it's missing. Keeps the N.A.V. walls (`scripts/nav/gate-nav.sh`) |
| `gate-apps.sh` | gate | podsvc | The phone apps get past the sign-in on their API paths only, and each app checks its own login: every Navidrome's `/rest/` (Subsonic apps), Audiobookshelf's API, `/api/` on Kavita, RomM and Paperless. No Remote-User is passed on those paths, and paths with `..` are refused. Also passes the signed-in person's Remote-Name and Remote-Groups next to Remote-User (eo-art's `/whoami`) |
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
