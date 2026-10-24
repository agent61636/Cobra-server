# 3. Set up SGIN (cobra-stream, Debian 13, 10.6.9.20)

**Result:** the SGIN runs Debian 13 bare metal and serves all storage (Samba), the media apps (one rootless Podman pod), Pi-hole #2 and Proxmox Backup Server.

🔌 The SGIN has **no built-in Ethernet**. Its network is a USB gigabit adapter (a TP-Link with an ASIX AX88179 chip, `0b95:1790`; not the Latitude's RTL8153 WAN adapter from part 1) plugged into the powered hub, with a cable from the adapter to your switch (behind OPNsense, from part 2) for the whole part. **The hub stays plugged into the SGIN the whole time, but unplug every drive from the hub until "Storage" (3.4)**, so the Debian installer can only see the internal SSD and can't touch a data drive. Keep the SGIN's lid **open** until 3.3a; before that, closing it puts the laptop to sleep.

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
- [ ] The data drives keep their files. In 3.4 **don't** run the `wipefs`/`mkfs` lines on them; only add their mount lines back. If one might be damaged, or you're not sure which drive is which, image it first (3.4, "Safe option first")
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

🔌 Plug the storage drives into the hub now (the SGIN's own USB-A ports are USB 2.0, see the port table at the top of this part): both WD external drives, and the dual-bay dock with its disks. The second dock gets added the same way later (see "Adding a drive later"). **Drives that hold files you want to keep, or that might be damaged (wd1): do "Safe option first: image wd1" below before anything else**, with only that drive and the rescue drive plugged in.

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

### Safe option first: image wd1 before anything writes to it

**Do this before any format line below touches a drive that holds files you want, and before any `fsck` or `mount -a` on one that may be damaged.** wd1 (the WD 6 TB Elements Desktop) is the drive this is written for. An image is a byte-for-byte copy of the **whole disk**: partition table, filesystem and every block outside them. Every repair is then tried on the image, where a mistake costs minutes, and the original stays untouched until the recovered files are checked.

It also covers the bad case. If the format block below ever ran on wd1 by mistake (a wrong `/dev/sdX` letter is the usual way), the file contents are almost always still on the platters. Don't mount it, `fsck` it or format it again: do the steps below, then follow the recovery plan, [Ext4 drive recovery plan + backup drive pick](https://claude.ai/artifact/V8Zmd8TybMABKAGyTvMwex), from Phase 3. It was tested on a practice disk with this exact accident and got 190 of 192 files back with their names.

**Needs:** the **Seagate Expansion Desktop 24 TB** as the rescue drive (about 21.8 TB usable: wd1's 6 TB image, dock1a's 1 TB image and the recovered files all fit), and about 11–14 hours for wd1.

**Rules until the files are verified:**

- **Never write to wd1.** No `mount -a`, `fsck`, `mkfs` or testdisk "Write" on the original. The drive is set read-only in the kernel below.
- **Address drives by `/dev/disk/by-id/…`, never `/dev/sdX`.** The letters move whenever drives or the hub get replugged.
- **Image the whole disk (`$D`), never just the partition (`$D-part1`).**
- **Every `mkfs`/`mke2fs` gets `-E nodiscard`.** Without it, the format tells the drive to throw blocks away, and anything in them is gone for good.
- **Only wd1 and the Seagate are plugged in.** Every other data drive comes off the hub, so there's nothing to mix up.
- Long commands run inside `tmux`, so a dropped SSH session doesn't stop them.

**1. Tools, and a tmux session to work in** (from the desktop, `ssh eels@10.6.9.20`):

```bash
# tmux keeps long jobs running if SSH drops; gddrescue = GNU ddrescue (the imager);
# testdisk is only needed if the partition table is gone (recovery plan, Phase 2)
sudo apt install -y tmux smartmontools gddrescue testdisk e2fsprogs dmsetup
tmux new -s rescue        # if SSH drops later: ssh back in, then  tmux attach -t rescue
```

**2. Freeze: stop everything that could write to a data drive, and keep boot from mounting them.** On a first install nothing is mounted yet, and these lines do nothing harmful:

```bash
sudo machinectl shell podsvc@ /usr/bin/systemctl --user stop stream-pod 2>/dev/null   # media apps (3.8), if they exist yet
sudo systemctl stop smbd 2>/dev/null                                                   # Samba shares (3.6), if set up yet
sudo umount /srv/storage/pool 2>/dev/null; sudo umount /srv/storage/disks/* 2>/dev/null
sudo cp /etc/fstab /etc/fstab.before-rescue                                  # the file to restore from later
sudo sed -i -E 's@^([^#].*/srv/storage/)@# RESCUE \1@' /etc/fstab           # comments out every drive line and the pool line
sudo systemctl daemon-reload
findmnt | grep /srv/storage        # must print nothing
```

**3. Plug in only wd1 and the Seagate.** 🔌 Unplug every other data drive from the hub. The network adapter stays where it is. wd1 and the Seagate both have their own power bricks: plug each brick into the UPS's battery-backed outlets, and each USB cable into one of the hub's **5 or 10 Gb/s data ports**, never a 45 W PD charging port. **Not** the SGIN's own USB-A ports: they're USB 2.0 (the port table at the top of this part), and at about 40 MB/s the 6 TB image would take two days instead of about 11 hours.

```bash
lsusb -t        # wd1 and the Seagate (Driver=uas or usb-storage) under the hub at 5000M or 10000M; 480M = reseat or another hub port
```

**4. Give wd1 a name that can't move, and make it read-only:**

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL,SERIAL                 # wd1 = ~5.5T, WD Elements; the Seagate = ~21.8T
ls -l /dev/disk/by-id/ | grep -v part | grep usb             # the whole-disk entries (no -part1 on the end)
D=/dev/disk/by-id/usb-WD_Elements_XXXX_XXXXXXXXXXXX-0:0      # paste wd1's whole-disk entry here
sudo smartctl -i -d sat $D | grep -E 'Model|Serial|Capacity' # must be the WD 6 TB (a WD60… model), not the Seagate
sudo blockdev --setro $D $D-part1                            # kernel-level read-only, until a replug or reboot
sudo blockdev --getro $D                                     # must print 1
```

- [ ] If wd1 drops off USB or gets replugged, run the `--setro` line again before anything else: read-only doesn't survive a replug.

**5. Health and the filesystem's details** (read-only). Screenshot both outputs: the recovery plan needs the `Inode count` and `Block count`, and `Last mount time` / `Mount count` say how much of the old index is likely still there:

```bash
sudo smartctl -H -A -d sat $D | grep -E 'result|Realloc|Pending|Uncorrect'   # non-zero Realloc/Pending/Uncorrect = failing: image now, nothing else
sudo dumpe2fs -h $D-part1 2>/dev/null | grep -E 'volume name|UUID|created|Last mount time|Mount count|Inode count|Block count|Block size|Filesystem features'
```

**6. Prepare the Seagate.** This is the **only** format in this section, and it erases the Seagate. It's new, so that's fine, but if it already holds anything you want, stop here. The checks refuse anything that isn't a different drive of more than 23 TB, so they can't hit wd1:

```bash
N=/dev/disk/by-id/usb-Seagate_Expansion_HDD_XXXXXXXXXXXX-0:0   # paste the Seagate's whole-disk entry here
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL,SERIAL $N                # must say ~21.8T and Seagate
[ "$(readlink -f $N)" != "$(readlink -f $D)" ] && [ $(sudo blockdev --getsize64 $N) -gt 23000000000000 ] && echo OK || echo STOP
```

Only if it printed `OK`:

```bash
sudo wipefs -a $N && sudo parted -s $N mklabel gpt mkpart rescue ext4 0% 100%   # new partition table on the Seagate only
sleep 3                                                                          # let udev create $N-part1
sudo mkfs.ext4 -L rescue -m 0 -E nodiscard $N-part1                              # -m 0: no root reserve; nodiscard: see the rules
sudo mkdir -p /mnt/rescue && sudo mount $N-part1 /mnt/rescue && df -h /mnt/rescue   # ~22T free
```

**7. Image the whole of wd1** (`$D`, not `$D-part1`). A fast first pass copies everything that reads cleanly; the second goes back three times over any spot that didn't:

```bash
sudo ddrescue -n  $D /mnt/rescue/wd1.img /mnt/rescue/wd1.map   # pass 1: no scraping, the bulk of the drive (~11 h)
sudo ddrescue -r3 $D /mnt/rescue/wd1.img /mnt/rescue/wd1.map   # pass 2: retry bad areas up to 3 times (minutes on a healthy drive)
```

Detach tmux with Ctrl+B then D and check back later (`tmux attach -t rescue`). It's done when it reports `pct rescued: 100%` (or as close as the drive allows) and `bad areas: 0`. If wd1 drops off USB mid-copy: replug it, rerun the `--setro` line from step 4, and rerun the **same** `ddrescue` command. The `.map` file makes it carry on where it stopped instead of starting over.

**8. Check the image and lock it:**

```bash
sudo ddrescuelog -t /mnt/rescue/wd1.map                        # summary: "rescued" ~6.0 TB, "bad areas" 0 (or very few)
sudo blockdev --getsize64 $D; stat -c %s /mnt/rescue/wd1.img   # the same number twice: the image is the whole disk
L=$(sudo losetup -r -fP --show /mnt/rescue/wd1.img); P=${L}p1  # attach the image READ-ONLY; its partition = $P (e.g. /dev/loop0p1)
sudo dumpe2fs -h $P 2>/dev/null | grep -E 'UUID|created|Inode count|Block count'   # matches step 5's screenshot
sudo losetup -d $L                                             # detach again; the recovery plan re-attaches it
sudo chattr +i /mnt/rescue/wd1.img /mnt/rescue/wd1.map         # nothing (not even root, by mistake) can change or delete them now
```

The recovery plan's repairs only **read** the image (they write to a throwaway overlay), so it can stay locked. If its Phase 2 (testdisk on the image) is ever needed, run `sudo chattr -i /mnt/rescue/wd1.img` just before that, and lock it again after.

**9. Set wd1 aside, untouched.** Unplug it, and stick a label on it: *ORIGINAL, do not format*. From here everything happens on the image. wd1 is your second copy until **every folder you care about has been copied off and checked**, and only then (recovery plan, Phase 4) does it get the format block below, with `-E nodiscard`, and its files copied back. Its fstab line stays commented (`# RESCUE`) until then.

- [ ] **Recover the files:** [Ext4 drive recovery plan + backup drive pick](https://claude.ai/artifact/V8Zmd8TybMABKAGyTvMwex), Phase 3 (rebuild the index on an overlay over `/mnt/rescue/wd1.img`), Phase 4 (copy off irreplaceable folders first, with checksum checks), Phase 5 (photorec for anything still missing)
- [ ] **dock1a too**, if it was formatted the same way: the same steps with `dock1a` in place of `wd1` in the file names, in dock bay A with bay B empty. Its 1 TB image takes about 2 hours, so the plan does it **first**, as a rehearsal
- [ ] Only once both drives' files are recovered and checked: restore `/etc/fstab.before-rescue` (or uncomment the `# RESCUE` lines), plug the drives back in and carry on with the rest of 3.4

**Reinstalling, and the drives were set up here before?** Skip the `wipefs`/`parted`/`mkfs` lines: those erase the drive. `lsblk` shows each one's old label (`wd1`, `dock1a`…); for each, run only the `L=…; U=…`, `mkdir`/`chattr` and `echo … | sudo tee -a /etc/fstab` lines with its partition, then carry on at "Then mount everything". The pool block, the `mkdir` lines and 3.5's `chown` are safe to run again.

**Empty drive, or one you've copied off first** (ext4 is the most reliable choice on Linux). ⚠️ This **erases** the drive. Name it by its by-id path, never `/dev/sdX`, and check it's the one you mean before the `wipefs` line:

```bash
D=/dev/disk/by-id/usb-XXXXXXXX-0:0                          # whole-disk entry from: ls -l /dev/disk/by-id/ | grep -v part
sudo smartctl -i -d sat $D | grep -E 'Model|Serial'         # the model and serial of the drive you mean to erase
lsblk -o NAME,SIZE,FSTYPE,LABEL $D                          # an FSTYPE or LABEL here means it holds a filesystem: if it has files you want, image it first (above)
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
| Windows desktops | File Explorer → Map network drive (log in as `eels`) | `\\cobra-stream\media`, `\scans`, `\roms` |
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
