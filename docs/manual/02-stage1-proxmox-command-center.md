# Elysidrome Build Manual — 02: Stage 1, Proxmox on command-center

> **Goal:** Proxmox VE 9 installed, updated and locked down on the Latitude 5580, with the bridges Stage 2 needs and the installers for Stages 2–4 already on the box.
> **Time:** ~2 h. **The house network is not touched.** Family internet keeps working.
> **You need:** the Proxmox USB stick, the USB 3 NIC, one Ethernet cable, and your Windows desktop.

---

## 1. Proxmox in five minutes

| Proxmox term | What it is | Closest thing you already know |
|---|---|---|
| **Proxmox VE** | Debian 13 + the KVM hypervisor + LXC containers + a web UI (`https://<ip>:8006`). | Debian with a built-in ESXi/Hyper-V Manager |
| **Node** | One physical Proxmox host. `command-center` is your only node until the R620 joins in Stage 8. | A Hyper-V host |
| **Datacenter** | The top of the tree in the UI. Holds settings shared by all nodes (users, permissions, storage definitions, firewall). | A vCenter / AD "domain" level |
| **VM** (QEMU/KVM) | Full virtual machine with its own kernel. Used for OPNsense (VM 100) and the gate (VM 110). | Hyper-V VM |
| **CT** (LXC container) | Shares the host's kernel, much lighter. Used for Pi-hole (CT 101). | A chroot/jail with its own network stack |
| **VMID** | Every guest has a number: 100–999 is yours. The plan uses 100, 101, 110. | — |
| **Storage `local`** | A directory (`/var/lib/vz`) for **files**: ISOs, CT templates, backup files. | A share for install media |
| **Storage `local-lvm`** | An LVM-thin pool for **guest disks**. Thin means a 32 GB disk only uses what's written. | Dynamic VHDX |
| **Linux bridge (`vmbrN`)** | A virtual switch inside the host. Physical NIC = uplink port; each guest NIC plugs into a bridge. | Hyper-V virtual switch (external) |
| **Repositories** | Proxmox ships pointed at the paid **enterprise** repo. Without a subscription you switch to **no-subscription**, which is free and fine for a home lab. | — |
| **Subscription nag** | A popup at login saying you have no subscription. Harmless; click **OK**. | — |

**How your two NICs map to bridges** (this is the heart of the whole build):

```
                 Latitude (command-center)
  USB 3 NIC ──► vmbr1 (WAN bridge) ──► OPNsense WAN    (Stage 2)
  (to Xfinity)    host has NO IP here after Stage 2

  I219-LM   ──► vmbr0 (LAN bridge) ──► OPNsense LAN, pihole-1, gate
  (to switch)     host mgmt IP 10.10.10.2
```

The host itself must never be reachable on the WAN side, so after Stage 2 `vmbr1` carries traffic for OPNsense but has no address of its own.

### The chicken-and-egg problem, and the Stage 1 workaround

The host's real address, `10.10.10.2`, lives on a LAN (`10.10.10.0/24`) that doesn't exist until OPNsense is built in Stage 2. But Proxmox needs internet now for updates.

So for Stage 1 only:

- `vmbr0` gets its final address `10.10.10.2/24` but **no gateway** and no cable (nothing to talk to yet).
- `vmbr1` (USB NIC) is cabled to the Xfinity gateway or your current switch and **temporarily takes a DHCP address** from Xfinity (`10.0.0.x`). You reach the web UI and SSH on that address from your desktop, and the host gets updates through it.

Stage 2's first step flips this: `vmbr1` loses its address and `vmbr0` gets its gateway back. While it's in this temporary state the host is on the Xfinity LAN, which also has Wi-Fi guests, so do §6 (passwords, 2FA, SSH keys) the same day.

---

## 2. BIOS settings on the Latitude

Power on, tap **F2** at the Dell logo.

| Setting (Dell BIOS path) | Value | Why |
|---|---|---|
| System Configuration → **SATA Operation** | **AHCI** | Default "RAID On" hides the NVMe drive from Linux. The installer will show no disk if you skip this. |
| Virtualization Support → **Virtualization** | Enabled | Required for KVM VMs. |
| Virtualization Support → **VT for Direct I/O** | Enabled | IOMMU; not needed today, needed for any later passthrough. |
| Power Management → **AC Behavior → Wake on AC** | Enabled | Box powers itself back on when power returns after the battery ran out. |
| Power Management → **Primary Battery Charge Configuration** | **Custom**: start 50 %, stop 80 % | It'll be plugged in 24/7; holding at 100 % wears the battery that's acting as your UPS. |
| Wireless → **Wireless Device Enable** | Untick WLAN and Bluetooth | Unused radios on a firewall host are attack surface. |
| Secure Boot | Leave **enabled** | Proxmox VE 8.1+ boots with Secure Boot. |
| Security → Admin Password | Set one (generate it, store in KeePassXC as `Hosts/command-center BIOS`) | Stops anyone booting a USB stick on your firewall. |

⚠️ Verify: if your 5580 is a vPro model, Intel AMT can listen on the onboard NIC. Look for **Intel AMT Capability** (or press **Ctrl+P** at boot for MEBx) and disable it.

**Apply → Exit.**

---

## 3. Install

1. Plug in the Proxmox stick. Power on, tap **F12**, pick the USB device (UEFI).
2. Choose **Install Proxmox VE (Graphical)**.
3. Accept the EULA.
4. **Target harddisk:** the 256 GB NVMe. Leave **Options → Filesystem = ext4** (the default gives you `local` + `local-lvm`). ZFS is great with multiple disks and plenty of RAM; on one disk with 16 GB it just eats RAM you want for guests.
5. **Location/time zone:** your country, your time zone, keyboard **U.S. English**.
6. **Administration password:** generate one in KeePassXC (letters + digits, ~20 chars; you'll type it at a console). Store it as `Hosts/command-center root`. **Email:** your real address (Proxmox sends alerts here later).
7. **Management network configuration:**

   | Field | Value |
   |---|---|
   | Management interface | The **onboard** NIC, usually `enp0s31f6` (driver `e1000e`). **Not** the USB NIC (`enx…`, driver `r8152`). Leave the USB NIC unplugged during install so there's only one choice. |
   | Hostname (FQDN) | `command-center.home.arpa` |
   | IP address (CIDR) | `10.10.10.2/24` |
   | Gateway | `10.10.10.1` |
   | DNS server | `10.10.10.1` |

   If the installer offers to **pin network interface names**, accept it. It stops a future kernel update from renaming NICs and breaking the bridges.

   > **Why `home.arpa`:** it's the domain reserved for home networks (RFC 8375). Using `command-center.elysidrome.com` would collide with Pi-hole answering `*.elysidrome.com → 10.10.10.10` (overview §4). Every internal hostname in this build uses `<name>.home.arpa`; Stage 2 sets the same domain in OPNsense.

8. **Summary → Install.** Remove the stick when it says to, let it reboot.

✅ Checkpoint: the console shows a login prompt with a banner saying `https://10.10.10.2:8006/`. (That URL won't work yet; see §1.)

---

## 4. Temporary uplink (console work)

Plug the **USB NIC** into the Latitude and cable it to the Xfinity gateway (or your current switch, which is on the Xfinity LAN). Leave the onboard port **unplugged**.

On command-center (console, as root):

```bash
ip -br link
```

You'll see `lo`, the onboard NIC (e.g. `enp0s31f6`), `vmbr0`, and the USB NIC as `enx` followed by its MAC (e.g. `enx00e04c680123`). Write the `enx…` name down.

```bash
cp /etc/network/interfaces /root/interfaces.installer
nano /etc/network/interfaces
```

Make the file look like this (keep your real NIC names):

```
auto lo
iface lo inet loopback

iface enp0s31f6 inet manual

# LAN bridge: onboard I219-LM -> your switch. Host mgmt 10.10.10.2.
auto vmbr0
iface vmbr0 inet static
        address 10.10.10.2/24
#       gateway 10.10.10.1      # STAGE 1: commented out. Stage 2 uncomments it.
        bridge-ports enp0s31f6
        bridge-stp off
        bridge-fd 0

iface enx00e04c680123 inet manual

# WAN bridge: USB 3 NIC -> Xfinity gateway. OPNsense WAN plugs in here.
auto vmbr1
iface vmbr1 inet dhcp           # STAGE 1 ONLY. Stage 2 changes this to "manual".
        bridge-ports enx00e04c680123
        bridge-stp off
        bridge-fd 0
```

Apply and check:

```bash
ifreload -a
ip -4 -br addr show vmbr1          # note the 10.0.0.x address
ip route                           # default via 10.0.0.1 dev vmbr1
ping -c3 download.proxmox.com
```

If DNS fails but `ping -c3 1.1.1.1` works, point the resolver at Xfinity for now (Stage 2 sets it back to `10.10.10.1`):

```bash
printf 'search home.arpa\nnameserver 10.0.0.1\n' > /etc/resolv.conf
```

✅ Checkpoint: `ping download.proxmox.com` gets replies. From your desktop, `https://10.0.0.x:8006` shows the Proxmox login (accept the self-signed certificate warning; Stage 4's certificates don't cover this host, so the warning is permanent and expected on the LAN). Log in as `root`, realm **Linux PAM**.

Optional but easy: reserve that `10.0.0.x` address for the USB NIC's MAC in the Xfinity app so it doesn't move during Stage 1.

From here on, work from the desktop: web UI **Shell** button, or SSH.

```powershell
ssh root@10.0.0.x
```

---

## 5. Repositories and updates

Proxmox VE 9 uses the deb822 `.sources` format. Turn off the two enterprise repos and add no-subscription.

On command-center (as root):

```bash
# Disable enterprise repos (they 401 without a subscription)
for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
  if [ -f "$f" ] && ! grep -q '^Enabled:' "$f"; then echo 'Enabled: no' >> "$f"; fi
done

# Add the free repo
cat > /etc/apt/sources.list.d/proxmox.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

apt update
apt full-upgrade -y
```

**Always `full-upgrade` (or `dist-upgrade`) on Proxmox, never plain `apt upgrade`.** Plain upgrade can hold back packages that must move together and leave Proxmox half-updated.

Same thing in the UI: node `command-center` → **Updates → Repositories** → select each enterprise line → **Disable**; **Add** → **No-Subscription**.

CPU microcode and a few tools:

```bash
grep -q non-free-firmware /etc/apt/sources.list.d/debian.sources || \
  sed -i 's/^Components: main contrib$/Components: main contrib non-free-firmware/' /etc/apt/sources.list.d/debian.sources
apt update
apt install -y intel-microcode sudo vim htop curl ethtool bzip2 lm-sensors
reboot
```

✅ Checkpoint (after reboot, SSH back in):

```bash
pveversion            # pve-manager/9.x...
apt update            # no 401/Unauthorized errors, no enterprise lines
journalctl -k | grep -i microcode | head -3
```

---

## 6. Accounts, 2FA and SSH

### 6.1 The `eels` admin

Proxmox has its own user list (**realms**). `@pam` users are real Linux accounts; `@pve` users exist only inside Proxmox. Using `eels@pam` means the same login works for SSH, sudo and the web UI.

```bash
adduser eels                       # generate the password, store as Hosts/command-center eels
usermod -aG sudo eels
pveum user add eels@pam --comment "Eels admin"
pveum acl modify / --users eels@pam --roles Administrator
```

### 6.2 Two-factor on the web UI

Log in to the web UI as `eels` (realm Linux PAM) → top-right **eels@pam → TFA → Add → TOTP**. Scan with your authenticator app, confirm with a code. Then **Add → Recovery Keys**, store them in KeePassXC.

Repeat as `root@pam`. Root keeps working at the physical console regardless, so you can't lock yourself out of the box.

✅ Checkpoint: log out, log back in as `eels@pam`, and you're asked for a TOTP code.

### 6.3 SSH keys, then no passwords over SSH

On the Windows desktop:

```powershell
ssh-keygen -t ed25519 -C "eels@desktop"          # accept the default path, set a passphrase
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh eels@10.0.0.x "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@10.0.0.x "cat >> /root/.ssh/authorized_keys"
ssh eels@10.0.0.x                                 # must log in with no password prompt
```

Proxmox keeps root's `authorized_keys` as a symlink into `/etc/pve`. Appending to it like this is fine.

On command-center (as root):

```bash
cat > /etc/ssh/sshd_config.d/10-elysidrome.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
sshd -t && systemctl reload ssh
```

`prohibit-password` instead of `no`: Proxmox clustering (the R620 in Stage 8) needs root-to-root SSH with keys.

✅ Checkpoint: in a **new** PowerShell window, `ssh eels@10.0.0.x` works with the key, and `ssh -o PubkeyAuthentication=no eels@10.0.0.x` is refused. Keep the old session open until both are true.

---

## 7. Laptop-as-server settings

### 7.1 Lid closed, screen off

```bash
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-lid.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
systemctl restart systemd-logind

# Blank the console after 60 s
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 consoleblank=60"/' /etc/default/grub
grep ^GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
update-grub
```

✅ Checkpoint: close the lid; `ping 10.0.0.x` from the desktop keeps answering.

### 7.2 Keep the USB NIC awake

USB autosuspend can drop the WAN link. Find the adapter's vendor/product IDs, then pin power on:

```bash
lsusb | grep -i -E 'realtek|asix|ethernet'      # e.g. ID 0bda:8153 Realtek ... RTL8153
cat > /etc/udev/rules.d/50-usb-nic-power.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8153", TEST=="power/control", ATTR{power/control}="on"
EOF
udevadm control --reload
```

(Change `0bda`/`8153` if `lsusb` shows different IDs.) It takes effect at the next boot or replug.

### 7.3 Shut down cleanly when the battery runs out

Without this, a long outage drains the battery and the firewall loses power mid-write.

```bash
apt install -y upower
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

⚠️ Verify: if `/etc/UPower/UPower.conf.d/` doesn't exist on your version, put the same keys in `/etc/UPower/UPower.conf` instead. Test it once in Stage 7 by unplugging and watching the log (`journalctl -fu upower`), not now.

When a power-off happens, Proxmox shuts guests down in reverse start order. Stages 2–4 set the start order (OPNsense first, then Pi-hole, then the gate) on each guest's **Options → Start/Shutdown order**.

### 7.4 Onboard NIC hang (only if you see it)

The I219 (`e1000e`) on some laptops logs `Detected Hardware Unit Hang` under load and drops the link. If you ever see that in `journalctl -k`, add this line under `iface vmbr0` and run `ifreload -a`:

```
        post-up /usr/sbin/ethtool -K enp0s31f6 tso off gso off
```

---

## 8. Stage the installers for Stages 2–4

`local` storage keeps ISOs in `/var/lib/vz/template/iso/` and container templates in `/var/lib/vz/template/cache/`.

On command-center (as root):

```bash
cd /var/lib/vz/template/iso

# OPNsense (Stage 2): copy the "dvd" amd64 link from https://opnsense.org/download/
OPN_URL='<paste the .iso.bz2 link>'
wget "$OPN_URL"
wget "$(dirname "$OPN_URL")/$(basename "$OPN_URL" | sed 's/-dvd-amd64.iso.bz2/-checksums-amd64.sha256/')"
sha256sum -c --ignore-missing OPNsense-*-checksums-amd64.sha256   # must print "OK" for your file
bunzip2 OPNsense-*-dvd-amd64.iso.bz2

# Debian 13 netinst (Stage 4 gate VM)
BASE=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd
wget -q $BASE/SHA256SUMS
ISO=$(awk '$2 ~ /^debian-[0-9.]+-amd64-netinst\.iso$/ {print $2}' SHA256SUMS)
wget $BASE/$ISO
sha256sum -c --ignore-missing SHA256SUMS                          # must print "<file>: OK"
rm SHA256SUMS OPNsense-*-checksums-amd64.sha256

# Debian 13 container template (Stage 3 pihole-1)
pveam update
TPL=$(pveam available --section system | awk '/debian-13-standard/ {print $2}' | sort -V | tail -1)
pveam download local "$TPL"
```

⚠️ Verify: if the OPNsense checksum file has a different name on the mirror, download it by hand from the same folder as the image. If its line names the `.iso` rather than the `.bz2`, run `bunzip2` first and then `sha256sum -c`.

✅ Checkpoint: web UI → **local (command-center)** → **ISO Images** lists the OPNsense and Debian ISOs; **CT Templates** lists `debian-13-standard_…`.

---

## 9. Optional: a 10-minute tour

Run this in the same shell as §8 (it reuses `$TPL`). The fastest way to understand guests is to make one and throw it away. CT 999 is a scratch number nothing else uses.

```bash
pct create 999 local:vztmpl/$TPL --hostname scratch --cores 1 --memory 512 \
  --rootfs local-lvm:4 --net0 name=eth0,bridge=vmbr1,ip=dhcp --unprivileged 1
pct start 999
pct enter 999            # you're root inside the container
ip -br a; cat /etc/os-release | head -2; exit
pct stop 999 && pct destroy 999
```

Watch it appear and disappear in the left tree while you do it. **Unprivileged** means root inside the container is a nobody on the host; every container in this build is unprivileged.

---

## 10. Save the host config off the box

```bash
tar czf /root/command-center-stage1-$(date +%F).tgz \
  /etc/network/interfaces /etc/hosts /etc/apt/sources.list.d \
  /etc/ssh/sshd_config.d /etc/systemd/logind.conf.d /etc/udev/rules.d \
  /etc/default/grub /etc/UPower /etc/pve/user.cfg /etc/pve/datacenter.cfg 2>/dev/null
```

On the Windows desktop:

```powershell
scp root@10.0.0.x:/root/command-center-stage1-*.tgz $HOME\Documents\Elysidrome\
```

---

## 11. What Stage 2 changes (hand-off)

Stage 2 starts by flipping the temporary network from §4. Don't do it yet; it's here so you know what's coming:

1. Create the OPNsense VM with **net0 → vmbr1 (WAN)** and **net1 → vmbr0 (LAN)**.
2. Edit `/etc/network/interfaces`: `iface vmbr1 inet dhcp` → `iface vmbr1 inet manual`; uncomment `gateway 10.10.10.1` under `vmbr0`.
3. Cable the onboard port to your switch. Set DNS back to `10.10.10.1` (node → **System → DNS**).
4. From then on the web UI is `https://10.10.10.2:8006` from the LAN or WireGuard only (overview port map).

---

## 12. Stage 1 exit checklist

- [ ] BIOS: AHCI, virtualization on, Wake on AC, battery 50–80 %, radios off, BIOS password set
- [ ] Proxmox VE 9 installed: `command-center.home.arpa`, `vmbr0` = `10.10.10.2/24` on the onboard NIC
- [ ] `vmbr1` on the USB NIC, temporary DHCP from Xfinity, internet works
- [ ] No-subscription repo, `apt full-upgrade` done, microcode installed, rebooted
- [ ] `eels@pam` is Administrator; TOTP + recovery keys for `eels` and `root`
- [ ] SSH key login works; password SSH refused
- [ ] Lid-close ignored, console blanks, USB NIC autosuspend off, low-battery power-off configured
- [ ] OPNsense ISO, Debian 13 ISO and Debian 13 CT template on `local`, checksums OK
- [ ] Config tarball copied to the desktop

Next: **Stage 2 — open-the-box (OPNsense)** (`03-stage2-open-the-box-opnsense.md`).
