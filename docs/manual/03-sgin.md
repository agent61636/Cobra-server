# 3. Set up SGIN (elysidrome-stream, Debian 13, 10.6.9.20)

**Result:** the SGIN runs Debian 13 bare metal and serves all storage (Samba), the media apps (one rootless Podman pod), Pi-hole #2 and Proxmox Backup Server.

🔌 SGIN onboard Ethernet → your switch (behind OPNsense, from part 2) for the whole part. **Unplug the USB hub from the SGIN until "Storage" (3.4)**, so the Debian installer can only see the internal SSD and can't touch a data drive.

**This part replaces your old server.** The SGIN gets wiped and reinstalled, so the old server's sites go offline here and come back under the new names in part 5. Plan to do parts 3 and 5 close together.

- [ ] Copy anything you need off the SGIN's internal disk (configs, databases, compose files). The USB drives aren't touched; they're unplugged during the install.
- [ ] After 3.2: OPNsense → delete the `10.6.9.200` static mapping and the port forwards pointing at it (from part 2.4)

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
| Network | Auto (DHCP), it gets `10.6.9.1xx` for now |
| Hostname / Domain | `elysidrome-stream` / `home.arpa` |
| Root password | **leave blank** (root is disabled and `eels` gets sudo) |
| User | full name `Eels`, username `eels`, generated password |
| Partitioning | Guided, use entire disk (the internal SSD, not a USB drive), all files in one partition |
| Software selection | untick desktop + GNOME; tick **SSH server** and **standard system utilities** only |
| GRUB | Yes, on the internal disk |

- [ ] After reboot: OPNsense → DHCP static mapping `10.6.9.20` for its MAC (`ip -br link` on the SGIN), then on the SGIN `sudo systemctl restart networking` or reboot
- [ ] From the desktop: `ssh eels@10.6.9.20`

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
- [ ] SSH key from the desktop: `type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh eels@10.6.9.20 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"`
- [ ] Same `/etc/ssh/sshd_config.d/10-elysidrome.conf` as part 1.7, but `PermitRootLogin no`; `sudo sshd -t && sudo systemctl reload ssh`

## 3.4 Storage

🔌 Plug the storage drives into the SGIN now: both WD external drives, and the dual-bay dock with its disks. The second dock gets added the same way later (see "Adding a drive later").

**Before anything else, about the docks' clone button:** on most dual-bay docks, clone mode **erases one bay and overwrites it with the other**. Put tape over the button. Nothing in this manual uses it.

### How the drives are combined

| Layer | Path | What it is |
|---|---|---|
| Each drive | `/srv/storage/disks/<label>` | Mounted on its own, by UUID. Unplug any one drive and the others keep working; any drive can be read on its own in another computer. |
| The library on each drive | `/srv/storage/disks/<label>/library` | The part of each drive that joins the pool |
| **The pool** | **`/srv/storage/pool`** | **mergerfs** shows every drive's `library` folder as one big folder. New files go to whichever drive has the most free space, so free space on every drive gets used. This is the only path apps, Samba and the gate ever see. |
| Backups | `/srv/storage/disks/<label>/pbs` | Proxmox Backup Server's datastore, on one drive, deliberately **outside** the pool so nobody can delete backups through a share |

Why mergerfs and not RAID: RAID across USB enclosures drops whole arrays when a USB link resets, and it needs matching drives. mergerfs takes any mix of sizes and filesystems, and losing one drive loses only the files on that drive. Protection against a dead drive comes from backups (part 5), plus optional SnapRAID parity once the second dock is in (end of this section).

The OptiPlex's internal WD drive stays in the OptiPlex. See part 4.6 for what it does there. Spare space on the machines' system drives (the Latitude's NVMe, the SGIN's own SSD) is **not** added to the pool. Those disks get wiped and reinstalled, and a pool member that lives on another machine disappears whenever that machine reboots.

### Set up the drives

```bash
sudo groupadd media                                        # owns the library (users come in 3.5)
sudo apt install -y mergerfs ntfs-3g
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MODEL,SERIAL          # write down every drive
```

For each drive, pick a short label: `wd1`, `wd2` for the externals, `dock1a`, `dock1b` for the dock's bays.

**Empty drive, or one you've copied off first** (ext4 is the most reliable choice on Linux):

```bash
sudo wipefs -a /dev/sdX && sudo parted -s /dev/sdX mklabel gpt mkpart data ext4 0% 100%
sudo mkfs.ext4 -L wd1 -m 0 /dev/sdX1                       # -m 0: no space reserved for root on a data drive
L=wd1; U=$(sudo blkid -s UUID -o value /dev/sdX1)
sudo mkdir -p /srv/storage/disks/$L
echo "UUID=$U /srv/storage/disks/$L ext4 defaults,noatime,nofail,x-systemd.device-timeout=15 0 2" | sudo tee -a /etc/fstab
```

**Drive that already holds files in NTFS** (keep it as it is):

```bash
L=wd2; U=$(sudo blkid -s UUID -o value /dev/sdY1)
sudo mkdir -p /srv/storage/disks/$L
echo "UUID=$U /srv/storage/disks/$L ntfs-3g uid=0,gid=$(getent group media | cut -d: -f3),umask=002,noatime,nofail,x-systemd.device-timeout=15 0 0" | sudo tee -a /etc/fstab
```

Then mount everything and give each drive its `library` folder. On a drive that already has files, move them into `library` (a move on the same drive is instant):

```bash
sudo systemctl daemon-reload && sudo mount -a && df -h /srv/storage/disks/*
for d in /srv/storage/disks/*; do sudo mkdir -p "$d/library"; done
# drive with existing files, e.g.:  sudo mv /srv/storage/disks/wd2/Movies /srv/storage/disks/wd2/library/movies
```

The pool:

```bash
sudo mkdir -p /srv/storage/pool
echo '/srv/storage/disks/*/library /srv/storage/pool fuse.mergerfs defaults,allow_other,use_ino,cache.files=off,dropcacheonclose=true,category.create=mfs,moveonenospc=true,minfreespace=20G,fsname=pool,nofail,x-systemd.requires-mounts-for=/srv/storage/disks 0 0' \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/pool && df -h /srv/storage/pool
```

- `category.create=mfs`: each new file goes to the drive with the most free space
- `minfreespace=20G`: a drive with less than 20 GB free gets no new files
- `moveonenospc=true`: if a drive fills mid-copy, the file moves to another drive instead of failing

Folder layout (made once, on the pool): `movies tv music/eels music/rachel books audiobooks comics roms filler youtube scans backups`.

- `filler`: short videos for TV breaks (ErsatzTV filler and the between-episodes plugin)
- `youtube`: MeTube saves here from the gate (part 5)
- `scans`: drop documents here from any machine and Paperless on the gate picks them up (part 5)
- `backups`: machines that keep files only on themselves (the cabinet's saves, part 4.5) copy them here, so the vault backup covers them

```bash
sudo mkdir -p /srv/storage/pool/{movies,tv,music/eels,music/rachel,books,audiobooks,comics,roms,filler,youtube,scans,backups}
```

- [ ] `df -h /srv/storage/pool` shows the combined size of all drives
- [ ] Reboot with one drive unplugged: the SGIN still boots, the pool still mounts with the other drives

### USB drives on Linux: two things to check

- **Link resets.** Some USB-to-SATA chips misbehave with the fast UAS driver. If `sudo dmesg | grep -i -E 'uas|reset'` shows repeated resets for a drive, note its ID from `lsusb` (e.g. `152d:0578`), add `usb-storage.quirks=152d:0578:u` to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, `sudo update-grub`, reboot.
- **The powered hub** (9-port USB 3.2 hub, 65 W adapter). Which ports to use:
  - **Bus-powered WD externals → the two 10 Gb/s USB-A 3.2 ports.** These ports draw their power from the hub's 65 W brick.
  - **Docks (they have their own power bricks) → any of the 5 Gb/s USB 3.0 ports**, or straight onto the SGIN.
  - **Leave both 45 W PD charging ports empty.** They share the same 65 W budget, and a phone or laptop charging there can starve the drives and make them drop.
  - Speed is fine: one spinning disk moves about 1.5–2 Gb/s, and mergerfs reads each file from a single drive. The hub only gets busy when several drives copy at full speed at once.
  - One point of failure: if the hub loses power or resets, every drive drops at the same moment. Plug its brick into the same outlet or UPS as the SGIN, never a switched strip. If `dmesg` shows whole-hub dropouts, move the docks to the SGIN's own USB 3 ports.
  - [ ] `lsusb -t` shows each drive at `5000M` or `10000M`. `480M` means it fell back to USB 2: reseat the cable or try another port.

### Adding a drive later (the second dock)

1. Label and mount it exactly as above (`dock2a`, `dock2b`), and `mkdir` its `library` folder.
2. `sudo umount /srv/storage/pool && sudo mount /srv/storage/pool`. The `*` in the fstab line picks it up; nothing else changes.
3. Optional, once there are four or more drives: **SnapRAID** turns one drive into parity for the rest, so a dead drive can be rebuilt. The parity drive must be at least as big as the biggest data drive. ⚠️ Decide when you know the sizes; it's a separate short setup.

## 3.5 Users and permissions

`podsvc` runs the containers; group `media` = everyone allowed to write the library (podsvc, eels, the cabinet's and the gate's Samba logins).

How the permissions fit together: files arrive from Samba owned by whoever wrote them, with group `media` and mode `664`/`2775`. Containers that only read the library (Jellyfin, Audiobookshelf, Kavita, Navidrome) can read those through the "other" bits. A rootless container drops `podsvc`'s supplementary groups unless its Quadlet says `GroupAdd=keep-groups`, so every container that **writes** to the library (RomM) or needs `/dev/dri` (Jellyfin, ErsatzTV) carries that line.

```bash
sudo useradd -m -s /bin/bash -G media,render,video podsvc
sudo loginctl enable-linger podsvc
sudo chown -R podsvc:media /srv/storage/pool && sudo chmod -R g+rwX /srv/storage/pool   # pool only, never the pbs folders
sudo find /srv/storage/pool -type d -exec chmod g+s {} +
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
   hosts allow = 10.6.9. 10.6.99. 127.
   map to guest = never

   # one set of permissions for every share
   valid users = @media
   force group = media
   create mask = 0664
   directory mask = 2775
   read only = no

[media]
   path = /srv/storage/pool

[roms]
   path = /srv/storage/pool/roms

[scans]
   path = /srv/storage/pool/scans
EOF
sudo testparm -s >/dev/null && sudo systemctl restart smbd
sudo smbpasswd -a eels
sudo useradd -M -s /usr/sbin/nologin -G media arcade && sudo smbpasswd -a arcade   # cabinet login
sudo useradd -M -s /usr/sbin/nologin -G media gate   && sudo smbpasswd -a gate     # gate VM (part 5)
sudo systemctl enable --now smbd
```

Every machine, and every share, by the same path:

| From | How | Path |
|---|---|---|
| Windows desktops | File Explorer → Map network drive (log in as `eels`) | `\\elysidrome-stream\media`, `\scans`, `\roms` |
| Cabinet | `R:` mapped in part 4 (log in as `arcade`) | `\\elysidrome-stream\roms` |
| Laptop/phone on WireGuard | Same as the desktops; short names resolve through Pi-hole (part 2) | `\\elysidrome-stream\media` |
| Gate VM | CIFS mount in part 5 (log in as `gate`) | `/srv/storage/pool` |
| Containers on the SGIN | Bind mounts in 3.8 | `/media/...` |
| Phones on Wi-Fi | Xfinity Wi-Fi is outside the firewall by design; use WireGuard there too | — |

- [ ] Windows: `\\elysidrome-stream\media` opens and you can create and delete a test folder

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
    ip saddr { 10.6.9.0/24, 10.6.99.0/24 } tcp dport { 22, 53, 80, 443, 445, 4533, 5000, 8007, 8080, 8096, 8409, 9090, 13378 } accept
    ip saddr { 10.6.9.0/24, 10.6.99.0/24 } udp dport 53 accept
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
ContainerName=jellyfin
Image=docker.io/jellyfin/jellyfin:latest
Pod=stream.pod
AutoUpdate=registry
AddDevice=/dev/dri
GroupAdd=keep-groups
Volume=/srv/stream/jellyfin/config:/config:Z
Volume=/srv/stream/jellyfin/cache:/cache:Z
Volume=/srv/storage/pool:/media:ro
[Install]
WantedBy=default.target
EOF
c ersatztv <<'EOF'
[Container]
ContainerName=ersatztv
Image=ghcr.io/ersatztv/legacy:latest
Pod=stream.pod
AutoUpdate=registry
AddDevice=/dev/dri
GroupAdd=keep-groups
Volume=/srv/stream/ersatztv:/config:Z
Volume=/srv/storage/pool:/media:ro
[Install]
WantedBy=default.target
EOF
c audiobookshelf <<'EOF'
[Container]
ContainerName=audiobookshelf
Image=ghcr.io/advplyr/audiobookshelf:latest
Pod=stream.pod
AutoUpdate=registry
Environment=PORT=13378
Volume=/srv/stream/abs/config:/config:Z
Volume=/srv/stream/abs/metadata:/metadata:Z
Volume=/srv/storage/pool:/media:ro
[Install]
WantedBy=default.target
EOF
c kavita <<'EOF'
[Container]
ContainerName=kavita
Image=docker.io/jvmilazz0/kavita:latest
Pod=stream.pod
AutoUpdate=registry
Volume=/srv/stream/kavita:/kavita/config:Z
Volume=/srv/storage/pool:/media:ro
[Install]
WantedBy=default.target
EOF
c navidrome <<'EOF'
[Container]
ContainerName=navidrome
Image=docker.io/deluan/navidrome:latest
Pod=stream.pod
AutoUpdate=registry
Environment=ND_SESSIONTIMEOUT=8h ND_MUSICFOLDER=/media/music/eels
Volume=/srv/stream/navidrome:/data:Z
Volume=/srv/storage/pool:/media:ro
[Install]
WantedBy=default.target
EOF
c romm-db <<EOF
[Container]
ContainerName=romm-db
Image=docker.io/library/mariadb:11
Pod=stream.pod
AutoUpdate=registry
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
ContainerName=romm
Image=docker.io/rommapp/romm:latest
Pod=stream.pod
AutoUpdate=registry
GroupAdd=keep-groups
Environment=DB_HOST=127.0.0.1 DB_NAME=romm DB_USER=romm DB_PASSWD=$DBPW ROMM_AUTH_SECRET_KEY=$SECRET
Volume=/srv/stream/romm/resources:/romm/resources:Z
Volume=/srv/stream/romm/assets:/romm/assets:Z
Volume=/srv/stream/romm/config:/romm/config:Z
Volume=/srv/stream/romm/redis:/redis-data:Z
Volume=/srv/storage/pool/roms:/romm/library/roms
[Install]
WantedBy=default.target
EOF
chmod 600 romm*.container
systemctl --user daemon-reload
systemctl --user start stream-pod
podman ps                                     # 7 containers Up
# logs: journalctl --user -u jellyfin -f     restart one: systemctl --user restart jellyfin
```

- [ ] App URLs: Jellyfin `http://10.6.9.20:8096`, ErsatzTV `:8409`, Audiobookshelf `:13378`, Kavita `:5000`, Navidrome `:4533`, RomM `:8080`

- [ ] Image names checked against the official docs (Oct 2026): ErsatzTV is now published as `ghcr.io/ersatztv/legacy`; RomM is `rommapp/romm`. RomM expects `roms/<platform>/` folders
- [ ] Don't put `:Z` on `/srv/storage/pool` mounts (shared with Samba)
- [ ] Jellyfin → Dashboard → Playback → Transcoding: **Intel QuickSync (QSV)**, device `/dev/dri/renderD128`, enable HEVC/HEVC 10-bit/VP9 decode (**not AV1**: Jasper Lake has no AV1 decode), **Low-Power H.264/HEVC encoder on**, tone mapping on. Users: hidden, Quick Connect off
- [ ] Jellyfin → Dashboard → Networking → **Known proxies: `10.6.9.10`**. Without it, every remote viewer looks like a LAN client coming from the gate, so remote bitrate limits and per-IP logs don't work
- [ ] Navidrome: the first library is Eels' (`ND_MUSICFOLDER`); add a second library `/media/music/rachel` in the UI, then one user each with only their library
- [ ] Each app: create admin user now (first visit = admin)

### 3.8a Live TV: ErsatzTV channels inside Jellyfin

ErsatzTV builds fake TV channels from your library (schedules, playlists, commercial breaks) and hands Jellyfin two links: a channel list (M3U) and a program guide (XMLTV). Jellyfin shows them under **Live TV** on every client, phones and TVs included. Both containers share the `stream` pod, so they talk over `127.0.0.1` and ErsatzTV never needs a public address.

**1. Give ErsatzTV access to Jellyfin's library**

- [ ] Jellyfin → Dashboard → API Keys → **+** → name `ersatztv` → copy the key
- [ ] Jellyfin → Dashboard → Libraries → **Add Media Library** → type *Home Videos and Photos* (or *Mixed*), name `Filler`, folder `/media/filler`. This makes filler searchable, though ErsatzTV reads it directly too.
- [ ] ErsatzTV (`http://10.6.9.20:8409`) → **Media Sources → Jellyfin** → address `http://127.0.0.1:8096`, the API key → **Save** → tick the Movies and TV libraries → **Sync**. Both containers mount the pool at `/media`, so the file paths Jellyfin reports are paths ErsatzTV can open.
- [ ] ErsatzTV → **Media Sources → Local** → add a library of type *Other Videos* → folder `/media/filler` → **Scan**

**2. Hardware transcoding** (ErsatzTV transcodes every channel while someone watches it)

- [ ] ErsatzTV → **Settings → FFmpeg Profiles** → edit the default → Hardware acceleration **VAAPI**, driver **iHD**, device `/dev/dri/renderD128`, video format **H.264** (plays everywhere), 1080p. ⚠️ Verify: if VAAPI errors on your build, try **QSV** with the same device.

**3. Build a channel**

| Step | Where in ErsatzTV | What to do |
|---|---|---|
| Content | **Lists → Collections / Smart Collections / Playlists** | A collection is "all of this show" or "these 40 movies"; a smart collection is a saved search (e.g. `genre:comedy`); a playlist is a fixed order you choose, mixing shows and movies |
| Commercial breaks | **Lists → Filler Presets** → Add | Kind **Pre-roll** (before each episode, i.e. between episodes), Mode **Count 1**, Collection = the `filler` library. For realistic TV timing add a **Pad** preset too: pads each episode out to the next 30-minute mark with filler. |
| Schedule | **Schedules** → Add | Add items (collections or playlists), playback order (chronological, shuffle, random), and the filler presets above |
| Channel | **Channels** → Add | Number, name, logo, FFmpeg profile from step 2, streaming mode **MPEG-TS** |
| Playout | **Playouts** → Add | Channel + schedule → **Build**. Rebuild after big schedule changes. |

**4. Hand the channels to Jellyfin**

- [ ] In ErsatzTV, the top-right buttons copy the **M3U** and **XMLTV** links. Replace the host part with `127.0.0.1:8409`; they look like `http://127.0.0.1:8409/iptv/channels.m3u` and `http://127.0.0.1:8409/iptv/xmltv.xml`. ⚠️ Verify the paths against what the buttons give you.
- [ ] Jellyfin → Dashboard → **Live TV** → Tuner Devices **+** → type **M3U Tuner** → paste the M3U link → Save
- [ ] Same page → TV Guide Data Providers **+** → **XMLTV** → paste the XMLTV link → Save → **Refresh Guide Data**
- [ ] Jellyfin web → **Live TV** → the channel plays, and the guide shows what's on now and next
- [ ] From outside (phone on cellular, `tv.elysidrome.com`): the same channel plays. Remote viewers watch through Jellyfin; ErsatzTV stays LAN-only.

Movie pre-rolls (the Local Intros plugin) and breaks between episodes **outside** Live TV are separate pieces; see [06-tv-breaks-plugin.md](06-tv-breaks-plugin.md).

### 3.8b Web arcade: RomM + EmulatorJS

RomM serves the browser arcade at `arcade.elysidrome.com`. The game runs in the player's browser (EmulatorJS), so the SGIN only serves files. It reads `/srv/storage/pool/roms`, the same folder the cabinet's LaunchBox uses as `R:\` (part 4).

- [ ] First visit to `http://10.6.9.20:8080` → the setup wizard creates the admin user
- [ ] Optional but recommended: a free metadata key (IGDB/Twitch, ScreenScraper or SteamGridDB) for covers and names. Add it as `Environment=` lines in `romm.container` per RomM's docs, then `systemctl --user daemon-reload && systemctl --user restart romm`.
- [ ] RomM → **Scan** → each `roms/<platform>` folder shows as a platform
- [ ] BIOS files: RomM → the platform → **Firmware** → upload. For systems that need several files, zip them together first.
- [ ] Netplay (play together in the browser): create `/srv/stream/romm/config/config.yml` with

  ```yaml
  emulatorjs:
    netplay:
      enabled: true
  ```

  then restart romm. Players connect to each other directly (WebRTC). Friends outside your house usually also need a TURN relay; RomM's EmulatorJS page lists free options under `ice_servers`.
- [ ] One user per player (RomM → Administration → Users), so each person's saves and states are their own
- The browser and the cabinet share ROMs, not saves: RetroArch's saves live on the cabinet, EmulatorJS's in RomM. Browser netplay and RetroArch netplay can't join each other's games.


## 3.9 Pi-hole #2 (as eels)

```bash
curl -sSL https://install.pi-hole.net | sudo bash
sudo pihole setpassword
sudo pihole-FTL --config dns.upstreams '["10.6.9.1"]'
sudo pihole-FTL --config dns.listeningMode ALL      # answer WireGuard clients too; nftables limits who can reach :53
# copy misc.dnsmasq_lines and dns.hosts exactly as on pihole-1 (part 2)
```

- [ ] OPNsense DHCP: DNS servers → `10.6.9.3`, `10.6.9.20`

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
PBSDISK=dock1a        # the drive with the most free space that is NOT holding your only copy of anything irreplaceable
sudo proxmox-backup-manager datastore create store1 /srv/storage/disks/$PBSDISK/pbs
sudo proxmox-backup-manager user create pve@pbs --password "$(openssl rand -base64 24 | tee /dev/stderr)"   # store it
sudo proxmox-backup-manager acl update /datastore/store1 DatastoreBackup --auth-id pve@pbs
sudo proxmox-backup-manager cert info | grep Fingerprint
```

- [ ] Keyring URL and checksum match the PBS install docs (checked Oct 2026)
- [ ] PBS owns `/srv/storage/disks/<drive>/pbs` from here on. It sits outside the pool, so the pool `chown` in 3.5 never touches it. Never `chown -R /srv/storage`.

## Done when

- [ ] `https://10.6.9.20:8007` (PBS), `:9090` (Cockpit), `:8096` Jellyfin plays a 4K HEVC file with transcoding showing `(hw)`
- [ ] `\\elysidrome-stream\media` opens from a desktop
