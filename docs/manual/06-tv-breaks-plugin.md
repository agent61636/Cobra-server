# 6. Breaks between episodes: cobra-breaks

**Result:** every show you choose gets a **"&lt;Show&gt; — with breaks"** playlist in Jellyfin, for each person who watches it. Pick it on the Roku or Apple TV app and it plays one episode, then a random video from your filler folder, then the next episode, and so on. Movies keep their pre-roll from **Local Intros**, and Live TV channels get breaks from ErsatzTV (part 3.8a).

**Needs:** part 3 (Jellyfin with the `Filler` library from 3.8a) and some short videos in `\\cobra-stream\media\wd1\filler`.

## Why playlists, not an intro plugin

Jellyfin has a hook that lets a plugin play videos before an item. Local Intros uses it for movies. **But Jellyfin's apps only ask for intros before movies, never before episodes.** The plugins that work around this (Projectionist, for example) inject a script into the Jellyfin *web page*, so they only work in a browser and Jellyfin Media Player. The **Roku and Apple TV apps don't load that page**, so nothing a plugin does can put a break between episodes there.

A playlist is a list of items stored on the server, and every Jellyfin app can play one. cobra-breaks builds those lists for you and keeps them current.

| Where you watch | Movies | Episodes on demand | Live TV |
|---|---|---|---|
| Roku, Apple TV, phones, browser | Local Intros pre-roll | **"… with breaks" playlist** | ErsatzTV filler |

## How it behaves

- **Follows your progress.** Each playlist starts at that person's **next unwatched** episode and reaches 40 episodes ahead (configurable). Watch from the playlist and Jellyfin marks the episodes watched; the 4 am rebuild then moves the playlist forward and picks new filler.
- **Every break is a different video.** Jellyfin silently drops repeated items from a playlist, so one playlist can't use the same filler twice. With 40 episodes and 1 break per gap you need **at least 39 filler videos of 3 minutes or less**. With fewer, cobra-breaks shortens the playlist so no break goes missing, and says so in its log. It also avoids filler used in the last 3 rebuilds when it can.
- **The playlist keeps its identity.** It's updated in place, so a pinned shortcut or "Continue watching" on the TV keeps working.
- **Per-show options:** 2 breaks per gap, a break before the first episode, or filler from one subfolder only (e.g. `filler/90s` for 90s shows).

## 6.1 Filler videos

- [ ] Put short videos in `\\cobra-stream\media\wd1\filler` (subfolders are fine): old commercials, bumpers, station IDs, trailers. Aim for 50+ to start.
- [ ] Jellyfin → Dashboard → Libraries → `Filler` → **Scan**. They show up in Jellyfin as Home Videos. ErsatzTV uses the same folder for Live TV breaks.
- [ ] Jellyfin → Dashboard → Users → each person in a `[[show]]` → **Access**: tick the `Filler` library. A user who can't see a video can't have it in their playlist. To keep it off their home screen: their Settings → Home → untick `Filler` under the libraries shown.

## 6.2 Install (cobra-stream)

On the desktop: GitHub → `cobra-server` → **Code → Download ZIP**, unzip it, open PowerShell in the folder that holds the unzipped `cobra-server-…` folder, and copy the app over:

```powershell
scp -r .\cobra-server-*\apps\cobra-breaks\cobra_breaks .\cobra-server-*\apps\cobra-breaks\breaks.example.toml eels@10.6.9.20:/tmp/
```

On cobra-stream (eels):

```bash
sudo mkdir -p /srv/stream/cobra-breaks-app /srv/stream/cobra-breaks
sudo rm -rf /srv/stream/cobra-breaks-app/cobra_breaks && sudo cp -r /tmp/cobra_breaks /srv/stream/cobra-breaks-app/
sudo cp -n /tmp/breaks.example.toml /srv/stream/cobra-breaks/breaks.toml
sudo chown -R podsvc: /srv/stream/cobra-breaks-app /srv/stream/cobra-breaks
```

- [ ] Jellyfin → Dashboard → **API Keys** → **+** → app name `cobra-breaks` → copy the key
- [ ] Save it: `echo '<the key>' | sudo tee /srv/stream/cobra-breaks/api_key >/dev/null && sudo chown podsvc: /srv/stream/cobra-breaks/api_key && sudo chmod 600 /srv/stream/cobra-breaks/api_key`
- [ ] Edit `/srv/stream/cobra-breaks/breaks.toml` (`sudo nano`): one `[[show]]` block per show, with its exact Jellyfin title and the Jellyfin user names who watch it

As podsvc (`sudo machinectl shell podsvc@`):

```bash
cd ~/.config/containers/systemd
cat > cobra-breaks.container <<'EOF'
[Container]
ContainerName=cobra-breaks
Image=docker.io/library/python:3.13-slim
Pod=stream.pod
AutoUpdate=registry
Environment=PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
Volume=/srv/stream/cobra-breaks-app:/app:ro,Z
Volume=/srv/stream/cobra-breaks:/config:Z
Volume=/etc/localtime:/etc/localtime:ro
WorkingDir=/app
Exec=python -m cobra_breaks serve --config /config/breaks.toml
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload && systemctl --user start cobra-breaks
journalctl --user -u cobra-breaks -n 20
```

The log should show one line per show and user, such as `created 'The Simpsons — with breaks' for eels: 40 episodes, 39 breaks`. After that it rebuilds every day at `run_at` (default 4:00, the SGIN's local time).

**Rebuild now** (after changing `breaks.toml` or adding filler):

```bash
podman exec cobra-breaks python -m cobra_breaks run --config /config/breaks.toml
```

## 6.3 Check it on the TVs

- [ ] **Roku** (Jellyfin app): Playlists → "The Simpsons — with breaks" → play. When an episode ends, a filler video plays, then the next episode.
- [ ] **Apple TV**: the same, in the Jellyfin app you use there (Swiftfin, Infuse or another). ⚠️ Check that it plays a playlist straight through; some tvOS players stop after each item or only play playlists from certain screens. If yours doesn't, try another tvOS Jellyfin client for these playlists, or use an ErsatzTV channel for that show (part 3.8a).
- [ ] Watch a couple of episodes from the playlist, then run the rebuild command: the playlist now starts at the next unwatched episode.

## Troubleshooting

| Log says | Fix |
|---|---|
| `no such Jellyfin user` | `users` must match Jellyfin user names (any capitalization) |
| `no series named ...` | Use the show's exact title as Jellyfin shows it, and make sure that user can see the library |
| `no library named 'Filler'` | Create it (part 3.8a), or set `filler_library` to its name |
| `only N filler videos fit the rules; playlist shortened` | Add filler, raise `max_filler_minutes`, or lower `episodes_per_playlist` |
| `0 breaks` or `no filler found` for one user only | That user has no access to the `Filler` library (6.1) |
| `HTTP 401` | The API key in `/srv/stream/cobra-breaks/api_key` is wrong or was deleted in Jellyfin |

## Sources

- Jellyfin forum, "Pre-roll plugin movies only": https://forum.jellyfin.org/t-pre-roll-plugin-movies-only
- Projectionist plugin (episode prerolls via the web client only): https://github.com/ZL154/jellyfin-projectionist
- Jellyfin source, playlist rules (duplicates dropped; who may update a playlist): `Emby.Server.Implementations/Playlists/PlaylistManager.cs` and `Jellyfin.Api/Controllers/PlaylistsController.cs` in github.com/jellyfin/jellyfin
