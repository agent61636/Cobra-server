# 3. Set up SGIN (elysidrome-stream, Debian 13, 10.10.10.20)

## Install

- [ ] Data backed up; storage drives unplugged during install
- [ ] Debian netinst USB: hostname `elysidrome-stream`, domain `home.arpa`, root password **blank** (gives `eels` sudo), user `eels`, guided entire disk, tasks: **SSH server + standard utilities** only
- [ ] OPNsense static mapping `.20` for its MAC

```bash
sudo sed -i 's/^Components: main.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources 2>/dev/null \
  || sudo sed -i 's/ main non-free-firmware$/ main contrib non-free non-free-firmware/' /etc/apt/sources.list
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y intel-microcode firmware-misc-nonfree intel-media-va-driver-non-free vainfo \
  podman crun slirp4netns passt uidmap fuse-overlayfs samba nftables cockpit curl rsync smartmontools
sudo vainfo --display drm --device /dev/dri/renderD128 | grep -i hevc   # expect HEVC Main10 decode/encode
```

- [ ] SSH key from desktop, then same `10-elysidrome.conf` as part 1 but `PermitRootLogin no`

## Storage

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID
sudo mkdir -p /srv/storage/media1        # one dir per drive label
# new/empty drive only:  sudo mkfs.ext4 -L media1 /dev/sdX1
echo 'UUID=<uuid> /srv/storage/media1 ext4 defaults,nofail,x-systemd.device-timeout=10 0 2' | sudo tee -a /etc/fstab
# existing NTFS drive instead: apt install ntfs-3g; fstype ntfs-3g, options uid=podsvc,gid=media,nofail
sudo systemctl daemon-reload && sudo mount -a && df -h /srv/storage/*
```

Folder layout per drive: `movies tv music/eels music/rachel books audiobooks comics roms pbs`.

## Users

```bash
sudo groupadd media
sudo useradd -m -s /bin/bash -G media,render,video podsvc
sudo loginctl enable-linger podsvc
sudo chown -R podsvc:media /srv/storage/* && sudo chmod -R g+rwX /srv/storage/*
sudo find /srv/storage -type d -exec chmod g+s {} +
sudo mkdir -p /srv/stream && sudo chown podsvc: /srv/stream
sudo usermod -aG media eels
```

## Samba

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.orig
sudo tee /etc/samba/smb.conf >/dev/null <<'EOF'
[global]
   workgroup = WORKGROUP
   server role = standalone server
   server min protocol = SMB3
   hosts allow = 10.10.10. 10.10.99. 127.
   map to guest = never

[media]
   path = /srv/storage/media1
   valid users = @media
   force group = media
   create mask = 0664
   directory mask = 2775
   read only = no

[roms]
   path = /srv/storage/media1/roms
   valid users = @media
   force group = media
   read only = no
EOF
sudo testparm -s >/dev/null && sudo systemctl restart smbd
sudo smbpasswd -a eels
sudo useradd -M -s /usr/sbin/nologin -G media arcade && sudo smbpasswd -a arcade   # cabinet login
```

## Firewall

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
    ip saddr { 10.10.10.0/24, 10.10.99.0/24 } tcp dport { 22, 53, 80, 443, 445, 4533, 5000, 8007, 8080, 8096, 8409, 9090, 13378 } accept
    ip saddr { 10.10.10.0/24, 10.10.99.0/24 } udp dport 53 accept
  }
}
EOF
sudo systemctl enable --now nftables
```

## Media pod (as podsvc: `sudo machinectl shell podsvc@`)

```bash
mkdir -p ~/.config/containers/systemd /srv/stream/{jellyfin/config,jellyfin/cache,ersatztv,abs/config,abs/metadata,kavita,navidrome,romm/resources,romm/assets,romm/config,romm/db}
cd ~/.config/containers/systemd
DBPW=$(openssl rand -hex 24); SECRET=$(openssl rand -hex 32)   # store both

cat > stream.pod <<'EOF'
[Pod]
PodName=stream
PublishPort=8096:8096
PublishPort=8409:8409
PublishPort=13378:13378
PublishPort=5000:5000
PublishPort=4533:4533
PublishPort=8080:8080
[Install]
WantedBy=default.target
EOF

c() { cat > "$1.container"; }
c jellyfin <<'EOF'
[Container]
Image=docker.io/jellyfin/jellyfin:latest
Pod=stream.pod
AddDevice=/dev/dri
GroupAdd=keep-groups
Volume=/srv/stream/jellyfin/config:/config:Z
Volume=/srv/stream/jellyfin/cache:/cache:Z
Volume=/srv/storage:/media:ro
[Install]
WantedBy=default.target
EOF
c ersatztv <<'EOF'
[Container]
Image=ghcr.io/ersatztv/ersatztv:latest
Pod=stream.pod
AddDevice=/dev/dri
GroupAdd=keep-groups
Volume=/srv/stream/ersatztv:/config:Z
Volume=/srv/storage:/media:ro
[Install]
WantedBy=default.target
EOF
c audiobookshelf <<'EOF'
[Container]
Image=ghcr.io/advplyr/audiobookshelf:latest
Pod=stream.pod
Environment=PORT=13378
Volume=/srv/stream/abs/config:/config:Z
Volume=/srv/stream/abs/metadata:/metadata:Z
Volume=/srv/storage:/media:ro
[Install]
WantedBy=default.target
EOF
c kavita <<'EOF'
[Container]
Image=docker.io/jvmilazz0/kavita:latest
Pod=stream.pod
Volume=/srv/stream/kavita:/kavita/config:Z
Volume=/srv/storage:/media:ro
[Install]
WantedBy=default.target
EOF
c navidrome <<'EOF'
[Container]
Image=docker.io/deluan/navidrome:latest
Pod=stream.pod
Environment=ND_SESSIONTIMEOUT=8h
Volume=/srv/stream/navidrome:/data:Z
Volume=/srv/storage:/media:ro
[Install]
WantedBy=default.target
EOF
c romm-db <<EOF
[Container]
Image=docker.io/library/mariadb:11
Pod=stream.pod
Environment=MARIADB_ROOT_PASSWORD=$DBPW MARIADB_DATABASE=romm MARIADB_USER=romm MARIADB_PASSWORD=$DBPW
Volume=/srv/stream/romm/db:/var/lib/mysql:Z
[Install]
WantedBy=default.target
EOF
c romm <<EOF
[Unit]
After=romm-db.service
Requires=romm-db.service
[Container]
Image=docker.io/rommapp/romm:latest
Pod=stream.pod
Environment=DB_HOST=127.0.0.1 DB_NAME=romm DB_USER=romm DB_PASSWD=$DBPW ROMM_AUTH_SECRET_KEY=$SECRET
Volume=/srv/stream/romm/resources:/romm/resources:Z
Volume=/srv/stream/romm/assets:/romm/assets:Z
Volume=/srv/stream/romm/config:/romm/config:Z
Volume=/srv/storage/media1/roms:/romm/library/roms
[Install]
WantedBy=default.target
EOF
chmod 600 romm*.container
systemctl --user daemon-reload
systemctl --user start stream-pod
podman ps
```

- [ ] ⚠️ Verify image names for ErsatzTV and RomM on their docs (they've moved registries before); RomM expects `roms/<platform>/` folders
- [ ] Don't put `:Z` on `/srv/storage` mounts (shared with Samba)
- [ ] Jellyfin → Dashboard → Playback → Transcoding: **Intel QuickSync (QSV)**, device `/dev/dri/renderD128`, enable HEVC/HEVC 10-bit/VP9/AV1 decode, tone mapping on. Users: hidden, Quick Connect off
- [ ] Navidrome: two libraries (`/media/.../music/eels`, `/media/.../music/rachel`), one user each with only their library
- [ ] Each app: create admin user now (first visit = admin)

## Pi-hole #2 (as eels)

```bash
curl -sSL https://install.pi-hole.net | sudo bash
sudo pihole setpassword
sudo pihole-FTL --config dns.upstreams '["10.10.10.1"]'
# copy misc.dnsmasq_lines and dns.hosts exactly as on pihole-1 (part 2)
```

- [ ] OPNsense DHCP: DNS servers → `10.10.10.3`, `10.10.10.20`

## Proxmox Backup Server

```bash
sudo wget -O /usr/share/keyrings/proxmox-archive-keyring.gpg https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg
sudo tee /etc/apt/sources.list.d/pbs.sources >/dev/null <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
sudo apt update && sudo apt install -y proxmox-backup-server
sudo proxmox-backup-manager datastore create store1 /srv/storage/media1/pbs
sudo proxmox-backup-manager user create pve@pbs --password "$(openssl rand -base64 24 | tee /dev/stderr)"   # store it
sudo proxmox-backup-manager acl update /datastore/store1 DatastoreBackup --auth-id pve@pbs
sudo proxmox-backup-manager cert info | grep Fingerprint
```

- [ ] ⚠️ Verify the keyring URL on pbs.proxmox.com docs if wget 404s

## Done when

- [ ] `https://10.10.10.20:8007` (PBS), `:9090` (Cockpit), `:8096` Jellyfin plays a 4K HEVC file with transcoding showing `(hw)`
- [ ] `\\elysidrome-stream\media` opens from a desktop
