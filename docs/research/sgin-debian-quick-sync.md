# SGIN: Debian 13 packages and settings for Quick Sync media serving

Research for part 3 ([`03-sgin.md`](../manual/03-sgin.md)), October 2026, ahead of a fresh Debian 13.7 install on the SGIN X15 (Celeron N5095A, Jasper Lake, 12 GB, run headless as `cobra-stream`).

## What part 3.3 already gets right

Keep these as they are:

| Already in 3.3 | Why it matters |
|---|---|
| `contrib non-free non-free-firmware` components | The Intel media driver and firmware live there |
| `intel-microcode` | CPU errata fixes for Jasper Lake |
| `firmware-intel-graphics` (with `firmware-misc-nonfree`) | Debian 13 moved the GuC/HuC blobs into this package. Without HuC, Jasper Lake can decode but can't encode at all |
| `options i915 enable_guc=2` + `update-initramfs` | Loads HuC on Gen11, which the low-power encoder needs |
| `intel-media-va-driver-non-free` + `vainfo` | Host-side check that the iHD driver sees HEVC Main10 and `EncSliceLP` |
| `podman crun passt uidmap fuse-overlayfs systemd-container` | Rootless Podman 5 + Quadlet + `machinectl shell` |
| `smartmontools`, `nftables`, `cockpit`, `samba` | Disk health, firewall, web console, shares |

**Worth knowing:** Jellyfin and ErsatzTV bring their own ffmpeg and their own copy of the Intel iHD driver inside the image. What the host must supply is only the kernel, the GPU firmware, `/dev/dri`, and the `render` group. So the host's `intel-media-va-driver-non-free` is there for the `vainfo` check, not for the containers. Debian 13's 6.12 LTS kernel supports Jasper Lake fully; **no backports kernel is needed**.

## Gaps, most important first

### 1. The SGIN is a laptop: stop it suspending when the lid closes ⚠️

Part 3 has no laptop-as-server step, but part 1.8 does for the Latitude. Without it, closing the lid (or a default idle action) suspends the SGIN and every share, stream and backup goes down. Copy part 1.8's block, including the USB NIC rule with the SGIN adapter's IDs (`0b95:1790`, ASIX AX88179; the SGIN has no built-in Ethernet), and prefix with `sudo`:

```bash
# Keep running with the lid closed
sudo mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\n' \
  | sudo tee /etc/systemd/logind.conf.d/10-lid.conf
sudo systemctl restart systemd-logind
# Belt and braces: nothing can suspend or hibernate it
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Blank the built-in screen after 60 s (saves the panel and a few watts)
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 consoleblank=60"/' /etc/default/grub
sudo update-grub

# Battery = built-in UPS: clean power-off at 10 % during a long outage
sudo apt install -y upower
sudo mkdir -p /etc/UPower/UPower.conf.d
printf '[UPower]\nUsePercentageForPolicy=true\nPercentageLow=25\nPercentageCritical=15\nPercentageAction=10\nCriticalPowerAction=PowerOff\n' \
  | sudo tee /etc/UPower/UPower.conf.d/10-cobra.conf
sudo systemctl restart upower
upower -i $(upower -e | grep BAT) | grep -E 'state|percentage'
```

- [ ] Close the lid; `ping 10.6.9.20` keeps answering
- [ ] Battery wear: a laptop held at 100 % on the charger for years can swell. Check `ls /sys/class/power_supply/BAT*/charge_control_end_threshold`. If it exists, `echo 80 | sudo tee` it (and make it stick with a udev rule or a tiny systemd unit). Budget laptops like the SGIN often don't expose it; then check the battery for bulging every few months.

### 2. Security updates: `unattended-upgrades`

Nothing in the manual installs automatic security updates on the bare-metal Debian hosts. The SGIN faces the internet through the gate, so it should patch itself:

```bash
sudo apt install -y unattended-upgrades apt-listchanges
sudo dpkg-reconfigure -plow unattended-upgrades     # Yes
```

Debian's default config only installs from `trixie-security`, which is what you want. It doesn't reboot by itself; `needrestart` (below) tells you when a kernel or library update needs one. PBS updates come from the Proxmox repo and stay manual (part 5's weekly check).

### 3. GPU monitoring: `intel-gpu-tools`

The stutter guide (`jellyfin/stutter-fixes.md`, now part 3.8c) tells you to run `intel_gpu_top` during a transcode, but 3.3 never installs it. Add it to the 3.3 package line so it's there when you need it. `intel_gpu_top` shows the **Video** engine busy during a QSV transcode; if it's idle while ffmpeg eats the CPU, the transcode is in software.

### 4. File-watch limits for Jellyfin, Kavita, Audiobookshelf, Navidrome

All four watch the library for new files, and they all run as the one `podsvc` user, which shares a single inotify budget. Debian's default `max_user_instances` is 128, and Jellyfin in containers is a well-known way to hit it ("The configured user limit (128) on the number of inotify instances has been reached"). Raise it once:

```bash
printf 'fs.inotify.max_user_instances=1024\nfs.inotify.max_user_watches=524288\n' | sudo tee /etc/sysctl.d/90-inotify.conf
sudo sysctl --system
```

### 5. Disk health on the USB drives: turn `smartd` on properly

`smartmontools` is installed, but USB-to-SATA bridges often hide SMART unless you tell `smartctl` the type. Check each drive once, then let `smartd` watch them:

```bash
sudo smartctl -d sat -H /dev/sdX          # "PASSED"; if -d sat fails, try without it
sudo systemctl enable --now smartd
journalctl -u smartd | tail               # lists the drives it's monitoring
```

Some cheap docks pass nothing through; that's the dock, not the drive.

### 6. Leave power tuners off: no TLP, no `powertop --auto-tune`

Laptop guides recommend TLP or `powertop --auto-tune`. **Don't use either on this box.** Both turn on USB autosuspend, which makes the hub, the USB drives and the USB network adapter (the SGIN's only network link) drop out, and that shows up as exactly the "random stutter, then the pool loses a drive" you're trying to avoid. The N5095A idles near 10 W already. (`powertop` on its own, just to look, is fine.)

Drive spin-down: the WD externals spin down on their own after a few idle minutes; the first play after that waits a few seconds for spin-up. That's normal. Don't add `hd-idle` or `hdparm -S`; more spin cycles wear the drives, and many USB bridges ignore the setting anyway.

### 7. Small, useful extras

| Package | What it does | Add? |
|---|---|---|
| `needrestart` | After an upgrade, says which services or the kernel need a restart | Yes |
| `firmware-realtek` | Firmware for Realtek PCI Ethernet chips (`r8169`) | No: the SGIN has no PCI Ethernet, and its USB adapter (AX88179) needs no firmware |
| `lm-sensors` | `sensors` shows CPU temperature; a laptop with the lid shut runs warmer | Yes |
| `htop`, `iotop-c`, `ncdu` | Live CPU/memory, live disk I/O per process, find what filled the SSD | Yes, handy for 3.8c |
| `mediainfo` | Shows a file's codec, bit depth, HDR and subtitle type, i.e. *why* it transcodes | Yes |
| `podman-compose` | Not needed; Quadlet and the scripts cover everything | No |
| `slirp4netns` | Podman 5 uses `passt` by default; harmless to keep | Optional |
| Backports kernel / `firmware-*` from backports | Only for very new Intel GPUs (Lunar Lake and up) | No |

### 8. Checks after first boot

```bash
systemctl is-enabled fstrim.timer          # "enabled": weekly TRIM for the internal SSD
cat /sys/module/i915/parameters/enable_guc # 2
sudo dmesg | grep -i -E 'huc.*(authenticated|loaded)'
ls -l /dev/dri                              # card0/card1 and renderD128, group render
id podsvc                                   # includes render and video (part 3.5)
```

Enable `fstrim.timer` with `sudo systemctl enable --now fstrim.timer` if it says `disabled`.

## Suggested additions to part 3.3 (summary)

1. Add to the `apt install` line: `intel-gpu-tools unattended-upgrades apt-listchanges needrestart lm-sensors mediainfo htop iotop-c ncdu upower` (and `firmware-realtek` if the NIC is Realtek).
2. New step "3.3a Laptop-as-server settings": the lid, sleep-mask, `consoleblank`, UPower and battery-threshold block from section 1.
3. After the packages: `dpkg-reconfigure -plow unattended-upgrades`, the inotify sysctl, `systemctl enable --now smartd fstrim.timer`.
4. A one-line warning: no TLP, no `powertop --auto-tune` (USB autosuspend drops the drives).
