# 3. Set up SGIN (cobra-stream, Debian 13, 10.6.9.20)

**Result:** the SGIN runs Debian 13 bare metal and serves all storage (Samba), the media apps (one rootless Podman pod), Pi-hole #2 and Proxmox Backup Server.

🔌 The SGIN has **no built-in Ethernet**. Its network is a USB gigabit adapter (a TP-Link with an ASIX AX88179 chip, `0b95:1790`; not the Latitude's RTL8153 WAN adapter from part 1) plugged into the powered hub, with a cable from the adapter to your switch, cobra-switch **port 2** (behind OPNsense, part 2.12), for the whole part. **The hub stays plugged into the SGIN the whole time, but unplug every drive from the hub until "Storage" (3.4)**, so the Debian installer can only see the internal SSD and can't touch a data drive. Keep the SGIN's lid **open** until 3.3a; before that, closing it puts the laptop to sleep.

**The SGIN's ports (SGIN X15, Celeron N5095):**

| Port | Speed (`lsusb -t`) | Used for |
|---|---|---|
| USB-C | `10000M` root, the **only** USB 3 port | The powered hub. Everything else (the network adapter and every drive) plugs into the hub |
| USB-A ×2 | `480M`, USB 2.0 only | The installer stick in 3.2; otherwise spare. Never the network adapter or a pool drive |

The network adapter has to sit on the hub because the USB-A ports would cap it at about 300 Mb/s. A USB-C splitter or dock wouldn't help: it's just another hub on the same port. The cost is one shared point of failure, covered in 3.4 under "The powered hub".

**Where you work from:** the install (3.2) happens at the SGIN's own keyboard and screen. Everything after that is SSH and browser work from a desktop that is **wired to the switch** (or a laptop on `cobra` Wi-Fi, part 2.10b, or on WireGuard, part 2.8). A PC on Xfinity Wi-Fi can't reach `10.6.9.x` at all (part 2.10a), so it can't SSH in, open the web pages or map the shares.

**This part replaces your old server.** The SGIN gets wiped and reinstalled, so the old server's sites go offline here and come back under the new names in part 5. Plan to do parts 3 and 5 close together.

- [ ] Copy anything you need off the SGIN's internal disk (configs, databases, compose files). The USB drives aren't touched; they're unplugged during the install.
- [ ] Today the SGIN is `10.6.9.200`, set on the box itself (Cockpit at `https://10.6.9.200:9090`). The reinstall wipes that setting, and from 3.2 on it's `10.6.9.20`. Part 2.4 forwarded ports to `.200` and part 2.6 may already list the SGIN's MAC. OPNsense allows only one mapping per MAC, so 3.2's last step **changes** that mapping to `.20` rather than adding a second one.

**Redoing part 3 on an SGIN that already ran it?** Do these first, then follow the part as written, with the reinstall notes in 3.4 and 3.10:

- [ ] Save to the desktop or a pool drive: `/srv/stream` (every app's settings and database), `/home/podsvc/.config/containers/systemd` (the Quadlet files, which hold the RomM passwords), `/etc/fstab` (the drive labels and UUIDs), `/etc/samba/smb.conf`, and the RomM `DBPW`/`SECRET` if you kept them. If you ran the apps with the `scripts/podman` scripts, their passwords are podman secrets that the reinstall deletes: copy them out first with `sudo machinectl shell podsvc@ /usr/bin/podman secret inspect --showsecret --format '{{.Name}} {{.SecretData}}' romm-db-password romm-auth-secret icecast-source-password icecast-admin-password icecast-relay-password`. Stop the pod first so the databases are closed: `sudo machinectl shell podsvc@ /usr/bin/systemctl --user stop stream-pod`, then e.g. `sudo tar -C / -czf /srv/storage/disks/wd1/sgin-backup.tgz srv/stream home/podsvc/.config/containers etc/fstab etc/samba/smb.conf`
- [ ] Pi-hole #2 → Settings → Teleporter → **Export** (or just re-import from Pi-hole #1 in 3.9)
- [ ] The data drives keep their files. In 3.4 **don't** run the `wipefs`/`mkfs` lines on them; only add their mount lines back. If one might be damaged, or you're not sure which drive is which, image it first (3.4r)
- [ ] On the desktop, forget the old SSH host key, or SSH refuses with "REMOTE HOST IDENTIFICATION HAS CHANGED": `ssh-keygen -R 10.6.9.20; ssh-keygen -R cobra-stream`

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

- [ ] Back up anything on the SGIN first (see the list above if part 3 ran before)
- [ ] On the desktop: debian.org → **Download** → the small **amd64 netinst** ISO (`debian-13.x.x-amd64-netinst.iso`). Rufus → pick the USB stick and the ISO → **Start** → when Rufus asks how to write it, choose **DD Image mode** → OK (this erases the stick)
- [ ] USB stick into one of the SGIN's USB-A ports; hub on the USB-C port with the network adapter on it and its cable to the switch; charger plugged in. Power on and tap the boot-menu key (F7, F11, F12 or Esc depending on the model; the first screen sometimes names it) → pick the USB stick, preferably its **UEFI:** entry → **Install** (the text installer)
- [ ] If it won't boot the stick: enter the firmware setup (Del or F2), leave Secure Boot as it is (Debian boots with it on), make sure USB boot is enabled, and try again

| Screen | Value |
|---|---|
| Language / location / keyboard | English / yours / American English |
| Primary network interface (only asked if it finds Wi-Fi too) | the **USB adapter**, `enx…` (named from its MAC, e.g. `enx9c69d3b6174b`), not `wlp…`. Its driver is built into the installer, so no firmware is needed |
| Network | Auto (DHCP), it gets `10.6.9.1xx` for now |
| Hostname / Domain | `cobra-stream` / `home.arpa` |
| Root password | **leave blank** and Continue, then blank again to confirm (root is disabled and `eels` gets sudo) |
| User | full name `Eels`, username `eels`, generated password (store it) |
| Clock | your time zone |
| Partitioning method | **Guided - use entire disk** |
| Disk | the internal SSD (the only disk listed, since the drives are unplugged; check the size) |
| Partitioning scheme | **All files in one partition** |
| Write changes? | **Finish partitioning and write changes** → **Yes** |
| Scan extra installation media? | No |
| Mirror | your country → `deb.debian.org` → HTTP proxy: blank |
| Popularity contest | No |
| Software selection | untick **Debian desktop environment** and **GNOME**; tick **SSH server** and **standard system utilities** only (space toggles, Tab to Continue) |
| GRUB (only asked on older BIOS-mode installs) | Yes, on the internal disk, not the USB stick |
| Installation complete | pull the USB stick → Continue |

- [ ] After reboot, log in on the SGIN's screen as `eels` and note its MAC: `ip -br link` (the `enx…` line). It's the USB adapter's MAC: replace the adapter and the `.20` mapping below has to be edited to the new MAC
- [ ] OPNsense → **Firewall → NAT → Port Forward**: delete each rule pointing at `10.6.9.200` (part 2.4) → **Apply**. The old sites stay offline until part 5's gate takes over 443
- [ ] OPNsense DHCP page from part 2.6 (**Services → ISC DHCPv4 → LAN** or **Services → Dnsmasq DNS & DHCP**) → static mappings / hosts: if a row has the SGIN's MAC (at `.200` or `.20`), edit it to IP `10.6.9.20`, hostname `cobra-stream`; otherwise **+** add one. Save → **Apply**
- [ ] On the SGIN: `sudo systemctl restart networking` (or `sudo reboot`)
- [ ] Check on the SGIN's screen: `ip -4 -br a` shows `10.6.9.20/24`
- [ ] From the desktop (PowerShell): `ssh eels@10.6.9.20` → type `yes` to the new host key → the `eels` password

## 3.3 Packages

The Intel media driver (Quick Sync) is in Debian's `non-free` section, which the installer leaves off; it turns on only `main non-free-firmware`. Until `non-free` is on, apt answers *Package 'intel-media-va-driver-non-free' has no installation candidate*. The first block rewrites the package sources outright, so it works whichever format the installer wrote (the old one-line `/etc/apt/sources.list` or the newer `debian.sources`), and saves the old file as `sources.list.bak`.

```bash
. /etc/os-release; echo "$PRETTY_NAME"      # must say Debian GNU/Linux 13 (trixie); anything else, stop here
sudo tee /etc/apt/sources.list.d/debian.sources >/dev/null <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: $VERSION_CODENAME $VERSION_CODENAME-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: $VERSION_CODENAME-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
[ ! -f /etc/apt/sources.list ] || sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak
sudo apt update                                   # no "Failed to fetch" or "Err:" lines
apt-cache policy intel-media-va-driver-non-free   # "Candidate:" shows a version, not (none)
```

- [ ] `apt update` shows `Err:`/`Failed to fetch` → the SGIN can't reach the internet or DNS. Check `ping -c2 deb.debian.org`, fix the network, rerun `sudo apt update`. Installing with old package lists is what gives "no installation candidate" even after the sources are right
- [ ] `Candidate: (none)` → `cat /etc/apt/sources.list.d/*.sources` and check the `Components:` lines both read `main contrib non-free non-free-firmware`

```bash
sudo apt full-upgrade -y
sudo apt install -y intel-microcode firmware-misc-nonfree firmware-intel-graphics intel-media-va-driver-non-free vainfo \
  podman crun slirp4netns passt uidmap fuse-overlayfs samba nftables cockpit curl rsync smartmontools systemd-container \
  intel-gpu-tools unattended-upgrades apt-listchanges needrestart lm-sensors mediainfo htop iotop-c ncdu upower pciutils git
# No firmware-realtek: the SGIN has no PCI Ethernet, and its USB adapter (AX88179) needs no firmware
# Debian 13 moved the Intel GPU firmware (GuC/HuC) out of firmware-misc-nonfree into
# firmware-intel-graphics; without it the i915 driver can't load HuC.
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

- [ ] No `HEVC Main10` lines from vainfo → the media driver isn't installed. No `EncSliceLP` lines → HuC didn't load; recheck `/etc/modprobe.d/i915.conf` and that `firmware-intel-graphics` is installed

Updates, file watching, disk health:

```bash
sudo dpkg-reconfigure -plow unattended-upgrades     # Yes: security updates install themselves daily
printf 'fs.inotify.max_user_instances=1024\nfs.inotify.max_user_watches=524288\n' | sudo tee /etc/sysctl.d/90-inotify.conf
sudo sysctl --system                                # Jellyfin, Kavita, ABS and Navidrome all watch the library as podsvc
sudo systemctl enable --now smartmontools fstrim.timer   # drive health warnings (Debian names it smartmontools; "smartd" is an alias systemctl refuses to enable); weekly TRIM for the internal SSD
```

- Unattended upgrades never reboot on their own. After an upgrade, `needrestart` lists the services it restarted and says when the kernel needs a reboot.
- ⚠️ **Don't install TLP or run `powertop --auto-tune`** on this laptop, whatever laptop guides say. Both turn on USB autosuspend, which drops the hub, the pool's drives **and the network adapter, the SGIN's only network link**. (`powertop` just to look is fine.)

SSH keys (the desktop's key is the one made in part 1.7; if `type` says the file doesn't exist, run `ssh-keygen -t ed25519` first):

- [ ] On the desktop (PowerShell): `type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh eels@10.6.9.20 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"`
- [ ] `ssh eels@10.6.9.20` now logs in without the account password (it may ask for the key's passphrase). Keep this session open
- [ ] On the SGIN, turn password logins off:

```bash
sudo tee /etc/ssh/sshd_config.d/10-cobra.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo sshd -t && sudo systemctl reload ssh
```

- [ ] New PowerShell window: `ssh eels@10.6.9.20` works; `ssh -o PubkeyAuthentication=no eels@10.6.9.20` is refused. Only then close the old session
- [ ] Cockpit: browser → `https://10.6.9.20:9090` → the certificate warning is expected (self-signed): **Advanced → Continue** → log in as `eels` with the account password → click **Turn on administrative access** (top) → enter the password again. Cockpit shows logs, updates, disks and a terminal

## 3.3a Laptop-as-server settings

The SGIN is a laptop. Without this, closing the lid (or an idle timer) suspends it and every share, stream and backup goes down. Same as part 1.8, including its USB network adapter rule, with the SGIN adapter's IDs:

```bash
# Stop USB power-saving from dropping the network adapter (ASIX AX88179 = 0b95:1790, from `lsusb`).
# It's the SGIN's only network link; a hub can't autosuspend while a device on it stays on.
echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0b95", ATTR{idProduct}=="1790", TEST=="power/control", ATTR{power/control}="on"' \
  | sudo tee /etc/udev/rules.d/50-usb-nic-power.rules
sudo udevadm control --reload && sudo udevadm trigger --action=add

# Keep running with the lid closed
sudo mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\n' \
  | sudo tee /etc/systemd/logind.conf.d/10-lid.conf
sudo systemctl restart systemd-logind
# Nothing can suspend or hibernate it
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Blank the built-in screen after 60 s
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 consoleblank=60"/' /etc/default/grub
sudo update-grub

# Battery = built-in UPS: clean power-off at 10 % during a long outage
sudo mkdir -p /etc/UPower/UPower.conf.d
printf '[UPower]\nUsePercentageForPolicy=true\nPercentageLow=25\nPercentageCritical=15\nPercentageAction=10\nCriticalPowerAction=PowerOff\n' \
  | sudo tee /etc/UPower/UPower.conf.d/10-cobra.conf
sudo systemctl restart upower
upower -i $(upower -e | grep BAT) | grep -E 'state|percentage'
```

- [ ] `for d in /sys/bus/usb/devices/*; do [ "$(cat $d/idProduct 2>/dev/null)" = 1790 ] && cat $d/power/control; done` prints `on` (not `auto`)
- [ ] `lsusb -t`: the adapter (`Driver=cdc_ncm` or `ax88179_178a`) sits under the hub on Bus 002 at `5000M`. `480M` means it's on a USB-A port or the hub fell back to USB 2
- [ ] Close the lid; `ping 10.6.9.20` from the desktop keeps answering
- [ ] If your UPower ignores `UPower.conf.d`, put the same lines in `/etc/UPower/UPower.conf`
- [ ] Battery wear: a laptop held at 100 % for years can swell. If `ls /sys/class/power_supply/BAT*/charge_control_end_threshold` finds a file, `echo 80 | sudo tee` that file (it resets at boot; a one-line systemd unit or `@reboot` cron makes it stick). If it doesn't exist, check the battery for bulging every few months
- [ ] `sensors` shows the CPU temperature; with the lid shut it runs warmer, so keep the vents clear

## 3.4 Storage

🔌 Plug the storage drives into the hub now (the SGIN's own USB-A ports are USB 2.0, see the port table at the top of this part): both WD external drives, and the dual-bay dock with its disks. The second dock gets added the same way later (see "Adding a drive later"). **Drives that hold files you want to keep, or that might be damaged (wd1): do 3.4r ("Recover wd1 onto the Seagate 24 TB") before anything else**, with only that drive and the Seagate plugged in.

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

### Safe option first: a drive that holds files (wd1)

⚠️ **Before any format line below touches a drive that holds files you want, and before any `fsck` or `mount -a` on one that may be damaged, image it first.** For wd1 (the WD 6 TB Elements Desktop), that and the full recovery are in **3.4r, "Recover wd1 onto the Seagate 24 TB"**, right after this section. Do 3.4r first, with only wd1 and the Seagate plugged in, and come back here once its files are recovered and checked.

**Reinstalling, and the drives were set up here before?** Skip the `wipefs`/`parted`/`mkfs` lines: those erase the drive. `lsblk` shows each one's old label (`wd1`, `dock1a`…); for each, run only the `L=…; U=…`, `mkdir`/`chattr` and `echo … | sudo tee -a /etc/fstab` lines with its partition, then carry on at "Then mount everything". The pool block, the `mkdir` lines and 3.5's `chown` are safe to run again.

**Empty drive, or one you've copied off first** (ext4 is the most reliable choice on Linux). ⚠️ This **erases** the drive. Name it by its by-id path, never `/dev/sdX`, and check it's the one you mean before the `wipefs` line:

```bash
D=/dev/disk/by-id/usb-XXXXXXXX-0:0                          # whole-disk entry from: ls -l /dev/disk/by-id/ | grep -v part
sudo smartctl -i -d sat $D | grep -E 'Model|Serial'         # the model and serial of the drive you mean to erase
lsblk -o NAME,SIZE,FSTYPE,LABEL $D                          # an FSTYPE or LABEL here means it holds a filesystem: if it has files you want, image it first (3.4r)
sudo wipefs -a $D && sudo parted -s $D mklabel gpt mkpart data ext4 0% 100%
sleep 3                                                     # let udev create $D-part1
sudo mkfs.ext4 -L wd1 -m 0 -E nodiscard $D-part1            # -m 0: no root reserve on a data drive; nodiscard: a mistake stays recoverable
L=wd1; U=$(sudo blkid -s UUID -o value $D-part1)
sudo mkdir -p /srv/storage/disks/$L && sudo chattr +i /srv/storage/disks/$L   # empty mount point can't be written to
echo "UUID=$U /srv/storage/disks/$L ext4 defaults,noatime,nofail,x-systemd.device-timeout=15 0 2" | sudo tee -a /etc/fstab
```

**Drive that already holds files in NTFS** (keep it as it is):

```bash
L=wd2; U=$(sudo blkid -s UUID -o value /dev/sdY1)
sudo mkdir -p /srv/storage/disks/$L && sudo chattr +i /srv/storage/disks/$L
echo "UUID=$U /srv/storage/disks/$L ntfs-3g uid=0,gid=$(getent group media | cut -d: -f3),umask=002,noatime,nofail,x-systemd.device-timeout=15 0 0" | sudo tee -a /etc/fstab
```

`chattr +i` locks the **empty** folder under each mount. If a drive is missing at boot (`nofail` lets the SGIN boot anyway), nothing can write into that folder by mistake and fill the system SSD; PBS and the pool just report the drive as missing. The mounted drive itself is unaffected.

Then mount everything and give each drive its `library` folder. On a drive that already has files, move them into `library` (a move on the same drive is instant):

```bash
sudo systemctl daemon-reload && sudo mount -a && df -h /srv/storage/disks/*
for d in /srv/storage/disks/*; do sudo mkdir -p "$d/library"; done
# drive with existing files, e.g.:  sudo mv /srv/storage/disks/wd2/Movies /srv/storage/disks/wd2/library/movies
```

The pool:

```bash
sudo mkdir -p /srv/storage/pool
# Writes (or rewrites) the pool's fstab line. It waits for every drive mounted so far,
# so at boot no drive is missing from the pool. Re-run it whenever you add a drive.
OPTS=defaults,allow_other,use_ino,cache.files=off,dropcacheonclose=true,category.create=mfs,moveonenospc=true,minfreespace=20G,fsname=pool,nofail
for d in /srv/storage/disks/*; do OPTS="$OPTS,x-systemd.after=$(systemd-escape --path --suffix=mount "$d")"; done
sudo sed -i '\#[[:space:]]/srv/storage/pool[[:space:]]#d' /etc/fstab
echo "/srv/storage/disks/*/library /srv/storage/pool fuse.mergerfs $OPTS 0 0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/pool && df -h /srv/storage/pool
```

- `category.create=mfs`: each new file goes to the drive with the most free space
- `minfreespace=20G`: a drive with less than 20 GB free gets no new files
- `moveonenospc=true`: if a drive fills mid-copy, the file moves to another drive instead of failing

Folder layout (made once, on the pool): `movies tv music/eels music/rachel books audiobooks comics roms filler youtube scans backups art`.

- `filler`: short videos for TV breaks (ErsatzTV filler and the between-episodes plugin)
- `youtube`: MeTube saves here from the gate (part 5)
- `scans`: drop documents here from any machine and Paperless on the gate picks them up (part 5)
- `backups`: machines that keep files only on themselves (the cabinet's saves, part 4.5) copy them here, so the vault backup covers them
- `art`: pictures for the station's landing pages (`art/movies`, `albums`, `books`, `comics`, `gaming`), served by eo-art on the gate (part 5.4)

```bash
sudo mkdir -p /srv/storage/pool/{movies,tv,music/eels,music/rachel,books,audiobooks,comics,roms,filler,youtube,scans,backups,art/{movies,albums,books,comics,gaming}}
```

- [ ] `df -h /srv/storage/pool` shows the combined size of all drives
- [ ] Reboot with one drive unplugged: the SGIN still boots, the pool still mounts with the other drives

### USB drives on Linux: two things to check

- **Link resets.** Some USB-to-SATA chips misbehave with the fast UAS driver. If `sudo dmesg | grep -i -E 'uas|reset'` shows repeated resets for a drive, note its ID from `lsusb` (e.g. `152d:0578`), add `usb-storage.quirks=152d:0578:u` to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, `sudo update-grub`, reboot.
- **The powered hub** (9-port USB 3.2 hub, 65 W adapter), on the SGIN's USB-C port, its only USB 3 port. Which hub ports to use:
  - **Bus-powered WD externals → the two 10 Gb/s USB-A 3.2 ports.** These ports draw their power from the hub's 65 W brick.
  - **Network adapter and docks (they have their own power bricks) → the 5 Gb/s USB 3.0 ports.** The adapter only needs 1 Gb/s.
  - **Leave both 45 W PD charging ports empty.** They share the same 65 W budget, and a phone or laptop charging there can starve the drives and make them drop.
  - Speed is fine: the hub links to the SGIN at 5 Gb/s (`5000M`), shared by every drive and the network adapter. One spinning disk moves about 1.5–2 Gb/s, mergerfs reads each file from a single drive, and the network adds at most 1 Gb/s. It only gets busy when several drives copy at full speed at once.
  - One point of failure: if the hub loses power or resets, every drive **and the network** drop at the same moment. The SGIN's USB-A ports are USB 2.0, so there's no second USB 3 port to move anything to. Plug the hub's brick and the SGIN's charger into the UPS's **battery-backed** outlets (many UPS units also have surge-only outlets that go dark in an outage), never a switched strip. A USB reset usually recovers by itself within seconds: the adapter comes back with the same `enx…` name and its `.20` address. If the SGIN stops answering and doesn't come back, use its own keyboard and screen: `sudo reboot`, or unplug the hub's brick for 10 s.
  - [ ] `lsusb -t` shows each drive and the network adapter at `5000M` or `10000M`. `480M` means it fell back to USB 2: reseat the cable at both ends, check it's a USB 3 cable (blue inside the plug, or a wide Micro-B 3.0 plug on WD drives), or try another hub port. To find which disk is slow: `for d in /sys/block/sd?; do echo "${d##*/}: $(readlink -f $d | grep -o 'usb[0-9]')"; done` (`usb1` is the USB 2 side).
  - Bare SATA-to-USB adapter cables (even the ones with their own AC brick) are fine for testing or copying a drive off, but use a dock or enclosure for anything that joins the pool. They often fall back to USB 2 and drop under load.

### Adding a drive later (the second dock)

1. Plug it into a 5 Gb/s port on the hub (there's no free USB 3 port on the SGIN itself) and check `lsusb -t` shows `5000M`. Label and mount it exactly as above (`dock2a`, `dock2b`), and `mkdir` its `library` folder.
2. Re-run the pool block above (the `OPTS=...` lines through `mount`), after `sudo umount /srv/storage/pool`. The `*` picks up the new drive, and the rewritten line makes boot wait for it too.
3. Optional, once there are four or more drives: **SnapRAID** turns one drive into parity for the rest, so a dead drive can be rebuilt. The parity drive must be at least as big as the biggest data drive. ⚠️ Decide when you know the sizes; it's a separate short setup.

## 3.4r Recover wd1 onto the Seagate 24 TB (maximum safety)

**Result:** every file that can be saved from wd1 (the WD 6 TB Elements Desktop) sits on the Seagate Expansion Desktop 24 TB, checked against checksums. wd1 itself is never written to until you decide, at the very end, that it can be wiped and refilled.

**Why it can work.** The format block in 3.4 (`wipefs`, `parted`, `mkfs.ext4`) writes a new, empty filesystem index over the old one, but it doesn't erase the file contents. The method below rebuilds the old index from what's still on the disk. It was tested on a practice disk with exactly this accident, and again with stage B's exact command lines on Debian's e2fsprogs: 57 of 60 files came back byte-for-byte, with their names, in `lost+found`. The files lost were the ones under the new filesystem's own metadata. The full background, with the reasons behind each flag, is in [Ext4 drive recovery plan + backup drive pick](https://claude.ai/artifact/V8Zmd8TybMABKAGyTvMwex).

**What you need:** the Seagate (new, about 21.8 TB usable: wd1's 6 TB image, dock1a's 1 TB image and every recovered file all fit), and about a day: roughly 11 h of imaging, 1–3 h of repair, then copying.

### The rules (read them twice)

1. **Never write to wd1.** No `mount`, `mount -a`, `fsck`, `mkfs`, testdisk "Write" or Windows "Initialize/Format" prompt on the original. It is set read-only in the kernel (stage A), and every repair happens on a **throwaway overlay over an image of it** (stage B).
2. **Address drives by `/dev/disk/by-id/…`, never `/dev/sdX`.** The `sdX` letters change whenever a drive or the hub replugs. A wrong letter is the most likely way this accident happened.
3. **Image the whole disk (`$D`), never just the partition (`$D-part1`)**, so nothing outside the partition table can be lost.
4. **Every `mkfs`/`mke2fs` gets `-E nodiscard`.** Without it, the format tells the drive to throw blocks away, and on a drive that honours that, anything in them is gone for good. The repair in stage B fails without it.
5. **Only the drive being rescued and the Seagate are plugged in**, both on the **hub's USB 3 ports** (5 or 10 Gb/s), never the SGIN's own USB-A ports (USB 2.0: the 6 TB image would take two days). Every other data drive comes off the hub. The network adapter stays.
6. **Every long command runs inside `tmux`**, so a dropped SSH session doesn't stop it.
7. **Stay the `eels` user and put `sudo` in front of each command. Never `sudo su`, `sudo -i` or `su -`.** `$D`, `$N`, `$P` and `$T` live only in the shell where you set them. A root shell starts with all of them empty, so `ddrescue $D /mnt/rescue/wd1.img /mnt/rescue/wd1.map` quietly becomes `ddrescue /mnt/rescue/wd1.img /mnt/rescue/wd1.map`, which copies the image over the map file. That has already happened once. The same goes for a new tmux window or a fresh SSH login: set the variables again, and run the `[ -b … ]` check before using them.
8. **Each "Only if it printed `OK`" means exactly that.** On `STOP`, stop and work out which drive is which before typing anything else.
9. **Keep the original and the image until the files are checked**, both drives' files, and a second copy of the irreplaceable folders exists (stage C). Stage E is the only step that erases wd1, and it starts with a decision only you make.

**dock1a** (the WD Blue 1 TB in dock bay A), if 3.4 formatted it too: the same stages, with `dock1a` in place of `wd1` in every file name and the `-L` label, in dock bay A with bay B **empty**. Its image takes about 2 hours, so the recovery plan does it **first**, as a rehearsal of the whole procedure on a smaller drive. If wd1's SMART check (A4) shows a failing drive, do wd1 first instead.

### Stage A: freeze, identify, image

**A1. Tools, and a tmux session.** From the desktop: `ssh eels@10.6.9.20`, then:

```bash
# gddrescue = GNU ddrescue (the imager); dmsetup builds the throwaway overlay in stage B;
# testdisk is only for a lost partition table (B0); e2fsprogs has mke2fs, e2fsck, dumpe2fs
sudo apt install -y tmux smartmontools gddrescue testdisk e2fsprogs dmsetup rsync
tmux new -s rescue        # if SSH drops: ssh back in, then  tmux attach -t rescue
```

**A2. Freeze.** Stop everything that could write to a data drive, and keep boot from mounting them. On a first install nothing is mounted yet, and these lines do nothing harmful:

```bash
sudo machinectl shell podsvc@ /usr/bin/systemctl --user stop stream-pod 2>/dev/null   # media apps (3.8), if they exist yet
sudo systemctl stop smbd 2>/dev/null                                                   # Samba shares (3.6), if set up yet
sudo umount /srv/storage/pool 2>/dev/null; sudo umount /srv/storage/disks/* 2>/dev/null
sudo cp /etc/fstab /etc/fstab.before-rescue                                  # the file to restore from later
sudo sed -i -E 's@^([^#].*/srv/storage/)@# RESCUE \1@' /etc/fstab           # comments out every drive line and the pool line
sudo systemctl daemon-reload
findmnt | grep /srv/storage        # must print nothing
```

**A3. Plug in only wd1 and the Seagate.** 🔌 Unplug every other data drive from the hub. wd1 and the Seagate both have their own power bricks: plug each into the UPS's battery-backed outlets, and each USB cable into one of the hub's **5 or 10 Gb/s data ports** (not a 45 W PD charging port).

```bash
lsusb -t     # wd1 and the Seagate (Driver=uas or usb-storage) under the hub at 5000M or 10000M; 480M = reseat or another hub port
```

**A4. Give wd1 a name that can't move, make it read-only, check its health:**

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL,SERIAL                 # wd1 = ~5.5T, WD Elements; the Seagate = ~21.8T
ls -l /dev/disk/by-id/ | grep -v part | grep usb             # the whole-disk entries (no -part1 on the end)
D=/dev/disk/by-id/usb-WD_Elements_XXXX_XXXXXXXXXXXX-0:0      # paste wd1's whole-disk entry here
sudo smartctl -i -d sat $D | grep -E 'Model|Serial|Capacity' # must be the WD 6 TB (a WD60… model), not the Seagate. Write the serial down
sudo blockdev --setro $D $D-part1                            # kernel-level read-only, until a replug or reboot
sudo blockdev --getro $D                                     # must print 1
sudo smartctl -H -A -d sat $D | grep -E 'result|Realloc|Pending|Uncorrect'   # non-zero Realloc/Pending/Uncorrect = failing: image now, nothing else
```

- [ ] If wd1 drops off USB, or after any replug or reboot: set `D=` again and rerun the `--setro` line **before anything else**. Read-only doesn't survive a replug.
- [ ] `$D-part1` doesn't exist? The partition table is gone too. Image anyway (it's the whole disk), and do B0 before B1.

**A5. Record the filesystem's details** (read-only). **Screenshot this output** and keep it: B2 needs `Inode count` and `Block count`, and `Last mount time` / `Mount count` say how much of the old index is likely still there:

```bash
sudo dumpe2fs -h $D-part1 2>/dev/null | grep -E 'volume name|UUID|created|Last mount time|Mount count|Inode count|Block count|Block size|Filesystem features'
```

| `Last mount time` / `Mount count` | What it means | What to expect |
|---|---|---|
| `n/a` / `0` | The new filesystem was never mounted, so the old index is intact | Most files back with names and folders |
| A time, mounted even briefly | Any read-write mount of the new filesystem starts ext4's lazy inode-table init, which zeroes the old index in the background. On a test disk, a 1-second mount left 0 of 192 files recoverable by name. On a USB hard drive the zeroing is throttled, so the loss grows with time mounted (roughly an hour per 1 TB) | Names may be largely lost. Still do stage B (some may survive), but expect to need stage D (photorec) for most files |
| Mounted for hours or days | Most of the old index is zeroed | Mostly stage D: contents back, names lost |

**A6. Check the Seagate and prepare it.** This is the **only** format in stages A–D, and it erases the **Seagate**. New Seagates come with a few factory files (Seagate's installer and a "Start Here" page). Look before erasing:

```bash
N=/dev/disk/by-id/usb-Seagate_Expansion_HDD_XXXXXXXXXXXX-0:0   # paste the Seagate's whole-disk entry here
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL,SERIAL $N                # must say ~21.8T and Seagate
sudo mkdir -p /mnt/look && sudo mount -o ro $N-part2 /mnt/look 2>/dev/null || sudo mount -o ro $N-part1 /mnt/look
ls -la /mnt/look; sudo du -sh /mnt/look; sudo umount /mnt/look # only Seagate's own files, a few MB? Then it's safe to erase
# (if neither partition mounts, lsblk's FSTYPE column above shows what's there; blank = nothing to lose)
[ "$(readlink -f $N)" != "$(readlink -f $D)" ] && [ $(sudo blockdev --getsize64 $N) -gt 23000000000000 ] && echo OK || echo STOP
```

⚠️ If `ls` shows **anything of yours** on the Seagate, stop: copy it off first. Only if the check printed `OK`:

```bash
sudo wipefs -a $N && sudo parted -s $N mklabel gpt mkpart rescue ext4 0% 100%   # new partition table, on the Seagate only
sleep 3                                                                          # let udev create $N-part1
sudo mkfs.ext4 -L rescue -m 0 -E nodiscard $N-part1                              # -m 0: no root reserve; nodiscard: rule 4
sudo mkdir -p /mnt/rescue && sudo mount $N-part1 /mnt/rescue && df -h /mnt/rescue   # ~22T free
```

The Seagate stays mounted at `/mnt/rescue` by hand. Don't add it to fstab, so it never joins the pool by mistake.

**A7. Image the whole of wd1** (`$D`, not `$D-part1`). A fast first pass copies everything that reads cleanly; the second goes back three times over any spot that didn't. First check that the variables are still set in **this** shell (rule 7). Run this before **every** `ddrescue` line, including after a reconnect:

```bash
echo "D=$D"; [ -b "$D" ] && [ "$(sudo blockdev --getro $D)" = 1 ] && [ -d /mnt/rescue ] && mountpoint -q /mnt/rescue && echo OK || echo STOP
#   OK   = $D is wd1's block device, still read-only, and the Seagate is mounted at /mnt/rescue
#   STOP = set D= again (A4), rerun --setro, remount the Seagate (A6's last line), then check again
```

Only if it printed `OK`:

```bash
sudo ddrescue -n  $D /mnt/rescue/wd1.img /mnt/rescue/wd1.map   # pass 1: no scraping, the bulk of the drive (~11 h)
sudo ddrescue -r3 $D /mnt/rescue/wd1.img /mnt/rescue/wd1.map   # pass 2: retry bad areas up to 3 times (minutes on a healthy drive)
```

Detach with **Ctrl+B, then D**, and check back later (`tmux attach -t rescue`). It's done when it reports `pct rescued: 100%` (or as close as the drive allows) and `bad areas: 0`. If wd1 drops off USB mid-copy: replug it, set `D=` and rerun `--setro` (A4), run the `[ -b "$D" ]` check above until it prints `OK`, then rerun the **same** `ddrescue` line. The `.map` file makes it continue where it stopped. Never delete the `.map`.

**A8. Check the image and lock it:**

```bash
sudo ddrescuelog -t /mnt/rescue/wd1.map                        # "rescued" ~6.0 TB, "bad areas" 0 (or very few)
sudo blockdev --getsize64 $D; stat -c %s /mnt/rescue/wd1.img   # the same number twice: the image is the whole disk
L=$(sudo losetup -r -fP --show /mnt/rescue/wd1.img); P=${L}p1; ls -l $P   # attach the image READ-ONLY; its partition = $P
sudo dumpe2fs -h $P 2>/dev/null | grep -E 'UUID|created|Inode count|Block count'   # matches A5's screenshot
sudo chattr +i /mnt/rescue/wd1.img /mnt/rescue/wd1.map         # nothing (not even root, by mistake) can change or delete them now
```

- [ ] `${L}p1` doesn't appear: the partition starts at the usual 1 MiB, so attach it by offset instead: `sudo losetup -d $L; P=$(sudo losetup -r -f --show -o 1048576 /mnt/rescue/wd1.img)`

**A9. Set wd1 aside, untouched.** Leave the image attached (stage B uses `$P`). Unplug **wd1** (not the Seagate), stick a label on it, *ORIGINAL, do not format*, and put it somewhere safe. From here everything works on the image. Unplugging it also makes it impossible to point a command at it by mistake.

### Stage B: rebuild the old index, on a throwaway overlay

The overlay is a thin layer on top of the image partition. Every write lands in a small `try.cow` file and the image is only read, so a wrong attempt costs a minute (run `mkov` again) instead of another 11-hour image.

**B0. Only if `$D-part1` was missing in A4** (otherwise skip to B1). testdisk finds the old partition inside the image file; its "Write" changes only the image, so unlock it first and lock it again after:

```bash
sudo losetup -d $L; sudo chattr -i /mnt/rescue/wd1.img
sudo testdisk /mnt/rescue/wd1.img    # Proceed → EFI GPT → Analyse → Quick Search (then Deeper Search if empty) →
                                     # the "Linux filesys. data" entry the size of the drive → Enter → Write → Y → Quit
sudo chattr +i /mnt/rescue/wd1.img
L=$(sudo losetup -r -fP --show /mnt/rescue/wd1.img); P=${L}p1; ls -l $P
sudo dumpe2fs -h $P 2>/dev/null | grep -E 'Inode count|Block count'   # use these in B2 if A5 had none
```

**B1. Build the overlay:**

```bash
# mkov: (re)builds a fresh overlay. Writes go to /mnt/rescue/try.cow; the image partition $P is only read.
mkov() { sudo umount /mnt/old 2>/dev/null; sudo dmsetup remove try 2>/dev/null; sudo losetup -j /mnt/rescue/try.cow -O NAME -n | xargs -r sudo losetup -d
  sudo rm -f /mnt/rescue/try.cow; sudo truncate -s 50G /mnt/rescue/try.cow    # sparse: uses only what's written
  local c=$(sudo losetup -f --show /mnt/rescue/try.cow)
  echo "0 $(sudo blockdev --getsz $P) snapshot $P $c P 8" | sudo dmsetup create try; }
mkov; T=/dev/mapper/try; ls -l $T          # run mkov again any time to throw everything away and start fresh
sudo mkdir -p /mnt/old && sudo mount -o ro,noload $T /mnt/old && ls /mnt/old; sudo umount /mnt/old   # just an empty lost+found: as expected
```

- [ ] `dmsetup create` fails (no device-mapper)? Don't work on the image itself. Make a working copy instead, about 10 hours: `sudo cp --sparse=always /mnt/rescue/wd1.img /mnt/rescue/wd1-work.img`, attach it **without** `-r` (`W=$(sudo losetup -fP --show /mnt/rescue/wd1-work.img); T=${W}p1`), and use that `$T` below. To start over, delete the copy and make a new one. The locked `wd1.img` stays pristine either way.

**B2. Dry run.** `mke2fs -n` only prints, it writes nothing. Put in the two numbers from A5's screenshot:

```bash
IC=<Inode count from A5>; BC=<Block count from A5>        # YOUR two numbers from the screenshot, digits only
sudo mke2fs -n -t ext4 -b 4096 -N $IC $T $BC              # "Creating filesystem with $BC 4k blocks and $IC inodes": same numbers
```

**B3. Rebuild the superblocks onto the overlay.** `-S` rewrites only the superblocks and group descriptors and leaves the old inode tables (the old index) in place. Type it exactly; it asks "Proceed anyway?": answer `y`:

```bash
[ -b "$T" ] && [ -n "$IC" ] && [ -n "$BC" ] && echo OK || echo STOP     # T, IC and BC set in this shell (rule 7)
sudo mke2fs -S -t ext4 -L wd1 -m 0 -b 4096 -N $IC -E nodiscard -O ^has_journal,^metadata_csum $T $BC
```

This works as written with Debian 13's e2fsprogs defaults: mke2fs drops the `orphan_file` and `metadata_csum_seed` features on its own when `metadata_csum` is turned off, so there's nothing to add.

| Flag | Why it's there (from the tests) |
|---|---|
| `-S` | Without it, the old index is wiped instead of reused. A plain `e2fsck` alone found nothing: 0 files |
| `-E nodiscard` | Without it, mke2fs discards the blocks. In the test that destroyed 83 % of the data |
| `-O ^has_journal` | With the journal left on, e2fsck refuses to start (the old journal's checksums don't match) |
| `-O ^metadata_csum` | With checksums left on, e2fsck deletes the old files as "corrupt": 7 of 192 came back instead of 190 |
| `-N $IC … $BC` | The same inode and block counts as the old filesystem, so the rebuilt layout lines up with the old index |

**B4. Let e2fsck rebuild the rest, still on the overlay.** Thousands of `Fix? yes` and `Connect to /lost+found? yes` lines are normal. The log is kept on the Seagate:

```bash
sudo e2fsck -fy -C0 $T 2>&1 | tee /mnt/rescue/wd1-fsck.log | tail -5
sudo e2fsck -fn $T >/dev/null 2>&1 && echo "clean" || echo "run the e2fsck -fy line once more"
```

**B5. Look, read-only:**

```bash
sudo mount -o ro $T /mnt/old && sudo du -sh /mnt/old                  # close to what wd1 used to hold?
sudo ls /mnt/old/lost+found | head -50                                # #12345-style names: your old folders
sudo find /mnt/old/lost+found -maxdepth 2 | head -100                 # inside each one, the real names are back
```

The new format replaced the root folder, so your old folders show up in `lost+found` as `#12345` names. Everything **inside** them keeps its real names. Open each one, work out what it is (Movies, Music, Photos…), and write a list: `#12345 = Music`. The names get fixed when you copy them off, in stage C.

- [ ] It looks wrong (`du` far below what wd1 held, or folders full of garbage): `mkov` and redo B2–B5. Check you typed A5's numbers, or try the counts from `sudo dumpe2fs -h $P` (the image's own superblock). Still nothing? Go to stage D.
- [ ] **Never put this rebuilt filesystem back into service.** It has no journal and no checksums. It's for copying files off, once.

### Stage C: copy off and check, irreplaceable folders first

Copy one folder per run, so each run is small enough to check before the next. Order by what you can't get again:

1. Photos, scans, backups, personal documents
2. `music/eels`, `music/rachel`, audiobooks, books, comics
3. ROMs and game saves
4. Movies and TV last (they can be re-ripped or re-downloaded)

For each folder (the `#12345` and `Music` here are examples from your B5 list):

```bash
sudo mkdir -p /mnt/rescue/files/wd1
# -a keeps dates and permissions, -H hard links, -A ACLs, -X extended attributes
sudo rsync -aHAX --info=progress2 "/mnt/old/lost+found/#12345/" /mnt/rescue/files/wd1/Music/
# Check: re-read both sides and compare the CONTENTS byte for byte (-c). Must list nothing.
sudo rsync -aHAXcn --itemize-changes "/mnt/old/lost+found/#12345/" /mnt/rescue/files/wd1/Music/
# Keep a checksum list next to the copy; stage E checks against it again
(cd /mnt/rescue/files/wd1/Music && sudo find . -type f -print0 | sudo xargs -0 sha256sum) | sudo tee /mnt/rescue/files/wd1/Music.sha256 >/dev/null
```

- [ ] After each folder, spot-check it from a desktop: open a few photos, play a few songs. (Read-only share for this, if you want one: Samba isn't running during the rescue, so use `scp eels@10.6.9.20:/mnt/rescue/files/wd1/Photos/… .`)
- [ ] Every folder from your B5 list is copied, its `rsync -c` check listed nothing, and it has a `.sha256` list

**Second copy of the irreplaceable folders (items 1 and 2).** Before any original gets erased, those folders should sit on two drives. The recovery plan uses the empty OptiPlex 4 TB in dock bay B, once both damaged drives are through stage C and unplugged. The size check refuses anything that isn't about 4 TB, so it can't hit the Seagate:

```bash
C=/dev/disk/by-id/usb-XXXXXXXX-0:1      # the 4 TB's whole-disk entry (bay B)
N=/dev/disk/by-id/usb-Seagate_Expansion_HDD_XXXXXXXXXXXX-0:0   # the Seagate's, set again in case this is a new session
sudo smartctl -i -d sat $C | grep -E 'Model|Serial'
S=$(sudo blockdev --getsize64 $C); [ $S -gt 3900000000000 ] && [ $S -lt 4100000000000 ] && [ -e "$N" ] && [ "$(readlink -f $C)" != "$(readlink -f $N)" ] && echo OK || echo STOP
```

Only if it printed `OK` (and it holds nothing you want; check with `lsblk -o NAME,FSTYPE,LABEL $C`):

```bash
sudo wipefs -a $C && sudo parted -s $C mklabel gpt mkpart copy2 ext4 0% 100%
sleep 3; sudo mkfs.ext4 -L copy2 -m 0 -E nodiscard $C-part1
sudo mkdir -p /mnt/copy2 && sudo mount $C-part1 /mnt/copy2
sudo rsync -aHAX --info=progress2 /mnt/rescue/files/wd1/Photos/ /mnt/copy2/wd1/Photos/          # one folder per run
sudo rsync -aHAXcn --itemize-changes /mnt/rescue/files/wd1/Photos/ /mnt/copy2/wd1/Photos/       # must list nothing
```

### Stage D: photorec, only for what stage C didn't bring back

photorec ignores the filesystem and finds files by their contents. It gets the contents back, but most files come back without names or folders (`f123456.jpg`), and large fragmented videos may be damaged. It works on the image, never the original, and writes to its own folder on the Seagate:

```bash
sudo mkdir -p /mnt/rescue/photorec/wd1
sudo photorec /log /d /mnt/rescue/photorec/wd1/ /mnt/rescue/wd1.img
#   pick the partition → File Opt (untick types you don't need) → Search → [ ext2/ext3/ext4 ] → Free
#   (Free = only the space the rebuilt filesystem doesn't account for; choose Whole if stage B found nothing)
```

Sorting what it finds: photos by date with `exiftool '-Directory<DateTimeOriginal' -d /mnt/rescue/sorted/photos/%Y/%m -r /mnt/rescue/photorec/wd1/`; music by its tags with MusicBrainz Picard or `beet import`; video with FileBot, or Jellyfin's Identify once it's back in the library.

### Stage E: put wd1 back into service (the only step that erases it)

⚠️ **Decision point: yours alone.** Go on only when **all** of these are true. Until then, wd1 stays unplugged and untouched, and that costs nothing:

- [ ] Stage C is finished for wd1 (and dock1a, if it was formatted too): every folder copied, every `rsync -c` check empty, every `.sha256` list made
- [ ] The irreplaceable folders also sit on the second drive (`/mnt/copy2`)
- [ ] You've looked at the copies yourself and you're happy nothing else is missing

**E1. Identify wd1 the long way** (plug it in alone with the Seagate, on the hub):

```bash
D=/dev/disk/by-id/usb-WD_Elements_XXXX_XXXXXXXXXXXX-0:0      # wd1's whole-disk entry again (ls -l /dev/disk/by-id/ | grep -v part)
N=/dev/disk/by-id/usb-Seagate_Expansion_HDD_XXXXXXXXXXXX-0:0   # the Seagate's, so the check below can tell them apart
sudo smartctl -i -d sat $D | grep -E 'Model|Serial'          # the serial you wrote down in A4
S=$(sudo blockdev --getsize64 $D); echo $S                   # about 6001175126016 (6.0 TB)
[ -e "$N" ] && [ "$(readlink -f $D)" != "$(readlink -f $N)" ] && [ $S -gt 5900000000000 ] && [ $S -lt 6100000000000 ] && echo OK || echo STOP
```

For dock1a, the size range in that check is `950000000000` to `1050000000000` (1.0 TB) instead.

**E2. Erase and reformat it** (only if E1 printed `OK` and the serial matches):

```bash
sudo blockdev --setrw $D                                     # undo stage A's read-only (only if it's still set)
sudo wipefs -a $D && sudo parted -s $D mklabel gpt mkpart data ext4 0% 100%
sleep 3; sudo mkfs.ext4 -L wd1 -m 0 -E nodiscard $D-part1
# fstab: the new filesystem has a NEW UUID, so remove the old wd1 line and add a new one
sudo sed -i '\#[[:space:]]/srv/storage/disks/wd1[[:space:]]#d' /etc/fstab
L=wd1; U=$(sudo blkid -s UUID -o value $D-part1)
sudo chattr -i /srv/storage/disks/$L 2>/dev/null; sudo mkdir -p /srv/storage/disks/$L && sudo chattr +i /srv/storage/disks/$L
echo "UUID=$U /srv/storage/disks/$L ext4 defaults,noatime,nofail,x-systemd.device-timeout=15 0 2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/disks/$L && df -h /srv/storage/disks/$L
```

**E3. Copy the files back and check them against stage C's lists:**

```bash
sudo mkdir -p /srv/storage/disks/wd1/library
sudo rsync -aHAX --info=progress2 /mnt/rescue/files/wd1/Music/ /srv/storage/disks/wd1/library/music/   # per folder, to its library name
(cd /srv/storage/disks/wd1/library/music && sudo sha256sum --quiet -c /mnt/rescue/files/wd1/Music.sha256)   # prints nothing = every file matches
```

**E4. Back to normal:**

```bash
sudo sed -i -E 's@^# RESCUE @@' /etc/fstab               # un-comment the other drives and the pool line from A2
grep -E 'srv/storage' /etc/fstab                          # wd1: only the NEW line from E2; one pool line
sudo systemctl daemon-reload && sudo mount -a && df -h /srv/storage/disks/* /srv/storage/pool
sudo chown -R podsvc:media /srv/storage/disks/wd1/library && sudo chmod -R g+rwX /srv/storage/disks/wd1/library   # 3.5's permissions
```

Then plug the other drives back in, and carry on with 3.4 where you left it (or 3.5 onward).

- [ ] Only now, once **both** drives are back and checked: `sudo umount /mnt/old; sudo dmsetup remove try; sudo losetup -D`. Keep the images on the Seagate for now; there's room
- [ ] **Keep the Seagate's copy for a few weeks** of the pool working normally. After that, `sudo chattr -i` the images, delete them, and the Seagate becomes the `vault` backup drive (part 5.6)

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
| Windows desktops (the-box, the-spire) | File Explorer → Map network drive (log in as `eels`) | `\\cobra-stream\media`, `\scans`, `\roms` |
| Cobra1 laptop on `cobra` Wi-Fi (2.10b) | Same as the desktops | `\\cobra-stream\media` |
| Cabinet | `R:` mapped in part 4 (log in as `arcade`) | `\\cobra-stream\roms` |
| Laptop/phone on WireGuard | Same as the desktops; short names resolve through Pi-hole (part 2) | `\\cobra-stream\media` |
| Gate VM | CIFS mount in part 5 (log in as `gate`) | `/srv/storage/pool` |
| Containers on the SGIN | Bind mounts in 3.8 | `/media/...` |
| Phones on Wi-Fi | Xfinity Wi-Fi is outside the firewall by design; use WireGuard there too | — |

Map the share on a Windows desktop (wired, or on WireGuard):

- [ ] File Explorer → **This PC** → **⋯** (or the Computer tab) → **Map network drive** → Drive `M:` → Folder `\\cobra-stream\media` → tick **Reconnect at sign-in** and **Connect using different credentials** → Finish → user `cobra-stream\eels`, the Samba password you just set → tick **Remember my credentials**
- [ ] If `\\cobra-stream` isn't found, use `\\10.6.9.20\media` (the name needs the desktop's DNS to be Pi-hole, part 2.9). If Windows says you're already connected with other credentials (from the old server), Control Panel → **Credential Manager** → Windows Credentials → remove the old `cobra-stream`/`10.6.9.200` entries, then try again
- [ ] Windows: `\\cobra-stream\media` opens and you can create and delete a test folder

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
sudo nft list ruleset | grep dport                  # the port list above
```

- [ ] Keep your SSH session open and open a **new** one: `ssh eels@10.6.9.20` still works. If it doesn't, the old session can fix the file (`sudo nano /etc/nftables.conf`, then `sudo systemctl restart nftables`)
- Part 8 adds the radio's port `8000` to this list; any new app on the SGIN needs its port added here too

## 3.8 Media pod

Run as podsvc: `sudo machinectl shell podsvc@` (a full login session, needed for `systemctl --user`). `exit` to leave.

**Reinstalling with a backup of `/srv/stream`?** Restore it before anything starts, as eels: `sudo tar -C / -xzpf /srv/storage/disks/wd1/sgin-backup.tgz srv/stream`. Then, as podsvc, either restore the saved Quadlet files into `~/.config/containers/systemd` and skip the `cat` lines below, or run the block as written but set `DBPW`/`SECRET` to the old values instead of new random ones (RomM's database already uses the old password). With the scripts: `ROMM_DB_PASSWORD=<old> ROMM_AUTH_SECRET=<old> ./romm.sh` the first time. If an app then says `Permission denied`, see the last bullet of this section.

**Prefer plain `podman run` scripts?** [`scripts/podman`](../../scripts/podman/README.md) has one script per app (`sgin/up-all.sh` runs them all) that builds the same `stream` pod with the same images, ports and folders. Use either the scripts or the Quadlet files below for an app, not both; the scripts' README explains how to switch.

```bash
mkdir -p ~/.config/containers/systemd /srv/stream/{jellyfin/config,jellyfin/cache,ersatztv,abs/config,abs/metadata,kavita,navidrome,romm/resources,romm/assets,romm/config,romm/redis,romm/db}
cd ~/.config/containers/systemd
DBPW=$(openssl rand -hex 24); SECRET=$(openssl rand -hex 32)
echo "RomM DBPW=$DBPW SECRET=$SECRET"   # copy both into your password manager now

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
Tmpfs=/transcode:rw,size=2g,mode=1777
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
Environment=ND_SESSIONTIMEOUT=8h ND_MUSICFOLDER=/media/music/eels ND_REVERSEPROXYWHITELIST=10.6.9.10/32
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

- [ ] Image names (Oct 2026): ErsatzTV is published as `ghcr.io/ersatztv/legacy` (its GitHub repo ErsatzTV/legacy builds that image; the older `ghcr.io/ersatztv/ersatztv` name still exists but isn't what that repo publishes); RomM is `rommapp/romm`. RomM expects `roms/<platform>/` folders. `Tmpfs=/transcode` keeps ErsatzTV's live segments in RAM instead of wearing the SSD
- [ ] Don't put `:Z` on `/srv/storage/pool` mounts (shared with Samba)
- [ ] Jellyfin → Dashboard → Playback → Transcoding: **Intel QuickSync (QSV)**, device `/dev/dri/renderD128`, enable H.264/HEVC/HEVC 10-bit/VP9 decode (**not AV1**: Jasper Lake has no AV1 decode), hardware encoding on, **Low-Power H.264/HEVC encoder on**, tone mapping on **and VPP tone mapping on**. Leave the transcode path on the internal SSD (the default). Users: hidden, Quick Connect off. If some movies stutter, see 3.8c
- [ ] Jellyfin → Dashboard → Networking → **Known proxies: `10.6.9.10`**. Without it, every remote viewer looks like a LAN client coming from the gate, so remote bitrate limits and per-IP logs don't work
- [ ] Navidrome: the first library is Eels' (`ND_MUSICFOLDER`); add a second library `/media/music/rachel` in the UI, then one user each with only their library
- `ND_REVERSEPROXYWHITELIST=10.6.9.10/32`: Navidrome trusts the `Remote-User` header from the gate only, so someone the station's sign-in (part 5.4) already let in isn't asked again. Give each person the same username here as in Authelia's `users.yml`.
- [ ] Each app: create its admin user now. Until you do, the first person to open the page becomes admin. First-run screens, all from the desktop's browser:

| App | First visit | Then |
|---|---|---|
| Jellyfin `:8096` | Wizard: language → admin user `eels` + password → **Add Media Library**: *Movies* → folder `/media/movies`; again for *Shows* → `/media/tv` (music and books live in Navidrome and ABS, so skip them here) → metadata language/country → **Allow remote connections: on**, **automatic port mapping: off** → Finish → log in | The Transcoding and Networking settings below |
| Audiobookshelf `:13378` | Create the **root** user + password | Settings → **Libraries → Add**: name `Audiobooks`, type **Book**, folder `/media/audiobooks`; again `Books` → `/media/books` for e-books. Settings → Users → one user each |
| Kavita `:5000` | Register the admin account (email can be anything local) | ⚙ → **Libraries → Add**: name `Comics`, type **Comic**, folder `/media/comics` → Save → **Scan**. Users → Invite (or add) one per person |
| Navidrome `:4533` | Create the admin user + password | It scans `ND_MUSICFOLDER` on its own; the library step below |
| ErsatzTV `:8409` | No login screen; it stays LAN/VPN-only because the gate never publishes it | 3.8a |
| RomM `:8080` | Setup wizard → admin user | 3.8b |
- [ ] If one container keeps restarting with `Permission denied` in `journalctl --user -u <name>`: that image switches to a non-root user inside, so its files must belong to that user. Find it with `podman exec <name> id` (often `1000`), add `UserNS=keep-id:uid=1000,gid=1000` under `[Container]` in its `.container` file, then `systemctl --user daemon-reload && systemctl --user restart <name>`. Your `podsvc` then *is* that user inside the container, so the folders it owns become writable.

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

- [ ] In ErsatzTV, the top-right buttons copy the **M3U** and **XMLTV** links. Replace the host part with `127.0.0.1:8409`; they are `http://127.0.0.1:8409/iptv/channels.m3u` and `http://127.0.0.1:8409/iptv/xmltv.xml`.
- [ ] Jellyfin → Dashboard → **Live TV** → Tuner Devices **+** → type **M3U Tuner** → paste the M3U link → Save
- [ ] Same page → TV Guide Data Providers **+** → **XMLTV** → paste the XMLTV link → Save → **Refresh Guide Data**
- [ ] Jellyfin web → **Live TV** → the channel plays, and the guide shows what's on now and next
- [ ] From outside (phone on cellular, `tv.songofeo.com`): the same channel plays. Remote viewers watch through Jellyfin; ErsatzTV stays LAN-only.

Movie pre-rolls (the Local Intros plugin) and breaks between episodes **outside** Live TV are separate pieces; see [part 6](06-tv-breaks-plugin.md).

### 3.8b Web arcade: RomM + EmulatorJS

RomM serves the browser arcade at `arcade.songofeo.com`. The game runs in the player's browser (EmulatorJS), so the SGIN only serves files. It reads `/srv/storage/pool/roms`, the same folder the cabinet's LaunchBox uses as `R:\` (part 4).

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

### 3.8c If some movies stutter

File size is rarely the cause: a 4 GB two-hour movie averages about 4.5 Mbps. The big files are usually **HEVC 10-bit or HDR, often with PGS/ASS subtitles**, and when a client can't play those natively Jellyfin transcodes them. The stutter comes from that transcode.

1. Play the movie, then Jellyfin → **Dashboard → Activity** (or ⚙ → Playback Info in the web player): note the play method and the **reason** for transcoding.
2. Fix by reason, most common first:

| Reason | Fix |
|---|---|
| Subtitle codec not supported | Subtitle burn-in. Pick an SRT track, or set the user's subtitle mode to *Smart* with image subtitles off by default |
| Video codec not supported | Use a client that plays HEVC 10-bit itself: the Android TV / Fire TV app, Jellyfin Media Player, Swiftfin or Infuse; Chrome or Edge rather than Firefox |
| Bitrate exceeds limit | Client app → Maximum streaming quality → *Auto*/highest; for VPN viewing, Dashboard → Playback → Streaming → raise the remote limit |

3. If it still transcodes, check the newest `FFmpeg.Transcode-…log` (Dashboard → Logs): the encoder must be `h264_qsv`/`hevc_qsv`. `libx264`/`libx265` means the CPU is doing it; recheck 3.3's `vainfo` and the Transcoding settings above. Inside the container: `podman exec jellyfin /usr/lib/jellyfin-ffmpeg/vainfo | grep -i hevc`. Live view while a movie plays: `sudo intel_gpu_top` on the SGIN shows the **Video** engine busy; if it sits at 0 % while `htop` shows ffmpeg eating the CPU, the transcode is in software.
4. Smooth but jerky pans: a 24 fps film on a 60 Hz TV. Turn on match frame rate in the TV app.

## 3.9 Pi-hole #2 (as eels)

```bash
curl -sSL https://install.pi-hole.net | sudo bash
```

The installer asks a few questions in a text window (arrow keys, Space to tick, Enter for OK):

| Screen | Answer |
|---|---|
| Welcome / donation | OK |
| Static IP needed | **Continue**: the address is fixed by the OPNsense mapping from 3.2 |
| Choose an interface (only if it lists several) | the USB adapter, `enx…` |
| Upstream DNS provider | any; the next commands replace it with OPNsense |
| Blocklists (StevenBlack) | Yes |
| Admin web interface / web server (older installers only) | Yes / Yes |
| Query logging | Yes |
| Privacy mode | 0, show everything |

It ends with a password and the address `http://10.6.9.20/admin`. Then:

```bash
sudo pihole setpassword
sudo pihole-FTL --config dns.upstreams '["10.6.9.1"]'
sudo pihole-FTL --config dns.listeningMode ALL      # answer WireGuard clients too; nftables limits who can reach :53
# the same local DNS as cobra-pihole-1 (part 2.9)
sudo pihole-FTL --config misc.dnsmasq_lines '["address=/*.songofeo.com/10.6.9.10","server=/www.songofeo.com/#"]'
sudo pihole-FTL --config dns.hosts '["10.6.9.1 cobra-firewall.home.arpa cobra-firewall","10.6.9.2 cobra-command.home.arpa cobra-command","10.6.9.3 cobra-pihole-1.home.arpa cobra-pihole-1","10.6.9.5 cobra-switch.home.arpa cobra-switch","10.6.9.6 cobra-ap.home.arpa cobra-ap","10.6.9.10 cobra-gate.home.arpa cobra-gate","10.6.9.20 cobra-stream.home.arpa cobra-stream","10.6.9.30 cobra-arcade.home.arpa cobra-arcade"]'
```

- [ ] Blocklists: Pi-hole #1 → Settings → Teleporter → Export, then Pi-hole #2 → Teleporter → Import (repeat after you change lists; part 5.7)
- [ ] From the desktop: `nslookup tv.songofeo.com 10.6.9.20` → `10.6.9.10`, and `nslookup cobra-gate 10.6.9.20` → `10.6.9.10`

- [ ] Web admin: `http://10.6.9.20/admin` → log in with the password you just set
- [ ] OPNsense DHCP page from part 2.6 (**Services → ISC DHCPv4 → LAN**, or **Services → Dnsmasq DNS & DHCP** → DHCP options) → DNS servers: change the second one from `10.6.9.1` to `10.6.9.20`, so the list is `10.6.9.3`, `10.6.9.20` → Save → **Apply**. Machines pick it up at their next lease renewal (on Windows: `ipconfig /renew`)

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
sudo apt update && sudo apt install -y proxmox-backup-server     # if a "Postfix Configuration" screen appears: "Local only", mail name `cobra-stream.home.arpa`
PBSDISK=dock1a        # your label for an ext4 drive (PBS can't use NTFS) with room to spare; part 5.6 adds a second copy on the vault drive
sudo proxmox-backup-manager datastore create store1 /srv/storage/disks/$PBSDISK/pbs
# Reinstall, and that pbs folder already holds backups? Use this instead, which keeps them:
#   sudo proxmox-backup-manager datastore create store1 /srv/storage/disks/$PBSDISK/pbs --reuse-datastore true
sudo proxmox-backup-manager user create pve@pbs --password "$(openssl rand -base64 24 | tee /dev/stderr)"   # store it
sudo proxmox-backup-manager acl update /datastore/store1 DatastoreBackup --auth-id pve@pbs
sudo proxmox-backup-manager cert info | grep Fingerprint                                     # store it; part 5.6 needs it
# Your own login for the web UI (root has no password on this box, so root@pam can't log in)
sudo proxmox-backup-manager user create eels@pam
sudo proxmox-backup-manager acl update / Admin --auth-id eels@pam
```

- [ ] Browser → `https://10.6.9.20:8007` → accept the certificate warning → user `eels`, realm **Linux PAM standard authentication**, the account password → **Datastore → store1** is listed
- [ ] Top right **eels@pam → TFA → Add → TOTP**, same as part 1.7
- [ ] Reinstall: the fingerprint and the `pve@pbs` password are new. If Proxmox already had this PBS (part 5.6), Proxmox UI → **Datacenter → Storage → pbs-stream → Edit** → paste both → OK, and update `/root/pbs.env` on the SGIN when you redo part 5.6's self-backup

- [ ] Keyring URL and checksum match the PBS install docs (checked Oct 2026)
- [ ] PBS owns `/srv/storage/disks/<drive>/pbs` from here on. It sits outside the pool, so the pool `chown` in 3.5 never touches it. Never `chown -R /srv/storage`.

## Done when

- [ ] `https://10.6.9.20:8007` (PBS), `:9090` (Cockpit), `:8096` Jellyfin plays a 4K HEVC file with transcoding showing `(hw)`
- [ ] `\\cobra-stream\media` opens from a desktop
- [ ] `df -h /srv/storage/pool` shows every drive's space combined; a file copied in from a desktop shows up in Jellyfin after a library scan
- [ ] Jellyfin → Live TV plays an ErsatzTV channel, and the guide fills in (3.8a)
- [ ] RomM at `:8080` lists your platforms, and one game starts in the browser (3.8b)
- [ ] `nslookup cobra-stream 10.6.9.20` answers `10.6.9.20` (Pi-hole #2)
- [ ] Lid closed, the SGIN still answers `ping 10.6.9.20` and a stream keeps playing (3.3a)
- [ ] `lsusb -t`: the network adapter and every drive at `5000M` or faster, and the adapter's `power/control` is `on` (3.3a, 3.4)
