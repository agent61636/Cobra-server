# 1. Set up Latitude (cobra-command, Proxmox VE 9)

**Result:** the Latitude runs Proxmox, is updated and locked down, and has the installers for OPNsense (part 2), Pi-hole (part 2) and the gate VM (part 5) waiting on it. Part 2 then turns it into the house gateway by running OPNsense as a VM on it.

**Needs:** Proxmox USB stick, USB 3 NIC (RTL8153), one Ethernet cable, your Windows desktop. **The house network is not touched in this part.**

**Your network today:** the Xfinity gateway is the router at `10.6.9.1` and hands out `10.6.9.x` addresses. That's also the range your finished LAN uses behind OPNsense, so for all of part 1 the Latitude simply joins today's network at its **final** address, `10.6.9.2`. In part 2's cutover, OPNsense takes over `10.6.9.1` and Xfinity moves to its own default range, `10.0.0.x`. The Latitude's settings don't change at all.

---

## Cables at a glance

"TP-Link" = the USB 3 NIC. "Onboard" = the Latitude's built-in Ethernet port.

| Steps | Onboard port | TP-Link USB NIC |
|---|---|---|
| 1.2–1.3 (BIOS) | empty | not plugged into the laptop |
| 1.4 to end of part 1 | cable → **your switch** (still connected to Xfinity, like today) | plugged into a USB port, **no cable** |
| Part 2, 2.2–2.3 | → switch (unchanged) | no cable (unchanged) |
| Part 2, 2.4 onward (final) | → switch | cable → **Xfinity gateway** directly; the switch's own cable to Xfinity is unplugged |

Each step below starts with a 🔌 line saying what should be plugged in.

---

## 1.1 Proxmox in one table

Proxmox VE is Debian with a hypervisor and a web UI on top. Everything below can be done in the web UI *or* in a root shell. This guide gives the shell command and names the UI spot.

| Term | What it is here |
|---|---|
| **Node** | The Latitude itself (`cobra-command`). Left tree: Datacenter → cobra-command. |
| **Datacenter** | Settings shared by all nodes: users, permissions, storage, backup jobs. You have one node until the R620 joins. |
| **VM** | Full virtual machine. VM **100** = OPNsense (`cobra-firewall`), VM **110** = `cobra-gate`. CLI: `qm`. |
| **CT** | LXC container, shares the host kernel, much lighter. CT **101** = `cobra-pihole-1`. CLI: `pct`. |
| **VMID** | Every VM/CT has a number. You'll only use 100, 101, 110 (and 9xx for throwaway tests). |
| **`local`** storage | Folder `/var/lib/vz`. Holds ISO files, CT templates, backup files. UI: cobra-command → local. |
| **`local-lvm`** storage | Thin LVM pool. Holds VM/CT disks. Thin = a 32 GB disk only uses what's written. |
| **`vmbr0`, `vmbr1`** | Linux bridges = virtual switches. A physical NIC is the bridge's uplink; VM NICs plug into bridges. |
| **Shell** | cobra-command → **>_ Shell** in the UI gives a root terminal in the browser. Same as SSH. |
| **Console** | VM/CT → **Console** = that guest's screen and keyboard. |
| **Subscription popup** | Appears at every login. Harmless. Click **OK**. |

### How the two NICs will be used

| Physical port | Bridge | Part 1 (now) | After part 2 |
|---|---|---|---|
| Onboard I219-LM (`enp0s31f6`) | `vmbr0` = **LAN** | `10.6.9.2/24`, gateway `10.6.9.1` (today that's Xfinity), cabled to your switch | Exactly the same; `10.6.9.1` is now OPNsense |
| USB 3 NIC (`enx…`) | `vmbr1` = **WAN** | No IP, no cable | Cabled to Xfinity. Host still has **no IP** here; only OPNsense's WAN uses it |

**Before you pick `.2`:** today Xfinity's DHCP hands out addresses from low numbers up, so it may give `.2` to something else. In the Xfinity app, either reserve `10.6.9.2` for the Latitude's onboard NIC, or set the DHCP range to start at `.100`. Do the same for every address in the IP plan you'll use before the cutover.

Finish 1.7 (2FA, SSH keys) the same day: until part 2, the host sits on the Xfinity network with nothing in front of it.

---

## 1.2 Before wiping

- [ ] Anything you want off the Latitude is copied elsewhere
- [ ] Download the Proxmox VE 9.x ISO from proxmox.com/downloads; check it on the desktop:
  ```powershell
  Get-FileHash .\proxmox-ve_9*.iso -Algorithm SHA256     # must equal the SHA256 on the download page
  ```
- [ ] Rufus → select ISO → GPT / UEFI → Start → choose **DD Image mode** when asked
- [ ] Optional while Windows is still on it: update the Dell BIOS (dell.com/support → service tag → BIOS)

## 1.3 BIOS (F2 at the Dell logo)

🔌 Onboard: empty · TP-Link: not plugged in


- [ ] System Configuration → SATA Operation → **AHCI** (*default "RAID On" hides the NVMe, and the installer shows no disk*)
- [ ] Virtualization Support → Virtualization → **Enabled**; VT for Direct I/O → **Enabled**
- [ ] Power Management → AC Behavior → **Wake on AC** → Enabled (powers back on after an outage)
- [ ] Power Management → Primary Battery Charge Configuration → **Custom**, start **50**, stop **80** (battery is the UPS; don't cook it at 100 %)
- [ ] Wireless → Wireless Device Enable → untick WLAN and Bluetooth
- [ ] Security → Admin Password → set one, store it
- [ ] vPro models only: disable Intel AMT (BIOS, or Ctrl+P at boot → MEBx). AMT listens on the onboard NIC.
- [ ] Secure Boot: leave on
- [ ] Apply → Exit

## 1.4 Install

🔌 Onboard → your switch · TP-Link: not plugged in

| # | Screen | Choose / type |
|---|---|---|
| 1 | Boot | Stick in, power on, **F12**, pick the UEFI USB entry |
| 2 | Menu | **Install Proxmox VE (Graphical)** → I agree |
| 3 | Target harddisk | The 256 GB NVMe. **Options** → Filesystem **ext4** (default). *ZFS wants more disks and RAM.* |
| 4 | Location | Country, time zone, keyboard **U.S. English** |
| 5 | Password / Email | Generated root password (letters + digits, ~20 chars; you'll type it on the console). Real email for alerts. |
| 6 | Management interface | Onboard NIC, usually **`enp0s31f6`** |
| 7 | Hostname (FQDN) | **`cobra-command.home.arpa`** (*not* `.songofeo.com`: Pi-hole sends that whole domain to the gate) |
| 8 | IP address (CIDR) | **`10.6.9.2/24`**. ⚠️ The installer pre-fills whatever address DHCP just handed out (e.g. `10.6.9.34`). **Overwrite it**, or that address becomes permanent. |
| 9 | Gateway | **`10.6.9.1`** |
| 10 | DNS server | **`10.6.9.1`** |
| 11 | "Pin network interface names" (if shown) | **Yes** (stops a kernel update from renaming NICs) |
| 12 | Summary | Check the IP says `10.6.9.2/24`, then **Install**. Pull the stick when told; it reboots. |

✅ Console shows a login prompt and `https://10.6.9.2:8006/`, and that page opens from the desktop.

## 1.5 Network config (on the Latitude's own keyboard)

🔌 **Now** plug the TP-Link into a USB port, **no cable** yet. Onboard → switch.

- [ ] Log in as `root`

**Already installed with the wrong address** (e.g. `10.6.9.34`)? This section fixes it; the address lives in two files.

```bash
ip -br link                                   # USB NIC shows as enx<mac>; write the name down
cp /etc/network/interfaces /root/interfaces.installer
nano /etc/network/interfaces
```

Replace the whole file with this, using your real `enx…` name (nano: Ctrl+O Enter to save, Ctrl+X to exit):

```
auto lo
iface lo inet loopback

iface enp0s31f6 inet manual

# LAN bridge (onboard NIC -> switch). Host management address. Never changes.
auto vmbr0
iface vmbr0 inet static
        address 10.6.9.2/24
        gateway 10.6.9.1
        bridge-ports enp0s31f6
        bridge-stp off
        bridge-fd 0

iface enxXXXXXXXXXXXX inet manual

# WAN bridge (USB NIC -> Xfinity in part 2). The host never has an address here;
# only OPNsense's WAN NIC uses it.
auto vmbr1
iface vmbr1 inet manual
        bridge-ports enxXXXXXXXXXXXX
        bridge-stp off
        bridge-fd 0
```

Proxmox also needs its own name to point at its address:

```bash
sed -i -E 's/^10\.6\.9\.[0-9]+(\s+cobra-command)/10.6.9.2\1/' /etc/hosts
grep cobra-command /etc/hosts                # 10.6.9.2 cobra-command.home.arpa cobra-command
printf 'search home.arpa\nnameserver 10.6.9.1\n' > /etc/resolv.conf
ifreload -a                                   # applies the file without a reboot
ip -br addr                                   # vmbr0 10.6.9.2/24; vmbr1 has NO address
ping -c3 download.proxmox.com
systemctl restart pve-cluster pveproxy        # only needed if you changed the address
```

- [ ] On the desktop: browse to `https://10.6.9.2:8006` → accept the certificate warning (self-signed; normal) → user `root`, realm **Linux PAM** → OK on the subscription popup

From here, work from the desktop: `ssh root@10.6.9.2`, or the UI's **>_ Shell**.

## 1.6 Repositories and updates

🔌 Onboard → switch · TP-Link: plugged in, no cable


Proxmox ships pointed at the paid **enterprise** repo, which fails without a subscription. Switch to the free **no-subscription** repo.

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
apt update                                    # no "401 Unauthorized" lines
apt full-upgrade -y                           # always full-upgrade on Proxmox, never plain "apt upgrade"
apt install -y intel-microcode sudo vim htop curl ethtool bzip2 lm-sensors
reboot
```

- [ ] UI equivalent: cobra-command → **Updates → Repositories** → disable both enterprise lines → **Add → No-Subscription**
- [ ] `intel-microcode` not found → add `non-free-firmware` to the `Components:` line of `/etc/apt/sources.list.d/debian.sources`, `apt update`, retry
- [ ] After reboot: `pveversion` shows `pve-manager/9.x`

## 1.7 Admin user, 2FA, SSH keys

🔌 Onboard → switch · TP-Link: plugged in, no cable


Proxmox has its own user list (**realms**). `@pam` users are normal Linux accounts, so `eels@pam` is one login for the UI, SSH and sudo.

```bash
adduser eels                                  # set a generated password
usermod -aG sudo eels
pveum user add eels@pam
pveum acl modify / --users eels@pam --roles Administrator   # full rights on everything ("/")
```

- [ ] UI: log out, log in as `eels` (realm Linux PAM)
- [ ] Top right **eels@pam → TFA → Add → TOTP** → scan with your authenticator → enter code
- [ ] **TFA → Add → Recovery Keys** → store them
- [ ] Repeat both for `root@pam` (root still works on the physical keyboard, so no lockout risk)

On the desktop (PowerShell):

```powershell
ssh-keygen -t ed25519                          # accept the default path, set a passphrase
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh eels@10.6.9.2 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@10.6.9.2 "cat >> /root/.ssh/authorized_keys"
ssh eels@10.6.9.2                              # must log in without the account password
```

On cobra-command (keep this session open until a **new** window logs in):

```bash
cat > /etc/ssh/sshd_config.d/10-cobra.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
sshd -t && systemctl reload ssh
```

- [ ] New PowerShell: `ssh eels@10.6.9.2` works; `ssh -o PubkeyAuthentication=no eels@10.6.9.2` is refused
- [ ] (`prohibit-password` not `no`: adding the R620 as a 2nd node later needs root SSH with keys)

## 1.8 Laptop-as-server settings

🔌 Onboard → switch · TP-Link: plugged in, no cable


```bash
# Keep running with the lid closed
mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\n' \
  > /etc/systemd/logind.conf.d/10-lid.conf
systemctl restart systemd-logind

# Blank the console screen after 60 s
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 consoleblank=60"/' /etc/default/grub
update-grub

# Stop USB power-saving from dropping the WAN NIC (IDs from `lsusb`; 0bda:8153 = RTL8153)
lsusb | grep -i -E 'realtek|asix|ethernet'
echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8153", TEST=="power/control", ATTR{power/control}="on"' \
  > /etc/udev/rules.d/50-usb-nic-power.rules
udevadm control --reload

# Clean power-off at 10 % battery during a long outage
apt install -y upower
mkdir -p /etc/UPower/UPower.conf.d
printf '[UPower]\nUsePercentageForPolicy=true\nPercentageLow=25\nPercentageCritical=15\nPercentageAction=10\nCriticalPowerAction=PowerOff\n' \
  > /etc/UPower/UPower.conf.d/10-cobra.conf
systemctl restart upower
upower -i $(upower -e | grep BAT) | grep -E 'state|percentage'
```

- [ ] Close the lid; `ping 10.6.9.2` from the desktop keeps answering
- [ ] If your UPower ignores `UPower.conf.d`, put the same lines in `/etc/UPower/UPower.conf`
- [ ] If `journalctl -k` ever shows `Detected Hardware Unit Hang` (known I219 quirk): add `        post-up /usr/sbin/ethtool -K enp0s31f6 tso off gso off` under `iface vmbr0`, then `ifreload -a`

## 1.9 Put the next installers on Proxmox

🔌 Onboard → switch · TP-Link: plugged in, no cable


ISOs go in `/var/lib/vz/template/iso/` (UI: local → ISO Images); CT templates in `/var/lib/vz/template/cache/` (UI: local → CT Templates → Templates button).

- [ ] Copy the OPNsense download link: opnsense.org/download → architecture **amd64**, image type **dvd**, any mirror → copy the `.iso.bz2` link

```bash
cd /var/lib/vz/template/iso

# OPNsense (part 2)
OPN_URL='<paste link>'
wget "$OPN_URL"
wget "$(dirname "$OPN_URL")/$(basename "$OPN_URL" | sed 's/-dvd-amd64.iso.bz2/-checksums-amd64.sha256/')"
sha256sum -c --ignore-missing OPNsense-*-checksums-amd64.sha256      # "OK"
bunzip2 OPNsense-*-dvd-amd64.iso.bz2

# Debian 13 netinst (part 5 gate VM)
BASE=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd
wget -q $BASE/SHA256SUMS
ISO=$(awk '$2 ~ /^debian-[0-9.]+-amd64-netinst\.iso$/ {print $2}' SHA256SUMS)
wget $BASE/$ISO && sha256sum -c --ignore-missing SHA256SUMS          # "OK"
rm SHA256SUMS OPNsense-*-checksums-amd64.sha256

# Debian 13 container template (part 2 Pi-hole)
pveam update
TPL=$(pveam available --section system | awk '/debian-13-standard/ {print $2}' | sort -V | tail -1)
pveam download local "$TPL"
```

- [ ] Checksum file named differently on your mirror → download it by hand from the same folder
- [ ] UI check: local → ISO Images shows OPNsense + Debian; CT Templates shows `debian-13-standard`

## 1.10 Optional 5-minute test: make and delete a container

Same shell as 1.9 (uses `$TPL`). Watch it appear in the left tree.

```bash
pct create 999 local:vztmpl/$TPL --hostname scratch --memory 512 --rootfs local-lvm:4 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp --unprivileged 1
pct start 999 && pct enter 999                # now root inside the container
ip -br a; exit
pct stop 999 && pct destroy 999
```

## 1.11 Save the config off the box

```bash
tar czf /root/cobra-command-$(date +%F).tgz /etc/network/interfaces /etc/hosts /etc/apt/sources.list.d \
  /etc/ssh/sshd_config.d /etc/systemd/logind.conf.d /etc/udev/rules.d /etc/default/grub /etc/UPower \
  /etc/pve/user.cfg /etc/pve/datacenter.cfg 2>/dev/null
```

```powershell
scp root@10.6.9.2:/root/cobra-command-*.tgz $HOME\Documents\
```

## Done when

- [ ] `pveversion` = 9.x; `apt update` clean
- [ ] UI login as eels asks for a TOTP code
- [ ] SSH works by key only
- [ ] Lid closed, host still answers
- [ ] OPNsense ISO, Debian ISO and Debian CT template are on `local`

Next: **[2. Redo networking](02-networking.md)**: OPNsense VM becomes the gateway, then Pi-hole.
