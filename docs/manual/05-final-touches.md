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
sudo mkdir -p /srv/storage/media1
PU=$(id -u podsvc); PG=$(id -g podsvc)
echo "//elysidrome-stream.home.arpa/media /srv/storage/media1 cifs credentials=/root/smb-gate.cred,vers=3.1.1,seal,uid=$PU,gid=$PG,file_mode=0664,dir_mode=0775,_netdev,nofail,x-systemd.automount 0 0" \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/media1 && ls /srv/storage/media1
```

- `uid`/`gid=podsvc`: inside the rootless containers that user is "root", so MeTube and Paperless can write. On the SGIN the files still land as user `gate`, group `media`.
- `seal`: SMB3 encryption on the wire. `x-systemd.automount`: the gate boots even if the SGIN is off, and the share mounts when first used.
- `/srv/storage/media1` is the same path as on the SGIN, so a path in one app's settings means the same folder everywhere.
- [ ] `touch /srv/storage/media1/scans/test && rm /srv/storage/media1/scans/test` works as eels

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
Image=docker.io/library/nginx:stable
Pod=gate.pod
Volume=/srv/gate/nginx/conf.d:/etc/nginx/conf.d:ro,Z
Volume=/srv/gate/nginx/certs:/certs:ro,Z
[Install]
WantedBy=default.target
EOF
c authelia <<'EOF'
[Container]
Image=docker.io/authelia/authelia:latest
Pod=gate.pod
Volume=/srv/gate/authelia:/config:Z
[Install]
WantedBy=default.target
EOF
c vaultwarden <<'EOF'
[Container]
Image=docker.io/vaultwarden/server:latest
Pod=gate.pod
Environment=ROCKET_PORT=8222 DOMAIN=https://vault.elysidrome.com SIGNUPS_ALLOWED=true
Volume=/srv/gate/vaultwarden:/data:Z
[Install]
WantedBy=default.target
EOF
c postgres <<EOF
[Container]
Image=docker.io/library/postgres:16
Pod=gate.pod
Environment=POSTGRES_DB=paperless POSTGRES_USER=paperless POSTGRES_PASSWORD=$PGPW
Volume=/srv/gate/postgres:/var/lib/postgresql/data:Z
[Install]
WantedBy=default.target
EOF
c redis <<'EOF'
[Container]
Image=docker.io/library/redis:7
Pod=gate.pod
Volume=/srv/gate/redis:/data:Z
[Install]
WantedBy=default.target
EOF
c paperless <<EOF
[Unit]
Requires=postgres.service redis.service
After=postgres.service redis.service
[Container]
Image=ghcr.io/paperless-ngx/paperless-ngx:latest
Pod=gate.pod
Environment=PAPERLESS_DBHOST=127.0.0.1 PAPERLESS_DBPASS=$PGPW PAPERLESS_REDIS=redis://127.0.0.1:6379 PAPERLESS_SECRET_KEY=$PLKEY PAPERLESS_URL=https://docs.elysidrome.com
Volume=/srv/gate/paperless/data:/usr/src/paperless/data:Z
Volume=/srv/gate/paperless/media:/usr/src/paperless/media:Z
Volume=/srv/gate/paperless/consume:/usr/src/paperless/consume:Z
Volume=/srv/gate/paperless/export:/usr/src/paperless/export:Z
[Install]
WantedBy=default.target
EOF
c metube <<'EOF'
[Container]
Image=ghcr.io/alexta69/metube:latest
Pod=gate.pod
Volume=/srv/gate/metube:/downloads:Z
[Install]
WantedBy=default.target
EOF
c homepage <<'EOF'
[Container]
Image=ghcr.io/gethomepage/homepage:latest
Pod=gate.pod
Environment=HOMEPAGE_ALLOWED_HOSTS=home.elysidrome.com
Volume=/srv/gate/homepage:/app/config:Z
[Install]
WantedBy=default.target
EOF
c uptime-kuma <<'EOF'
[Container]
Image=docker.io/louislam/uptime-kuma:2
Pod=gate.pod
Volume=/srv/gate/uptime-kuma:/app/data:Z
[Install]
WantedBy=default.target
EOF
chmod 600 *.container
```

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
limit_req_zone $binary_remote_addr zone=perip:10m rate=10r/s;
server { listen 80 default_server; return 301 https://$host$request_uri; }

ssl_certificate /certs/fullchain.pem;  ssl_certificate_key /certs/privkey.pem;
ssl_protocols TLSv1.2 TLSv1.3;
client_max_body_size 0;
proxy_set_header Host $host;  proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;  proxy_set_header X-Forwarded-Proto https;
proxy_http_version 1.1;  proxy_set_header Upgrade $http_upgrade;  proxy_set_header Connection $http_connection;

map $host $backend {
  tv.elysidrome.com           http://10.10.10.20:8096;
  books.elysidrome.com        http://10.10.10.20:13378;
  comics.elysidrome.com       http://10.10.10.20:5000;
  eelsmusic.elysidrome.com    http://10.10.10.20:4533;
  rupaulradio.elysidrome.com  http://10.10.10.20:4533;
  arcade.elysidrome.com       http://10.10.10.20:8080;
  auth.elysidrome.com         http://127.0.0.1:9091;
}
server {   # catch-all: bare IP, unknown names, scanners -> drop the connection
  listen 443 ssl default_server; http2 on; server_name _;
  return 444;
}
server {   # no Authelia (apps have own logins / mobile clients)
  listen 443 ssl; http2 on;
  server_name tv.elysidrome.com books.elysidrome.com comics.elysidrome.com eelsmusic.elysidrome.com rupaulradio.elysidrome.com arcade.elysidrome.com auth.elysidrome.com;
  location / { limit_req zone=perip burst=50 nodelay; proxy_pass $backend; }
}
server {   # LAN/VPN only
  listen 443 ssl; http2 on; server_name vault.elysidrome.com;
  allow 10.10.10.0/24; allow 10.10.99.0/24; deny all;
  location / { proxy_pass http://127.0.0.1:8222; }
}
map $host $protected {
  docs.elysidrome.com    http://127.0.0.1:8000;
  metube.elysidrome.com  http://127.0.0.1:8081;
  home.elysidrome.com    http://127.0.0.1:3000;
  status.elysidrome.com  http://127.0.0.1:3001;
}
server {   # behind Authelia 2FA
  listen 443 ssl; http2 on;
  server_name docs.elysidrome.com metube.elysidrome.com home.elysidrome.com status.elysidrome.com;
  location /internal/authelia/authz {
    internal;
    proxy_pass http://127.0.0.1:9091/api/authz/auth-request;
    proxy_set_header X-Original-Method $request_method;
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header X-Forwarded-For $remote_addr;   # a location's own proxy_set_header drops the inherited ones
    proxy_set_header Content-Length ""; proxy_set_header Connection "";
    proxy_pass_request_body off;
  }
  location / {
    auth_request /internal/authelia/authz;
    auth_request_set $redirection_url $upstream_http_location;
    error_page 401 =302 $redirection_url;
    limit_req zone=perip burst=50 nodelay;
    proxy_pass $protected;
  }
}
# scores.elysidrome.com -> 127.0.0.1:8090  (reserved, add when hiscore exists)
```

```bash
systemctl --user daemon-reload && systemctl --user start gate-pod && podman ps
podman exec nginx nginx -t
```

- [ ] Vaultwarden: create your account at `https://vault.elysidrome.com`, then set `SIGNUPS_ALLOWED=false`, `systemctl --user restart vaultwarden`. Import the interim password DB.
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
- [ ] Offsite copy of `/srv/storage/media1/pbs` + photos to a second disk/cloud

## 5.7 Monitoring

- [ ] Uptime Kuma: HTTP monitors for every hostname, TCP for `10.10.10.1:53`, `10.10.10.3:53`, `10.10.10.20:53`, `10.10.10.2:8006`, `10.10.10.20:8007`
- [ ] Homepage `services.yaml`: tiles for all apps + Proxmox, OPNsense, PBS, both Pi-holes
- [ ] Proxmox → Datacenter → Notifications: SMTP target with your email
- [ ] OPNsense → System → Firmware: check updates weekly; Proxmox/Debian: `apt full-upgrade` weekly
- [ ] Pi-hole #1 → Settings → Teleporter export → import on Pi-hole #2 after list changes
