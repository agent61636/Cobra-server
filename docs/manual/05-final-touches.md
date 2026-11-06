# 5. Final touches (gate VM 110, public access, backups)

**Result:** `cobra-gate` (VM 110 on the Latitude) terminates TLS for `*.songofeo.com`, runs the station's one sign-in (Authelia: a password for the station's floors, plus a TOTP code for the admin apps), proxies to the SGIN's media apps, and is the only thing reachable from the internet (TCP 443). Nightly backups go to PBS.

🔌 No cable changes. Everything is already wired from part 2.

## 5.1 Terms

| Term | Meaning |
|---|---|
| **Reverse proxy (nginx)** | Receives every `https://<name>.songofeo.com` request and forwards it by hostname to the right app. |
| **Wildcard cert** | One Let's Encrypt cert for `songofeo.com` + `*.songofeo.com`, obtained by DNS challenge (lego writes a TXT record through the Porkbun API), so nothing needs to be open to get it. |
| **Authelia** | The sign-in screen at `gate.songofeo.com`. nginx asks it "is this person signed in?" before serving any app. One sign-in covers every `*.songofeo.com` floor for 6 hours. |
| **The station** | The public homepage at the bare `songofeo.com` (Porkbun static hosting, the Project-Eo repository). Its **Sign in** button and every floor's Log In lead here, to the gate. |
| **Gate pod** | All gate apps in one rootless Podman pod. Only nginx's 80/443 are published; the apps listen on `127.0.0.1` inside the pod. |

## 5.2 Gate VM (cobra-command shell, root)

```bash
qm create 110 --name cobra-gate --ostype l26 --cpu host --cores 2 --memory 6144 \
  --scsihw virtio-scsi-single --scsi0 local-lvm:64,discard=on,iothread=1 --net0 virtio,bridge=vmbr0 \
  --cdrom local:iso/$(ls /var/lib/vz/template/iso | grep -m1 netinst) --agent 1 \
  --onboot 1 --startup order=3
qm start 110
```

- [ ] Proxmox → 110 → **Console** → Install. Same answers as part 3.2 except:

| Screen | Value |
|---|---|
| Network | **Configure manually** (Esc out of DHCP if it already ran): IP `10.6.9.10/24`, gateway `10.6.9.1`, DNS **`10.6.9.3 10.6.9.20`** (both Pi-holes, so the gate's own apps, like Uptime Kuma checking `tv.songofeo.com`, reach the LAN addresses) |
| Hostname | `cobra-gate` |
| Disk | the 64 GB virtual disk (`sda`) |
- [ ] `qm set 110 --ide2 none,media=cdrom`
- [ ] **Check the address is fixed, not DHCP** (gate console): `ip -br addr` shows `10.6.9.10/24` and nothing else on the NIC, and `grep -A4 'iface' /etc/network/interfaces` says `inet static`. The Pi-holes send every `*.songofeo.com` name to `.10`, so a gate that took a DHCP lease (it would show on OPNsense's **Leases** page as `cobra-gate`, e.g. `10.6.9.176`) breaks every app name at home. To fix it from the cobra-command shell (backs up both files first; the gate reboots):

```bash
sudo qm guest exec 110 -- cp -a /etc/network/interfaces /etc/network/interfaces.bak     # keep the old file
sudo qm guest exec 110 -- cp -a /etc/resolv.conf /etc/resolv.conf.bak
# one short line per change, so nothing breaks when pasted
sudo qm guest exec 110 -- sed -i 's/^iface ens18 inet dhcp$/iface ens18 inet static/' /etc/network/interfaces
sudo qm guest exec 110 -- sed -i '/^iface ens18 inet static$/a gateway 10.6.9.1' /etc/network/interfaces
sudo qm guest exec 110 -- sed -i '/^iface ens18 inet static$/a address 10.6.9.10/24' /etc/network/interfaces   # lands above gateway
sudo qm guest exec 110 -- cat /etc/network/interfaces                                    # ends: static / address / gateway
sudo qm guest exec 110 -- bash -c 'echo "search home.arpa" > /etc/resolv.conf'
sudo qm guest exec 110 -- bash -c 'echo "nameserver 10.6.9.3" >> /etc/resolv.conf'
sudo qm guest exec 110 -- bash -c 'echo "nameserver 10.6.9.20" >> /etc/resolv.conf'
sudo qm reboot 110                                                                       # then: ip -br addr shows 10.6.9.10
```

On gate (eels):

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y qemu-guest-agent podman crun passt uidmap cockpit nftables systemd-container curl openssl git   # curl + openssl: scripts/podman/gate/check.sh; git: to clone the scripts
# rootless containers may bind 80/443
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/90-ports.conf && sudo sysctl --system
sudo useradd -m -s /bin/bash podsvc && sudo loginctl enable-linger podsvc
sudo mkdir -p /srv/gate/{nginx/certs,nginx/conf.d/soon,authelia,vaultwarden,paperless/{data,media,consume,export},postgres,redis,metube,homepage,uptime-kuma,hiscore,eo-art}
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
    ip saddr { 10.6.9.0/24, 10.6.99.0/24 } tcp dport { 22, 9090 } accept
  }
}
EOF
sudo systemctl enable --now nftables
```

Shared storage from the SGIN (MeTube saves into the library, Paperless reads the `scans` drop folder, eo-art reads the station's pictures from `art`):

```bash
sudo apt install -y cifs-utils
sudo install -m 600 /dev/null /root/smb-gate.cred
printf 'username=gate\npassword=%s\n' '<gate Samba password from part 3.6>' | sudo tee /root/smb-gate.cred >/dev/null
sudo mkdir -p /srv/storage/disks
PU=$(id -u podsvc); PG=$(id -g podsvc)
echo "//10.6.9.20/media /srv/storage/disks cifs credentials=/root/smb-gate.cred,vers=3.1.1,seal,uid=$PU,gid=$PG,file_mode=0666,dir_mode=0777,_netdev,nofail,x-systemd.automount 0 0" \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/disks && ls /srv/storage/disks   # wd1 dock1a dock1b wd2
```

- `file_mode=0666,dir_mode=0777`: Paperless and MeTube run as a non-root user *inside* their containers, which is some unnamed ID on the gate, so the mount lets anyone on the gate write. Only `eels` and `podsvc` log in there. This setting is local to the gate; on the SGIN the files still land as user `gate`, group `media`, mode 664, like everything else written over Samba.
- `seal`: SMB3 encryption on the wire. `x-systemd.automount`: the gate boots even if the SGIN is off, and the share mounts when first used.
- The share is addressed by IP on purpose, so it mounts even if both Pi-holes are down.
- `/srv/storage/disks` is the same path as on the SGIN, with the same drive folders under it, so a path in one app's settings means the same folder everywhere.
- [ ] `touch /srv/storage/disks/dock1a/scans/test && rm /srv/storage/disks/dock1a/scans/test` works as eels

## 5.3 Wildcard cert (as eels)

**lego** gets one Let's Encrypt certificate for `songofeo.com` and `*.songofeo.com` by putting a temporary TXT record in your Porkbun DNS (the DNS challenge), so nothing has to be open to the internet to get it. Certbot has no Porkbun plugin in Debian.

Use lego's **official build from GitHub**, not `apt install lego`: Debian 13 ships lego 4.9, which has no Porkbun provider (it fails with `unrecognized DNS provider: porkbun`). The commands below are for lego **5.x**, where the options go after the word `run`.

Credentials: the `cobra-acme` Porkbun API key and secret key from part 0.4 (separate from the DDNS key, so either can be revoked alone).

```bash
cd /tmp
V=5.6.0                                       # the latest release on github.com/go-acme/lego/releases
curl -fLO https://github.com/go-acme/lego/releases/download/v$V/lego_v${V}_linux_amd64.tar.gz
curl -fLO https://github.com/go-acme/lego/releases/download/v$V/lego_${V}_checksums.txt
grep "lego_v${V}_linux_amd64.tar.gz" lego_${V}_checksums.txt | sha256sum -c -   # must say OK
tar xzf lego_v${V}_linux_amd64.tar.gz lego
sudo install -m 755 lego /usr/local/bin/lego
/usr/local/bin/lego --version
sudo install -m 600 /dev/null /root/porkbun.env
sudo tee /root/porkbun.env >/dev/null <<'EOF'
PORKBUN_API_KEY=pk1_...
PORKBUN_SECRET_API_KEY=sk1_...
PORKBUN_PROPAGATION_TIMEOUT=900
EOF

# The deploy step: copy the cert where nginx reads it, then restart nginx
sudo tee /usr/local/sbin/gate-cert-deploy >/dev/null <<'EOF'
#!/bin/sh
set -e
C=/etc/lego/certificates
install -o podsvc -m 600 $C/songofeo.com.crt /srv/gate/nginx/certs/fullchain.pem
install -o podsvc -m 600 $C/songofeo.com.key /srv/gate/nginx/certs/privkey.pem
# Restart nginx so it loads the new cert. The very first run happens before the pod exists (part 5.4),
# so a failure here is not fatal, but it is written to the journal (journalctl -t gate-cert-deploy)
# instead of being hidden: a renewal that never reaches nginx would let the old cert expire.
runuser -u podsvc -- env XDG_RUNTIME_DIR=/run/user/$(id -u podsvc) systemctl --user restart nginx \
  || logger -t gate-cert-deploy "new cert copied, but nginx did not restart; run: systemctl --user restart nginx (as podsvc)"
EOF
sudo chmod 755 /usr/local/sbin/gate-cert-deploy

# First certificate (takes a few minutes while Porkbun's DNS updates)
sudo sh -c 'set -a; . /root/porkbun.env; set +a; /usr/local/bin/lego run --path /etc/lego --email "<your email>" \
  --accept-tos --dns porkbun --dns.resolvers 9.9.9.9:53 -d songofeo.com -d "*.songofeo.com"'
sudo /usr/local/sbin/gate-cert-deploy
```

- Already ran `apt install lego`? Leave it or `sudo apt remove lego`; just always call `/usr/local/bin/lego`. If an earlier attempt left files in `/etc/lego`, move them aside first (`sudo mv /etc/lego /etc/lego-v4-old`).
- lego 5 has no `renew` command: `lego run` on an existing certificate renews it only when it's due, and says "Skip renewal" otherwise.
- `songofeo.com.crt` already contains the full chain, which is what nginx wants as `fullchain.pem`.
- `--dns.resolvers 9.9.9.9:53`: lego checks the challenge record against public DNS, not the Pi-holes, which answer every `songofeo.com` name with the gate's LAN address.

Automatic renewal (a systemd timer, daily; lego renews when fewer than 30 days remain):

```bash
sudo tee /etc/systemd/system/lego-renew.service >/dev/null <<'EOF'
[Unit]
Description=Renew the songofeo.com wildcard certificate
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
EnvironmentFile=/root/porkbun.env
ExecStart=/usr/local/bin/lego run --path /etc/lego --email "<your email>" --accept-tos --dns porkbun --dns.resolvers 9.9.9.9:53 -d songofeo.com -d *.songofeo.com --renew-days 30 --deploy-hook /usr/local/sbin/gate-cert-deploy
EOF
sudo tee /etc/systemd/system/lego-renew.timer >/dev/null <<'EOF'
[Unit]
Description=Daily certificate renewal check
[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true
[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now lego-renew.timer
sudo systemctl start lego-renew.service && sudo journalctl -u lego-renew -n 5   # "Skip renewal" is the expected answer today
```

- [ ] `sudo ls -l /srv/gate/nginx/certs/` shows `fullchain.pem` and `privkey.pem`, owned by podsvc
- [ ] `systemctl list-timers lego-renew.timer` shows the next run

## 5.4 Gate pod (as podsvc: `sudo machinectl shell podsvc@`)

The same pod as plain `podman run` scripts: [`scripts/podman`](../../scripts/podman/README.md) (`gate/up-all.sh`). Either way, the Authelia and nginx config files below are still needed.

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
Environment=ROCKET_PORT=8222 DOMAIN=https://vault.songofeo.com SIGNUPS_ALLOWED=true
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
Environment=PAPERLESS_DBHOST=127.0.0.1 PAPERLESS_DBPASS=$PGPW PAPERLESS_REDIS=redis://127.0.0.1:6379 PAPERLESS_SECRET_KEY=$PLKEY PAPERLESS_URL=https://papers.songofeo.com PAPERLESS_CONSUMER_POLLING=60
Volume=/srv/gate/paperless/data:/usr/src/paperless/data:Z
Volume=/srv/gate/paperless/media:/usr/src/paperless/media:Z
Volume=/srv/storage/disks/dock1a/scans:/usr/src/paperless/consume
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
Volume=/srv/storage/disks/wd2/youtube:/downloads
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
Environment=HOMEPAGE_ALLOWED_HOSTS=command.songofeo.com
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
c eo-art <<'EOF'
[Container]
ContainerName=eo-art
Image=docker.io/library/python:3-slim
Pod=gate.pod
AutoUpdate=registry
Environment=EO_ART_ADDR=127.0.0.1:8790 EO_ART_MOVIES=/art/movies EO_ART_RADIO=/art/albums EO_ART_BOOKS=/art/books EO_ART_COMICS=/art/comics EO_ART_GAMING=/art/gaming
Volume=/srv/gate/eo-art:/app:ro,Z
Volume=/srv/storage/disks/dock1a/art:/art:ro
Exec=python3 /app/eo_art.py
[Service]
Restart=on-failure
RestartSec=60
[Install]
WantedBy=default.target
EOF
chmod 600 *.container
```

**eo-art** hands the station's landing pages one random picture at a time (a movie backdrop for the Cinema, album covers for Music, book, comic and game-book covers for the Library, Comics and the Game Cellar) at `art.songofeo.com`, behind the sign-in. It's one standard-library Python file from the Project-Eo repository, `home/eo-art/eo_art.py`. From the desktop:

```powershell
scp .\Project-Eo-main\home\eo-art\eo_art.py eels@10.6.9.10:/tmp/
```

```bash
# on the gate, as eels
sudo install -o podsvc -m 644 /tmp/eo_art.py /srv/gate/eo-art/eo_art.py
mkdir -p /srv/storage/disks/dock1a/art/{movies,albums,books,comics,gaming}
```

Each `art/` folder is a flat set of `.jpg` files (copies, not the library itself) that you fill however you like; eo-art rescans them every two minutes. Until a folder has pictures, that page shows its own drawn artwork instead.

Where the gate's apps keep their files:

| App | Its own data (on the gate's disk, in the nightly VM backup) | Shared files (on the SGIN's drives, over the CIFS mount) |
|---|---|---|
| Paperless | database, search index, the archived originals: `/srv/gate/paperless`, `/srv/gate/postgres` | **Inbox:** `dock1a/scans`. Drop a PDF or photo into `\\cobra-stream\scans` from any machine; within a minute Paperless files it and removes it from the inbox. Polling is on because change notifications don't cross SMB. |
| MeTube | queue and history: `/srv/gate/metube` | **Finished videos:** `wd2/youtube`, on the Seagate's spare space, so Jellyfin can show them (add `/media/wd2/youtube` as a Home Videos library) |
| eo-art | just its script: `/srv/gate/eo-art` | **Pictures for the station:** `dock1a/art/movies`, `albums`, `books`, `comics`, `gaming` (read-only) |

`Restart=on-failure`: if the gate boots while the SGIN is off, those three can't find their shared folder and fail. systemd retries every minute until the SGIN is back.

### The station's sign-in (Authelia)

This is the one login screen for the whole station. Someone taps the gold star **Sign in** on the station (or a floor's Enter, when they aren't signed in yet), lands on `gate.songofeo.com`, types their username and password once, and goes back where they came from. The session cookie is set for all of `songofeo.com`, so for the next **6 hours** every floor (Cinema, Music, Library, Comics, Arcade, Game Cellar, The Ward), the landing pages' live pictures, the website's players and the Android app let them straight through. The admin apps (`papers.`, `metube.`, `command.`, `status.`) also ask for a TOTP code.

At home and over WireGuard the station's floors skip the sign-in, so the music and audiobook apps on phones keep working; they still have their own logins. From anywhere else the sign-in comes first.

**`tv.` is the one exception: it never goes through the gate's sign-in, from anywhere.** Friends watch on smart-TV, Roku, Fire TV and phone Jellyfin apps, which can't show a web sign-in page, so `tv.songofeo.com` relies on Jellyfin's own login alone. That makes the Jellyfin accounts the lock on the front door: one account per person with a strong password, only you as administrator, and leave Jellyfin's own failed-login lock-out on (Dashboard → Users → each user → "Maximum number of failed login attempts"). Every other name keeps the gate's sign-in.

Authelia config (`/srv/gate/authelia/configuration.yml`). Still as podsvc, write the file, then swap the three `SECRETn` placeholders for random values:

```bash
cat > /srv/gate/authelia/configuration.yml <<'EOF'
theme: dark
server: { address: 'tcp://127.0.0.1:9091/' }   # inside the pod only; the internet reaches it through nginx
totp: { issuer: songofeo.com }
identity_validation: { reset_password: { jwt_secret: 'SECRET1' } }
authentication_backend: { file: { path: /config/users.yml } }
# Wrong passwords: 5 tries within 10 minutes locks that username for 1 hour.
regulation: { max_retries: 5, find_time: 10m, ban_time: 1h }
definitions:
  network:
    home: [10.6.9.0/24, 10.6.99.0/24]     # the LAN and WireGuard
access_control:
  default_policy: deny                    # any name not listed below is refused, even after signing in
  rules:
    # admin apps: password + TOTP, from anywhere
    - domain: [papers.songofeo.com, metube.songofeo.com, command.songofeo.com, status.songofeo.com]
      policy: two_factor
    # the station's floors and its pictures: open at home, one password everywhere else
    - domain: &station [music.songofeo.com, mustang.songofeo.com,
                        books.songofeo.com, comics.songofeo.com, arcade.songofeo.com, gaming.songofeo.com,
                        sessions.songofeo.com, art.songofeo.com]
      networks: [home]
      policy: bypass
    - domain: *station
      policy: one_factor
session:
  secret: 'SECRET2'
  remember_me: -1                     # no "remember me" box: every sign-in lasts the same 6 hours
  cookies:
    - domain: songofeo.com            # the whole station: the bare domain and every *.songofeo.com
      authelia_url: 'https://gate.songofeo.com'
      default_redirection_url: 'https://songofeo.com'   # signing in straight at gate. lands on the station
      expiration: 6h
      inactivity: 6h
storage: { encryption_key: 'SECRET3', local: { path: /config/db.sqlite3 } }
notifier: { filesystem: { filename: /config/notification.txt } }   # "emails" (one-time codes) are written to this file
EOF
# Replace each placeholder with its own 64-character random secret (a different one each time)
for s in SECRET1 SECRET2 SECRET3; do
  sed -i "s/'$s'/'$(openssl rand -hex 32)'/" /srv/gate/authelia/configuration.yml
done
grep -c SECRET /srv/gate/authelia/configuration.yml     # must print 0: no placeholder left
chmod 600 /srv/gate/authelia/configuration.yml           # only podsvc (and Authelia inside its container) can read it
```

- The three secrets never need typing anywhere else, so you don't have to write them down. They're in the nightly VM backup with the rest of `/srv/gate`. If you ever change `SECRET3`, Authelia can no longer read its database (`db.sqlite3`): everyone has to register TOTP again.
- `definitions.network`: Authelia 4.38 moved the named networks here from `access_control.networks`; the old spelling only prints a warning today and may stop working in a later release.
- The `home` bypass trusts the address nginx hands Authelia, which is always the real address the connection came from (`X-Forwarded-For $remote_addr` in nginx below), never a header the visitor sends. That only works because rootless Podman on Debian 13 (pasta) keeps the visitor's real address on published ports; the checks at the end of 5.4 and 5.5 prove it on your hardware.
- `expiration: 6h` and `inactivity: 6h`: a sign-in lasts six hours, then Authelia asks again. Change both together if you want longer or shorter.
- `&station` / `*station` is plain YAML: the second rule reuses the first rule's list, so a new floor is added in one place.
- Parts 7 and 8 add `scores.` and `radio.` to `access_control.rules` the same way.

Users (`/srv/gate/authelia/users.yml`). One block per person; everyone signs in to the whole station with these:

```bash
# hash NAME: asks for NAME's password without showing it (so it never lands in the shell history),
# and prints Authelia's argon2 hash of it. Only the hash is stored, never the password.
hash() {
  local pw; read -rsp "Password for $1: " pw </dev/tty; echo >/dev/tty
  podman run --rm docker.io/authelia/authelia:latest authelia crypto hash generate argon2 --password "$pw" | awk '{print $2}'
}
cat > /srv/gate/authelia/users.yml <<EOF
users:
  eels:
    displayname: Eels
    email: <you@email>
    password: "$(hash eels)"
  rachel:
    displayname: Rachel
    email: <their@email>
    password: "$(hash rachel)"
EOF
chmod 600 /srv/gate/authelia/*.yml
grep -c 'argon2id' /srv/gate/authelia/users.yml   # must print 2 (one per person); 0 means a hash failed, run it again
```

- Use the **same usernames** as in Navidrome (part 3.8). Navidrome then signs in whoever Authelia signed in, so Music never asks a second time.
- Adding someone later: add a block, then `systemctl --user restart authelia`. Removing someone: delete their block and restart; their session ends at once. (Sessions live in Authelia's memory, so any restart signs **everyone** out; they just sign in again.)
- **TOTP for the admin apps** (once per person who uses `papers.`, `metube.`, `command.` or `status.`): open one of them, sign in, choose **Register device** → **One-Time Password**. Authelia asks for a one-time code "sent by email"; with the `filesystem` notifier above it's written to a file instead. Read it on the gate as podsvc: `tail -n 20 /srv/gate/authelia/notification.txt`, type the code, then scan the QR code with an authenticator app (Aegis, 2FAS, Google Authenticator, or the Bitwarden app with Vaultwarden). The file holds codes, so keep it at mode 600 and empty it once you're set up: `: > /srv/gate/authelia/notification.txt`. Password resets work the same way.
- **Sign in** on the station links to `https://gate.songofeo.com/?rd=https%3A%2F%2Fsongofeo.com%2F`. `rd` is where Authelia sends people back to; it only accepts addresses under `songofeo.com`. To sign out: `https://gate.songofeo.com/logout`. If the station's pages (the Project-Eo repository) still link to the older `auth.songofeo.com`, change those links to `gate.songofeo.com` there: `auth.` has no DNS record and no server block any more.
- Jellyfin, Audiobookshelf, Kavita and RomM still show their own login the first time on each device (they remember it after that). On the website's players that's the **station pass**: one username and password, asked once per browser, signs in to all four (so keep the same username and password in each app). Wiring them to Authelia too (OpenID Connect) is a later step.
- **The website's players** (`songofeo.com/cinema/play/` and the rest, from the Project-Eo repository) call the apps from the station's pages, so the floors' server answers `songofeo.com` with CORS headers: `station-cors.inc`, included in the floors' `location /` below. Copy it from the Project-Eo repository (`home/nginx/station-cors.inc`) along with eo-art:

  ```powershell
  scp .\Project-Eo-main\home\nginx\station-cors.inc eels@10.6.9.10:/tmp/
  ```

  ```bash
  # on the gate, as eels
  sudo install -o podsvc -m 644 /tmp/station-cors.inc /srv/gate/nginx/conf.d/station-cors.inc
  ```

  The `.inc` name keeps nginx from loading it on its own; only the include line below uses it. The include is written as `station-cors*.inc` (a pattern), so nginx still starts if the file isn't there yet; the players then say *Home isn't answering* and everything else works as before. (A plain `include` of a missing file would stop nginx from starting at all, which takes every floor and the sign-in down.)
  - nginx drops every `add_header` inherited from above as soon as a block has one of its own, and this file most likely adds the CORS headers with `add_header`. That can silently remove the HSTS header (which tells browsers "never use plain http here") from the floors. The `curl -sI` check at the end of 5.4 tests for it; if it fails, add the line to the end of the file as podsvc: `echo 'add_header Strict-Transport-Security "max-age=31536000" always;' >> /srv/gate/nginx/conf.d/station-cors.inc`, then `podman exec nginx nginx -t && podman exec nginx nginx -s reload`.

- [ ] The portal's hostname is **`gate.songofeo.com`**, the same name the DDNS updater already keeps pointed at your home (part 2.10, an **A** record) and that every app's CNAME points at. So it needs **no new DNS record**: don't add a CNAME for `gate` (a name can't have both, and Porkbun would refuse or replace the A record). On the LAN the Pi-holes already answer it with `10.6.9.10`. Before this part, `gate.songofeo.com` on 443 got the catch-all; from here it's the sign-in screen

nginx (`/srv/gate/nginx/conf.d/songofeo.conf`). As podsvc, everything from the `cat` line to the closing `EOF` is one paste; the quoted `'EOF'` keeps the shell from touching nginx's `$` variables:

```bash
cat > /srv/gate/nginx/conf.d/songofeo.conf <<'EOF'
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
# The gate is the first proxy, so the visitor's address is $remote_addr, full stop. Passing on an
# X-Forwarded-For the visitor sent ($proxy_add_x_forwarded_for) would let them pick the address
# that Authelia's lock-out, Jellyfin's logs and the apps' own checks see.
proxy_set_header Host $host;  proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $remote_addr;  proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header Upgrade $http_upgrade;  proxy_set_header Connection $connection_upgrade;
proxy_set_header Remote-User "";   # never pass on a visitor's own Remote-User header (only the floors set it, below)

server { listen 80 default_server; return 301 https://$host$request_uri; }
server {   # catch-all: bare IP, unknown names, scanners -> refuse the TLS handshake
  listen 443 ssl default_server; http2 on; server_name _;
  ssl_reject_handshake on;   # no certificate is shown, so a scan of your IP doesn't learn the domain name
}

# --- the station's floors: the Authelia sign-in first (skipped at home and over WireGuard), then the app ---
map $host $station {
  music.songofeo.com        http://10.6.9.20:4533;    # Music: Navidrome (each person sees their own library)
  mustang.songofeo.com  http://10.6.9.20:4533;    # Navidrome (Rachel's library)
  books.songofeo.com        http://10.6.9.20:13378;   # Library: Audiobookshelf
  comics.songofeo.com       http://10.6.9.20:5000;    # Comics: Kavita
  arcade.songofeo.com       http://10.6.9.20:8080;    # Arcade: RomM + EmulatorJS
  art.songofeo.com          http://127.0.0.1:8790;    # the landing pages' live pictures (eo-art)
}
server {
  listen 443 ssl; http2 on;
  server_name music.songofeo.com mustang.songofeo.com
              books.songofeo.com comics.songofeo.com arcade.songofeo.com art.songofeo.com;
  location /internal/authelia/authz {
    internal;
    proxy_pass http://127.0.0.1:9091/api/authz/auth-request;
    # a location's own proxy_set_header replaces ALL inherited ones, so list what Authelia needs
    proxy_set_header X-Original-Method $request_method;
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Content-Length ""; proxy_set_header Connection "";
    proxy_set_header Authorization "";   # an app's own token (players, Android app) is for the app, not Authelia
    proxy_pass_request_body off;
  }
  location / {
    include /etc/nginx/conf.d/station-cors*.inc;  # the website's players (Project-Eo home/nginx); answers their preflight first. The * lets nginx start before the file exists
    auth_request /internal/authelia/authz;
    auth_request_set $redirection_url $upstream_http_location;
    auth_request_set $signed_in_user $upstream_http_remote_user;
    error_page 401 =302 $redirection_url;
    limit_req zone=media burst=300 nodelay;
    proxy_buffering off;              # stream video/audio/ROM downloads straight through, don't spool to the gate's disk
    proxy_request_buffering off;      # same for uploads (RomM, Audiobookshelf)
    proxy_read_timeout 1h;  proxy_send_timeout 1h;   # long streams and websockets
    # Setting one header here drops the inherited ones, so all of them are listed again.
    proxy_set_header Host $host;  proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $remote_addr;  proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header Upgrade $http_upgrade;  proxy_set_header Connection $connection_upgrade;
    # Who Authelia signed in. Navidrome trusts it from the gate only (part 3.8); empty at home, and a
    # visitor's own Remote-User header is always replaced, never passed on.
    proxy_set_header Remote-User $signed_in_user;
    proxy_pass $station;
  }
}

# --- Cinema: Jellyfin's own login only, no gate sign-in (friends' TV and phone apps can't show one) ---
server {
  listen 443 ssl; http2 on; server_name tv.songofeo.com;
  location / {
    include /etc/nginx/conf.d/station-cors*.inc;
    limit_req zone=media burst=300 nodelay;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 1h;  proxy_send_timeout 1h;
    proxy_pass http://10.6.9.20:8096;   # Jellyfin (+ ErsatzTV channels inside it); headers come from the shared settings above
  }
}

# --- Game Cellar and The Ward: no app yet, so signed-in visitors get a holding page ---
server {
  listen 443 ssl; http2 on; server_name gaming.songofeo.com sessions.songofeo.com;
  location /internal/authelia/authz {
    internal;
    proxy_pass http://127.0.0.1:9091/api/authz/auth-request;
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
    root /etc/nginx/conf.d/soon;  try_files /index.html =404;
  }
}

# --- Authelia portal ---
server {
  listen 443 ssl; http2 on; server_name gate.songofeo.com;
  location / { limit_req zone=perip burst=50 nodelay; proxy_pass http://127.0.0.1:9091; }
}

# --- Vaultwarden: LAN/VPN only ---
server {
  listen 443 ssl; http2 on; server_name vault.songofeo.com;
  allow 10.6.9.0/24; allow 10.6.99.0/24; deny all;
  location / { proxy_pass http://127.0.0.1:8222; }
}

# --- admin apps on the gate, behind Authelia 2FA ---
map $host $protected {
  papers.songofeo.com    http://127.0.0.1:8000;    # Paperless-ngx
  metube.songofeo.com  http://127.0.0.1:8081;    # MeTube
  command.songofeo.com    http://127.0.0.1:3000;    # Homepage
  status.songofeo.com  http://127.0.0.1:3001;    # Uptime Kuma
}
server {
  listen 443 ssl; http2 on;
  server_name papers.songofeo.com metube.songofeo.com command.songofeo.com status.songofeo.com;
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
# scores.songofeo.com -> 127.0.0.1:8090  (reserved, add when hiscore exists)
EOF
```

Every protected `location /` above has its own `auth_request` line. That's the whole SSO: a `server` or `location` without one is open to anyone who can reach the gate. When you add a hostname later (parts 7 and 8 do), copy a whole `server` block with its `/internal/authelia/authz` location, and add the name to Authelia's `access_control` too; `default_policy: deny` refuses any name Authelia doesn't know, so forgetting that step locks people out instead of letting them in.

The holding page for the Game Cellar and The Ward (when their apps exist, move the two names into the `$station` map and the first `server_name` list, with the app's address):

```bash
cat > /srv/gate/nginx/conf.d/soon/index.html <<'EOF'
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Opening soon</title>
<body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#07060a;color:#ffe6dc;font:600 18px system-ui,sans-serif;text-align:center">
<div><p style="letter-spacing:.2em">THIS FLOOR IS STILL BEING BUILT</p><p><a href="https://songofeo.com/" style="color:#c1121f">Back to the station</a></p></div>
EOF
```

```bash
# 1. Test the nginx config BEFORE starting anything: a throwaway nginx with the same two folders.
#    It must end with "test is successful". A broken config would otherwise keep the gate's nginx from starting.
podman run --rm -v /srv/gate/nginx/conf.d:/etc/nginx/conf.d:ro -v /srv/gate/nginx/certs:/certs:ro \
  docker.io/library/nginx:stable nginx -t
# 2. Turn the Quadlet files into systemd services and start the pod (that starts every container in it)
systemctl --user daemon-reload && systemctl --user start gate-pod
# 3. Every container should say "Up". One that keeps restarting: podman logs <name>
podman ps --format '{{.Names}}\t{{.Status}}'
# 4. Only 80 and 443 may be published; nothing else from the pod is reachable from outside it.
#    The gate's listening ports: 22 (SSH), 80, 443 and 9090 (Cockpit). 9091, 8000, 8222, 3000, 3001,
#    8081, 8790, 5432 or 6379 in this list would mean an app is reachable without nginx and Authelia.
ss -tlnH | awk '{print $4}' | sort -u
podman exec nginx nginx -t
podman logs authelia 2>&1 | grep -iE 'level=(error|fatal)|deprecat' || echo "Authelia: no errors"
```

Checks before going public (from a desktop on the LAN, where Pi-hole sends every name to the gate):

- [ ] **Every hostname in one go.** On the gate (as eels or podsvc), from the repo checkout: `~podsvc/cobra-server/scripts/podman/gate/check.sh`. It asks the gate's own nginx for each name below and prints OK, NOTE or FAIL with what to look at. Run from the gate it's the view from *outside* the house, so the floors must send you to the sign-in too. Expected before parts 7 and 8: `scores.` and `radio.` show NOTE (no server block yet). The other checks below are the ones a script can't do for you (real browsers, the cookie, apps' own logins).

| Hostname | Goes to | Sign-in |
|---|---|---|
| `gate.` | Authelia (the sign-in page itself) | none |
| `tv.` | Jellyfin `:8096` on the SGIN `10.6.9.20` | **never** (Jellyfin's own login only, for the TV apps) |
| `music.` `mustang.` `books.` `comics.` `arcade.` | Navidrome `:4533` (two names), Audiobookshelf `:13378`, Kavita `:5000`, RomM `:8080`, all on the SGIN `10.6.9.20` | skipped at home and over WireGuard, password elsewhere |
| `art.` | eo-art `127.0.0.1:8790` on the gate | same as the floors |
| `gaming.` `sessions.` | the holding page (`conf.d/soon`) | same as the floors |
| `papers.` `metube.` `command.` `status.` | Paperless `:8000`, MeTube `:8081`, Homepage `:3000`, Uptime Kuma `:3001` on the gate | password + TOTP, everywhere |
| `vault.` | Vaultwarden `:8222` on the gate | none; LAN and WireGuard only, 403 elsewhere |
| `scores.` (part 7) | hiscore `127.0.0.1:8090` | password (except `/upload/`, `/public/`, `/screen`) |
| `radio.` (part 8) | Icecast `10.6.9.20:8000` | password; `/admin` LAN and WireGuard only |
| anything else, or the bare IP | nothing: the TLS handshake is refused | |

Every name except `gate.`, `vault.`, `status.` and `art.` must also be a CNAME to `gate.songofeo.com` in Porkbun (5.5) before it works from outside; those four are home and WireGuard only (`gate.` is the A record itself).

- [ ] `podman exec nginx nginx -t` says `syntax is ok` and `test is successful`
- [ ] Each hostname loads with a valid padlock: `tv. music. books. comics. mustang. arcade. gaming. sessions. art. gate. papers. metube. command. status. vault.`
- [ ] `papers.` and `metube.` bounce you to `gate.` first, then back
- [ ] `https://gate.songofeo.com` shows the dark sign-in screen; signing in there lands on the station (`songofeo.com`)
- [ ] Jellyfin: play a movie, then Dashboard → Activity shows your desktop's IP (not `10.6.9.10`), so the Known proxies setting from part 3 works
- [ ] Jellyfin's phone app connects with server address `https://tv.songofeo.com` (no port)
- [ ] Navidrome: Eels logs in at `music.` and, as the admin, sees every library; Rachel logs in at `mustang.` and sees only hers. Each person you add later gets their own name, folder and login the same way
- [ ] `https://10.6.9.10` (bare IP) gets no page at all: the browser says the connection was reset or closed (the catch-all refuses the handshake)
- [ ] **The gate sees real addresses.** Load `https://tv.songofeo.com` from the desktop, then as podsvc on the gate: `podman logs --tail 3 nginx`. Each line must start with the **desktop's** `10.6.9.x` address. If every line starts with `127.0.0.1` or `10.0.2.x`, the pod isn't using pasta: stop here, because the home bypass, the Vaultwarden LAN rule and Jellyfin's logs all depend on it. Check `podman info --format '{{.Host.RootlessNetworkCmd}}'` says `pasta`
- [ ] Authelia is up: `curl -s https://gate.songofeo.com/api/health` from the desktop prints `{"status":"OK"}`
- [ ] **Bypass at home, but only for the floors:** in a private window on the desktop, `music.` opens Navidrome straight away (no sign-in, you're home), while `papers.` still sends you to the sign-in and then asks for the TOTP code
- [ ] **The cookie.** After signing in, browser → F12 → Application (Chrome) or Storage (Firefox) → Cookies → `https://gate.songofeo.com`: `authelia_session` has Domain `.songofeo.com`, **Secure** ✓, **HttpOnly** ✓, SameSite **Lax**, and expires in 6 hours
- [ ] **Redirects stay at home.** Signed out, open `https://gate.songofeo.com/?rd=https%3A%2F%2Fexample.com%2F` and sign in: you must land on the station (`songofeo.com`), never on example.com. Authelia only sends people back to `https://` addresses under `songofeo.com`
- [ ] HSTS on the floors and the admin apps: `curl -sI https://tv.songofeo.com/ | grep -i strict-transport` and `curl -sI https://papers.songofeo.com/ | grep -i strict-transport` each print one line. Nothing for `tv.` means `station-cors.inc` drops it (see above)
- [ ] Signing out works everywhere: `https://gate.songofeo.com/logout`, then `papers.` asks for the sign-in again
- [ ] The website's players: signed in with the gold star, `https://songofeo.com/radio/play/` lists albums straight away, and `https://songofeo.com/cinema/play/` asks for the station pass once, then lists films. *Home isn't answering* means `station-cors.inc` isn't included yet

- [ ] Vaultwarden: create your account at `https://vault.songofeo.com`, then close sign-ups: `sed -i 's/SIGNUPS_ALLOWED=true/SIGNUPS_ALLOWED=false/' ~/.config/containers/systemd/vaultwarden.container && systemctl --user daemon-reload && systemctl --user restart vaultwarden`. Import the interim password DB.
- [ ] Paperless admin: `podman exec -it paperless python3 manage.py createsuperuser`

## 5.5 Go public

- [ ] Porkbun → `songofeo.com` → DNS: one **CNAME** per app, each with answer `gate.songofeo.com`: `tv music books comics mustang arcade gaming sessions papers metube command`, plus `vpn` for WireGuard (2.10) (not `vault`, which stays LAN/VPN-only, and not `gate`, which is already the A record). `status` and `art` get no public record for now: they still work at home and over WireGuard, where the Pi-holes answer every `*.songofeo.com` name, but from outside they don't resolve (so the station's landing pages show their drawn artwork instead of live pictures there). They follow the `gate` A record that DDNS keeps up to date (2.10). Leave the bare `songofeo.com` and `www` records alone: they belong to Porkbun's static hosting (the station). Make sure Porkbun's **URL Forwarding** has nothing for these names.
- [ ] **Before the 443 forward below:** the station's **Sign in** button and every floor's Log In (Project-Eo, live on Porkbun's hosting) must point at `https://gate.songofeo.com/?rd=...`, not `auth.songofeo.com`. Open `https://songofeo.com`, hover Sign in, and check the address in the browser's status bar. Fix them in Project-Eo and redeploy the site if they don't match
- [ ] OPNsense → Firewall → NAT → **Destination NAT** (called Port Forward in older versions) → **+**: Interface WAN, IPv4, TCP, Source **any**, Destination **WAN address** port HTTPS (443), Redirect target **`10.6.9.10`** port HTTPS (443), description `WAN 443 to gate` → Save → **Apply**. Don't forward 80: certs use the DNS challenge, and the overview promises 443 is the only public TCP port
- [ ] Its **Firewall rule** field defaults to *Manual*, which adds no pass rule, so the forward is blocked. Add one: Firewall → Rules → **WAN** → **+**: Pass, In, IPv4, TCP, Source any, Destination **Single host `10.6.9.10`** (not WAN address: rules see the address after the forward rewrote it), port HTTPS (443), description `Allow 443 to gate` → Save → **Apply**
- [ ] OPNsense → Firewall → NAT → Destination NAT has **exactly one enabled** rule: WAN TCP 443 → `10.6.9.10` (old rules may stay listed greyed out, disabled). Nothing points at the SGIN (`10.6.9.20`), where Jellyfin, Navidrome and the other apps answer without the gate. (Part 3.1 deleted the old rules; check again here.) Firewall → Rules → **WAN** has only that 443 rule and the UDP 51820 WireGuard rule from 2.8
- [ ] OPNsense → System → Firmware → **Plugins**: `os-upnp` is **not** installed. UPnP would let any device on the LAN open its own port to the internet, around the gate
- [ ] From cellular (Wi-Fi off): each URL loads; `papers.` demands Authelia 2FA; `vault.` returns 403
- [ ] **No bypass from outside.** From cellular in a private window, `https://music.songofeo.com` must send you to the sign-in screen first (it's only skipped at home and over WireGuard), while `https://tv.songofeo.com` shows Jellyfin's own login. On the gate as podsvc, `podman logs --tail 3 nginx` shows the phone's **public** address (not `10.6.9.x`): if it showed a `10.6.9.x` address, OPNsense is rewriting the source and the outside world would get the home bypass, so stop and check OPNsense → Firewall → NAT → **Outbound** for a rule on the LAN interface
- [ ] **No way around the gate.** Still on cellular, find your public IP (OPNsense → Interfaces → Overview → WAN), then try `http://<public IP>:8096`, `:4533`, `:8080`, `:13378`, `:5000` and `:9091`: each must time out. Only `https://tv.songofeo.com` (443) reaches anything
- On the **Xfinity Wi-Fi** (not the cobra network), no `songofeo.com` name loads: they point at your public address, and the Xfinity gateway won't loop traffic back in to itself (no NAT loopback). WireGuard's `vpn.songofeo.com` hits the same wall there. Use cellular, or a second WireGuard profile "home" whose Endpoint is `10.0.0.2:51820` (OPNsense's WAN address on the Xfinity side), until the cobra Wi-Fi access point (2.10b) exists
- [ ] Turn WireGuard on (still on cellular): `music.` now opens without the sign-in, and `podman logs --tail 3 nginx` shows the phone as `10.6.99.x`
- [ ] The station end to end, from cellular in a private window: open `https://songofeo.com`, tap **Sign in**, sign in once, and you're back on the station. The Cinema, Library and Comics landing pages now show real pictures (once the `art` folders have some), and every floor's Log In goes straight to its app with no second sign-in screen from the gate. Six hours later the gate asks again.

## 5.6 Backups

On cobra-command:

```bash
pvesm add pbs pbs-stream --server 10.6.9.20 --datastore store1 --username pve@pbs \
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
- [ ] Test restore: Proxmox → CT 101 → Backup → restore to new VMID 901. **Before starting it**, cut its network so it doesn't steal Pi-hole #1's `10.6.9.3`: `pct set 901 --net0 name=eth0,bridge=vmbr0,ip=10.6.9.3/24,gw=10.6.9.1,link_down=1`. Start, `pct enter 901`, check `pihole status`, then stop and destroy
- [ ] Second copy of the PBS datastore (`/srv/storage/vault/store1`) and of anything irreplaceable: see part 4.6 (the OptiPlex drive) and add a cloud copy for photos and documents

### Backing up the library (the ~10 TB on the data drives)

Until the backup drive exists, the library has **no backup**: a dead drive loses whatever was on it. The fix is one dedicated backup drive that holds no live library folders of its own.

**The backup drive is the Seagate 24 TB** (3.4's "The Seagate" section), once 3.4r's rescue is finished and the recovered files have been fine on their drives for a few weeks. It already sits at `/srv/storage/vault`, next to `store1`. Its `wd2` folder is lent out as extra space and isn't backed up (it's on the same drive).

**How it works:** Proxmox Backup Server, already running on the SGIN, gets a second datastore called `vault` on the Seagate. Every night the SGIN backs up wd1, dock1a and dock1b into it. After the first full run (expect a day or more for 5 TB over USB), each night only reads what changed. You can restore a single file from the PBS web UI, and a weekly verify job re-reads everything to catch a failing disk early.

On stream (eels):

```bash
sudo proxmox-backup-manager datastore create vault /srv/storage/vault/pbs
sudo proxmox-backup-manager acl update /datastore/vault DatastoreBackup --auth-id pve@pbs
echo '0 1 * * * root . /root/pbs.env && export PBS_PASSWORD PBS_FINGERPRINT && PBS_REPOSITORY=pve@pbs@127.0.0.1:vault proxmox-backup-client backup wd1.pxar:/srv/storage/disks/wd1 dock1a.pxar:/srv/storage/disks/dock1a dock1b.pxar:/srv/storage/disks/dock1b --exclude /lost+found --change-detection-mode=metadata' \
  | sudo tee /etc/cron.d/pbs-library
```

- Delete the 3.4r rescue images (`wd1.img`, `dock1a.img` and their copies, after `sudo chattr -i`) once you're sure you won't need them: they take about 8 TB.
- [ ] PBS UI → Datastore **vault** → Prune: keep-daily 7, keep-weekly 4, keep-monthly 3. GC daily. Verify weekly.
- `store1` (the VM backups) is on the same Seagate, so there's no sync job between them. Their second copy is part 4.6 and the off-site copy below.
- [ ] First run: start it by hand inside `tmux` (`sudo apt install -y tmux`, then paste everything after `root` from the cron line, prefixed with `sudo bash -c '...'`) so it survives closing the SSH window, and leave it overnight
- [ ] Restore test: PBS UI → vault → the newest `host/cobra-stream` snapshot → `wd1.pxar` → browse → download one file and open it
- `--change-detection-mode=metadata` (PBS backup client docs): each night it compares file metadata with the last snapshot and only reads files that changed, instead of re-reading all 10 TB.

**What this doesn't cover: fire, theft, a power surge through the hub.** The backup drive sits next to the originals. For the files you could never get back (photos, home video, documents, your own music, saves), keep a third copy outside the house: a second backup drive you swap with one kept at a relative's every month or two, or a cloud backup of just that irreplaceable part. Movies and TV you could re-rip or re-buy can live with two copies at home.

## 5.7 Monitoring

- [ ] Uptime Kuma (`status.songofeo.com`): an **HTTP** monitor for every public hostname (the gate resolves them to itself through the Pi-holes, so this tests nginx + the app); **HTTP with "Ignore TLS errors"** for `https://10.6.9.2:8006`, `https://10.6.9.1`, `https://10.6.9.20:8007`; **DNS** monitors against `10.6.9.3` and `10.6.9.20` (resolve `tv.songofeo.com`, expect `10.6.9.10`); **TCP** `10.6.9.20:445` (Samba). Settings → Notifications: add your email or phone app, and attach it to every monitor.
- [ ] Homepage: a starter dashboard. As podsvc on the gate, write these two files, then `systemctl --user restart homepage`. Each tile links to the app, and the dot on it turns red when the app stops answering.

```bash
cat > /srv/gate/homepage/settings.yaml <<'EOF'
title: Cobra
theme: dark
color: slate
headerStyle: clean
layout:
  Watch & listen: { style: row, columns: 4 }
  Read & play:    { style: row, columns: 3 }
  Files:          { style: row, columns: 3 }
  Admin:          { style: row, columns: 4 }
EOF
cat > /srv/gate/homepage/services.yaml <<'EOF'
- Watch & listen:
    - Jellyfin:     { href: "https://tv.songofeo.com",          icon: jellyfin.png,       description: "Movies, shows, Live TV", siteMonitor: "http://10.6.9.20:8096" }
    - ErsatzTV:     { href: "http://10.6.9.20:8409",            icon: ersatztv.png,       description: "Channel builder (LAN)",  siteMonitor: "http://10.6.9.20:8409" }
    - Music:        { href: "https://music.songofeo.com",       icon: navidrome.png,      siteMonitor: "http://10.6.9.20:4533" }
    - Rachel's music: { href: "https://mustang.songofeo.com", icon: navidrome.png,    siteMonitor: "http://10.6.9.20:4533" }
- Read & play:
    - Audiobookshelf: { href: "https://books.songofeo.com",     icon: audiobookshelf.png, siteMonitor: "http://10.6.9.20:13378" }
    - Kavita:       { href: "https://comics.songofeo.com",      icon: kavita.png,         siteMonitor: "http://10.6.9.20:5000" }
    - Arcade:       { href: "https://arcade.songofeo.com",      icon: romm.png,           siteMonitor: "http://10.6.9.20:8080" }
- Files:
    - Paperless:    { href: "https://papers.songofeo.com",        icon: paperless-ngx.png,  siteMonitor: "http://127.0.0.1:8000" }
    - MeTube:       { href: "https://metube.songofeo.com",      icon: metube.png,         siteMonitor: "http://127.0.0.1:8081" }
    - Vaultwarden:  { href: "https://vault.songofeo.com",       icon: vaultwarden.png,    description: "LAN/VPN only", siteMonitor: "http://127.0.0.1:8222" }
- Admin:
    - Proxmox:      { href: "https://10.6.9.2:8006",            icon: proxmox.png }
    - OPNsense:     { href: "https://10.6.9.1",                 icon: opnsense.png }
    - Backups (PBS): { href: "https://10.6.9.20:8007",          icon: proxmox.png }
    - Pi-hole 1:    { href: "http://10.6.9.3/admin",            icon: pi-hole.png,        siteMonitor: "http://10.6.9.3/admin" }
    - Pi-hole 2:    { href: "http://10.6.9.20/admin",           icon: pi-hole.png,        siteMonitor: "http://10.6.9.20/admin" }
    - Status:       { href: "https://status.songofeo.com",      icon: uptime-kuma.png,    siteMonitor: "http://127.0.0.1:3001" }
EOF
```

- Proxmox, OPNsense and PBS have no status dot: they use self-signed certificates, which Homepage's checker rejects. Uptime Kuma watches them instead (below), where you can tick "ignore TLS errors".
- Later, Homepage widgets can show live numbers (Jellyfin streams, Pi-hole blocks, Proxmox load). Each needs an API key in `services.yaml`; see Homepage's docs per service.
- [ ] Proxmox → Datacenter → Notifications: SMTP target with your email
- [ ] OPNsense → System → Firmware: check updates weekly; Proxmox/Debian: `apt full-upgrade` weekly
- [ ] Container updates, weekly, as podsvc on the gate and on the SGIN: `podman auto-update --dry-run` lists which images have a newer version; `podman auto-update` pulls them and restarts those containers (and rolls a container back if it fails to start). Read the release notes for Authelia, Paperless and RomM first; they occasionally change their config between major versions.
- [ ] Pi-hole #1 → Settings → Teleporter export → import on Pi-hole #2 after list changes
