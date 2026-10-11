# Elysidrome Build Manual — 02: Stage 1, Proxmox on command-center

**Result:** Proxmox VE 9 installed, updated and locked down on the Latitude 5580, with the installers for Stages 2–4 already on it.
**Time:** ~2 h. **The house network is not touched.**
**You need:** the Proxmox USB stick, the USB 3 NIC, an Ethernet cable, and your Windows desktop.

Tables are followed top to bottom. **Run** says where: `console` = keyboard on the Latitude, `PS` = PowerShell on your desktop, `ssh` = root shell on command-center over SSH (or the web UI's **Shell** button). Where a step says *File A*, *File B*… the contents are in the box right under that table.

---

## Proxmox terms you'll meet

| Term | Meaning | You know it as |
|---|---|---|
| Node | One physical Proxmox host (`command-center`) | Hyper-V host |
| Datacenter | Top of the UI tree: users, permissions, storage, firewall shared by all nodes | vCenter level |
| VM | Full virtual machine (OPNsense = VM 100, gate = VM 110) | Hyper-V VM |
| CT | LXC container, shares the host kernel (pihole-1 = CT 101) | Lightweight jail |
| `local` | Folder storage for ISOs, CT templates, backup files | Install-media share |
| `local-lvm` | Thin-provisioned pool for guest disks | Dynamic VHDX |
| `vmbr0` / `vmbr1` | Linux bridges = virtual switches. Physical NIC is the uplink. | Hyper-V external switch |
| no-subscription repo | Free update channel. The default "enterprise" one needs a paid key. | — |
| Subscription popup | Shown at every login. Harmless, click **OK**. | — |

## Wiring (Stage 1 vs. after Stage 2)

| Port | Bridge | Stage 1 (now) | After Stage 2 |
|---|---|---|---|
| USB 3 NIC (`enx…`) | `vmbr1` WAN | Cabled to Xfinity, **temporary DHCP 10.0.0.x**. You manage Proxmox here. | Cabled to Xfinity, **no host IP**. Only OPNsense's WAN uses it. |
| Onboard I219-LM (`enp0s31f6`) | `vmbr0` LAN | `10.10.10.2/24`, **no gateway, no cable** | `10.10.10.2/24`, gateway `10.10.10.1`, cabled to your switch |

Why: `10.10.10.0/24` has no router until OPNsense exists, so updates go out through the Xfinity side for now. While the host sits on the Xfinity LAN, finish Table 6 (2FA, SSH keys) the same day.

---

## Table 1 — BIOS (F2 at the Dell logo)

| # | Setting | Set to | Why |
|---|---|---|---|
| 1.1 | System Configuration → **SATA Operation** | **AHCI** | "RAID On" hides the NVMe. Skip this and the installer shows no disk. |
| 1.2 | Virtualization Support → Virtualization | Enabled | KVM needs it |
| 1.3 | Virtualization Support → VT for Direct I/O | Enabled | For later passthrough |
| 1.4 | Power Management → AC Behavior → **Wake on AC** | Enabled | Powers back on after an outage |
| 1.5 | Power Management → Primary Battery Charge Configuration | Custom: start **50**, stop **80** | Battery is your UPS; don't hold it at 100 % |
| 1.6 | Wireless → Wireless Device Enable | Untick WLAN, Bluetooth | Unused radios on a firewall |
| 1.7 | Secure Boot | Leave enabled | Proxmox supports it |
| 1.8 | Security → Admin Password | Generate, store in KeePassXC | Stops USB booting by others |
| 1.9 | Intel AMT (vPro models only; or Ctrl+P at boot → MEBx) | Disabled | ⚠️ Verify your model has it. AMT listens on the onboard NIC. |
| 1.10 | **Apply → Exit** | | |

## Table 2 — Install

USB NIC **unplugged** during install, so there's only one NIC to pick.

| # | Screen | Enter / choose |
|---|---|---|
| 2.1 | Boot | Stick in, power on, **F12**, pick the UEFI USB entry |
| 2.2 | Menu | **Install Proxmox VE (Graphical)** → accept EULA |
| 2.3 | Target harddisk | 256 GB NVMe. Options → Filesystem **ext4** (default) |
| 2.4 | Location | Your country, your time zone, keyboard **U.S. English** |
| 2.5 | Password | Generated, ~20 chars, letters+digits. KeePassXC: `Hosts/command-center root` |
| 2.6 | Email | Your real address (alerts) |
| 2.7 | Management interface | Onboard NIC, usually **`enp0s31f6`** (e1000e) |
| 2.8 | Hostname (FQDN) | **`command-center.home.arpa`** |
| 2.9 | IP address (CIDR) | **`10.10.10.2/24`** |
| 2.10 | Gateway | **`10.10.10.1`** |
| 2.11 | DNS server | **`10.10.10.1`** |
| 2.12 | "Pin network interface names" (if offered) | **Yes** |
| 2.13 | Summary | **Install**. Pull the stick when told, let it reboot. |
| ✅ | Console shows a login prompt mentioning `https://10.10.10.2:8006/` | That URL won't work yet. Expected. |

`home.arpa` is the domain reserved for home networks. A name under `elysidrome.com` would collide with Pi-hole sending `*.elysidrome.com` to the gate. All internal hostnames use `<name>.home.arpa`; Stage 2 sets the same domain in OPNsense.

ext4 rather than ZFS: ZFS shines with several disks and spare RAM. With one disk and 16 GB it just eats guest memory.

## Table 3 — Temporary uplink

| # | Run | Do | Expect |
|---|---|---|---|
| 3.1 | — | Plug the USB NIC into the Latitude, cable it to the Xfinity gateway (or your current switch). Onboard port stays unplugged. | |
| 3.2 | console | Log in as `root`, run `ip -br link` | An `enx…` name (the USB NIC). Write it down. |
| 3.3 | console | `cp /etc/network/interfaces /root/interfaces.installer` | Backup of the original |
| 3.4 | console | `nano /etc/network/interfaces`, replace the contents with **File A** (your real NIC names) | |
| 3.5 | console | `ifreload -a` | No errors |
| 3.6 | console | `ip -4 -br addr show vmbr1` | `vmbr1 UP 10.0.0.x/24`. Write down the `10.0.0.x`. |
| 3.7 | console | `ping -c3 download.proxmox.com` | 3 replies |
| 3.7a | console | Only if 3.7 says it can't resolve but `ping -c3 1.1.1.1` works: `printf 'search home.arpa\nnameserver 10.0.0.1\n' > /etc/resolv.conf` | 3.7 now works |
| 3.8 | browser | `https://10.0.0.x:8006` → accept the certificate warning → `root`, realm **Linux PAM** | Proxmox dashboard. Click OK on the subscription popup. |
| 3.9 | Xfinity app | Optional: reserve that `10.0.0.x` for the USB NIC's MAC | Address won't move during Stage 1 |

From here on, work from the desktop: `ssh root@10.0.0.x`.

**File A — `/etc/network/interfaces`**

```
auto lo
iface lo inet loopback

iface enp0s31f6 inet manual

# LAN bridge: onboard I219-LM -> your switch
auto vmbr0
iface vmbr0 inet static
        address 10.10.10.2/24
#       gateway 10.10.10.1      # STAGE 1: commented out. Stage 2 uncomments it.
        bridge-ports enp0s31f6
        bridge-stp off
        bridge-fd 0

iface enx00e04c680123 inet manual

# WAN bridge: USB 3 NIC -> Xfinity
auto vmbr1
iface vmbr1 inet dhcp           # STAGE 1 ONLY. Stage 2 changes "dhcp" to "manual".
        bridge-ports enx00e04c680123
        bridge-stp off
        bridge-fd 0
```

## Table 4 — Repositories and updates

| # | Run | Command | Expect |
|---|---|---|---|
| 4.1 | ssh | Paste **File B** | Enterprise repos disabled, no-subscription added |
| 4.2 | ssh | `apt update` | No `401 Unauthorized` lines |
| 4.3 | ssh | `apt full-upgrade -y` | Upgrades install. **Never use plain `apt upgrade` on Proxmox**; it can leave it half-updated. |
| 4.4 | ssh | `apt install -y intel-microcode sudo vim htop curl ethtool bzip2 lm-sensors` | Installs. If `intel-microcode` isn't found, check that `/etc/apt/sources.list.d/debian.sources` lists `non-free-firmware` in **Components:**, add it, re-run 4.2. |
| 4.5 | ssh | `reboot`, wait 1 min, SSH back in | |
| 4.6 | ssh | `pveversion` | `pve-manager/9.x…` |

Same thing in the UI if you prefer: node → **Updates → Repositories** → disable both enterprise lines → **Add → No-Subscription**.

**File B — repositories**

```bash
for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
  if [ -f "$f" ] && ! grep -q '^Enabled:' "$f"; then echo 'Enabled: no' >> "$f"; fi
done
cat > /etc/apt/sources.list.d/proxmox.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
```

## Table 5 — Admin account

`@pam` users are real Linux accounts, so `eels@pam` is one login for SSH, sudo and the web UI.

| # | Run | Command | Expect |
|---|---|---|---|
| 5.1 | ssh | `adduser eels` | Prompts for password. Generate it, store as `Hosts/command-center eels`. |
| 5.2 | ssh | `usermod -aG sudo eels` | |
| 5.3 | ssh | `pveum user add eels@pam --comment "Eels admin"` | |
| 5.4 | ssh | `pveum acl modify / --users eels@pam --roles Administrator` | |
| 5.5 | browser | Log out, log in as `eels`, realm Linux PAM | Full tree visible |

## Table 6 — 2FA and SSH keys

| # | Run | Do | Expect |
|---|---|---|---|
| 6.1 | browser | As `eels`: top right **eels@pam → TFA → Add → TOTP**, scan, confirm code | |
| 6.2 | browser | **TFA → Add → Recovery Keys**, store them in KeePassXC | |
| 6.3 | browser | Repeat 6.1–6.2 as `root@pam` | Root still works at the physical console, so no lockout risk |
| 6.4 | PS | `ssh-keygen -t ed25519 -C "eels@desktop"` (default path, set a passphrase) | |
| 6.5 | PS | `type $env:USERPROFILE\.ssh\id_ed25519.pub \| ssh eels@10.0.0.x "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"` | Asks for eels' password once |
| 6.6 | PS | `type $env:USERPROFILE\.ssh\id_ed25519.pub \| ssh root@10.0.0.x "cat >> /root/.ssh/authorized_keys"` | |
| 6.7 | PS | `ssh eels@10.0.0.x` | Logs in with only the key passphrase |
| 6.8 | ssh | Paste **File C**, keep this session open | `sshd -t` prints nothing |
| 6.9 | PS (new window) | `ssh eels@10.0.0.x` | Works |
| 6.10 | PS | `ssh -o PubkeyAuthentication=no eels@10.0.0.x` | **Permission denied** |
| ✅ | browser | Log out and in as eels | TOTP code requested |

Root SSH stays allowed with keys (`prohibit-password`) because joining the R620 to the cluster in Stage 8 needs it.

**File C — SSH hardening**

```bash
cat > /etc/ssh/sshd_config.d/10-elysidrome.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
sshd -t && systemctl reload ssh
```

## Table 7 — Laptop-as-server settings

| # | Run | Do | Expect |
|---|---|---|---|
| 7.1 | ssh | Paste **File D** (lid + screen blank) | `update-grub` ends with `done` |
| 7.2 | — | Close the lid; `ping 10.0.0.x` from the desktop | Still replies |
| 7.3 | ssh | `lsusb \| grep -i -E 'realtek\|asix\|ethernet'` | e.g. `ID 0bda:8153 Realtek … RTL8153` |
| 7.4 | ssh | Paste **File E** (change `0bda`/`8153` if 7.3 differs) | USB NIC never autosuspends (from next boot) |
| 7.5 | ssh | Paste **File F** (power off at 10 % battery) | Last line shows `state: fully-charged` or `charging` and a percentage |
| 7.6 | — | Only if `journalctl -k` ever shows `Detected Hardware Unit Hang`: add `post-up /usr/sbin/ethtool -K enp0s31f6 tso off gso off` under `iface vmbr0`, run `ifreload -a` | Known I219 quirk; fixes link drops |

Guest start order (OPNsense → Pi-hole → gate) is set on each guest in Stages 2–4 (**Options → Start/Shutdown order**). Proxmox shuts guests down in reverse.

**File D — lid and screen**

```bash
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-lid.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
systemctl restart systemd-logind
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 consoleblank=60"/' /etc/default/grub
update-grub
```

**File E — USB NIC power**

```bash
cat > /etc/udev/rules.d/50-usb-nic-power.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8153", TEST=="power/control", ATTR{power/control}="on"
EOF
udevadm control --reload
```

**File F — low-battery shutdown**

```bash
apt install -y upower
mkdir -p /etc/UPower/UPower.conf.d
cat > /etc/UPower/UPower.conf.d/10-elysidrome.conf <<'EOF'
[UPower]
UsePercentageForPolicy=true
PercentageLow=25
PercentageCritical=15
PercentageAction=10
CriticalPowerAction=PowerOff
EOF
systemctl restart upower
upower -i $(upower -e | grep BAT) | grep -E 'state|percentage'
```

⚠️ Verify: if your UPower version ignores the `.conf.d` folder, put the same lines in `/etc/UPower/UPower.conf`. Unplug-test it in Stage 7, not now.

## Table 8 — Put the next stages' installers on Proxmox

| # | Run | Do | Expect |
|---|---|---|---|
| 8.1 | browser | Go to `https://opnsense.org/download/`, pick **amd64 / dvd**, a mirror, and copy the `.iso.bz2` link | |
| 8.2 | ssh | Run **File G**, pasting the link where it says | Two lines ending `: OK`, then the template download finishes |
| ✅ | browser | **local (command-center) → ISO Images** | OPNsense and Debian 13 netinst ISOs |
| ✅ | browser | **local (command-center) → CT Templates** | `debian-13-standard_…` |

| Installer | Used in |
|---|---|
| OPNsense ISO | Stage 2, VM 100 open-the-box |
| Debian 13 CT template | Stage 3, CT 101 pihole-1 |
| Debian 13 netinst ISO | Stage 4, VM 110 elysidrome-gate |

**File G — downloads with checksum checks**

```bash
cd /var/lib/vz/template/iso
OPN_URL='<paste the .iso.bz2 link>'
wget "$OPN_URL"
wget "$(dirname "$OPN_URL")/$(basename "$OPN_URL" | sed 's/-dvd-amd64.iso.bz2/-checksums-amd64.sha256/')"
sha256sum -c --ignore-missing OPNsense-*-checksums-amd64.sha256
bunzip2 OPNsense-*-dvd-amd64.iso.bz2

BASE=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd
wget -q $BASE/SHA256SUMS
ISO=$(awk '$2 ~ /^debian-[0-9.]+-amd64-netinst\.iso$/ {print $2}' SHA256SUMS)
wget $BASE/$ISO
sha256sum -c --ignore-missing SHA256SUMS
rm SHA256SUMS OPNsense-*-checksums-amd64.sha256

pveam update
TPL=$(pveam available --section system | awk '/debian-13-standard/ {print $2}' | sort -V | tail -1)
pveam download local "$TPL"
```

⚠️ Verify: if the OPNsense checksum file has another name, download it by hand from the same mirror folder. If its line names the `.iso` instead of the `.bz2`, run `bunzip2` first, then `sha256sum -c`.

## Table 9 — Save the config off the box

| # | Run | Command |
|---|---|---|
| 9.1 | ssh | `tar czf /root/command-center-stage1-$(date +%F).tgz /etc/network/interfaces /etc/hosts /etc/apt/sources.list.d /etc/ssh/sshd_config.d /etc/systemd/logind.conf.d /etc/udev/rules.d /etc/default/grub /etc/UPower /etc/pve/user.cfg /etc/pve/datacenter.cfg 2>/dev/null` |
| 9.2 | PS | `scp root@10.0.0.x:/root/command-center-stage1-*.tgz $HOME\Documents\Elysidrome\` |

---

## What Stage 2 changes first (don't do it yet)

| # | Change |
|---|---|
| 1 | Create VM 100 OPNsense: net0 → `vmbr1` (WAN), net1 → `vmbr0` (LAN) |
| 2 | `/etc/network/interfaces`: `vmbr1 inet dhcp` → `inet manual`; uncomment `gateway 10.10.10.1` |
| 3 | Cable the onboard port to the switch; node → System → DNS → `10.10.10.1` |
| 4 | Web UI moves to `https://10.10.10.2:8006`, reachable from LAN and WireGuard only |

## Stage 1 done when

| ✔ | Check |
|---|---|
| ☐ | BIOS: AHCI, virtualization, Wake on AC, battery 50–80 %, radios off, BIOS password |
| ☐ | `command-center.home.arpa`, `vmbr0` = `10.10.10.2/24`, `vmbr1` on the USB NIC with temporary DHCP |
| ☐ | No-subscription repo, full-upgrade done, microcode, rebooted |
| ☐ | `eels@pam` Administrator; TOTP + recovery keys on `eels` and `root` |
| ☐ | SSH by key only |
| ☐ | Lid ignored, console blanks, USB NIC stays awake, low-battery power-off set |
| ☐ | OPNsense ISO, Debian ISO, Debian CT template on `local` |
| ☐ | Config tarball on the desktop |

Next: Stage 2, open-the-box (OPNsense), `03-stage2-open-the-box-opnsense.md`.
