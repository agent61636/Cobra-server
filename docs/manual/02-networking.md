# 2. Redo networking (OPNsense gateway VM 100, Pi-hole CT 101)

**Result:** OPNsense, running as a VM on the Latitude, is the router/firewall for the house. All wired gear sits behind it on `10.10.10.0/24`, Pi-hole filters DNS, and WireGuard gets you in from outside.

**Needs:** part 1 done. Cloudflare zone for `elysidrome.com` active. A Cloudflare API token (My Profile → API Tokens → "Edit zone DNS" template, add Zone · Zone · Read, zone = `elysidrome.com`). A 2–3 h window: **wired internet is down from 2.4 until 2.5 is finished.** Xfinity Wi-Fi keeps working the whole time.

---

## 2.1 OPNsense in one table

OPNsense is a FreeBSD-based firewall distro managed from a web UI. You configure it almost entirely by clicking. Menu paths below are from the left sidebar.

| Term | Meaning |
|---|---|
| **WAN / LAN** | Interface roles. WAN = `vtnet0` (plugged into `vmbr1` → USB NIC → Xfinity). LAN = `vtnet1` (plugged into `vmbr0` → onboard NIC → switch). |
| **Console menu** | Text menu on the VM's screen (Proxmox → 100 → Console). Options 1 (assign interfaces) and 2 (set IP) rescue you if the web UI is unreachable. |
| **Rules** | Firewall → Rules → per interface. Default: LAN may go anywhere, WAN blocks all inbound. Rules are evaluated on the interface where traffic **enters**. |
| **NAT → Port Forward** | Inbound forwards (TCP 443 to the gate, in part 5). Creating one auto-creates its WAN pass rule. |
| **Unbound** | OPNsense's DNS resolver. Here it forwards to Cloudflare/Quad9 over TLS (port 853). Pi-hole uses it as its upstream. |
| **Plugins** | Extra packages: System → Firmware → Plugins. You need `os-ddclient` and `os-crowdsec`. |
| **Apply** | Most pages need **Save** *and then* **Apply changes** (a yellow banner). Nothing takes effect until you apply. |

Final path of a packet: client → Pi-hole (`10.10.10.3`, DNS) / OPNsense (`10.10.10.1`, gateway) → OPNsense NAT → Xfinity `10.0.0.1` (Xfinity DMZ → `10.0.0.2`) → internet.

---

## 2.2 Create the VM (command-center shell, root)

🔌 Onboard: empty · TP-Link → Xfinity (same as part 1). Manage Proxmox at `https://10.0.0.x:8006`.


```bash
qm create 100 --name open-the-box --ostype other --cpu host --cores 2 --memory 4096 --balloon 0 \
  --scsihw virtio-scsi-single --scsi0 local-lvm:32,discard=on,iothread=1 \
  --net0 virtio,bridge=vmbr1 --net1 virtio,bridge=vmbr0 \
  --cdrom local:iso/$(ls /var/lib/vz/template/iso | grep -m1 'OPNsense.*\.iso$') \
  --boot 'order=scsi0;ide2' --onboot 1 --startup order=1,up=60
qm start 100
qm config 100 | grep net0                     # write down the WAN MAC (for the Xfinity reservation)
```

| Flag | Why |
|---|---|
| `net0 → vmbr1`, `net1 → vmbr0` | OPNsense sees them as `vtnet0` (WAN) and `vtnet1` (LAN) in that order |
| `--balloon 0` | FreeBSD and memory ballooning don't mix well; give it fixed 4 GB |
| `--onboot 1 --startup order=1,up=60` | Starts first at boot, and Proxmox waits 60 s before starting Pi-hole and the gate |

UI equivalent: **Create VM** (top right), same values on each tab; OS type **Other**.

## 2.3 Install OPNsense (Proxmox → 100 → Console)

🔌 Onboard: empty · TP-Link → Xfinity


- [ ] At the login prompt: user **`installer`**, password **`opnsense`**
- [ ] Keymap: default (US) → **Install (UFS)** → disk **`da0`** → confirm
- [ ] Set a generated root password when prompted → **Complete Install** → **Reboot**
- [ ] Remove the ISO: `qm set 100 --ide2 none,media=cdrom` (command-center shell)
- [ ] Log in at the console as `root` → menu appears

Console menu:

| Option | Answers |
|---|---|
| **1) Assign interfaces** | Configure LAGGs: **N**. VLANs: **N**. WAN: **`vtnet0`**. LAN: **`vtnet1`**. Optional: blank. Proceed: **y** |
| **2) Set interface IP address** → LAN | DHCP: **N**. IPv4: **`10.10.10.1`**, bits **`24`**, upstream gateway: blank. IPv6: **N** / blank. Enable DHCP server on LAN: **y**, range **`10.10.10.100`** to **`10.10.10.199`**. Change GUI to HTTP: **N**. Restore defaults: **N** |
| WAN | Leave as DHCP (default). It'll pick up `10.0.0.x` from Xfinity once cabled. |

✅ Console header shows `LAN (vtnet1) -> v4: 10.10.10.1/24` and `WAN (vtnet0) -> v4/DHCP4: 10.0.0.x`.

## 2.4 Cut over (internet down from here)

🔌 Run the commands first (cables unchanged), **then** recable per the table below. Final state: onboard → switch, TP-Link → Xfinity.


On command-center, move the host onto the LAN:

```bash
sed -i 's/^iface vmbr1 inet dhcp.*/iface vmbr1 inet manual/; s/^#\s*gateway 10.10.10.1.*/        gateway 10.10.10.1/' /etc/network/interfaces
printf 'search home.arpa\nnameserver 10.10.10.1\n' > /etc/resolv.conf
ifreload -a
ip -br a                                      # vmbr0 10.10.10.2/24, vmbr1 has NO address
```

Your SSH/UI session on `10.0.0.x` drops here. Expected.

Recable:

| Cable | From → To |
|---|---|
| TP-Link USB NIC | stays → Xfinity gateway (from part 1) |
| Latitude **onboard port** | **now** cable → your switch |
| Switch's old uplink to Xfinity | **unplug** (nothing else connects to Xfinity by wire) |
| Both desktops, SGIN, OptiPlex | → switch |

- [ ] Desktop: `ipconfig /renew` → gets `10.10.10.1xx`
- [ ] Desktop: `https://10.10.10.2:8006` → Proxmox (now the permanent address)
- [ ] Desktop: `https://10.10.10.1` → OPNsense login, `root` + the password from 2.3
- [ ] Xfinity app: **reserve `10.0.0.2`** for the WAN MAC from 2.2, then **Advanced → DMZ → `10.0.0.2`**
- [ ] OPNsense → Interfaces → Overview → WAN → **Reload** (picks up `10.0.0.2`)

## 2.5 OPNsense base setup (web UI)

🔌 Final cabling from here on: onboard → switch · TP-Link → Xfinity · nothing else wired to Xfinity


**Wizard** (System → Wizard, or it opens on first login):

| Page | Value |
|---|---|
| General | Hostname `open-the-box`, domain `home.arpa`. Primary/secondary DNS: blank. **Untick** "Override DNS". Unbound: enabled. |
| Time | Default NTP servers, your time zone |
| WAN | Type DHCP. At the bottom, **untick "Block RFC1918 private networks"** (*the WAN side is Xfinity's `10.0.0.0/24`, so this would block your own upstream*). Keep "Block bogon networks" ticked. |
| LAN | `10.10.10.1` / `24` (already set) |
| Root password | Skip (already set) |
| Reload | Yes |

✅ Desktop: `ping 1.1.1.1` and `nslookup google.com 10.10.10.1` both work. **Internet is back.**

Then:

- [ ] **System → Settings → General**: DNS servers blank; **untick** "Allow DNS server list to be overridden by DHCP/PPP on WAN". Save.
- [ ] **System → Settings → Administration**: Listen Interfaces = **LAN** only; HTTP redirect: disable; Secure Shell: off. Save.
- [ ] **2FA:** System → Access → Servers → **Add** → Type **Local + Timebased One Time Password**, name `TOTP`. Save. → System → Access → Users → root → OTP seed: **Generate**, Save, scan the QR. → System → Settings → Administration → Authentication server: **TOTP** only. Log out; log in with password = **code then password** (e.g. `123456MyPassword`). ⚠️ Verify the token order on the TOTP server's "Reverse token order" setting.
- [ ] **System → Firmware → Status → Check for updates** → update → reboot if asked
- [ ] **System → Firmware → Plugins**: install `os-ddclient`, `os-crowdsec`

## 2.6 DHCP reservations and DNS servers handed out

OPNsense versions differ on which DHCP service is active for LAN. Use whichever page shows LAN **enabled**: **Services → ISC DHCPv4 → LAN** (older) or **Services → Dnsmasq DNS & DHCP** (newer).

- [ ] DNS servers: `10.10.10.3` (Pi-hole, created in 2.9) and `10.10.10.1` (*fallback; changed to `10.10.10.20` in part 3*)
- [ ] Domain name: `home.arpa`
- [ ] Static mappings / hosts (MAC from `ipconfig /all`, `ip -br link`, or Services → DHCP leases after each box has connected once):

| IP | Host |
|---|---|
| 10.10.10.20 | elysidrome-stream (SGIN) |
| 10.10.10.30 | elysidrome-arcade (OptiPlex) |
| 10.10.10.40 / .41 | R620 iDRAC / R620 (later) |
| 10.10.10.50 / .51 | Desktops |

`.2`, `.3`, `.10` are static on the hosts themselves; don't add them here.

## 2.7 DNS over TLS (Services → Unbound DNS)

- [ ] **General**: Enable, Listen interfaces **LAN** (add **WG** after 2.8), DNSSEC: tick. Save, Apply.
- [ ] **DNS over TLS** → Add:

| Server IP | Port | Verify CN |
|---|---|---|
| `1.1.1.1` | 853 | `cloudflare-dns.com` |
| `1.0.0.1` | 853 | `cloudflare-dns.com` |
| `9.9.9.9` | 853 | `dns.quad9.net` |

- [ ] Apply. Check from the desktop: `nslookup example.com 10.10.10.1` works. Optional: Interfaces → Diagnostics → Packet Capture on WAN, port 53, should stay empty.

## 2.8 WireGuard (remote admin)

**On OPNsense, VPN → WireGuard:**

- [ ] **Instances** → Add: name `wg0`, click the gear to **generate keys**, Listen port `51820`, Tunnel address `10.10.99.1/24`. Save. Copy the **public key**.
- [ ] On the phone/laptop: WireGuard app → **+** → create from scratch → it generates the client key pair. Copy the client's **public key**.
- [ ] **Peers** → Add: name `phone`, Public key = client's, Allowed IPs `10.10.99.2/32`, Instances `wg0`. Save. (Next device: `.3`, `.4`, …)
- [ ] **Settings**: Enable WireGuard. Apply.
- [ ] **Interfaces → Assignments**: add `wg0` → description `WG` → Save → open `WG`, tick Enable, Save, Apply.
- [ ] **Firewall → Rules → WAN** → Add: Pass, Protocol **UDP**, Destination **WAN address**, Port **51820**. Save, Apply.
- [ ] **Firewall → Rules → WG** → Add: Pass, Source **WG net**, Destination **LAN net**. Save, Apply.
- [ ] Unbound → General → Listen interfaces: add **WG**.

Client config (the app shows these fields):

```ini
[Interface]
PrivateKey = <client private key, generated by the app>
Address = 10.10.99.2/32
DNS = 10.10.10.3

[Peer]
PublicKey = <wg0 public key from OPNsense>
Endpoint = elysidrome.com:51820
AllowedIPs = 10.10.10.0/24, 10.10.99.0/24
PersistentKeepalive = 25
```

✅ After 2.10 (DDNS): phone on cellular, Wi-Fi off, tunnel on → `https://10.10.10.2:8006` loads.

## 2.9 Pi-hole CT 101 (command-center shell)

```bash
TPL=$(ls /var/lib/vz/template/cache | grep -m1 debian-13-standard)
pct create 101 local:vztmpl/$TPL --hostname pihole-1 --cores 1 --memory 512 --swap 512 \
  --rootfs local-lvm:4 --net0 name=eth0,bridge=vmbr0,ip=10.10.10.3/24,gw=10.10.10.1 \
  --nameserver 10.10.10.1 --searchdomain home.arpa \
  --unprivileged 1 --features nesting=1 --onboot 1 --startup order=2
pct start 101
pct enter 101                                 # root shell inside the container
```

`--unprivileged 1`: root in the container is a nobody on the host. `nesting=1`: Debian 13's systemd needs it inside an unprivileged CT.

Inside CT 101:

```bash
apt update && apt full-upgrade -y && apt install -y curl
curl -sSL https://install.pi-hole.net | bash
#   Upstream DNS: Custom -> 10.10.10.1   |  Blocklist: yes  |  Query logging: on  |  Privacy: 0
pihole setpassword
pihole-FTL --config dns.upstreams '["10.10.10.1"]'
# *.elysidrome.com -> the gate, so LAN traffic never leaves the house
pihole-FTL --config misc.dnsmasq_lines '["address=/elysidrome.com/10.10.10.10"]'
# local names
pihole-FTL --config dns.hosts '["10.10.10.1 open-the-box.home.arpa","10.10.10.2 command-center.home.arpa","10.10.10.3 pihole-1.home.arpa","10.10.10.10 elysidrome-gate.home.arpa","10.10.10.20 elysidrome-stream.home.arpa","10.10.10.30 elysidrome-arcade.home.arpa"]'
exit
```

- [ ] Admin UI: `http://10.10.10.3/admin`
- [ ] Desktop: `ipconfig /renew`, then `ipconfig /all` lists DNS `10.10.10.3`
- [ ] `nslookup tv.elysidrome.com` → `10.10.10.10`; `nslookup google.com` → real IP; queries show in Pi-hole

## 2.10 Dynamic DNS (Services → Dynamic DNS)

Keeps `elysidrome.com` (apex A record) pointed at your home IP. App hostnames get CNAMEs to the apex in part 5.

- [ ] **Settings**: Enable. Accounts → Add:

| Field | Value |
|---|---|
| Service | Cloudflare |
| Username | ⚠️ Verify per the field's help text (token auth usually wants the zone name or `token`) |
| Password | the API token |
| Zone | `elysidrome.com` |
| Hostname(s) | `elysidrome.com` |
| Check ip method | a web service (e.g. `cloudflare` or `ipify-ipv4`), **not** "Interface" (*WAN is `10.0.0.2`, a private address*) |

- [ ] Save, Apply. Within a few minutes Cloudflare → DNS shows an A record for `elysidrome.com` with your public IP. Click the cloud **grey (DNS only)** if it's orange.

## 2.11 IDS/IPS and CrowdSec

- [ ] **Interfaces → Settings**: tick Disable hardware CRC, Disable hardware TSO, Disable hardware LRO. Save, **reboot OPNsense** (*IPS mode needs these off on virtio NICs*).
- [ ] **Services → Intrusion Detection → Administration → Settings**: Enabled, **IPS mode**, Pattern matcher **Hyperscan**, Interfaces **WAN**. Apply.
- [ ] **Download** tab: tick the `ET open/*` rulesets → **Enable selected** → **Download & Update Rules**.
- [ ] **Policy** tab → Add: Rulesets = the ET open ones, Action = Alert, New action = **Drop**. Save, Apply. (*Rules ship as alert-only; the policy is what makes IPS block.*)
- [ ] **Schedule** tab: enable daily rule updates.
- [ ] **Services → CrowdSec → Settings**: Enable log processor, LAPI and firewall bouncer (on by default after install on most versions). Apply.
- [ ] Check: Services → Intrusion Detection → Alerts fills over the next day; CrowdSec → Overview shows decisions.

## Done when

- [ ] Wired devices get `10.10.10.1xx` (or their reservation), DNS `10.10.10.3`, and browse normally
- [ ] Proxmox at `https://10.10.10.2:8006`, OPNsense at `https://10.10.10.1` (TOTP)
- [ ] `nslookup anything.elysidrome.com` on the LAN → `10.10.10.10`
- [ ] Cloudflare A record for `elysidrome.com` = your public IP, grey cloud
- [ ] Phone on cellular reaches Proxmox through WireGuard
- [ ] Back up the OPNsense config: System → Configuration → Backups → **Download configuration**

Next: **[3. Set up SGIN](03-sgin.md)**.
