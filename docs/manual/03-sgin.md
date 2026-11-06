# 3. Set up SGIN (cobra-stream, Debian 13, 10.6.9.20)

**Result:** the SGIN runs Debian 13 bare metal and serves all storage (Samba), the media apps (one rootless Podman pod), Pi-hole #2 and Proxmox Backup Server.

🔌 The SGIN has **no built-in Ethernet**. Its network is a USB gigabit adapter (a TP-Link with an ASIX AX88179 chip, `0b95:1790`; not the Latitude's RTL8153 WAN adapter from part 1) plugged into the powered hub, with a cable from the adapter to your switch, cobra-switch **port 2** (behind OPNsense, part 2.12), for the whole part. **The hub stays plugged into the SGIN the whole time, but unplug every drive from the hub until "Storage" (3.4)**, so the Debian installer can only see the internal SSD and can't touch a data drive. Keep the SGIN's lid **open** until 3.3a; before that, closing it puts the laptop to sleep.

**The SGIN's ports (SGIN X15, Celeron N5095):**

| Port | Speed (`lsusb -t`) | Used for |
|---|---|---|
| USB-C | `10000M` root, the **only** USB 3 port | The powered hub. Everything else (the network adapter and every drive) plugs into the hub |
| USB-A ×2 | `480M`, USB 2.0 only | The installer stick in 3.2; otherwise spare. Never the network adapter or a data drive |

The network adapter has to sit on the hub because the USB-A ports would cap it at about 300 Mb/s. A USB-C splitter or dock wouldn't help: it's just another hub on the same port. The cost is one shared point of failure, covered in 3.4 under "The powered hub".

**Where you work from:** the install (3.2) happens at the SGIN's own keyboard and screen. Everything after that is SSH and browser work from a desktop that is **wired to the switch** (or a laptop on `cobra` Wi-Fi, part 2.10b, or on WireGuard, part 2.8). A PC on Xfinity Wi-Fi can't reach `10.6.9.x` at all (part 2.10a), so it can't SSH in, open the web pages or map the shares.

**This part replaces your old server.** The SGIN gets wiped and reinstalled, so the old server's sites go offline here and come back under the new names in part 5. Plan to do parts 3 and 5 close together.

- [ ] Copy anything you need off the SGIN's internal disk (configs, databases, compose files). The USB drives aren't touched; they're unplugged during the install.
- [ ] Today the SGIN is `10.6.9.200`, set on the box itself (Cockpit at `https://10.6.9.200:9090`). The reinstall wipes that setting, and from 3.2 on it's `10.6.9.20`. Part 2.4 forwarded ports to `.200` and part 2.6 may already list the SGIN's MAC. OPNsense allows only one mapping per MAC, so 3.2's last step **changes** that mapping to `.20` rather than adding a second one.

**Redoing part 3 on an SGIN that already ran it?** Do these first, then follow the part as written, with the reinstall notes in 3.4 and 3.10:

- [ ] Save to the desktop or a data drive: `/srv/stream` (every app's settings and database), `/home/podsvc/.config/containers/systemd` (the Quadlet files, which hold the RomM passwords), `/etc/fstab` (the drive labels and UUIDs), `/etc/samba/smb.conf`, and the RomM `DBPW`/`SECRET` if you kept them. If you ran the apps with the `scripts/podman` scripts, their passwords are podman secrets that the reinstall deletes: copy them out first with `sudo machinectl shell podsvc@ /usr/bin/podman secret inspect --showsecret --format '{{.Name}} {{.SecretData}}' romm-db-password romm-auth-secret icecast-source-password icecast-admin-password icecast-relay-password`. Stop the pod first so the databases are closed: `sudo machinectl shell podsvc@ /usr/bin/systemctl --user stop stream-pod`, then e.g. `sudo tar -C / -czf /srv/storage/disks/wd1/sgin-backup.tgz srv/stream home/podsvc/.config/containers etc/fstab etc/samba/smb.conf`
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
- ⚠️ **Don't install TLP or run `powertop --auto-tune`** on this laptop, whatever laptop guides say. Both turn on USB autosuspend, which drops the hub, the data drives **and the network adapter, the SGIN's only network link**. (`powertop` just to look is fine.)

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
grep -q consoleblank /etc/default/grub || sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 consoleblank=60"/' /etc/default/grub
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

### Which drive holds what

No RAID, and only one small pool: each drive is mounted on its own, holds its own folders, and you always know where a file lives. Unplug any one drive and the others keep working; any drive can be read on its own in another computer. The one exception is Jellyfin's video: wd1 and wd2 are joined into `video` (below), so movies and shows each look like one folder. **Only wd1 and wd2 are ever pooled.** The dock bays (dock1 now, dock2 later) are plug-and-play drive slots: each bay's drive mounts on its own, and pulling one only takes its own folders away. Never add a dock drive to a pool.

| Drive | Mounted at | Holds |
|---|---|---|
| **wd1** (WD 6 TB Elements) | `/srv/storage/disks/wd1` | `movies`, `series`, `filler`, `pre-rolls` |
| **dock1a** (1 TB, dock bay A) | `/srv/storage/disks/dock1a` | `music/eels`, `music/rachel`, `comedy` (stand-up albums), `sessions` (your recorded podcasts), `audiobooks`, `books`, `comics`, plus the small shared folders `scans`, `backups`, `art` |
| **dock1b** (1 TB, dock bay B) | `/srv/storage/disks/dock1b` | `roms` (the nightly copy from the cabinet, for the web arcade) |
| **wd2** (a folder on the Seagate) | `/srv/storage/disks/wd2` | `movies` and `series` (same layout as wd1, joined with it in `video`), `youtube`. Its files have **no second copy** (they sit on the backup drive itself), so keep it to things you could download again |
| **video** (wd1 + wd2 pooled) | `/srv/storage/disks/video` | wd1 and wd2 seen as one: `video/movies`, `video/series`. Jellyfin uses only this. New files go to **wd1 first** and spill onto wd2 only when wd1 is nearly full |
| **Seagate** (24 TB Expansion) | `/srv/storage/vault` | The backup drive: Proxmox Backup Server's datastores (3.10, 5.6), the 3.4r rescue images, and the `wd2` folder. Mounted **outside** `/srv/storage/disks`, so the backups never show up in a share |

The other WD 6 TB (the old `wd2`) holds personal files and stays on the-box, shared from there; the SGIN doesn't use it.

`/srv/storage/disks` is the one folder everything uses. Samba shares it as `\\cobra-stream\media`, so Windows sees `wd1`, `dock1a`, `dock1b`, `wd2` and `video`, and the apps in 3.8 see the same under `/media`. A path tells you the drive: `/media/wd1/movies` is on wd1. When a drive fills up, move a folder to another drive yourself and point the app at its new place. If a folder ever outgrows its drive, give it a second home (`movies` on wd1 and on a new drive) and add both folders to the app's library; Jellyfin, Navidrome and Audiobookshelf all take several folders per library.

- `filler`: short videos for TV breaks (ErsatzTV filler and the between-episodes plugin, part 6). `pre-rolls`: the movie intros for Local Intros (part 6)
- `youtube`: MeTube saves here from the gate (part 5)
- `scans`: drop documents here from any machine and Paperless on the gate picks them up (part 5)
- `backups`: machines that keep files only on themselves (the cabinet's saves, part 4.5) copy them here, so the vault backup covers them
- `art`: pictures for the station's landing pages (`art/movies`, `albums`, `books`, `comics`, `gaming`), served by eo-art on the gate (part 5.4)

Protection against a dead drive comes from backups (part 5.6), not from the layout: losing one drive loses only that drive's folders, until you restore them.

The OptiPlex's internal WD drive (4 TB, NTFS) stays in the OptiPlex as `D:`. It holds the games, the ROMs' main copy and an extra copy of the irreplaceable folders; see part 4.6. `dock1b/roms` is the copy the cabinet sends each night, so RomM's web arcade keeps working while the cabinet is off or asleep. Spare space on the machines' system drives (the Latitude's NVMe, the SGIN's own SSD) isn't used for the library. Those disks get wiped and reinstalled.

### Set up the drives

```bash
sudo groupadd media                                        # owns the library (users come in 3.5)
sudo apt install -y mergerfs ntfs-3g
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MODEL,SERIAL          # write down every drive
```

For each drive, pick a short label: `wd1` for the external, `dock1a`, `dock1b` for the dock's bays. The Seagate gets its own steps below.

### The dock drives: wipe both and start fresh (no recovery)

The two 1 TB drives in the dock are used as blank space: their old files don't matter. (One of them, the WD Blue `WD10EALX`, went through the same format accident as wd1. Its music is almost all backed up elsewhere, and the ROMs, e-books and audiobooks are backed up in full, so it's wiped and filled again from those backups. Photorec's nameless copy of it, `photorec/dock1a` on the Seagate, can stay there as a last resort until you've restored the music.)

Which drive is which goes by **bay**, not by model: **bay A = dock1a, bay B = dock1b**. The dock reports the same `usb-…Dual_SATA_Bridge_000…` name for both bays, ending in `-0:0` for bay A and `-0:1` for bay B, and often hides the model, so the check below reads the model and serial from the drive itself. Old fstab lines for either bay must be commented out (`# RESCUE …`) or gone, so plugging the dock in mounts nothing. Do one bay at a time:

```bash
BAY=0; L=dock1a          # bay A. For bay B: BAY=1; L=dock1b
D=$(ls /dev/disk/by-id/usb-*Dual_SATA_Bridge_*-0:$BAY); echo "$D -> $(readlink -f $D)"
sudo smartctl -i -d sat $D | grep -E 'Model|Serial'         # write down the serial; it's the drive you're about to erase
sudo smartctl -H -A -d sat $D | grep -E 'result|Reallocated_Sector|Current_Pending|Offline_Uncorrectable'
S=$(sudo blockdev --getsize64 $D); echo $S                  # about 1000204886016 (1.0 TB)
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS $D         # nothing mounted
[ -n "$D" ] && [ $(echo "$D" | wc -l) -eq 1 ] && [ $S -gt 950000000000 ] && [ $S -lt 1050000000000 ] \
  && [ -z "$(lsblk -nro MOUNTPOINTS $D | tr -d '[:space:]')" ] && echo OK || echo STOP
```

- Health: `PASSED`, and the raw values (last column) of `Reallocated_Sector_Ct`, `Current_Pending_Sector` and `Offline_Uncorrectable` all `0` or close to it. A drive that fails here, or that throws `Input/output error` when you read it (`sudo fdisk -l $D`), isn't worth filling: swap in another drive.
- Only if it printed `OK`. ⚠️ This erases the drive in that bay:

```bash
sudo wipefs -a $D && sudo parted -s $D mklabel gpt mkpart data ext4 0% 100%
sleep 3; sudo mkfs.ext4 -F -L $L -m 0 $D-part1
sudo sed -i "\#[[:space:]]/srv/storage/disks/$L[[:space:]]#d" /etc/fstab    # the bay's old line, commented or not
U=$(sudo blkid -s UUID -o value $D-part1); echo $U
sudo chattr -i /srv/storage/disks/$L 2>/dev/null; sudo mkdir -p /srv/storage/disks/$L && sudo chattr +i /srv/storage/disks/$L
echo "UUID=$U /srv/storage/disks/$L ext4 defaults,noatime,nofail,x-systemd.device-timeout=15 0 2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/disks/$L && df -h /srv/storage/disks/$L
```

Then make their folders (below, "Then mount everything") and copy your backups in from Windows through `\\cobra-stream\media\dock1a` and `\dock1b` once Samba is up (3.6).

### Safe option first: a drive that holds files (wd1)

⚠️ **Before any format line below touches a drive that holds files you want, and before any `fsck` or `mount -a` on one that may be damaged, image it first.** For wd1 (the WD 6 TB Elements Desktop), that and the full recovery are in **3.4r, "Recover wd1 onto the Seagate 24 TB"**, right after this section. Do 3.4r first, with only wd1 and the Seagate plugged in, and come back here once its files are recovered and checked.

**Reinstalling, and the drives were set up here before?** Skip the `wipefs`/`parted`/`mkfs` lines: those erase the drive. `lsblk` shows each one's old label (`wd1`, `dock1a`…); for each, run only the `L=…; U=…`, `mkdir`/`chattr` and `echo … | sudo tee -a /etc/fstab` lines with its partition, then carry on at "Then mount everything". The folder `mkdir` lines and 3.5's `chown` are safe to run again.

**Empty drive, or one you've copied off first** (ext4 is the most reliable choice on Linux). ⚠️ This **erases** the drive. Name it by its by-id path, never `/dev/sdX`, and check it's the one you mean before the `wipefs` line.

Pick the drive by its `ata-` name: it carries the drive's own model and serial. The `usb-` names come from the enclosure, and a dual-bay dock like the Sabrent reports one serial (`000000…`) for **both** bays, so its two entries differ only in `-0:0`/`-0:1`. Match on the model and let the shell fill in the rest; never type a serial from a screenshot:

```bash
ls -l /dev/disk/by-id/ | grep -v part | grep -E 'ata-|usb-'  # every whole-disk entry, with the sdX it points to now
MODEL=PUT_MODEL_HERE      # the part after "ata-" up to the next "-", e.g. WDC_WD40EFRX. Left as-is, the check below says STOP
D=$(ls /dev/disk/by-id/ata-$MODEL-* 2>/dev/null | grep -v part); echo "$D -> $(readlink -f $D)"
sudo smartctl -i -d sat $D | grep -E 'Model|Serial'         # the model and serial of the drive you mean to erase
lsblk -o NAME,SIZE,FSTYPE,LABEL $D
[ -n "$D" ] && [ $(echo "$D" | wc -l) -eq 1 ] && [ -z "$(lsblk -no FSTYPE,LABEL $D | tr -d '[:space:]')" ] && echo OK || echo STOP   # STOP = no drive, two drives, or it already holds a filesystem
```

Only if it printed `OK`. `STOP` means no drive matched, more than one did, or the drive already holds a filesystem. If there's any chance it has files you want, image it first (3.4r). A brand-new drive often ships pre-formatted (exFAT or NTFS, with the maker's software on it): look at what's there the way 3.4r A6 does for the Seagate, and only when it's nothing of yours, run the `wipefs` line anyway. This check is the one that would have stopped the accident 3.4r recovers from.

```bash
sudo wipefs -a $D && sudo parted -s $D mklabel gpt mkpart data ext4 0% 100%
sleep 3                                                     # let udev create $D-part1
sudo mkfs.ext4 -L wd1 -m 0 -E nodiscard $D-part1            # -m 0: no root reserve on a data drive; nodiscard: a mistake stays recoverable
L=wd1; U=$(sudo blkid -s UUID -o value $D-part1)
sudo mkdir -p /srv/storage/disks/$L && sudo chattr +i /srv/storage/disks/$L   # empty mount point can't be written to
echo "UUID=$U /srv/storage/disks/$L ext4 defaults,noatime,nofail,x-systemd.device-timeout=15 0 2" | sudo tee -a /etc/fstab
```

**Drive that already holds files in NTFS** (keep it as it is):

```bash
L=ntfs1; U=$(sudo blkid -s UUID -o value /dev/sdY1)      # any free label; none of today's drives is NTFS
sudo mkdir -p /srv/storage/disks/$L && sudo chattr +i /srv/storage/disks/$L
echo "UUID=$U /srv/storage/disks/$L ntfs-3g uid=0,gid=$(getent group media | cut -d: -f3),umask=002,noatime,nofail,x-systemd.device-timeout=15 0 0" | sudo tee -a /etc/fstab
```

`chattr +i` locks the **empty** folder under each mount. If a drive is missing at boot (`nofail` lets the SGIN boot anyway), nothing can write into that folder by mistake and fill the system SSD; PBS, Samba and the apps just see an empty folder. The mounted drive itself is unaffected.

⚠️ **Once a drive has an fstab line, plugging it in mounts it.** systemd turns each fstab line into a mount unit tied to that UUID, and starts it whenever the drive appears, with no command typed. The first mount of a new ext4 filesystem also starts the kernel's **lazy init**, which zeroes every inode table in the background (about an hour per TB). On an empty drive that's harmless. On a drive formatted by mistake, it wipes the old file index. That's what happened to dock1a on Oct 22: formatted at 13:24, plugged back in at 13:38, and lazy init had zeroed all 7,453 groups by 14:38. Its files could only come back without names (3.4r stage D). If you ever suspect a format hit the wrong drive, **unplug it at once** and start 3.4r before plugging it in again.

Then mount everything and make each drive's folders (the table above). On a drive that already has files, move them into those folders (a move on the same drive is instant):

```bash
sudo systemctl daemon-reload && sudo mount -a && df -h /srv/storage/disks/*
for d in wd1 dock1a dock1b wd2; do mountpoint -q /srv/storage/disks/$d && echo "$d mounted" || echo "$d MISSING: plug it in (wd2: the Seagate, below) before the next line"; done
sudo mkdir -p /srv/storage/disks/wd1/{movies,series,filler,pre-rolls} \
  /srv/storage/disks/dock1a/{music/eels,music/rachel,comedy,sessions,audiobooks,books,comics,scans,backups,art/{movies,albums,books,comics,gaming}} \
  /srv/storage/disks/dock1b/roms \
  /srv/storage/disks/wd2/{movies,series,youtube}
# wd1 kept its old TV folder name, series; wd2 uses the same name so the pool joins them
```

Only run the `mkdir` line once every drive printed `mounted`. On a missing drive it fails (the empty mount point is locked), which is what you want.

- [ ] `df -h /srv/storage/disks/*` lists wd1, dock1a and dock1b with their own sizes, and wd2 with the Seagate's
- [ ] Reboot with one drive unplugged: the SGIN still boots and the others still mount

### The Seagate: backup drive, with a `wd2` folder

The Seagate 24 TB is first the rescue drive (3.4r, mounted by hand at `/mnt/rescue`). Once 3.4r is finished, it becomes the backup drive and gets a permanent home at `/srv/storage/vault`, with one folder, `wd2`, lent out as extra space. It's a folder, not a partition: nothing gets shrunk, and `wd2` can use as much or as little of the drive as you need. Its catch: a file that lives only in `wd2` has no second copy, because it sits on the backup drive itself.

```bash
N=$(ls /dev/disk/by-id/usb-Seagate_Expansion_HDD_*-0:0); echo "$N -> $(readlink -f $N)"
U=$(sudo blkid -s UUID -o value $N-part1); echo $U                        # the Seagate's filesystem (the one 3.4r A6 made)
sudo umount /mnt/rescue 2>/dev/null                                       # done with the rescue? Its files stay on the drive
sudo sed -i '\#[[:space:]]/mnt/rescue[[:space:]]#d' /etc/fstab            # any old line for it
sudo mkdir -p /srv/storage/vault && sudo chattr +i /srv/storage/vault
echo "UUID=$U /srv/storage/vault ext4 defaults,noatime,nofail,x-systemd.device-timeout=15 0 2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/vault && df -h /srv/storage/vault
# wd2: the Seagate's wd2 folder, shown at /srv/storage/disks/wd2 like a drive
sudo mkdir -p /srv/storage/vault/wd2 /srv/storage/disks/wd2 && sudo chattr +i /srv/storage/disks/wd2
echo "/srv/storage/vault/wd2 /srv/storage/disks/wd2 none bind,nofail,x-systemd.requires-mounts-for=/srv/storage/vault 0 0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/disks/wd2 && findmnt /srv/storage/disks/wd2
```

- `bind`: the same folder seen at a second path. Samba and the apps see `wd2` next to the real drives; the rest of the Seagate (the backups, the rescue images) stays out of every share.
- [ ] `findmnt /srv/storage/disks/wd2` shows `/srv/storage/vault/wd2` as its source
- [ ] Keep `wd2` well short of full: `df -h /srv/storage/vault` shows the whole Seagate, backups included, and the backups need room to grow

### The video pool (wd1 + wd2, for Jellyfin)

**mergerfs** shows wd1 and wd2 as one folder, `/srv/storage/disks/video`. It's only a view: every file still sits whole on one drive, either drive still reads fine on its own, and `\\cobra-stream\media\wd1` and `\wd2` still show exactly what's on each. Copy new movies and shows into `video` and the pool picks the drive; copy into `wd1` or `wd2` directly when you want to choose.

Do this after both wd1 and the Seagate's `wd2` folder are mounted (above):

```bash
sudo mkdir -p /srv/storage/disks/video && sudo chattr +i /srv/storage/disks/video
OPTS=defaults,allow_other,use_ino,cache.files=off,dropcacheonclose=true,category.create=ff,minfreespace=100G,moveonenospc=true,fsname=video,nofail
OPTS=$OPTS,x-systemd.requires-mounts-for=/srv/storage/disks/wd1,x-systemd.requires-mounts-for=/srv/storage/disks/wd2
echo "/srv/storage/disks/wd1:/srv/storage/disks/wd2 /srv/storage/disks/video fuse.mergerfs $OPTS 0 0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/disks/video && ls /srv/storage/disks/video
```

- `wd1:wd2` + `category.create=ff`: a new file goes to the **first** drive in that list with room, so wd1 fills first and only the overflow lands on wd2, which has no second copy. `minfreespace=100G` is the "nearly full" point; `moveonenospc` moves a file to wd2 if wd1 fills mid-copy.
- `requires-mounts-for`: at boot, the pool waits for both drives, so it never starts with one missing.
- [ ] `ls /srv/storage/disks/video` shows `movies`, `series`, `filler`, `pre-rolls`, `youtube`, everything from both drives
- [ ] Copy a test file into `\\cobra-stream\media\video\movies`: it shows up in `wd1\movies`

### USB drives on Linux: two things to check

- **Link resets.** Some USB-to-SATA chips misbehave with the fast UAS driver. If `sudo dmesg | grep -i -E 'uas|reset'` shows repeated resets for a drive, note its ID from `lsusb` (e.g. `152d:0578`), add `usb-storage.quirks=152d:0578:u` to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, `sudo update-grub`, reboot.
- **The powered hub** (9-port USB 3.2 hub, 65 W adapter), on the SGIN's USB-C port, its only USB 3 port. Which hub ports to use:
  - The plan in use (intpw 9-in-1 hub): **Sabrent dock (dock1a + dock1b) → the USB-C 3.2 data port**, with its own USB-C cable (no adapter tip); **Seagate and wd1 → the two USB-A 3.2 ports**; **network adapter → a USB-A 3.0 port** (it only needs 1 Gb/s); a second dock → another USB-A 3.0 port. Avoid USB-C-to-A tips on drives: a cheap one can drop a drive to USB 2 (`480M`). Every drive here has its own power brick, so the hub's brick only powers the hub itself and the adapter.
  - The port labels matter less than they look: every drive and dock here is a 5 Gb/s device, and the whole hub shares one 5 Gb/s link to the SGIN (next point). Any data port works at full speed; just keep data devices off the two charge-only PD ports.
  - **Leave both 45 W PD charging ports empty.** They share the same 65 W budget, and a phone or laptop charging there can starve the drives and make them drop.
  - Speed is fine: the hub links to the SGIN at 5 Gb/s (`5000M`), shared by every drive and the network adapter. One spinning disk moves about 1.5–2 Gb/s, each file is read from the one drive it lives on, and the network adds at most 1 Gb/s. It only gets busy when several drives copy at full speed at once.
  - One point of failure: if the hub loses power or resets, every drive **and the network** drop at the same moment. The SGIN's USB-A ports are USB 2.0, so there's no second USB 3 port to move anything to. Plug the hub's brick and the SGIN's charger into the UPS's **battery-backed** outlets (many UPS units also have surge-only outlets that go dark in an outage), never a switched strip. A USB reset usually recovers by itself within seconds: the adapter comes back with the same `enx…` name and its `.20` address. If the SGIN stops answering and doesn't come back, use its own keyboard and screen: `sudo reboot`, or unplug the hub's brick for 10 s.
  - [ ] `lsusb -t` shows each drive and the network adapter at `5000M` or `10000M`. `480M` means it fell back to USB 2: reseat the cable at both ends, check it's a USB 3 cable (blue inside the plug, or a wide Micro-B 3.0 plug on WD drives), or try another hub port. To find which disk is slow: `for d in /sys/block/sd?; do echo "${d##*/}: $(readlink -f $d | grep -o 'usb[0-9]')"; done` (`usb1` is the USB 2 side).
  - Bare SATA-to-USB adapter cables (even the ones with their own AC brick) are fine for testing or copying a drive off, but use a dock or enclosure for anything that stays plugged in as a data drive. They often fall back to USB 2 and drop under load.

### Adding a drive later (the second dock)

1. Plug it into a 5 Gb/s port on the hub (there's no free USB 3 port on the SGIN itself) and check `lsusb -t` shows `5000M`. Label and mount it exactly as above (`dock2a`, `dock2b`), then make its folders and add a row for it to the table at the top of 3.4. Each bay is its own mount, never part of a pool: that's what keeps the bays plug-and-play.
2. Run 3.5's `chown` loop again. Samba and the apps see it at once as `\\cobra-stream\media\dock2a` and `/media/dock2a` (restart the apps with `systemctl --user restart stream-pod` as podsvc so their containers see the new mount), then add its folders to the app libraries that should use them.
3. Optional, once there are four or more drives: **SnapRAID** turns one drive into parity for the rest, so a dead drive can be rebuilt. The parity drive must be at least as big as the biggest data drive. ⚠️ Decide when you know the sizes; it's a separate short setup.

## 3.4r Recover wd1 onto the Seagate 24 TB (maximum safety)

**Result:** every file that can be saved from wd1 (the WD 6 TB Elements Desktop) sits on the Seagate Expansion Desktop 24 TB, checked against checksums. wd1 itself is never written to until you decide, at the very end, that it can be wiped and refilled.

**Why it can work.** The format block in 3.4 (`wipefs`, `parted`, `mkfs.ext4`) writes a new, empty filesystem index over the old one, but it doesn't erase the file contents. The method below rebuilds the old index from what's still on the disk. It was tested on a practice disk with exactly this accident, and again with stage B's exact command lines on Debian's e2fsprogs: 57 of 60 files came back byte-for-byte, with their names, in `lost+found`. The files lost were the ones under the new filesystem's own metadata. The full background, with the reasons behind each flag, is in [Ext4 drive recovery plan + backup drive pick](https://claude.ai/artifact/V8Zmd8TybMABKAGyTvMwex).

**What you need:** the Seagate (new, about 21.8 TB usable: wd1's 6 TB image, dock1a's 1 TB image and every recovered file all fit), and about a day: roughly 17 h of imaging, 1–3 h of repair, then copying.

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

**The dock drives** aren't recovered on this build: their files are restored from backups instead, and 3.4 wipes them ("The dock drives: wipe both and start fresh"). For reference, a 1 TB drive like the one the accident hit (a WD Blue `WD10EALX`) would go through the same stages, with `dock1a` in place of `wd1` in every file name and the `-L` label, in dock bay A with bay B **empty**. Its image takes about 2 hours, so the recovery plan does it **first**, as a rehearsal of the whole procedure on a smaller drive. If wd1's SMART check (A4) shows a failing drive, do wd1 first instead.

### Stage A: freeze, identify, image

**A1. Tools, and a tmux session.** From the desktop: `ssh eels@10.6.9.20`, then:

```bash
# gddrescue = GNU ddrescue (the imager); dmsetup builds the throwaway overlay in stage B;
# testdisk is only for a lost partition table (B0); e2fsprogs has mke2fs, e2fsck, dumpe2fs
sudo apt install -y tmux smartmontools gddrescue testdisk e2fsprogs dmsetup rsync
tmux new -A -s rescue     # attaches if "rescue" exists, creates it if not. If SSH drops: ssh back in and run it again
```

A line of numbers like `^[[?61;4;6;7;…c` or `]10;rgb:cccc/…` at the prompt as tmux starts, followed by `command not found`, is harmless: it's Windows Terminal answering tmux's question about what it supports, landing in the shell. Nothing runs. `clear` tidies it up, and `echo $TMUX` printing a path proves you're inside tmux.

**A2. Freeze.** Stop everything that could write to a data drive, and keep boot from mounting them. On a first install nothing is mounted yet, and these lines do nothing harmful:

```bash
sudo machinectl shell podsvc@ /usr/bin/systemctl --user stop stream-pod 2>/dev/null   # media apps (3.8), if they exist yet
sudo systemctl stop smbd 2>/dev/null                                                   # Samba shares (3.6), if set up yet
sudo umount /srv/storage/disks/* 2>/dev/null
sudo cp /etc/fstab /etc/fstab.before-rescue                                  # the file to restore from later
sudo sed -i -E 's@^([^#].*/srv/storage/)@# RESCUE \1@' /etc/fstab           # comments out every drive line
sudo systemctl daemon-reload
findmnt | grep /srv/storage        # must print nothing
```

**A3. Plug in only wd1 and the Seagate.** 🔌 Unplug every other data drive from the hub. wd1 and the Seagate both have their own power bricks: plug each into the UPS's battery-backed outlets, and each USB cable into one of the hub's **5 or 10 Gb/s data ports** (not a 45 W PD charging port).

```bash
lsusb -t     # wd1 and the Seagate (Driver=uas or usb-storage) under the hub at 5000M or 10000M; 480M = reseat or another hub port
```

The link speed of each disk, by name (run it again after A4 and A6 set `$D` and `$N`):

```bash
for d in $(lsblk -dno NAME -e7 | grep '^sd'); do p=$(readlink -f /sys/block/$d); while [ "$p" != / ] && [ ! -f $p/speed ]; do p=$(dirname $p); done; echo "$d: $(cat $p/speed 2>/dev/null) Mb/s  $(lsblk -dno SIZE,MODEL /dev/$d)"; done
```

- [ ] Every drive reads `5000` or `10000`. `480` means USB 2.0 somewhere along the path, and a 6 TB image would take several days instead of about 17 hours. The usual culprit is a **USB-C to USB-A adapter**: most small ones carry only the USB 2.0 wires. Use a cable rated 5 or 10 Gbps instead. If you're short of fast ports during the rescue, the network adapter can give up its hub port and sit on one of the SGIN's USB-A ports for now: SSH needs very little, and USB 2.0's ~300 Mb/s is plenty. Move it back afterwards.

**A4. Give wd1 a name that can't move, make it read-only, check its health:**

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL,SERIAL                 # wd1 = ~5.5T, WDC WD60EDAZ; the Seagate = ~21.8T, Expansion HDD
ls -l /dev/disk/by-id/ | grep -v part | grep -E 'ata-|usb-'  # the whole-disk entries (no -part1 on the end)
D=$(ls /dev/disk/by-id/ata-WDC_WD60EDAZ-* | grep -v part); echo "$D -> $(readlink -f $D)"   # wd1
sudo smartctl -i -d sat $D | grep -E 'Model|Serial|Capacity' # must be the WD 6 TB (WD60EDAZ), not the Seagate. Write the serial down
sudo blockdev --setro $D $D-part1                            # kernel-level read-only, until a replug or reboot
sudo blockdev --getro $D $D-part1                            # must print 1 twice
sudo smartctl -H -A -d sat $D | grep -E 'result|Realloc|Pending|Uncorrect'   # non-zero Realloc/Pending/Uncorrect = failing: image now, nothing else
```

- [ ] Why the `ata-` name: it's built from the drive's own model and serial, so it can't point at another drive. The `usb-` names come from the enclosure, and the Sabrent dual-bay dock reports serial `000000…` for both bays. Its entries differ only in `-0:0`/`-0:1`, one character apart. If no `ata-` entry shows up for a drive (some enclosures hide it), use its `usb-` entry and double-check the serial with `smartctl -i`.
- [ ] `ls` matching on the model prefix means you never type a serial. A misread `1`/`I` or `0`/`O` from a screenshot can't happen. If the `echo` prints two paths, two drives of that model are plugged in: unplug the one you aren't rescuing.
- [ ] If wd1 drops off USB, or after any replug, reboot or cable move: rerun the `--setro` and `--getro` lines **before anything else**. Read-only doesn't survive a replug. `$D` itself stays valid, because the by-id path comes back the same.
- [ ] `$D-part1` doesn't exist? The partition table is gone too. Image anyway (it's the whole disk), and do B0 before B1.

**A5. Record the filesystem's details** (read-only). **Screenshot this output** and keep it: B2 needs `Inode count` and `Block count`, and `Last mount time` / `Mount count` say how much of the old index is likely still there:

```bash
sudo dumpe2fs -h $D-part1 2>/dev/null | grep -E 'volume name|UUID|created|Last mount time|Last write time|Mount count|Inode count|Block count|Free blocks|Block size|Lifetime writes|Filesystem features'
```

Then measure how much of the old index the new filesystem has already wiped. The first line takes a few seconds and prints one line:

```bash
echo "groups: $(sudo dumpe2fs $D-part1 2>/dev/null | grep -c '^Group [0-9]')  zeroed: $(sudo dumpe2fs $D-part1 2>/dev/null | grep -c ITABLE_ZEROED)"
# and a direct look at the disk: the inode table of a group near the end, non-zero bytes = something survived there
g=$(( $(sudo dumpe2fs $D-part1 2>/dev/null | grep -c '^Group [0-9]') - 50 )); r=$(sudo dumpe2fs $D-part1 2>/dev/null | grep -A8 "^Group $g:" | grep -o 'Inode table at [0-9]*-[0-9]*' | grep -o '[0-9]*-[0-9]*'); echo "group $g ($r): $(sudo dd if=$D-part1 bs=4096 skip=${r%-*} count=$(( ${r#*-} - ${r%-*} + 1 )) status=none | tr -d '\0' | wc -c) non-zero bytes"
```

| What A5 shows | What it means | What to do |
|---|---|---|
| `Last mount time: n/a`, `Mount count: 0` | The new filesystem was never mounted, so the old index is intact | Stage B: most files back with names and folders |
| Mounted, and `zeroed` well below `groups` | The kernel's **lazy init** started zeroing the old index in the background and was stopped partway (about an hour per TB to finish) | Stage B for what's left, stage D for the rest |
| `zeroed` = `groups`, and the direct look reads `0 non-zero bytes` | The whole old index is gone | Skip stage B. Go to stage D (photorec, **Whole**): contents back, names lost |
| Used space (`Block count` − `Free blocks`, × 4 KiB) well above an empty filesystem's (Inode count × 256 bytes for the inode tables, plus about 1 GiB of journal) | Files were **written** to the new filesystem, over old contents | Expect some files to be damaged or missing even in stage D |

Any read-write mount starts lazy init, even a brief one: on a test disk, a 1-second mount left 0 of 192 files recoverable by name. On a USB hard drive the zeroing is throttled, so the loss grows with time mounted. So if A5 shows any mount at all, still try stage B where the table says so, but expect to need stage D (photorec) for most files.

`Lifetime writes` near the size of the inode tables (Inode count × 256 bytes) is just lazy init. Much more means something wrote files. A `needs_recovery` feature means it was never cleanly unmounted. That's why no plain `mount` may touch it: mounting would replay the journal and write. The rescue only uses `ro,noload` on the overlay.

**dock1a, Oct 25 (for reference):** formatted 13:24, mounted once at 13:38 when it was plugged back in (its fstab line did that, see 3.4), last write 14:38. `zeroed` 7,453 of 7,453, and the direct look read 0 bytes in four groups. Only about 16 GB had been written, all of it the new inode tables and journal. Result: stage D only.

**A6. Check the Seagate and prepare it.** This is the **only** format in stages A–D, and it erases the **Seagate**. New Seagates come with a few factory files (Seagate's installer and a "Start Here" page). Look before erasing:

```bash
N=$(ls /dev/disk/by-id/usb-Seagate_Expansion_HDD_*-0:0); echo "$N -> $(readlink -f $N)"   # finds the Seagate's whole-disk entry
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL,SERIAL $N                # must say ~21.8T and Expansion HDD
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

The Seagate stays mounted at `/mnt/rescue` by hand. Don't add it to fstab, so it never mounts under `/srv/storage/disks` and shows up in the shares by mistake.

**A7. Image the whole of wd1** (`$D`, not `$D-part1`). A fast first pass copies everything that reads cleanly; the second goes back three times over any spot that didn't. First check that the variables are still set in **this** shell (rule 7). Run this before **every** `ddrescue` line, including after a reconnect:

```bash
echo "D=$D"; [ -b "$D" ] && [ "$(sudo blockdev --getro $D)" = 1 ] && [ -d /mnt/rescue ] && mountpoint -q /mnt/rescue && echo OK || echo STOP
#   OK   = $D is wd1's block device, still read-only, and the Seagate is mounted at /mnt/rescue
#   STOP = set D= again (A4), rerun --setro, remount the Seagate (A6's last line), then check again
```

Only if it printed `OK`:

```bash
sudo ddrescue -n  $D /mnt/rescue/wd1.img /mnt/rescue/wd1.map   # pass 1: no scraping, the bulk of the drive (~17 h)
sudo ddrescue -r3 $D /mnt/rescue/wd1.img /mnt/rescue/wd1.map   # pass 2: only if pass 1 left anything unread (see below)
```

**Pass 2 only when pass 1 left something.** Look at pass 1's final screen. If `non-trimmed`, `non-scraped` and `bad-sector` all read `0 B`, `bad areas` reads `0` and `pct rescued` reads `100.00%`, the image is already complete. Pass 2 would find nothing to retry, so skip it and go to A8. Otherwise run pass 2.

**wd1, Oct 26 (for reference):** pass 1 alone finished in 16 h 53 m at an average of 99 MB/s, with every counter at `0` and `100.00%` rescued, so pass 2 was skipped. The rate drops toward the end of the disk (the inner tracks are slower), so the remaining-time estimate runs short in the last hours.

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

The overlay is a thin layer on top of the image partition. Every write lands in a small `try.cow` file and the image is only read, so a wrong attempt costs a minute (run `mkov` again) instead of another 17-hour image.

**Skip this stage** if A5 showed `zeroed` = `groups` and a direct look of `0 non-zero bytes`: there's no old index left for it to rebuild, so go straight to stage D with **Whole**. If you're unsure, run it anyway. On the overlay it costs nothing but time.

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

**B2. Dry run.** `mke2fs -n` only prints, it writes nothing. The first two lines read the inode and block counts from the image itself, so you don't have to type them. Check them against A5's screenshot:

```bash
IC=$(sudo dumpe2fs -h $P 2>/dev/null | awk -F': *' '/^Inode count/{print $2}')
BC=$(sudo dumpe2fs -h $P 2>/dev/null | awk -F': *' '/^Block count/{print $2}')
echo "IC=$IC BC=$BC"                                       # must match A5's screenshot exactly; if either is blank, stop
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
sudo e2fsck -fy -C0 $T 2>&1 | sudo tee /mnt/rescue/wd1-fsck.log | tail -5   # sudo tee: /mnt/rescue is root-owned, a plain tee gets "Permission denied"
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
2. `music/eels`, `music/rachel`, `comedy`, `sessions`, audiobooks, books, comics
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

**Second copy of the irreplaceable folders (items 1 and 2).** Before any original gets erased, those folders should sit on two drives. The second drive is the OptiPlex's 4 TB (`D:`, NTFS), which stays inside the cabinet (part 4.6), so nothing gets formatted for this. The cabinet pulls each folder over SSH while Samba is still off. Windows 11 has `scp` built in.

On the cabinet, plain PowerShell (not Admin), one folder per run (`Photos` is an example from your B5 list):

```powershell
$f = 'Photos'                                    # the folder's name under /mnt/rescue/files/wd1
New-Item -ItemType Directory -Force D:\Cobra-copy\wd1 | Out-Null
# -r folders, -p keeps the dates; the .sha256 list from above comes along for the check
scp -r -p "eels@10.6.9.20:/mnt/rescue/files/wd1/$f" D:\Cobra-copy\wd1\
scp -p "eels@10.6.9.20:/mnt/rescue/files/wd1/$f.sha256" D:\Cobra-copy\wd1\
# Check every file against the list. Prints nothing = every file matches.
Get-Content -LiteralPath "D:\Cobra-copy\wd1\$f.sha256" | ForEach-Object {
  $hash, $rel = $_ -split '  ', 2
  $file = Join-Path "D:\Cobra-copy\wd1\$f" ($rel -replace '^\./', '')
  if (-not (Test-Path -LiteralPath $file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $hash.ToUpper()) { "BAD  $rel" }
}
```

- If `scp` says `Permission denied` for some files, list them on the SGIN with `sudo find /mnt/rescue/files/wd1/$f ! -perm -o+r`. Opening them up for reading (`sudo chmod -R a+rX /mnt/rescue/files/wd1/$f`) changes only the permissions on the Seagate's copy, never wd1, and not the contents the `.sha256` list checks.
- Any `BAD` line: delete that one file under `D:\Cobra-copy\wd1\$f`, then run the two `scp` lines and the check again.
- Windows can't store names with `: * ? " < > |`, which are fine on Linux. `scp` stops on such a file; rename it on the Seagate copy (`sudo mv`), then add the new name to the `.sha256` list with `sha256sum`.

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
- [ ] The irreplaceable folders also sit on the second drive (the cabinet's `D:\Cobra-copy\wd1`), and their checks printed nothing
- [ ] You've looked at the copies yourself and you're happy nothing else is missing

**E1. Identify wd1 the long way** (plug it in alone with the Seagate, on the hub):

```bash
D=$(ls /dev/disk/by-id/ata-WDC_WD60EDAZ-* /dev/disk/by-id/usb-WD_Elements_25A3_*-0:0 2>/dev/null | grep -v part | head -1)
echo "$D -> $(readlink -f $D)"                               # wd1. Inside its WD Elements case there's often no ata- name, only usb-WD_Elements_25A3_…
N=$(ls /dev/disk/by-id/usb-Seagate_Expansion_HDD_*-0:0)        # the Seagate's, so the check below can tell them apart
sudo smartctl -i -d sat $D | grep -E 'Model|Serial'          # the serial you wrote down in A4
S=$(sudo blockdev --getsize64 $D); echo $S                   # about 6001175126016 (6.0 TB)
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS $D                # one disk and one part, nothing mounted, no dm overlay under it
[ -e "$N" ] && [ "$(readlink -f $D)" != "$(readlink -f $N)" ] && [ $S -gt 5900000000000 ] && [ $S -lt 6100000000000 ] \
  && [ $(lsblk -nr $D | wc -l) -le 2 ] && [ -z "$(lsblk -nro MOUNTPOINTS $D | tr -d '[:space:]')" ] && echo OK || echo STOP
```

`STOP` from the last line: wrong drive, or something still uses it (a stage B overlay over the raw drive: `sudo umount` it and `sudo dmsetup remove` it first). For dock1a, the size range in that check is `950000000000` to `1050000000000` (1.0 TB) instead.

**E2. Erase and reformat it** (only if E1 printed `OK` and the serial matches):

```bash
sudo blockdev --setrw $D $D-part1                            # undo stage A's read-only on both (only if it's still set)
sudo wipefs -a $D && sudo parted -s $D mklabel gpt mkpart data ext4 0% 100%
sleep 3; sudo mkfs.ext4 -L wd1 -m 0 -E nodiscard $D-part1
# fstab: the new filesystem has a NEW UUID, so remove the old wd1 line and add a new one
sudo sed -i '\#[[:space:]]/srv/storage/disks/wd1[[:space:]]#d' /etc/fstab
L=wd1; U=$(sudo blkid -s UUID -o value $D-part1)
sudo chattr -i /srv/storage/disks/$L 2>/dev/null; sudo mkdir -p /srv/storage/disks/$L && sudo chattr +i /srv/storage/disks/$L
echo "UUID=$U /srv/storage/disks/$L ext4 defaults,noatime,nofail,x-systemd.device-timeout=15 0 2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/storage/disks/$L && df -h /srv/storage/disks/$L
```

**E3. Copy the files back and check them.** This reads the Seagate and writes wd1: two disks, full speed (about 5 TB in 9–10 hours). Each folder goes where 3.4's table puts it. For wd1, that's the whole recovered library back at the top of the drive. Run it in tmux, so a dropped SSH session doesn't stop it:

```bash
tmux new -As copyback
SRC=/mnt/rescue/wd1-library        # where stage C put the copy (the per-folder way: /mnt/rescue/files/wd1)
ls $SRC && mountpoint -q /srv/storage/disks/wd1 && echo OK || echo STOP
sudo rsync -a --info=progress2 $SRC/ /srv/storage/disks/wd1/
```

Finished = the shell prompt is back and the last progress line says `100%`. Then check, and give the folders their 3.4 names:

```bash
sudo rsync -rn --size-only --itemize-changes $SRC/ /srv/storage/disks/wd1/ | head    # prints nothing = every file there, same size
sudo dmesg | grep -i -E 'I/O error|ext4.*error' | tail                              # prints nothing = no disk errors during the copy
sudo find $SRC -type f | shuf -n 20 | while read -r f; do
  [ "$(sudo sha256sum < "$f")" = "$(sudo sha256sum < "/srv/storage/disks/wd1/${f#$SRC/}")" ] && echo same || echo "DIFFERENT: $f"
done                                                                                 # 20 random files, byte for byte: 20 × same
sudo mkdir -p /srv/storage/disks/wd1/{movies,series,filler,pre-rolls}; ls /srv/storage/disks/wd1
```

Copied it the per-folder way with stage C's `.sha256` lists? Check each folder against its list instead: `(cd /srv/storage/disks/wd1/movies && sudo sha256sum --quiet -c /mnt/rescue/files/wd1/Movies.sha256)`, which prints nothing when every file matches. Other old folders (e.g. `staging`, `downloads`) can stay at the top of wd1 until you sort them; Jellyfin only reads `movies` and `series`.

**E4. Back to normal:**

Look at the lines A2 commented out before un-commenting any. Only bring back a drive that's still in 3.4's table; a line for anything else (an old drive that now lives elsewhere, `/mnt/old-wd1`, a rescue mount) gets deleted instead:

```bash
grep -n -E 'RESCUE|srv/storage|/mnt/' /etc/fstab          # wd1: only the NEW line from E2
# un-comment one drive's line, e.g. dock1b (one line per drive you keep):
sudo sed -i -E 's@^# RESCUE (.*[[:space:]]/srv/storage/disks/dock1b[[:space:]])@\1@' /etc/fstab
# delete a line you don't need any more, by its number from the grep (e.g. line 22):
#   sudo sed -i '22d' /etc/fstab        # one at a time, and grep again after each: the numbers shift
# the dock bays: delete nothing here; 3.4's "The dock drives: wipe both" replaces their lines
sudo systemctl daemon-reload && sudo mount -a && df -h /srv/storage/disks/*
sudo chown -R podsvc:media /srv/storage/disks/wd1/movies && sudo chmod -R g+rwX /srv/storage/disks/wd1/movies   # 3.5's permissions, per folder you copied back
```

Then plug the other drives back in. **E5. Bring the shares and apps back** (stopped in A2), once every drive is back: dock1a too, if it went through the rescue. With a drive missing, its folders are empty, and a library scan in Jellyfin or Navidrome could treat them as deleted and lose their watch history.

```bash
sudo mount -a && df -h /srv/storage/disks/*                # every drive listed, each with its own size
ls /srv/storage/disks/*                                    # each drive's folders (movies, shows, music…), not an empty listing
sudo systemctl start smbd                                  # Samba shares (3.6)
sudo machinectl shell podsvc@ /usr/bin/systemctl --user start stream-pod jellyfin ersatztv audiobookshelf kavita navidrome navidrome-comedy navidrome-rachel navidrome-sessions romm-db romm   # media apps (3.8)
sudo machinectl shell podsvc@ /usr/bin/podman ps          # every container Up
```

Then carry on with 3.4 where you left it (or 3.5 onward).

- [ ] Only now, once **both** drives are back and checked: `sudo umount /mnt/old; sudo dmsetup remove try; sudo losetup -D`. Keep the images on the Seagate for now; there's room
- [ ] **Keep the Seagate's copy for a few weeks** of the drives working normally. After that, `sudo chattr -i` the images, delete them, and the Seagate becomes the `vault` backup drive (part 5.6)

## 3.5 Users and permissions

`podsvc` runs the containers; group `media` = everyone allowed to write the library (podsvc, eels, the cabinet's and the gate's Samba logins).

How the permissions fit together: files arrive from Samba owned by whoever wrote them, with group `media` and mode `664`/`2775`. Containers that only read the library (Jellyfin, Audiobookshelf, Kavita, Navidrome) can read those through the "other" bits. A rootless container drops `podsvc`'s supplementary groups unless its Quadlet says `GroupAdd=keep-groups`, so every container that **writes** to the library (RomM) or needs `/dev/dri` (Jellyfin, ErsatzTV) carries that line.

```bash
sudo useradd -m -s /bin/bash -G media,render,video podsvc
sudo loginctl enable-linger podsvc
# every top-level folder on every drive, except lost+found
for f in $(sudo find /srv/storage/disks/{wd1,dock1a,dock1b,wd2}/ -mindepth 1 -maxdepth 1 -type d ! -name lost+found); do   # the real drives, not the video pool
  sudo chown -R podsvc:media "$f" && sudo chmod -R g+rwX "$f" && sudo find "$f" -type d -exec chmod g+s {} +
done
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

   # PBS's datastores and fsck's lost+found stay invisible in every share
   veto files = /pbs/lost+found/

[media]
   path = /srv/storage/disks

[roms]
   path = /srv/storage/disks/dock1b/roms

[scans]
   path = /srv/storage/disks/dock1a/scans
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
| Cabinet | Its nightly copy in part 4.5 (log in as `arcade`): its ROMs up to `roms`, its saves up to `media\dock1a\backups` | `\\cobra-stream\roms`, `\media` |
| Laptop/phone on WireGuard | Same as the desktops; short names resolve through Pi-hole (part 2) | `\\cobra-stream\media` |
| Gate VM | CIFS mount in part 5 (log in as `gate`) | `/srv/storage/disks` |
| Containers on the SGIN | Bind mounts in 3.8 | `/media/...` |
| Phones on Wi-Fi | Xfinity Wi-Fi is outside the firewall by design; use WireGuard there too | — |

Map the share on a Windows desktop (wired, or on WireGuard):

- [ ] File Explorer → **This PC** → **⋯** (or the Computer tab) → **Map network drive** → Drive `M:` → Folder `\\cobra-stream\media` → tick **Reconnect at sign-in** and **Connect using different credentials** → Finish → user `cobra-stream\eels`, the Samba password you just set → tick **Remember my credentials**
- [ ] If `\\cobra-stream` isn't found, use `\\10.6.9.20\media` (the name needs the desktop's DNS to be Pi-hole, part 2.9). If Windows says you're already connected with other credentials (from the old server), Control Panel → **Credential Manager** → Windows Credentials → remove the old `cobra-stream`/`10.6.9.200` entries, then try again
- [ ] Windows: `\\cobra-stream\media` opens and shows `wd1`, `dock1a`, `dock1b`, `wd2`; you can create and delete a test folder inside one of them
- Want a drive letter per drive? Map `\\cobra-stream\media\wd1` as `W:` and so on. One mapping of `media` is enough, though: the four folders are the four drives

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
    ip saddr { 10.6.9.0/24, 10.6.99.0/24 } tcp dport { 22, 53, 80, 443, 445, 4533, 4534, 4535, 4536, 4537-4549, 5000, 8007, 8080, 8096, 8409, 9090, 13378 } accept
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

Run as podsvc, never as eels: `sudo machinectl shell podsvc@` (a full login session, needed for `systemctl --user`). The prompt must read `podsvc@cobra-stream`. `exit` to leave. Paste the long block below in a few parts; the `DBPW` line and the two romm files must go into the same shell.

**Reinstalling with a backup of `/srv/stream`?** Restore it before anything starts, as eels: `sudo tar -C / -xzpf /srv/storage/disks/wd1/sgin-backup.tgz srv/stream`. Then, as podsvc, either restore the saved Quadlet files into `~/.config/containers/systemd` and skip the `cat` lines below, or run the block as written but set `DBPW`/`SECRET` to the old values instead of new random ones (RomM's database already uses the old password). With the scripts: `ROMM_DB_PASSWORD=<old> ROMM_AUTH_SECRET=<old> ./romm.sh` the first time. If an app then says `Permission denied`, see the last bullet of this section.

**Prefer plain `podman run` scripts?** [`scripts/podman`](../../scripts/podman/README.md) has one script per app (`sgin/up-all.sh` runs them all) that builds the same `stream` pod with the same images, ports and folders. Use either the scripts or the Quadlet files below for an app, not both; the scripts' README explains how to switch.

```bash
mkdir -p ~/.config/containers/systemd /srv/stream/{jellyfin/config,jellyfin/cache,ersatztv,abs/config,abs/metadata,kavita,navidrome,navidrome-comedy,navidrome-rachel,navidrome-sessions,romm/resources,romm/assets,romm/config,romm/redis,romm/db}
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
PublishPort=4534:4534
PublishPort=4535:4535
PublishPort=4536:4536
PublishPort=4537-4549:4537-4549
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
Volume=/srv/storage/disks:/media:ro,rbind
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
Volume=/srv/storage/disks:/media:ro,rbind
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
Volume=/srv/storage/disks:/media:ro,rbind
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
Volume=/srv/storage/disks:/media:ro,rbind
[Install]
WantedBy=default.target
EOF
c navidrome <<'EOF'
[Container]
ContainerName=navidrome
Image=docker.io/deluan/navidrome:latest
Pod=stream.pod
AutoUpdate=registry
Environment=ND_SESSIONTIMEOUT=8h ND_MUSICFOLDER=/media/dock1a/music ND_REVERSEPROXYWHITELIST=10.6.9.10/32
Volume=/srv/stream/navidrome:/data:Z
Volume=/srv/storage/disks:/media:ro,rbind
[Install]
WantedBy=default.target
EOF
c navidrome-comedy <<'EOF'
[Container]
ContainerName=navidrome-comedy
Image=docker.io/deluan/navidrome:latest
Pod=stream.pod
AutoUpdate=registry
Environment=ND_PORT=4534 ND_SESSIONTIMEOUT=8h ND_MUSICFOLDER=/media/dock1a/comedy ND_REVERSEPROXYWHITELIST=10.6.9.10/32
Volume=/srv/stream/navidrome-comedy:/data:Z
Volume=/srv/storage/disks:/media:ro,rbind
[Install]
WantedBy=default.target
EOF
c navidrome-rachel <<'EOF'
[Container]
ContainerName=navidrome-rachel
Image=docker.io/deluan/navidrome:latest
Pod=stream.pod
AutoUpdate=registry
Environment=ND_PORT=4535 ND_SESSIONTIMEOUT=8h ND_MUSICFOLDER=/media/dock1a/music/rachel ND_REVERSEPROXYWHITELIST=10.6.9.10/32
Volume=/srv/stream/navidrome-rachel:/data:Z
Volume=/srv/storage/disks:/media:ro,rbind
[Install]
WantedBy=default.target
EOF
c navidrome-sessions <<'EOF'
[Container]
ContainerName=navidrome-sessions
Image=docker.io/deluan/navidrome:latest
Pod=stream.pod
AutoUpdate=registry
Environment=ND_PORT=4536 ND_SESSIONTIMEOUT=8h ND_MUSICFOLDER=/media/dock1a/sessions ND_REVERSEPROXYWHITELIST=10.6.9.10/32
Volume=/srv/stream/navidrome-sessions:/data:Z
Volume=/srv/storage/disks:/media:ro,rbind
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
Volume=/srv/storage/disks/dock1b/roms:/romm/library/roms
[Install]
WantedBy=default.target
EOF
chmod 600 romm*.container
systemctl --user daemon-reload
systemctl --user start stream-pod jellyfin ersatztv audiobookshelf kavita navidrome navidrome-comedy navidrome-rachel navidrome-sessions romm-db romm   # first run pulls every image: a few quiet minutes
podman ps                                     # stream-infra + 10 containers Up
# logs: journalctl --user -u jellyfin -f     restart one: systemctl --user restart jellyfin
```

- [ ] App URLs: Jellyfin `http://10.6.9.20:8096`, ErsatzTV `:8409`, Audiobookshelf `:13378`, Kavita `:5000`, Navidrome `:4533`, the comedy Navidrome `:4534`, Rachel's Navidrome `:4535`, the sessions Navidrome `:4536`, RomM `:8080`

- [ ] Image names (Oct 2026): ErsatzTV is published as `ghcr.io/ersatztv/legacy` (its GitHub repo ErsatzTV/legacy builds that image; the older `ghcr.io/ersatztv/ersatztv` name still exists but isn't what that repo publishes); RomM is `rommapp/romm`. RomM expects `roms/<platform>/` folders. `Tmpfs=/transcode` keeps ErsatzTV's live segments in RAM instead of wearing the SSD
- [ ] Don't put `:Z` on `/srv/storage/disks` mounts (shared with Samba). `rbind` carries each drive's own mount into the container, so `/media/wd1` is wd1 and not the empty folder under it
- [ ] Each container sees the drives that were mounted when it started. After plugging a drive back in, as podsvc: `systemctl --user restart stream-pod`, and only then scan libraries
- [ ] Jellyfin → Dashboard → Playback → Transcoding: **Intel QuickSync (QSV)**, device `/dev/dri/renderD128`, enable H.264/HEVC/HEVC 10-bit/VP9 decode (**not AV1**: Jasper Lake has no AV1 decode), hardware encoding on, **Low-Power H.264/HEVC encoder on**, tone mapping on **and VPP tone mapping on**. Leave the transcode path on the internal SSD (the default). Users: hidden, Quick Connect off. If some movies stutter, see 3.8c
- [ ] Jellyfin → Dashboard → Networking → **Known proxies: `10.6.9.10`**. Without it, every remote viewer looks like a LAN client coming from the gate, so remote bitrate limits and per-IP logs don't work
- [ ] Navidrome: **one instance per person**, not one instance with several libraries. `navidrome` (`:4533`, `music.`) is Eels' and reads all of `dock1a/music`, so it sees everyone's music; `navidrome-rachel` (`:4535`, `mustang.`) reads only `dock1a/music/rachel`; `navidrome-comedy` (`:4534`, `comedy.`) reads `dock1a/comedy`; `navidrome-sessions` (`:4536`, `sessions.`) reads `dock1a/sessions`, your recorded podcasts. Someone new gets a **Cobra N.A.V.**: a block on the switchboard that switches genre, artist or album folders of the one shared `dock1a/music` on for them (read-only, nothing copied), built with `nav.sh` and walled off on the gate with `gate-nav.sh`. Ports 4537-4549 are the clone slots. See [`scripts/nav`](../../scripts/nav/README.md)
- `ND_REVERSEPROXYWHITELIST=10.6.9.10/32`: Navidrome trusts the `Remote-User` header from the gate only, so someone the station's sign-in (part 5.4) already let in isn't asked again. Give each person the same username here as in Authelia's `users.yml`.
- [ ] Each app: create its admin user now. Until you do, the first person to open the page becomes admin. First-run screens, all from the desktop's browser:

| App | First visit | Then |
|---|---|---|
| Jellyfin `:8096` | Wizard: language → admin user `eels` + password → **Add Media Library**: *Movies* → folder `/media/video/movies`; again for *Shows* → `/media/video/series` (music and books live in Navidrome and ABS, so skip them here) → metadata language/country → **Allow remote connections: on** (newer Jellyfin has no automatic port mapping option, which is what we want) → Finish → log in | The Transcoding and Networking settings below |
| Audiobookshelf `:13378` | Create the **root** user + password | Settings → **Libraries → Add**: name `Audiobooks`, type **Book**, folder `/media/dock1a/audiobooks`; again `Books` → `/media/dock1a/books` for e-books. Settings → Users → one user each |
| Kavita `:5000` | Register the admin account (email can be anything local) | ⚙ → **Libraries → Add**: name `Comics`, type **Comic**, folder `/media/dock1a/comics` → Save → **Scan**. Users → Invite (or add) one per person |
| Navidrome `:4533` | Create the admin user + password | It scans `ND_MUSICFOLDER` on its own; the library step below |
| Comedy Navidrome `:4534` | Create the admin user + password (same username as in Authelia) | It scans `dock1a/comedy` (stand-up albums, one folder per album) on its own. Kept apart from `music.` so stand-up never lands in music shuffles or searches. Public at `comedy.songofeo.com` |
| Rachel's Navidrome `:4535` | Create the admin user `rachel` (her Authelia username) + password | It scans only `dock1a/music/rachel`. Public at `mustang.songofeo.com` |
| Sessions Navidrome `:4536` | Create the admin user + password (same username as in Authelia) | It scans `dock1a/sessions`: your own recorded podcasts, one folder per show, tagged as albums. Public at `sessions.songofeo.com` (The Ward) |
| ErsatzTV `:8409` | No login screen; it stays LAN/VPN-only because the gate never publishes it | 3.8a |
| RomM `:8080` | Setup wizard → admin user | 3.8b |
- [ ] If one container keeps restarting with `Permission denied` in `journalctl --user -u <name>`: that image switches to a non-root user inside, so its files must belong to that user. Find it with `podman exec <name> id` (often `1000`), add `UserNS=keep-id:uid=1000,gid=1000` under `[Container]` in its `.container` file, then `systemctl --user daemon-reload && systemctl --user restart <name>`. Your `podsvc` then *is* that user inside the container, so the folders it owns become writable.

### 3.8a Live TV: ErsatzTV channels inside Jellyfin

ErsatzTV builds fake TV channels from your library (schedules, playlists, commercial breaks) and hands Jellyfin two links: a channel list (M3U) and a program guide (XMLTV). Jellyfin shows them under **Live TV** on every client, phones and TVs included. Both containers share the `stream` pod, so they talk over `127.0.0.1` and ErsatzTV never needs a public address.

**1. Give ErsatzTV access to Jellyfin's library**

- [ ] Jellyfin → Dashboard → API Keys → **+** → name `ersatztv` → copy the key
- [ ] Jellyfin → Dashboard → Libraries → **Add Media Library** → type *Home Videos and Photos* (or *Mixed*), name `Filler`, folder `/media/wd1/filler`. This makes filler searchable, though ErsatzTV reads it directly too.
- [ ] ErsatzTV (`http://10.6.9.20:8409`) → **Media Sources → Jellyfin** → address `http://127.0.0.1:8096`, the API key → **Save** → tick the Movies and TV libraries → **Sync**. Both containers mount `/srv/storage/disks` at `/media`, so the file paths Jellyfin reports are paths ErsatzTV can open.
- [ ] ErsatzTV → **Media Sources → Local** → add a library of type *Other Videos* → folder `/media/wd1/filler` → **Scan**

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

RomM serves the browser arcade at `arcade.songofeo.com`. The game runs in the player's browser (EmulatorJS), so the SGIN only serves files. It reads `/srv/storage/disks/dock1b/roms`, which the cabinet fills each night from its own `D:\Roms` (part 4.5). Add new ROMs on the cabinet; the copy only runs cabinet → SGIN.

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
sudo pihole-FTL --config misc.dnsmasq_lines '["address=/*.songofeo.com/10.6.9.10","server=/www.songofeo.com/#","server=/vpn.songofeo.com/#"]'
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
# store1 (the VM backups) lives on the Seagate, mounted at /srv/storage/vault in 3.4; part 5.6 adds the library's backups next to it
sudo proxmox-backup-manager datastore create store1 /srv/storage/vault/store1
# Reinstall, and that folder already holds backups? Use this instead, which keeps them:
#   sudo proxmox-backup-manager datastore create store1 /srv/storage/vault/store1 --reuse-datastore true
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
- [ ] PBS owns `/srv/storage/vault/store1` from here on. It's outside `/srv/storage/disks`, so 3.5's `chown` loop and Samba never reach it. Never `chown -R /srv/storage`.

## Done when

- [ ] `https://10.6.9.20:8007` (PBS), `:9090` (Cockpit), `:8096` Jellyfin plays a 4K HEVC file with transcoding showing `(hw)`
- [ ] `\\cobra-stream\media` opens from a desktop
- [ ] `df -h /srv/storage/disks/*` lists wd1, dock1a, dock1b, wd2 and video; a movie copied into `\\cobra-stream\media\video\movies` from a desktop shows up in Jellyfin after a library scan
- [ ] Jellyfin → Live TV plays an ErsatzTV channel, and the guide fills in (3.8a)
- [ ] RomM at `:8080` lists your platforms, and one game starts in the browser (3.8b)
- [ ] `nslookup cobra-stream 10.6.9.20` answers `10.6.9.20` (Pi-hole #2)
- [ ] Lid closed, the SGIN still answers `ping 10.6.9.20` and a stream keeps playing (3.3a)
- [ ] `lsusb -t`: the network adapter and every drive at `5000M` or faster, and the adapter's `power/control` is `on` (3.3a, 3.4)
