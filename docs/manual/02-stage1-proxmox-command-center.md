# Elysidrome Build Manual — 02: Stage 1, Proxmox on `command-center`

> **Goal:** Proxmox VE 9 installed on the Latitude, updated, hardened for admin access, both bridges built (LAN `vmbr0`, WAN `vmbr1`), laptop quirks handled, and the Stage 2 installers already on local storage.
> **Time:** about 2 h.
> **Assumes:** Stage 0 is done, or at least the backups and the Proxmox USB. You know Debian. Proxmox itself is explained as it comes up.

---

## 0. Proxmox in two minutes (for a Debian admin)

Proxmox VE 9 **is Debian 13 (trixie)**. It's Debian with a Proxmox kernel, KVM/QEMU, LXC, and a web UI on port **8006**. Everything you know about apt, systemd, journald and `/etc` still applies. The parts that are new:

| Concept | What it is |
|---|---|
| **VM** (`qm` CLI) | A full KVM virtual machine with its own kernel. OPNsense (VM 100) and the gate (VM 110) are VMs. |
| **CT** (`pct` CLI) | An LXC container that shares the host kernel. It's light: Pi-hole #1 (CT 101) runs in 512 MB. |
| **`/etc/pve`** | A cluster filesystem (`pmxcfs`, FUSE, backed by SQLite). It holds all VM/CT configs, users, firewall rules and certificates. Don't hand-edit files you aren't told to. |
| **Storage** (`pvesm`) | With the ext4 install you get two: **`local`**, a directory at `/var/lib/vz` that holds ISOs, CT templates and backups, and **`local-lvm`**, an LVM thin pool that holds VM and CT disks. |
| **Bridges** | Ordinary Linux bridges, configured in `/etc/network/interfaces` with **ifupdown2**. A VM's virtual NIC plugs into a bridge, the way a cable plugs into a switch port. Changes made in the GUI are staged in `interfaces.new` until you click **Apply Configuration**, which runs `ifreload -a`. |
| **Realms** | `@pam` users are Linux accounts. `@pve` users exist only in Proxmox. Permissions are ACLs: user + path + role. |
| **Repos** | The **enterprise** repo needs a paid subscription. The **no-subscription** repo is free and fine for a home lab. Without a subscription, the GUI shows a "No valid subscription" popup at login. Ignore it. |

How the network works in this build:

```
Xfinity ──(USB NIC)── vmbr1 ── VM100 open-the-box (WAN)       host has NO IP here
switch  ──(I219-LM)── vmbr0 ─┬ VM100 open-the-box (LAN 10.10.10.1)
                             ├ CT101 pihole-1, VM110 gate
                             └ host management IP (10.10.10.2:8006)
```

**Temporary arrangement during Stage 1.** OPNsense doesn't exist yet, so `10.10.10.0/24` doesn't exist either. You'll install with a **temporary management IP on the Xfinity LAN (`10.0.0.5`)**, with the I219 plugged into the Xfinity gateway or the switch that's currently behind it. Stage 2 runs the cutover in §8.

---

## 1. Installer

Boot USB #1 (F12 → UEFI USB) → **Install Proxmox VE (Graphical)**.

| Screen | Value | Notes |
|---|---|---|
| Target harddisk | The 256 GB NVMe. Click **Options → Filesystem: `ext4`** | **Not ZFS.** It's a single disk, so ZFS gives no redundancy, and its ARC cache would take GBs of RAM away from 16 GB that's already budgeted (§2 of the overview). Leave `hdsize`/`swapsize`/`maxroot` at their defaults: about 60 GB root, 8 GB swap, and the rest goes to `local-lvm`. |
| Country / TZ / keyboard | Yours | |
| Password / email | `root` password from the password manager. Use your real email | The email is where Proxmox sends notifications (Stage 7). |
| Management interface | The one whose driver is **`e1000e`** (the I219-LM) | **Not** the USB NIC. Leave the USB NIC unplugged during the install so you can't pick it by mistake. |
| Hostname (FQDN) | `command-center.home.arpa` | `home.arpa` is the reserved name for home networks (RFC 8375). OPNsense uses the same domain in Stage 2. |
| IP (CIDR) | `10.0.0.5/24` | Temporary (§0). Stage 0 moved Xfinity's DHCP pool to start at `.10`. |
| Gateway / DNS | `10.0.0.1` / `10.0.0.1` | |

⚠️ Verify: some PVE 9.x installers offer to **pin network interface names** (to `nic0`, `nic1`, …). If yours does, accept, and use the pinned names wherever this guide says `enp0s31f6`. Pinning stops a future kernel or firmware update from renaming the NIC, which would leave a firewall host with no network.

Reboot and pull the USB stick when it asks.

✅ Checkpoint: the console shows `https://10.0.0.5:8006/`. From your desktop, open it, accept the self-signed certificate, and log in as `root`, realm **Linux PAM**.

---

## 2. Repositories and updates

You can run everything from here on in **the node's Shell** in the GUI (*Datacenter → command-center → >_ Shell*) or over SSH as root, which still allows passwords at this point. PVE 9 uses deb822 `.sources` files.

```bash
cd /etc/apt/sources.list.d && ls
# expect: ceph.sources  debian.sources  pve-enterprise.sources

# Disable the subscription-only repos (works whether or not an Enabled: line exists)
for f in pve-enterprise.sources ceph.sources; do
  [ -f "$f" ] && { sed -i '/^Enabled:/d' "$f"; echo 'Enabled: no' >> "$f"; }
done

# Add the no-subscription repo
cat > /etc/apt/sources.list.d/proxmox.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# Make sure Debian's non-free-firmware component is there (needed for intel-microcode)
grep -E '^Components' /etc/apt/sources.list.d/debian.sources
grep -q non-free-firmware /etc/apt/sources.list.d/debian.sources || \
  sed -i 's/^Components: main contrib$/Components: main contrib non-free-firmware/' /etc/apt/sources.list.d/debian.sources

apt update
apt full-upgrade -y
apt install -y intel-microcode ethtool sudo htop iftop tmux
```

✅ Checkpoint: `apt update` has no 401 errors from `enterprise.proxmox.com`, and *Node → Updates → Repositories* in the GUI shows no errors. A warning that says "no-subscription repository isn't recommended for production" is expected.

Don't reboot yet. §5 needs a reboot too, so you'll do both at once.

---

## 3. Admin user, 2FA, SSH

The convention (overview §7) is that `eels` is the admin everywhere. On Proxmox that means a Linux account with sudo **and** a matching `eels@pam` Proxmox user with the Administrator role.

```bash
adduser eels                       # password from the password manager
usermod -aG sudo eels
pveum user add eels@pam --comment "Admin"
pveum acl modify / --users eels@pam --roles Administrator
pveum user list
```

**TOTP for the web UI.** *Datacenter → Permissions → Two Factor → Add → TOTP.* Do it once for `root@pam` and once for `eels@pam`. Scan with your authenticator app and test the code. While you're on that screen, also add **Recovery Keys** for both users and store them. Proxmox 2FA applies to web/API logins. It doesn't apply to SSH, which §3's key-only setup covers.

**SSH key.** From your Windows desktop:

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh eels@10.0.0.5 "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"
ssh eels@10.0.0.5        # must log in with the key: you're asked for the key passphrase, not a password
```

**Harden sshd.** Keep the session from the last command open while you do this, so a mistake can't lock you out.

```bash
sudo tee /etc/ssh/sshd_config.d/10-elysidrome.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
AllowUsers eels root
EOF
sudo sshd -t && sudo systemctl reload ssh
```

`root` still gets in **by key only**. Proxmox needs that when the R620 joins as a second node (Stage 8). Cluster join manages those keys itself. Don't put your personal key on root.

✅ Checkpoint, from a **new** PowerShell window:

```powershell
ssh eels@10.0.0.5 id                                 # works with the key
ssh -o PubkeyAuthentication=no eels@10.0.0.5         # must fail: Permission denied (publickey)
```

From now on, use `ssh eels@…` and `sudo -i` for root work. The commands below assume a root shell.

---

## 4. WAN bridge `vmbr1` (USB NIC)

Plug in the USB 3 NIC. Use a **blue** port. Don't connect a cable to it yet.

```bash
ip -br link                         # new interface named enx<mac>, e.g. enx00e04c680123
NIC=enx00e04c680123                 # ← set yours
ethtool -i $NIC | grep driver       # r8152 (Realtek) or ax88179_178a (ASIX)
lsusb -t | grep -B1 -iE 'r8152|ax88179'   # must say 5000M (USB 3). 480M = it's in a USB 2 port
```

The `enx<mac>` name comes from the NIC's MAC address, so it stays the same across reboots. Record it in your inventory.

**Why IPv6 gets disabled on the WAN side.** The host must have **no address on the WAN**: only the OPNsense VM should touch the internet. Linux bridges accept IPv6 router advertisements by default. Xfinity does IPv6, so without the `disable_ipv6` lines below, the Proxmox host would SLAAC itself a **public IPv6 address on the WAN, around your firewall**. Disabling it stops only the host's own IP stack. The bridge still passes IPv6 frames through to OPNsense.

```bash
cp /etc/network/interfaces /etc/network/interfaces.bak-$(date +%F)

cat >> /etc/network/interfaces <<EOF

iface ${NIC} inet manual
	post-up sysctl -qw net.ipv6.conf.${NIC}.disable_ipv6=1

auto vmbr1
iface vmbr1 inet manual
	bridge-ports ${NIC}
	bridge-stp off
	bridge-fd 0
	post-up sysctl -qw net.ipv6.conf.vmbr1.disable_ipv6=1
#WAN - Xfinity (no host IP)
EOF

ifreload -a
```

(The equivalent in the GUI is *Node → System → Network → Create → Linux Bridge*, with bridge ports set to the `enx…` name and no IP, then **Apply Configuration**. The GUI can't add the `post-up` lines, though, so the CLI is simpler here.)

✅ Checkpoint:

```bash
bridge link                          # enx… master vmbr1, enp0s31f6 master vmbr0
ip -br addr show vmbr1               # vmbr1  UP  (no addresses at all)
ip -6 addr show dev vmbr1            # prints nothing
cat /proc/sys/net/ipv6/conf/vmbr1/disable_ipv6   # 1
```

Leave the USB NIC **without a cable** until Stage 2.

### 4.1 Known issue: Intel I219 "Hardware Unit Hang"

The `e1000e` driver on some I219 chips drops the link under load with TSO/GSO enabled. Check whether it has happened (run this again after Stage 2 has real traffic flowing):

```bash
journalctl -k | grep -i 'hardware unit hang'
```

Only if it shows up: add the line below to the `iface enp0s31f6 inet manual` stanza in `/etc/network/interfaces`, then run `ifreload -a`.

```
	post-up ethtool -K enp0s31f6 tso off gso off
```

---

## 5. Laptop-as-server tweaks

**Lid closed = keep running.**

```bash
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-lid.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
```

**Kernel command line.** The screen blanks after 2 minutes, and USB autosuspend is off. Autosuspend can make the USB WAN NIC drop off the bus. An ext4 install boots via **GRUB**, so edit `/etc/default/grub`:

```bash
proxmox-boot-tool status            # "not configured" / GRUB is expected on an ext4 install
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet consoleblank=120 usbcore.autosuspend=-1"/' /etc/default/grub
grep ^GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
update-grub
```

⚠️ Verify: if `proxmox-boot-tool status` instead says it manages ESPs with **systemd-boot**, put the parameters in `/etc/kernel/cmdline` (one line, appended to what's there) and run `proxmox-boot-tool refresh` instead of `update-grub`.

**Battery = UPS.** Shut down cleanly when the battery is running low. Proxmox's `pve-guests` service stops the VMs and CTs gracefully before the host powers off.

```bash
ls /sys/class/power_supply/          # expect AC and BAT0 (⚠️ adjust the names below if different)

cat > /usr/local/sbin/battery-guard <<'EOF'
#!/bin/sh
# Clean shutdown when on battery and capacity <= 25 %.
AC=/sys/class/power_supply/AC/online
CAP=/sys/class/power_supply/BAT0/capacity
[ -r "$AC" ] && [ -r "$CAP" ] || exit 0
if [ "$(cat "$AC")" = 0 ] && [ "$(cat "$CAP")" -le 25 ]; then
  logger -t battery-guard "On battery at $(cat "$CAP")%, shutting down"
  systemctl poweroff
fi
EOF
chmod 755 /usr/local/sbin/battery-guard

cat > /etc/systemd/system/battery-guard.service <<'EOF'
[Unit]
Description=Shut down cleanly on low battery

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/battery-guard
EOF

cat > /etc/systemd/system/battery-guard.timer <<'EOF'
[Unit]
Description=Check battery every minute

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now battery-guard.timer
```

Test it: pull the AC cable for about 10 seconds.

```bash
cat /sys/class/power_supply/AC/online     # 0 while unplugged, 1 after
sh -x /usr/local/sbin/battery-guard       # on battery: shows the test evaluating, no shutdown (capacity > 25)
```

Together with BIOS **Wake on AC** (Stage 0 §7), the host comes back on by itself when power returns. Stage 2 sets the VMs to start at boot.

Keep in mind that the battery keeps the **firewall** up, but the **Xfinity gateway** has no battery. If you want the internet to stay up during outages, put the gateway and the switch on a small UPS. Otherwise the battery mainly buys you clean shutdowns and no filesystem damage.

**Reboot now.** That applies the kernel, microcode, cmdline and logind changes.

```bash
reboot
```

✅ Checkpoint after the reboot:

```bash
cat /proc/cmdline                                    # contains consoleblank=120 usbcore.autosuspend=-1
cat /sys/module/usbcore/parameters/autosuspend       # -1
journalctl -b | grep -i microcode | head -3          # microcode updated / revision line
systemctl list-timers battery-guard.timer            # next run scheduled
ip -6 addr show dev vmbr1                            # still nothing
```

Close the lid and confirm that SSH and the web UI stay up.

---

## 6. Stage 2 installers onto `local`

Download these now, while the host still has internet through Xfinity. During the Stage 2 cutover there's a window where it has none (§8).

**OPNsense** (installed as VM 100 in Stage 2):

```bash
cd /var/lib/vz/template/iso
OPN=26.7            # ⚠️ Verify: set this to the current release on opnsense.org/download
wget https://pkg.opnsense.org/releases/${OPN}/OPNsense-${OPN}-dvd-amd64.iso.bz2
wget https://pkg.opnsense.org/releases/${OPN}/OPNsense-${OPN}-checksums-amd64.sha256
sha256sum -c --ignore-missing OPNsense-${OPN}-checksums-amd64.sha256   # → dvd-amd64.iso.bz2: OK
bunzip2 OPNsense-${OPN}-dvd-amd64.iso.bz2
rm OPNsense-${OPN}-checksums-amd64.sha256
```

⚠️ Verify: if `pkg.opnsense.org` doesn't serve `/releases/`, choose a mirror from the download page. The path after the mirror's base URL is the same.

**Debian 13 netinst** (the gate VM 110 in Stage 4):

```bash
cd /var/lib/vz/template/iso
BASE=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd
wget -q $BASE/SHA256SUMS
DEB=$(grep -o 'debian-13[^ ]*-amd64-netinst\.iso' SHA256SUMS | head -1); echo $DEB
wget $BASE/$DEB
sha256sum -c --ignore-missing SHA256SUMS            # → netinst.iso: OK
rm SHA256SUMS
```

**Debian 13 LXC template** (Pi-hole #1, CT 101, Stage 3):

```bash
pveam update
pveam available --section system | grep debian-13
pveam download local $(pveam available --section system | awk '/debian-13-standard/ {print $2}' | tail -1)
```

✅ Checkpoint:

```bash
pvesm list local          # shows the OPNsense .iso, the Debian .iso, the debian-13-standard .tar.zst
```

---

## 7. Final checks

```bash
pveversion                            # pve-manager/9.x
systemctl --failed                    # 0 loaded units listed
journalctl -p err -b --no-pager       # read it; nothing recurring or network-related
pvesm status                          # local + local-lvm both "active"
chronyc tracking | grep -E 'Leap|System time'   # Leap status: Normal
smartctl -H /dev/nvme0n1              # PASSED
free -h                               # ~15 GiB total, almost all free (nothing running yet)
```

The firewall is still off at the Datacenter level (the default). That's deliberate: the host isn't exposed yet, and Stage 7 turns the Proxmox firewall on along with the rest of the hardening.

---

## Stage 1 done when

- [ ] Web UI works with TOTP for `root@pam` and `eels@pam`
- [ ] SSH works with the key only, and password login is refused
- [ ] Updated from the no-subscription repo, microcode loaded
- [ ] `vmbr1` exists on the USB NIC with no IPv4 and no IPv6, cable not connected yet
- [ ] Lid, console blanking, USB autosuspend and battery-guard all verified after the reboot
- [ ] OPNsense ISO, Debian ISO and Debian 13 CT template are on `local`

**Next:** `03-stage2-open-the-box-opnsense.md`. It begins with §8.

---

## 8. Cutover to `10.10.10.2` (run only when Stage 2 tells you to)

This puts the host on its permanent LAN and cables the box in its final layout. **Do it at the Latitude's own keyboard and screen.** SSH goes down the moment the IP changes.

1. Cables: **USB NIC → Xfinity gateway LAN port. I219 (onboard) → your switch.** No other device stays on the Xfinity LAN except Wi-Fi clients (overview §3).
2. On the console, as root:

```bash
cp /etc/network/interfaces /etc/network/interfaces.bak-cutover
sed -i 's#address 10\.0\.0\.5/24#address 10.10.10.2/24#; s#gateway 10\.0\.0\.1#gateway 10.10.10.1#' /etc/network/interfaces
sed -i 's/^10\.0\.0\.5\([[:space:]]\)/10.10.10.2\1/' /etc/hosts
printf 'search home.arpa\nnameserver 10.10.10.1\n' > /etc/resolv.conf
ifreload -a
ip -br addr show vmbr0                # 10.10.10.2/24
grep command-center /etc/hosts        # 10.10.10.2 command-center.home.arpa command-center
```

3. Until OPNsense is serving DHCP on the LAN, give your desktop a **static** address so you can reach the web UI: `10.10.10.50/24`, gateway `10.10.10.1`, DNS `10.10.10.1`.

```powershell
# Admin PowerShell on the desktop. Get the interface alias from Get-NetAdapter
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.10.10.50 -PrefixLength 24 -DefaultGateway 10.10.10.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.10.10.1
# Revert to DHCP after Stage 2:
# Remove-NetIPAddress -InterfaceAlias "Ethernet" -Confirm:$false; Remove-NetRoute -InterfaceAlias "Ethernet" -DestinationPrefix 0.0.0.0/0 -Confirm:$false
# Set-NetIPInterface -InterfaceAlias "Ethernet" -Dhcp Enabled; Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses
```

✅ `https://10.10.10.2:8006` loads from the desktop. The host has no internet until OPNsense is up. That's expected, and it's why §6 downloaded everything first.

**Rollback** if something goes wrong:

```bash
cp /etc/network/interfaces.bak-cutover /etc/network/interfaces
sed -i 's/^10\.10\.10\.2\([[:space:]]\)/10.0.0.5\1/' /etc/hosts
printf 'search home.arpa\nnameserver 10.0.0.1\n' > /etc/resolv.conf
ifreload -a
```

Then move the I219 cable back to the Xfinity side.
