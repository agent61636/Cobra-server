# 5. Final touches (gate VM 110, public access, backups)

**Result:** `elysidrome-gate` (VM 110 on the Latitude) terminates TLS for `*.elysidrome.com`, puts Authelia 2FA in front of the admin apps, proxies to the SGIN's media apps, and is the only thing reachable from the internet (TCP 443). Nightly backups go to PBS.

🔌 No cable changes. Everything is already wired from part 2.

## 5.1 Terms

| Term | Meaning |
|---|---|
| **Reverse proxy (nginx)** | Receives every `https://<name>.elysidrome.com` request and forwards it by hostname to the right app. |
| **Wildcard cert** | One Let's Encrypt cert for `elysidrome.com` + `*.elysidrome.com`, obtained by DNS challenge (certbot writes a TXT record via the Cloudflare token), so nothing needs to be open to get it. |
| **Authelia** | Login + TOTP portal at `auth.elysidrome.com`. nginx asks it "is this user logged in?" before serving the protected apps. |
| **Gate pod** | All gate apps in one rootless Podman pod. Only nginx's 80/443 are published; the apps listen on `127.0.0.1` inside the pod. |

## 5.2 Gate VM (command-center shell, root)

```bash
qm create 110 --name elysidrome-gate --ostype l26 --cpu host --cores 2 --memory 6144 \
  --scsihw virtio-scsi-single --scsi0 local-lvm:64,discard=on,iothread=1 --net0 virtio,bridge=vmbr0 \
  --cdrom local:iso/$(ls /var/lib/vz/template/iso | grep -m1 netinst) --agent 1 \
  --onboot 1 --startup order=3
qm start 110
```

- [ ] Proxmox → 110 → **Console** → Install. Same answers as part 3.2 except:

| Screen | Value |
|---|---|
| Network | **Configure manually** (Esc out of DHCP if it already ran): IP `10.10.10.10/24`, gateway `10.10.10.1`, DNS `10.10.10.1` |
| Hostname | `elysidrome-gate` |
| Disk | the 64 GB virtual disk (`sda`) |
- [ ] `qm set 110 --ide2 none,media=cdrom`

On gate (eels):

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y qemu-guest-agent podman crun passt uidmap cockpit certbot python3-certbot-dns-cloudflare nftables systemd-container
# rootless containers may bind 80/443
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/90-ports.conf && sudo sysctl --system
sudo useradd -m -s /bin/bash podsvc && sudo loginctl enable-linger podsvc
sudo mkdir -p /srv/gate/{nginx/certs,nginx/conf.d,authelia,vaultwarden,paperless/{data,media,consume,export},postgres,redis,metube,homepage,uptime-kuma,hiscore}
sudo chown -R podsvc: /srv/gate
```

- [ ] SSH key + hardening as part 3.3 (`PermitRootLogin no`)

Firewall (the gate is the one box the internet reaches, so it gets its own):

```bash
sudo tee /etc/nftables.conf >/dev/null <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif lo accept
    ip protocol icmp accept
    tcp dport { 80, 443 } accept
    ip saddr { 10.10.10.0/24, 10.10.99.0/24 } tcp dport { 22, 9090 } accept
  }
}
EOF
sudo systemctl enable --now nftables
```

Shared storage from the SGIN (MeTube saves into the library, Paperless reads the `scans` drop folder):

```bash
sudo apt install -y cifs-utils
sudo install -m 600 /dev/null /root/smb-gate.cred
printf 'username=gate\npassword=%s\n' '<gate Samba password from part 3.6>' | sudo tee /root/smb-gate.cred >/dev/null
sudo mkdir -p /srv/storage/pool
PU=$(id -u podsvc); PG=$(id -g podsvc)
echo "//elysidrome-stream.home.arpa/media /srv/storage/pool cifs credentials=/root/smb-gate.cred,vers=3.1.1,seal,uid=$PU,gid=$PG,file_mode=0666,dir_mode=0777,_netdev,nofail,x-systemd.automount 0 0" \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/pool && ls /srv/storage/pool
```

- `file_mode=0666,dir_mode=0777`: Paperless and MeTube run as a non-root user *inside* their containers, which is some unnamed ID on the gate, so the mount lets anyone on the gate write. Only `eels` and `podsvc` log in there. This setting is local to the gate; on the SGIN the files still land as user `gate`, group `media`, mode 664, like everything else written over Samba.
- `seal`: SMB3 encryption on the wire. `x-systemd.automount`: the gate boots even if the SGIN is off, and the share mounts when first used.
- `/srv/storage/pool` is the same path as on the SGIN, so a path in one app's settings means the same folder everywhere.
- [ ] `touch /srv/storage/pool/scans/test && rm /srv/storage/pool/scans/test` works as eels

## 5.3 Wildcard cert (as eels)

Token: Cloudflare → My Profile → API Tokens → **Edit zone DNS** template, zone `elysidrome.com`. Make a separate one from part 2's DDNS token so either can be revoked alone.

```bash
sudo install -m 600 /dev/null /root/cloudflare.ini
echo 'dns_cloudflare_api_token = <gate-acme token>' | sudo tee /root/cloudflare.ini >/dev/null
sudo certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/cloudflare.ini \
  -d elysidrome.com -d '*.elysidrome.com' --agree-tos -m <your email> -n
sudo tee /etc/letsencrypt/renewal-hooks/deploy/gate.sh >/dev/null <<'EOF'
#!/bin/sh
install -o podsvc -m 600 /etc/letsencrypt/live/elysidrome.com/fullchain.pem /srv/gate/nginx/certs/
install -o podsvc -m 600 /etc/letsencrypt/live/elysidrome.com/privkey.pem /srv/gate/nginx/certs/
runuser -u podsvc -- env XDG_RUNTIME_DIR=/run/user/$(id -u podsvc) systemctl --user restart nginx 2>/dev/null || true
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/gate.sh && sudo /etc/letsencrypt/renewal-hooks/deploy/gate.sh
```

## 5.4 Gate pod (as podsvc: `sudo machinectl shell podsvc@`)

```bash
cd ~ && mkdir -p .config/containers/systemd && cd .config/containers/systemd
PGPW=$(openssl rand -hex 24); PLKEY=$(openssl rand -hex 32)          # store both
cat > gate.pod <<'EOF'
[Pod]
PodName=gate
PublishPort=80:80
PublishPort=443:443
[Install]
WantedBy=default.target
EOF
c() { cat > "$1.container"; }
c nginx <<'EOF'
[Container]
ContainerName=nginx
Image=docker.io/library/nginx:stable
Pod=gate.pod
AutoUpdate=registry
Volume=/srv/gate/nginx/conf.d:/etc/nginx/conf.d:ro,Z
Volume=/srv/gate/nginx/certs:/certs:ro,Z
[Install]
WantedBy=default.target
EOF
c authelia <<'EOF'
[Container]
ContainerName=authelia
Image=docker.io/authelia/authelia:latest
Pod=gate.pod
AutoUpdate=registry
Volume=/srv/gate/authelia:/config:Z
[Install]
WantedBy=default.target
EOF
c vaultwarden <<'EOF'
[Container]
ContainerName=vaultwarden
Image=docker.io/vaultwarden/server:latest
Pod=gate.pod
AutoUpdate=registry
Environment=ROCKET_PORT=8222 DOMAIN=https://vault.elysidrome.com SIGNUPS_ALLOWED=true
Volume=/srv/gate/vaultwarden:/data:Z
[Install]
WantedBy=default.target
EOF
c postgres <<EOF
[Container]
ContainerName=postgres
Image=docker.io/library/postgres:16
Pod=gate.pod
AutoUpdate=registry
Environment=POSTGRES_DB=paperless POSTGRES_USER=paperless POSTGRES_PASSWORD=$PGPW
Volume=/srv/gate/postgres:/var/lib/postgresql/data:Z
[Install]
WantedBy=default.target
EOF
c redis <<'EOF'
[Container]
ContainerName=redis
Image=docker.io/library/redis:7
Pod=gate.pod
AutoUpdate=registry
Volume=/srv/gate/redis:/data:Z
[Install]
WantedBy=default.target
EOF
c paperless <<EOF
[Unit]
Requires=postgres.service redis.service
After=postgres.service redis.service
[Container]
ContainerName=paperless
Image=ghcr.io/paperless-ngx/paperless-ngx:latest
Pod=gate.pod
AutoUpdate=registry
Environment=PAPERLESS_DBHOST=127.0.0.1 PAPERLESS_DBPASS=$PGPW PAPERLESS_REDIS=redis://127.0.0.1:6379 PAPERLESS_SECRET_KEY=$PLKEY PAPERLESS_URL=https://docs.elysidrome.com PAPERLESS_CONSUMER_POLLING=60
Volume=/srv/gate/paperless/data:/usr/src/paperless/data:Z
Volume=/srv/gate/paperless/media:/usr/src/paperless/media:Z
Volume=/srv/storage/pool/scans:/usr/src/paperless/consume
Volume=/srv/gate/paperless/export:/usr/src/paperless/export:Z
[Service]
Restart=on-failure
RestartSec=60
[Install]
WantedBy=default.target
EOF
c metube <<'EOF'
[Container]
ContainerName=metube
Image=ghcr.io/alexta69/metube:latest
Pod=gate.pod
AutoUpdate=registry
Environment=DOWNLOAD_DIR=/downloads STATE_DIR=/state TEMP_DIR=/state/tmp
Volume=/srv/storage/pool/youtube:/downloads
Volume=/srv/gate/metube:/state:Z
[Service]
Restart=on-failure
RestartSec=60
[Install]
WantedBy=default.target
EOF
c homepage <<'EOF'
[Container]
ContainerName=homepage
Image=ghcr.io/gethomepage/homepage:latest
Pod=gate.pod
AutoUpdate=registry
Environment=HOMEPAGE_ALLOWED_HOSTS=home.elysidrome.com
Volume=/srv/gate/homepage:/app/config:Z
[Install]
WantedBy=default.target
EOF
c uptime-kuma <<'EOF'
[Container]
ContainerName=uptime-kuma
Image=docker.io/louislam/uptime-kuma:2
Pod=gate.pod
AutoUpdate=registry
Volume=/srv/gate/uptime-kuma:/app/data:Z
[Install]
WantedBy=default.target
EOF
chmod 600 *.container
```

Where the gate's apps keep their files:

| App | Its own data (on the gate's disk, in the nightly VM backup) | Shared files (on the SGIN pool, over the CIFS mount) |
|---|---|---|
| Paperless | database, search index, the archived originals: `/srv/gate/paperless`, `/srv/gate/postgres` | **Inbox:** `scans`. Drop a PDF or photo into `\\elysidrome-stream\scans` from any machine; within a minute Paperless files it and removes it from the inbox. Polling is on because change notifications don't cross SMB. |
| MeTube | queue and history: `/srv/gate/metube` | **Finished videos:** `youtube`, so they're on the big drives and Jellyfin can show them (add `/media/youtube` as a Home Videos library) |

`Restart=on-failure`: if the gate boots while the SGIN is off, those two can't find their shared folder and fail. systemd retries every minute until the SGIN is back.

Authelia config (`/srv/gate/authelia/configuration.yml`; fill the three secrets with `openssl rand -hex 32`):

```yaml
server: { address: 'tcp://127.0.0.1:9091/' }
totp: { issuer: elysidrome.com }
identity_validation: { reset_password: { jwt_secret: 'SECRET1' } }
authentication_backend: { file: { path: /config/users.yml } }
access_control:
  default_policy: deny
  rules:
    - domain: [docs.elysidrome.com, metube.elysidrome.com, home.elysidrome.com, status.elysidrome.com]
      policy: two_factor
session:
  secret: 'SECRET2'
  cookies: [{ domain: elysidrome.com, authelia_url: 'https://auth.elysidrome.com', expiration: 8h, inactivity: 1h }]
storage: { encryption_key: 'SECRET3', local: { path: /config/db.sqlite3 } }
notifier: { filesystem: { filename: /config/notification.txt } }
```

```bash
HASH=$(podman run --rm docker.io/authelia/authelia:latest authelia crypto hash generate argon2 --password '<your password>' | awk '{print $2}')
printf 'users:\n  eels:\n    displayname: Eels\n    email: <you@email>\n    password: "%s"\n' "$HASH" > /srv/gate/authelia/users.yml
chmod 600 /srv/gate/authelia/*.yml
```

- [ ] Extra hostname: **`auth.elysidrome.com`** (Authelia portal) — add to Cloudflare CNAMEs below

nginx (`/srv/gate/nginx/conf.d/elysidrome.conf`):

```nginx
# --- shared settings (http level; every server below inherits them) ---
limit_req_zone $binary_remote_addr zone=perip:10m rate=10r/s;    # admin apps
limit_req_zone $binary_remote_addr zone=media:10m rate=50r/s;    # media apps load dozens of images per page
limit_req_status 429;
map $http_upgrade $connection_upgrade { default upgrade; '' ''; } # websockets; '' keeps upstream keepalive

ssl_certificate /certs/fullchain.pem;  ssl_certificate_key /certs/privkey.pem;
ssl_protocols TLSv1.2 TLSv1.3;  ssl_session_cache shared:SSL:10m;
add_header Strict-Transport-Security "max-age=31536000" always;
client_max_body_size 0;
proxy_http_version 1.1;
proxy_set_header Host $host;  proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;  proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header Upgrade $http_upgrade;  proxy_set_header Connection $connection_upgrade;

server { listen 80 default_server; return 301 https://$host$request_uri; }
server {   # catch-all: bare IP, unknown names, scanners -> drop the connection
  listen 443 ssl default_server; http2 on; server_name _;
  return 444;
}

# --- media apps on the SGIN: own logins, phone/TV apps, no Authelia ---
map $host $media {
  tv.elysidrome.com           http://10.10.10.20:8096;    # Jellyfin (+ ErsatzTV channels inside it)
  books.elysidrome.com        http://10.10.10.20:13378;   # Audiobookshelf
  comics.elysidrome.com       http://10.10.10.20:5000;    # Kavita
  eelsmusic.elysidrome.com    http://10.10.10.20:4533;    # Navidrome (Eels' library)
  rupaulradio.elysidrome.com  http://10.10.10.20:4533;    # Navidrome (Rachel's library)
  arcade.elysidrome.com       http://10.10.10.20:8080;    # RomM + EmulatorJS
}
server {
  listen 443 ssl; http2 on;
  server_name tv.elysidrome.com books.elysidrome.com comics.elysidrome.com
              eelsmusic.elysidrome.com rupaulradio.elysidrome.com arcade.elysidrome.com;
  location / {
    limit_req zone=media burst=300 nodelay;
    proxy_buffering off;              # stream video/audio/ROM downloads straight through, don't spool to the gate's disk
    proxy_request_buffering off;      # same for uploads (RomM, Audiobookshelf)
    proxy_read_timeout 1h;  proxy_send_timeout 1h;   # long streams and websockets
    proxy_pass $media;
  }
}

# --- Authelia portal ---
server {
  listen 443 ssl; http2 on; server_name auth.elysidrome.com;
  location / { limit_req zone=perip burst=50 nodelay; proxy_pass http://127.0.0.1:9091; }
}

# --- Vaultwarden: LAN/VPN only ---
server {
  listen 443 ssl; http2 on; server_name vault.elysidrome.com;
  allow 10.10.10.0/24; allow 10.10.99.0/24; deny all;
  location / { proxy_pass http://127.0.0.1:8222; }
}

# --- admin apps on the gate, behind Authelia 2FA ---
map $host $protected {
  docs.elysidrome.com    http://127.0.0.1:8000;    # Paperless-ngx
  metube.elysidrome.com  http://127.0.0.1:8081;    # MeTube
  home.elysidrome.com    http://127.0.0.1:3000;    # Homepage
  status.elysidrome.com  http://127.0.0.1:3001;    # Uptime Kuma
}
server {
  listen 443 ssl; http2 on;
  server_name docs.elysidrome.com metube.elysidrome.com home.elysidrome.com status.elysidrome.com;
  location /internal/authelia/authz {
    internal;
    proxy_pass http://127.0.0.1:9091/api/authz/auth-request;
    # a location's own proxy_set_header replaces ALL inherited ones, so list what Authelia needs
    proxy_set_header X-Original-Method $request_method;
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Content-Length ""; proxy_set_header Connection "";
    proxy_pass_request_body off;
  }
  location / {
    auth_request /internal/authelia/authz;
    auth_request_set $redirection_url $upstream_http_location;
    error_page 401 =302 $redirection_url;
    limit_req zone=perip burst=50 nodelay;
    proxy_read_timeout 1h;               # Uptime Kuma and MeTube keep a websocket open
    proxy_pass $protected;
  }
}
# scores.elysidrome.com -> 127.0.0.1:8090  (reserved, add when hiscore exists)
```

```bash
systemctl --user daemon-reload && systemctl --user start gate-pod && podman ps
podman exec nginx nginx -t
```

Checks before going public (from a desktop on the LAN, where Pi-hole sends every name to the gate):

- [ ] `podman exec nginx nginx -t` says `syntax is ok` and `test is successful`
- [ ] Each hostname loads with a valid padlock: `tv. books. comics. eelsmusic. rupaulradio. arcade. auth. docs. metube. home. status. vault.`
- [ ] `docs.` and `metube.` bounce you to `auth.` first, then back
- [ ] Jellyfin: play a movie, then Dashboard → Activity shows your desktop's IP (not `10.10.10.10`), so the Known proxies setting from part 3 works
- [ ] Jellyfin's phone app connects with server address `https://tv.elysidrome.com` (no port)
- [ ] Navidrome: Eels logs in at `eelsmusic.`, Rachel at `rupaulradio.`; each sees only their own library
- [ ] `https://10.10.10.10` (bare IP) gets no page at all (the 444 catch-all)

- [ ] Vaultwarden: create your account at `https://vault.elysidrome.com`, then close sign-ups: `sed -i 's/SIGNUPS_ALLOWED=true/SIGNUPS_ALLOWED=false/' ~/.config/containers/systemd/vaultwarden.container && systemctl --user daemon-reload && systemctl --user restart vaultwarden`. Import the interim password DB.
- [ ] Paperless admin: `podman exec -it paperless python3 manage.py createsuperuser`

## 5.5 Go public

- [ ] Cloudflare: CNAME → `elysidrome.com`, **DNS only**: `tv books comics eelsmusic rupaulradio arcade auth docs metube home status` (not `vault`)
- [ ] OPNsense → Firewall → NAT → Port Forward: WAN TCP 443 → `10.10.10.10:443`, filter rule auto-added. Don't forward 80: certs use the DNS challenge, and the overview promises 443 is the only public TCP port
- [ ] From cellular (Wi-Fi off): each URL loads; `docs.` demands Authelia 2FA; `vault.` returns 403

## 5.6 Backups

On command-center:

```bash
pvesm add pbs pbs-stream --server 10.10.10.20 --datastore store1 --username pve@pbs \
  --fingerprint '<fingerprint from part 3>' --password '<pve@pbs password>'
pvesh create /cluster/backup --schedule 02:00 --storage pbs-stream --all 1 --mode snapshot \
  --prune-backups keep-daily=7,keep-weekly=4,keep-monthly=6
```

On stream (eels): back up its own config and app data to PBS nightly.

```bash
sudo apt install -y proxmox-backup-client
sudo tee /root/pbs.env >/dev/null <<'EOF'
PBS_REPOSITORY=pve@pbs@127.0.0.1:store1
PBS_PASSWORD=<pve@pbs password>
PBS_FINGERPRINT=<fingerprint>
EOF
sudo chmod 600 /root/pbs.env
echo '30 3 * * * root . /root/pbs.env && export PBS_REPOSITORY PBS_PASSWORD PBS_FINGERPRINT && proxmox-backup-client backup etc.pxar:/etc stream.pxar:/srv/stream' | sudo tee /etc/cron.d/pbs-self
```

- [ ] PBS UI → Datastore store1 → Prune & GC jobs: daily; Verify job: weekly
- [ ] Test restore: Proxmox → CT 101 → Backup → restore to new VMID 901. **Before starting it**, cut its network so it doesn't steal Pi-hole #1's `10.10.10.3`: `pct set 901 --net0 name=eth0,bridge=vmbr0,ip=10.10.10.3/24,gw=10.10.10.1,link_down=1`. Start, `pct enter 901`, check `pihole status`, then stop and destroy
- [ ] Second copy of the PBS datastore (`/srv/storage/disks/<drive>/pbs`) and of anything irreplaceable: see part 4.6 (the OptiPlex drive) and add a cloud copy for photos and documents

### Backing up the library (the ~10 TB on the pool)

Until the backup drive exists, the pool has **no backup**: a dead drive loses whatever was on it. The fix is one dedicated backup drive that is never part of the pool.

**What to buy:** one 3.5" desktop drive of **18–20 TB** (NAS or enterprise class), for a bay of the second dock. 10 TB of data plus room to grow, plus a few weeks of older versions. 14 TB is the smallest that works, and it would fill within a year or two.

**How it works:** Proxmox Backup Server, already running on the SGIN, gets a second datastore called `vault` on the new drive. Every night the SGIN backs up the whole pool into it. After the first full run (expect a day or more for 10 TB over USB), each night only reads what changed. You can restore a single file from the PBS web UI, and a weekly verify job re-reads everything to catch a failing disk early. The VM backups get copied into `vault` too, so they no longer depend on a pool drive.

On stream (eels), once the drive is mounted at `/srv/storage/disks/vault` (same steps as 3.4, but **don't** create a `library` folder, so it stays out of the pool):

```bash
sudo proxmox-backup-manager datastore create vault /srv/storage/disks/vault/pbs
sudo proxmox-backup-manager acl update /datastore/vault DatastoreBackup --auth-id pve@pbs
echo '0 1 * * * root . /root/pbs.env && export PBS_PASSWORD PBS_FINGERPRINT && PBS_REPOSITORY=pve@pbs@127.0.0.1:vault proxmox-backup-client backup library.pxar:/srv/storage/pool --change-detection-mode=metadata' \
  | sudo tee /etc/cron.d/pbs-library
```

- [ ] PBS UI → Datastore **vault** → Prune: keep-daily 7, keep-weekly 4, keep-monthly 3. GC daily. Verify weekly.
- [ ] PBS UI → Datastore **vault** → Sync Jobs → Add: source **store1** (local), daily. The VM backups now exist on two drives.
- [ ] First run: start it by hand inside `tmux` (`sudo apt install -y tmux`, then paste everything after `root` from the cron line, prefixed with `sudo bash -c '...'`) so it survives closing the SSH window, and leave it overnight
- [ ] Restore test: PBS UI → vault → library → browse → download one file and open it
- ⚠️ Verify `--change-detection-mode=metadata` is in your PBS client version (`proxmox-backup-client help backup`). Without it, each night re-reads all 10 TB to find changes. It still works, just slowly.

**What this doesn't cover: fire, theft, a power surge through the hub.** The backup drive sits next to the originals. For the files you could never get back (photos, home video, documents, your own music, saves), keep a third copy outside the house: a second backup drive you swap with one kept at a relative's every month or two, or a cloud backup of just that irreplaceable part. Movies and TV you could re-rip or re-buy can live with two copies at home.

## 5.7 Monitoring

- [ ] Uptime Kuma: HTTP monitors for every hostname, TCP for `10.10.10.1:53`, `10.10.10.3:53`, `10.10.10.20:53`, `10.10.10.2:8006`, `10.10.10.20:8007`
- [ ] Homepage `services.yaml`: tiles for all apps + Proxmox, OPNsense, PBS, both Pi-holes
- [ ] Proxmox → Datacenter → Notifications: SMTP target with your email
- [ ] OPNsense → System → Firmware: check updates weekly; Proxmox/Debian: `apt full-upgrade` weekly
- [ ] Container updates, weekly, as podsvc on the gate and on the SGIN: `podman auto-update --dry-run` lists which images have a newer version; `podman auto-update` pulls them and restarts those containers (and rolls a container back if it fails to start). Read the release notes for Authelia, Paperless and RomM first; they occasionally change their config between major versions.
- [ ] Pi-hole #1 → Settings → Teleporter export → import on Pi-hole #2 after list changes
