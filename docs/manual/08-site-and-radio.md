# 8. Landing site and radio

**Result:** `https://radio.songofeo.com` is an always-on station shuffled from your music library.

> **The public homepage lives on Porkbun's static hosting** at the bare `songofeo.com`: see the SongofEo project's `site/README.md`. Its Cinema, Radio and Arcade buttons send people to `tv.`, `music.` and `arcade.songofeo.com`. The radio asks for an Authelia login (8.3); Jellyfin and RomM use their own logins. 8.1 below is optional: use it only for a buttons page served from home on another hostname (for example `home.songofeo.com`), never on the bare domain. If you do, change `server_name songofeo.com` below to that hostname and add its CNAME to `gate.songofeo.com`.
> **The public homepage lives on Porkbun's static hosting** at the bare `songofeo.com`: the station from the Project-Eo repository. Its **Sign in** button goes to `auth.songofeo.com`, and its floors send people to `tv.`, `music.` (Navidrome), `books.`, `comics.`, `arcade.`, `gaming.` and `sessions.songofeo.com`, all behind the one sign-in from part 5.4. 8.1 below is optional: use it only for a buttons page served from home on another hostname (for example `links.songofeo.com`; `home.` is the Homepage dashboard), never on the bare domain. If you do, change `server_name songofeo.com` below to that hostname and add its CNAME to `gate.songofeo.com`.

**Needs:** parts 3 and 5.

## 8.1 Landing site (gate)

The page is `apps/site/index.html` in this repository: one static file, light and dark mode, with no scripts and nothing loaded from other sites. Edit the names and buttons to taste; each button is one `<a class="tile">` line.

From the desktop (repository ZIP, part 6.2):

```powershell
scp .\cobra-server-*\apps\site\index.html eels@10.6.9.10:/tmp/
```

On the gate (eels):

```bash
sudo mkdir -p /srv/gate/site && sudo cp /tmp/index.html /srv/gate/site/ && sudo chown -R podsvc: /srv/gate/site
```

As podsvc, give nginx the folder, and add the site to `/srv/gate/nginx/conf.d/songofeo.conf`:

```bash
sed -i 's#^Volume=/srv/gate/nginx/certs:/certs:ro,Z#&\nVolume=/srv/gate/site:/site:ro,Z#' ~/.config/containers/systemd/nginx.container
grep Volume ~/.config/containers/systemd/nginx.container      # three lines: conf.d, certs, site
```

```nginx
# --- landing page: public, static ---
server {
  listen 443 ssl; http2 on; server_name songofeo.com;
  root /site; index index.html;
  location / { limit_req zone=media burst=100 nodelay; try_files $uri $uri/ =404; }
}
```

```bash
systemctl --user daemon-reload && systemctl --user restart nginx && podman exec nginx nginx -t
```

- [ ] The buttons page loads on the hostname you chose, from home and from a phone on cellular.

## 8.2 Radio (cobra-stream)

Two containers join the `stream` pod. **Liquidsoap** is the DJ: it shuffles the music folder with short crossfades. **Icecast** is the transmitter that listeners connect to. The script is `apps/radio/radio.liq`.

**Before you open it to the public:** streaming music you don't hold the rights to, to anyone on the internet, needs public-performance licences. That's true even for a small station. So this setup puts the radio **behind a login** (Authelia, password only) for you and the people you add. Make it fully public (8.4) only with music you have the rights to stream: your own, Creative Commons, or royalty-free.

On the desktop:

```powershell
scp .\cobra-server-*\apps\radio\radio.liq eels@10.6.9.20:/tmp/
```

On cobra-stream (eels):

```bash
sudo mkdir -p /srv/stream/radio && sudo cp /tmp/radio.liq /srv/stream/radio/ && sudo chown -R podsvc: /srv/stream/radio
# let the gate reach Icecast: add 8000 to the LAN/VPN port list in /etc/nftables.conf (part 3.7)
sudo sed -i 's/tcp dport { 22, 53, 80, 443, 445,/tcp dport { 22, 53, 80, 443, 445, 8000,/' /etc/nftables.conf && sudo systemctl reload nftables
```

As podsvc (or, with the Podman scripts, just `sgin/radio.sh` from [`scripts/podman`](../../scripts/podman/README.md)):

```bash
cd ~/.config/containers/systemd
SRCPW=$(openssl rand -hex 16); ADMPW=$(openssl rand -hex 16); echo "Icecast admin password: $ADMPW"   # store it
sed -i 's/^PublishPort=8080:8080$/&\nPublishPort=8000:8000/' stream.pod
c() { cat > "$1.container"; }
c icecast <<EOF
[Container]
ContainerName=icecast
Image=docker.io/libretime/icecast:latest
Pod=stream.pod
AutoUpdate=registry
Environment=ICECAST_SOURCE_PASSWORD=$SRCPW ICECAST_ADMIN_PASSWORD=$ADMPW ICECAST_RELAY_PASSWORD=$(openssl rand -hex 16) ICECAST_HOSTNAME=radio.songofeo.com ICECAST_MAX_CLIENTS=50
[Install]
WantedBy=default.target
EOF
c radio <<EOF
[Unit]
After=icecast.service
Requires=icecast.service
[Container]
ContainerName=radio
Image=docker.io/savonet/liquidsoap:v2.4.x-latest
Pod=stream.pod
AutoUpdate=registry
Environment=ICECAST_SOURCE_PASSWORD=$SRCPW RADIO_MUSIC=/media/music RADIO_NAME="Song of Eo Radio"
Volume=/srv/stream/radio:/radio:ro,Z
Volume=/srv/storage/pool/music:/media/music:ro
Exec=/radio/radio.liq
[Service]
Restart=on-failure
RestartSec=10
[Install]
WantedBy=default.target
EOF
chmod 600 icecast.container radio.container
systemctl --user daemon-reload && systemctl --user restart stream-pod
journalctl --user -u radio -n 30
```

- The log should show Liquidsoap connecting to Icecast and starting a track. If it says it can't run `/radio/radio.liq` as a command, the image wants the program name too: change the line to `Exec=liquidsoap /radio/radio.liq`, then `daemon-reload` and restart radio.
- `RADIO_MUSIC=/media/music` plays both music libraries. For a separate station playlist, make a folder (say `\\cobra-stream\media\radio`), copy or move the songs there, and change both the `Volume=` source and `RADIO_MUSIC`.
- [ ] LAN check: `http://10.6.9.20:8000/stream` plays in VLC or a browser

## 8.3 Radio through the gate

Add this to `/srv/gate/nginx/conf.d/songofeo.conf`:

```nginx
# --- radio: listeners log in through Authelia (see 8.2 about licences); Icecast's admin pages are LAN/VPN-only ---
server {
  listen 443 ssl; http2 on; server_name radio.songofeo.com;
  location /internal/authelia/authz {
    internal;
    proxy_pass http://127.0.0.1:9091/api/authz/auth-request;
    proxy_set_header X-Original-Method $request_method;
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Content-Length ""; proxy_set_header Connection "";
    proxy_pass_request_body off;
  }
  location /admin {
    allow 10.6.9.0/24; allow 10.6.99.0/24; deny all;
    proxy_pass http://10.6.9.20:8000;
  }
  location / {
    auth_request /internal/authelia/authz;
    auth_request_set $redirection_url $upstream_http_location;
    error_page 401 =302 $redirection_url;
    proxy_buffering off;               # audio flows straight through
    proxy_read_timeout 24h;            # a listener can stay tuned in all day
    proxy_pass http://10.6.9.20:8000;
  }
}
```

Authelia (`configuration.yml` → `access_control.rules`):

```yaml
    - domain: [radio.songofeo.com]
      policy: one_factor
```

```bash
podman exec nginx nginx -t && systemctl --user restart nginx authelia
```

Porkbun: add a **CNAME** `radio` → `gate.songofeo.com`. (The wildcard certificate from part 5 already covers it.) `music.` is Navidrome, the station's Music floor (part 5.4).

- [ ] `https://radio.songofeo.com/stream` asks for a login once, then plays in the browser
- [ ] `https://radio.songofeo.com/admin/` from a phone on cellular (VPN off) is refused

## 8.4 Making the radio public (only with music you have the rights to stream)

Delete the `/internal/authelia/authz` location and the three `auth_request…`/`error_page` lines from the radio block, and remove the Authelia rule. Then any player (VLC, a phone radio app, a smart speaker) can open `https://radio.songofeo.com/stream` directly. Before you do: Icecast's 50-listener cap and your Xfinity upload speed are the limits, and each listener at 192 kb/s uses about 0.2 Mb/s of upload.

## Done when

- [ ] `songofeo.com` loads publicly
- [ ] The radio plays, from home and away, after one login
- [ ] Uptime Kuma: HTTP monitors for `https://songofeo.com` and `http://10.6.9.20:8000/status-json.xsl`
