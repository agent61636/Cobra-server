# 7. Hiscore board: cabinet sync + scores.songofeo.com

**Result:** whenever a game on the cabinet saves a new high-score file, it's uploaded within seconds to `scores.songofeo.com`. There, every version is kept, and an arcade-style board lists every game **newest score first**. No game gets special treatment: anything that writes a `.hi` file shows up.

**Needs:** parts 1–5 done (the gate pod, nginx, Authelia, the wildcard certificate), and the cabinet from part 4 with hiscores turned on (4.4).

The code lives in this repository: `apps/hiscore/` (the server), `apps/hiscore-agent/` (the cabinet agent) and `apps/hiscore-launchbox/` (the LaunchBox plugin). All are tested; see their READMEs.

## How it fits together

```
cabinet (Windows, user arcade)                 gate VM, gate pod
RetroArch quits → writes galaga.hi
   │
   ├─► LaunchBox plugin (the moment the game closes)
   │     PUT /upload/fbneo/galaga.hi        ──┐
   │     PUT /upload/fbneo/galaga.hi/meta   ──┤  title "Galaga", platform, hi2txt's score table
   │                                          │
   └─► hiscore agent (every 15 s, retries)    │
         PUT /upload/fbneo/galaga.hi        ──┴─► nginx ──► hiscore (127.0.0.1:8090)
              API key, no 2FA on /upload/ only                ├─ raw/fbneo/galaga.hi/<time>-<hash>.hi
                                                              ├─ hiscore.db (index, titles, score tables)
                                                              ├─ the board (behind Authelia)
                                                              └─ /screen and /public/ (no login, scores only)
```

- **"Last updated"** is when the server received a changed file. An upload with the same bytes as the last one is ignored, so quitting a game without a new score doesn't bump it.
- **Every version is kept,** byte for byte, and can be downloaded from the board. That's your backup against a lost cabinet disk.
- **Both cabinet pieces upload, and that's fine.** The plugin is quick and knows the game's title; the agent catches games started outside LaunchBox and retries while the network is down. The server ignores a file it already has.
- **What a card shows:** the game (its title from LaunchBox, or its ROM name until the plugin has sent one), the system (the RetroArch core folder, e.g. `fbneo`), when it changed, how many versions there are, and a download link. A **NEW** badge marks anything updated in the last 24 hours.
- **Readable score tables** (rank, initials, score) appear on a card only when something can read the file: hi2txt on the cabinet through the plugin (7.6), or a decoder on the server (7.8). A `.hi` file is a copy of the game's memory, not text, so reading it needs a per-game definition. That's optional and generic: whatever games a decoder knows get tables, and everything else still lists by last updated.

## 7.1 Put the app on the gate (desktop, then gate as eels)

On the desktop: the repository ZIP from part 6.2 (or GitHub → `cobra-server` → **Code → Download ZIP** again for the newest version), unzipped, then in PowerShell next to it:

```powershell
scp -r .\cobra-server-*\apps\hiscore\hiscore eels@10.6.9.10:/tmp/
```

On the gate (eels):

```bash
sudo mkdir -p /srv/gate/hiscore-app /srv/gate/hiscore
sudo rm -rf /srv/gate/hiscore-app/hiscore && sudo cp -r /tmp/hiscore /srv/gate/hiscore-app/
sudo chown -R podsvc: /srv/gate/hiscore-app /srv/gate/hiscore
```

Updating later is the same three commands with a newer ZIP, then `systemctl --user restart hiscore` as podsvc.

## 7.2 The API key for the cabinet (gate, as podsvc: `sudo machinectl shell podsvc@`)

```bash
cd /srv/gate/hiscore-app && podman run --rm -v "$PWD":/app:ro,Z -w /app docker.io/library/python:3.13-slim python -m hiscore hash-key cabinet
```

It prints two lines. Store the **API key** in your password manager; the cabinet needs it in 7.5. Put the **keys.txt line** into the server's key file:

```bash
echo 'cabinet <the long hash it printed>' > /srv/gate/hiscore/keys.txt && chmod 600 /srv/gate/hiscore/keys.txt
```

The server keeps only the key's hash. To replace a key, make a new one and swap the line.

## 7.3 The container (gate, as podsvc)

Using the Podman scripts instead of Quadlets? Run `gate/hiscore.sh` from [`scripts/podman`](../../scripts/podman/README.md) and skip the file below.

```bash
cd ~/.config/containers/systemd
cat > hiscore.container <<'EOF'
[Container]
ContainerName=hiscore
Image=docker.io/library/python:3.13-slim
Pod=gate.pod
AutoUpdate=registry
Environment=HISCORE_DATA=/data HISCORE_BIND=127.0.0.1:8090 PYTHONDONTWRITEBYTECODE=1
Environment=HISCORE_PUBLIC=1
Volume=/srv/gate/hiscore-app:/app:ro,Z
Volume=/srv/gate/hiscore:/data:Z
WorkingDir=/app
Exec=python -m hiscore
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload && systemctl --user start hiscore
podman exec hiscore python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8090/healthz').read())"   # b'{"ok": true}'
```

No image to build: the app uses only Python's standard library, so the stock Python image runs it straight from `/srv/gate/hiscore-app`.

`HISCORE_PUBLIC=1` lets anyone read the score tables (game titles, initials and scores, nothing else) so the arcade screen on `songofeo.com/arcade` works without a login (7.7). Leave that line out to keep every score behind the login; the screen then shows demo scores to visitors and the real ones only to people signed in.

## 7.4 nginx, Authelia and DNS

**nginx:** add this to `/srv/gate/nginx/conf.d/songofeo.conf`, replacing the `# scores.songofeo.com ... (reserved ...)` comment line at the end:

```nginx
# --- hiscore board: people log in through Authelia; the cabinet agent uploads with its API key ---
server {
  listen 443 ssl; http2 on; server_name scores.songofeo.com;
  location /internal/authelia/authz {
    internal;
    proxy_pass http://127.0.0.1:9091/api/authz/auth-request;
    proxy_set_header X-Original-Method $request_method;
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Content-Length ""; proxy_set_header Connection "";
    proxy_pass_request_body off;
  }
  location /upload/ {                 # the agent only; nothing else is reachable without a login
    limit_except PUT { deny all; }
    client_max_body_size 256k;
    limit_req zone=perip burst=50 nodelay;
    proxy_pass http://127.0.0.1:8090;
  }
  location /public/ {                 # score tables for the arcade screen; only answers when HISCORE_PUBLIC=1
    limit_except GET { deny all; }
    limit_req zone=perip burst=50 nodelay;
    proxy_pass http://127.0.0.1:8090;
  }
  location = /screen {                # the big arcade screen page (no data in it; it reads /public/)
    limit_except GET { deny all; }
    limit_req zone=perip burst=50 nodelay;
    proxy_pass http://127.0.0.1:8090;
  }
  location / {
    auth_request /internal/authelia/authz;
    auth_request_set $redirection_url $upstream_http_location;
    error_page 401 =302 $redirection_url;
    limit_req zone=perip burst=50 nodelay;
    proxy_pass http://127.0.0.1:8090;
  }
}
```

**Authelia:** in `/srv/gate/authelia/configuration.yml`, add a rule under `access_control.rules`, so viewers need a password but not a TOTP code:

```yaml
    - domain: [scores.songofeo.com]
      policy: one_factor
```

Friends who should see the board each get an entry in `/srv/gate/authelia/users.yml` (same hash command as part 5.4).

```bash
podman exec nginx nginx -t && systemctl --user restart nginx authelia
```

**DNS:** Porkbun → `songofeo.com` → add a **CNAME** `scores` → `gate.songofeo.com`. The Pi-holes already answer `scores.songofeo.com` on the LAN.

- [ ] `https://scores.songofeo.com` from a desktop asks for an Authelia login, then shows the empty board ("No scores yet")
- [ ] `curl -X PUT -H "Authorization: Bearer wrong" --data-binary x https://scores.songofeo.com/upload/test/x.hi` answers `401`
- [ ] `https://scores.songofeo.com/screen` opens without a login (demo scores until the first game is played)

## 7.5 The agent on the cabinet (as arcade, plain non-admin PowerShell)

Copy `apps\hiscore-agent\` from the ZIP to the cabinet (a USB stick, or `\\cobra-stream\media\wd2\backups`), open PowerShell in that folder, then:

```powershell
.\install.ps1          # asks for the API key from 7.2, then starts the agent at every logon
notepad C:\Cobra\hiscore-agent\config.json
```

In `config.json`, check the two folder paths point at your RetroArch install (the `saves` and `system` folders; part 4.4 found where your cores write `.hi` files). Add more folders the same way, e.g. a standalone MAME's `hi` folder with `"system": "mame"`. After any change, restart it: `Stop-ScheduledTask 'Cobra hiscore agent'; Start-ScheduledTask 'Cobra hiscore agent'`.

- [ ] Play a game, set a score, quit to Big Box. Within about 30 seconds `C:\Cobra\hiscore-agent\agent.log` shows `uploaded fbneo/<game>.hi (201)`, and the game is at the top of the board with **NEW**.
- [ ] Unplug the cabinet's network cable, set another score, plug it back in: the log shows `will retry …`, then `uploaded …` once the network is back.

## 7.6 The LaunchBox plugin (as arcade)

The plugin uploads a game's `.hi` file the moment the game closes, and adds what only LaunchBox knows: the game's proper title and platform. With hi2txt installed on the cabinet it also sends the readable score table. It reads the server, folders and API key from the agent (7.5), so set that up first.

Build and install it as `apps/hiscore-launchbox/README.md` says: `dotnet build` against your LaunchBox folder, then copy `CobraHiscore.dll` and `config.json` into `LaunchBox\Plugins\CobraHiscore\`.

**Score tables with hi2txt:** hi2txt (by GreatStone) is freeware for Windows with per-game definitions for many MAME and FinalBurn Neo games. ⚠️ It isn't open source: read its license, download it yourself to `C:\Cobra\hi2txt\`, and test a few of your games by hand (the plugin README has the command), because RetroArch cores and standalone MAME can store some games differently. Then set `"hi2txt"` and each core's `hiscore.dat` in the plugin's `config.json`.

- [ ] Play a game from Big Box, set a score, quit. `Plugins\CobraHiscore\plugin.log` shows `uploaded fbneo/<game>.hi` and `sent details`, and the board shows the game's real title.
- [ ] With hi2txt set up: the card shows rank, initials and score.

## 7.7 The arcade screen on songofeo.com

`https://scores.songofeo.com/screen` is the big screen above the arcade: attract mode that cycles through each game's top scores, newest first, with a ticker of the latest. The server lets `songofeo.com` show it in a frame and nothing else. The arcade page embeds it like this:

```html
<iframe src="https://scores.songofeo.com/screen?embed=1" title="High scores" loading="lazy"
        style="width:100%;aspect-ratio:16/9;border:0"></iframe>
```

Options: `?embed=1` (no page background), `?seconds=8` (time per game), `?game=galaga` (one game only), `?demo=1` (made-up station games, for trying layouts). Pages that would rather draw their own screen can read `https://scores.songofeo.com/public/v1/board` directly; `songofeo.com` is allowed to:

```json
[{"game": "galaga", "title": "Galaga", "system": "fbneo", "platform": "Arcade",
  "updated_at": "2026-10-14T06:07:51+00:00",
  "scores": [{"rank": "1", "score": "52310", "name": "EEL"}]}]
```

Newest first, up to 100 games (`?limit=` up to 500), at most 10 scores each. `scores` is empty for a game nobody can read yet. Other sites are added with `HISCORE_ORIGINS` in `hiscore.container` (space-separated).

## 7.8 Optional: a decoder on the server

The server runs a decoder command for each new version if `HISCORE_DECODER` is set. The command gets the file path, the game name and the system. It must print JSON: a list of rows like `{"rank": 1, "score": "52310", "name": "EEL"}`. Rows show on the card; if the decoder fails or doesn't know the game, the card simply shows "Score table saved".

Most setups don't need this: hi2txt is a Windows program, so it runs best on the cabinet through the plugin (7.6). A server decoder is for a tool that runs on Linux. When both send a table for the same version, the server's wins. Add `HISCORE_DECODER=/app/decode.sh` (or similar) to `hiscore.container`.

**Proper game titles** instead of ROM names: put a `titles.tsv` in `/srv/gate/hiscore/` with one `romname<TAB>Title` line per game (MAME's game list can produce it), then restart hiscore.

## 7.9 Backups and monitoring

- `/srv/gate/hiscore` is inside VM 110, so the nightly Proxmox backup (part 5.6) covers every version of every file. The cabinet's own `.hi` files are also in its nightly copy (part 4.5).
- Uptime Kuma: an HTTP monitor for `http://127.0.0.1:8090/healthz`. It runs in the same pod, so it skips the login.
- Homepage: add a tile to `services.yaml` under "Read & play": `- High scores: { href: "https://scores.songofeo.com", icon: mdi-trophy, siteMonitor: "http://127.0.0.1:8090/healthz" }`

## Later: scores from the browser arcade

Browser games (RomM + EmulatorJS) write their `.hi` files inside each player's browser, and RomM syncs saves and states but doesn't mention hiscore files. Getting those onto the board needs either a small script on RomM's player page that posts the file to `/upload/` when a game closes, or upstream support in RomM/EmulatorJS. The server side is ready for it: a browser upload is just another `PUT`, with its own key.

## Sources

- FinalBurn Neo core docs (hiscore option, `hiscore.dat` location): https://docs.libretro.com/library/fbneo/
- LaunchBox "MAME Hi-Score Display" plugin (credits hi2txt): https://forums.launchbox-app.com/files/file/2173-mame-hi-score-display-a-plugin-for-bigbox/
- RomM EmulatorJS player docs (saves, states, netplay): https://docs.romm.app/4.7.0/Platforms-and-Players/EmulatorJS-Player/
