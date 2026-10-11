# 1. Set up Latitude (command-center, Proxmox VE 9)

Needs: Proxmox USB stick, USB 3 NIC (RTL8153), Windows desktop. House network untouched.

**Gotcha:** `10.10.10.0/24` has no router until part 2. Until then the host gets internet on the USB NIC via Xfinity DHCP (`10.0.0.x`) and you manage it at `https://10.0.0.x:8006`. Part 2 flips this.

## Before wiping

- [ ] Anything you want off the Latitude is copied elsewhere
- [ ] Proxmox ISO checksum matches (`Get-FileHash .\proxmox-ve_9*.iso`), written with Rufus in **DD mode**

## BIOS (F2)

- [ ] System Configuration → SATA Operation → **AHCI** (*"RAID On" hides the NVMe from the installer*)
- [ ] Virtualization → Enabled; VT for Direct I/O → Enabled
- [ ] Power Management → AC Behavior → Wake on AC → Enabled
- [ ] Power Management → Primary Battery Charge → Custom, start 50, stop 80
- [ ] Wireless → untick WLAN and Bluetooth
- [ ] Security → Admin password set (store it)
- [ ] vPro models: disable Intel AMT (BIOS or Ctrl+P → MEBx)
- [ ] Secure Boot: leave on

## Install (F12 → USB, USB NIC unplugged)

| Screen | Value |
|---|---|
| Filesystem | ext4 on the NVMe |
| Keyboard | U.S. English |
| Management NIC | onboard, usually `enp0s31f6` |
| Hostname | `command-center.home.arpa` (*not* `.elysidrome.com`: Pi-hole sends that whole domain to the gate) |
| IP / Gateway / DNS | `10.10.10.2/24` / `10.10.10.1` / `10.10.10.1` |
| Pin interface names (if offered) | Yes |

## Temporary uplink (console, root)

- [ ] Plug USB NIC into Xfinity (or the current switch). Onboard port stays unplugged.

```bash
ip -br link                                   # note the enx... name
cp /etc/network/interfaces /root/interfaces.installer
nano /etc/network/interfaces                  # make it match below
```

```
auto lo
iface lo inet loopback

iface enp0s31f6 inet manual

auto vmbr0
iface vmbr0 inet static
        address 10.10.10.2/24
#       gateway 10.10.10.1      # part 2 uncomments
        bridge-ports enp0s31f6
        bridge-stp off
        bridge-fd 0

iface enxXXXXXXXXXXXX inet manual

auto vmbr1
iface vmbr1 inet dhcp           # part 2 changes to manual
        bridge-ports enxXXXXXXXXXXXX
        bridge-stp off
        bridge-fd 0
```

```bash
ifreload -a
ip -4 -br addr show vmbr1                     # note 10.0.0.x
ping -c3 download.proxmox.com
# only if DNS fails:
printf 'search home.arpa\nnameserver 10.0.0.1\n' > /etc/resolv.conf
```

- [ ] Browser: `https://10.0.0.x:8006`, root / Linux PAM. Subscription popup: click OK (harmless).

## Repos + updates (SSH as root from here)

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
apt update && apt full-upgrade -y             # never plain "apt upgrade" on Proxmox
apt install -y intel-microcode sudo vim htop curl ethtool bzip2 lm-sensors
reboot
```

- [ ] `intel-microcode` not found → add `non-free-firmware` to `Components:` in `/etc/apt/sources.list.d/debian.sources`, `apt update`, retry

## Admin user, 2FA, SSH

```bash
adduser eels
usermod -aG sudo eels
pveum user add eels@pam
pveum acl modify / --users eels@pam --roles Administrator
```

- [ ] Web UI as eels → eels@pam → TFA → Add TOTP, then Add Recovery Keys. Repeat for root.

Desktop (PowerShell):

```powershell
ssh-keygen -t ed25519
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh eels@10.0.0.x "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@10.0.0.x "cat >> /root/.ssh/authorized_keys"
```

Host (keep the current session open until a new one works):

```bash
cat > /etc/ssh/sshd_config.d/10-elysidrome.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
sshd -t && systemctl reload ssh
```

(`prohibit-password`, not `no`: clustering the R620 later needs root key SSH.)

## Laptop-as-server

```bash
# lid closed = keep running; blank console after 60 s
mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\n' \
  > /etc/systemd/logind.conf.d/10-lid.conf
systemctl restart systemd-logind
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 consoleblank=60"/' /etc/default/grub
update-grub

# USB NIC never autosuspends (check IDs with: lsusb)
echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8153", TEST=="power/control", ATTR{power/control}="on"' \
  > /etc/udev/rules.d/50-usb-nic-power.rules
udevadm control --reload

# power off at 10 % battery
apt install -y upower
mkdir -p /etc/UPower/UPower.conf.d
printf '[UPower]\nUsePercentageForPolicy=true\nPercentageLow=25\nPercentageCritical=15\nPercentageAction=10\nCriticalPowerAction=PowerOff\n' \
  > /etc/UPower/UPower.conf.d/10-elysidrome.conf
systemctl restart upower
```

- [ ] If UPower ignores `UPower.conf.d` on your version, put those lines in `/etc/UPower/UPower.conf`
- [ ] If `journalctl -k` ever shows `Detected Hardware Unit Hang`: add `post-up /usr/sbin/ethtool -K enp0s31f6 tso off gso off` under `vmbr0`, `ifreload -a`

## Download installers for later parts

Copy the OPNsense **amd64 / dvd** `.iso.bz2` link from opnsense.org/download first.

```bash
cd /var/lib/vz/template/iso
OPN_URL='<paste link>'
wget "$OPN_URL"
wget "$(dirname "$OPN_URL")/$(basename "$OPN_URL" | sed 's/-dvd-amd64.iso.bz2/-checksums-amd64.sha256/')"
sha256sum -c --ignore-missing OPNsense-*-checksums-amd64.sha256
bunzip2 OPNsense-*-dvd-amd64.iso.bz2

BASE=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd
wget -q $BASE/SHA256SUMS
ISO=$(awk '$2 ~ /^debian-[0-9.]+-amd64-netinst\.iso$/ {print $2}' SHA256SUMS)
wget $BASE/$ISO && sha256sum -c --ignore-missing SHA256SUMS
rm SHA256SUMS OPNsense-*-checksums-amd64.sha256

pveam update
TPL=$(pveam available --section system | awk '/debian-13-standard/ {print $2}' | sort -V | tail -1)
pveam download local "$TPL"
```

- [ ] OPNsense checksum file named differently on your mirror → grab it by hand from the same folder

## Save config

```bash
tar czf /root/command-center-$(date +%F).tgz /etc/network/interfaces /etc/hosts /etc/apt/sources.list.d \
  /etc/ssh/sshd_config.d /etc/systemd/logind.conf.d /etc/udev/rules.d /etc/default/grub /etc/UPower \
  /etc/pve/user.cfg /etc/pve/datacenter.cfg 2>/dev/null
```

```powershell
scp root@10.0.0.x:/root/command-center-*.tgz $HOME\Documents\
```

## Done when

- [ ] `pveversion` shows 9.x, `apt update` has no 401 errors
- [ ] Web UI login asks for TOTP; SSH works by key, `ssh -o PubkeyAuthentication=no eels@10.0.0.x` is refused
- [ ] Lid closed, host still pings
- [ ] local → ISO Images: OPNsense + Debian; CT Templates: debian-13-standard
