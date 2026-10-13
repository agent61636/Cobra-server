# 3. Set up SGIN (elysidrome-stream, Debian 13, 10.10.10.20)

**Result:** the SGIN runs Debian 13 bare metal and serves all storage (Samba), the media apps (one rootless Podman pod), Pi-hole #2 and Proxmox Backup Server.

🔌 SGIN onboard Ethernet → your switch (behind OPNsense, from part 2) for the whole part. Storage drives **unplugged** until "Storage".

## 3.1 Terms

| Term | Meaning |
|---|---|
| **Rootless Podman** | Containers run as the unprivileged user `podsvc`, not root. A container escape lands as a nobody. |
| **Pod** | Group of containers sharing one network namespace: they reach each other on `127.0.0.1`, and only the pod's published ports are reachable from the LAN. |
| **Quadlet** | A `.pod`/`.container` file in `~/.config/containers/systemd/`. systemd turns each into a service (`jellyfin.container` → `jellyfin.service`; `stream.pod` → `stream-pod.service`). Start/stop/logs with `systemctl --user` / `journalctl --user -u`. |
| **Linger** | Lets `podsvc`'s services run at boot without anyone logged in. |
| **`:Z`** on a volume | Relabels the folder for that container only. Don't use it on folders shared with Samba or other containers. |
| **PBS datastore** | A folder where Proxmox Backup Server keeps deduplicated backups. Proxmox (part 5) backs up VMs/CTs into it. |

## 3.2 Install Debian

- [ ] Back up anything on the SGIN first
- [ ] Debian netinst USB (Rufus, DD mode) → F7/F11/Esc for the boot menu (varies by mini-PC) → **Install** (text)

| Screen | Value |
|---|---|
| Language / location / keyboard | English / yours / American English |
| Network | Auto (DHCP), it gets `10.10.10.1xx` for now |
| Hostname / Domain | `elysidrome-stream` / `home.arpa` |
| Root password | **leave blank** (root is disabled and `eels` gets sudo) |
| User | full name `Eels`, username `eels`, generated password |
| Partitioning | Guided, use entire disk (the internal SSD, not a USB drive), all files in one partition |
| Software selection | untick desktop + GNOME; tick **SSH server** and **standard system utilities** only |
| GRUB | Yes, on the internal disk |

- [ ] After reboot: OPNsense → DHCP static mapping `10.10.10.20` for its MAC (`ip -br link` on the SGIN), then on the SGIN `sudo systemctl restart networking` or reboot
- [ ] From the desktop: `ssh eels@10.10.10.20`

## 3.3 Packages

Needs `contrib non-free` for the Intel media driver (Quick Sync).

```bash
sudo sed -i 's/^Components: main.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources 2>/dev/null \
  || sudo sed -i 's/ main non-free-firmware$/ main contrib non-free non-free-firmware/' /etc/apt/sources.list
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y intel-microcode firmware-misc-nonfree intel-media-va-driver-non-free vainfo \
  podman crun slirp4netns passt uidmap fuse-overlayfs samba nftables cockpit curl rsync smartmontools systemd-container
# Jasper Lake can ONLY encode in low-power mode, which needs the HuC firmware loaded.
# Without this, decode works but every transcode fails.
echo 'options i915 enable_guc=2' | sudo tee /etc/modprobe.d/i915.conf
sudo update-initramfs -u && sudo reboot
```

After the reboot:

```bash
sudo dmesg | grep -i -E 'guc|huc'                                        # "HuC ... authenticated", no FAIL/ERROR
sudo vainfo --display drm --device /dev/dri/renderD128 | grep -i hevc   # expect HEVC Main10 decode and EncSliceLP
```

- [ ] No `HEVC Main10` lines from vainfo → the media driver isn't installed. No `EncSliceLP` lines → HuC didn't load; recheck `/etc/modprobe.d/i915.conf` and `firmware-misc-nonfree`
- [ ] SSH key from the desktop: `type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh eels@10.10.10.20 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"`
- [ ] Same `/etc/ssh/sshd_config.d/10-elysidrome.conf` as part 1.7, but `PermitRootLogin no`; `sudo sshd -t && sudo systemctl reload ssh`

## 3.4 Storage

🔌 Plug the storage drives into the SGIN now.


```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID
sudo mkdir -p /srv/storage/media1        # one dir per drive label
# new/empty drive only:  sudo mkfs.ext4 -L media1 /dev/sdX1
echo 'UUID=<uuid> /srv/storage/media1 ext4 defaults,nofail,x-systemd.device-timeout=10 0 2' | sudo tee -a /etc/fstab
# existing NTFS drive instead: apt install ntfs-3g; fstype ntfs-3g, options uid=podsvc,gid=media,nofail
sudo systemctl daemon-reload && sudo mount -a && df -h /srv/storage/*
```

Folder layout per drive: `movies tv music/eels music/rachel books audiobooks comics roms pbs`.

## 3.5 Users and permissions

`podsvc` runs the containers; group `media` = everyone allowed to write the library (podsvc, eels, the cabinet's Samba login).

```bash
sudo groupadd media
sudo useradd -m -s /bin/bash -G media,render,video podsvc
sudo loginctl enable-linger podsvc
sudo chown -R podsvc:media /srv/storage/* && sudo chmod -R g+rwX /srv/storage/*
sudo find /srv/storage -type d -exec chmod g+s {} +
sudo mkdir -p /srv/stream && sudo chown podsvc: /srv/stream
sudo usermod -aG media eels
```

## 3.6 Samba (Windows shares)

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

## 3.7 Firewall (LAN + VPN only)

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

## 3.8 Media pod

Run as podsvc: `sudo machinectl shell podsvc@` (a full login session, needed for `systemctl --user`). `exit` to leave.

```bash
mkdir -p ~/.config/containers/systemd /srv/stream/{jellyfin/config,jellyfin/cache,ersatztv,abs/config,abs/metadata,kavita,navidrome,romm/resources,romm/assets,romm/config,romm/redis,romm/db}
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
Image=ghcr.io/ersatztv/legacy:latest
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
Environment=ND_SESSIONTIMEOUT=8h ND_MUSICFOLDER=/media/media1/music/eels
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
Volume=/srv/stream/romm/redis:/redis-data:Z
Volume=/srv/storage/media1/roms:/romm/library/roms
[Install]
WantedBy=default.target
EOF
chmod 600 romm*.container
systemctl --user daemon-reload
systemctl --user start stream-pod
podman ps                                     # 7 containers Up
# logs: journalctl --user -u jellyfin -f     restart one: systemctl --user restart jellyfin
```

- [ ] App URLs: Jellyfin `http://10.10.10.20:8096`, ErsatzTV `:8409`, Audiobookshelf `:13378`, Kavita `:5000`, Navidrome `:4533`, RomM `:8080`

- [ ] Image names checked against the official docs (Oct 2026): ErsatzTV is now published as `ghcr.io/ersatztv/legacy`; RomM is `rommapp/romm`. RomM expects `roms/<platform>/` folders
- [ ] Don't put `:Z` on `/srv/storage` mounts (shared with Samba)
- [ ] Jellyfin → Dashboard → Playback → Transcoding: **Intel QuickSync (QSV)**, device `/dev/dri/renderD128`, enable HEVC/HEVC 10-bit/VP9 decode (**not AV1**: Jasper Lake has no AV1 decode), **Low-Power H.264/HEVC encoder on**, tone mapping on. Users: hidden, Quick Connect off
- [ ] Jellyfin → Dashboard → Networking → **Known proxies: `10.10.10.10`**. Without it, every remote viewer looks like a LAN client coming from the gate, so remote bitrate limits and per-IP logs don't work
- [ ] Navidrome: the first library is Eels' (`ND_MUSICFOLDER`); add a second library `/media/media1/music/rachel` in the UI, then one user each with only their library
- [ ] Each app: create admin user now (first visit = admin)

## 3.9 Pi-hole #2 (as eels)

```bash
curl -sSL https://install.pi-hole.net | sudo bash
sudo pihole setpassword
sudo pihole-FTL --config dns.upstreams '["10.10.10.1"]'
sudo pihole-FTL --config dns.listeningMode ALL      # answer WireGuard clients too; nftables limits who can reach :53
# copy misc.dnsmasq_lines and dns.hosts exactly as on pihole-1 (part 2)
```

- [ ] OPNsense DHCP: DNS servers → `10.10.10.3`, `10.10.10.20`

## 3.10 Proxmox Backup Server

```bash
sudo wget -O /usr/share/keyrings/proxmox-archive-keyring.gpg https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg
sha256sum /usr/share/keyrings/proxmox-archive-keyring.gpg
#   must be 136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45
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

- [ ] Keyring URL and checksum match the PBS install docs (checked Oct 2026)
- [ ] PBS owns `/srv/storage/media1/pbs` from here on. **Never re-run the `chown -R ... /srv/storage/*` from 3.5** without excluding it, or backups stop working

## Done when

- [ ] `https://10.10.10.20:8007` (PBS), `:9090` (Cockpit), `:8096` Jellyfin plays a 4K HEVC file with transcoding showing `(hw)`
- [ ] `\\elysidrome-stream\media` opens from a desktop
