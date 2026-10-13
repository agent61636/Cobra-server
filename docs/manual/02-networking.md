# 2. Redo networking (OPNsense gateway VM 100, Pi-hole CT 101)

**Result:** OPNsense, running as a VM on the Latitude, is the router/firewall for the house. All wired gear sits behind it on `10.6.9.0/24`, Pi-hole filters DNS, and WireGuard gets you in from outside.

**Needs:** part 1 done. `songofeo.com` on Porkbun with **API Access turned on** for the domain, and the `cobra-ddns` Porkbun API key + secret key (part 0.4). A 2–3 h window: **wired internet is down from 2.4 until 2.5 is finished.** Xfinity Wi-Fi keeps working except for a minute while the gateway restarts.

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

Final path of a packet: client → Pi-hole (`10.6.9.3`, DNS) / OPNsense (`10.6.9.1`, gateway) → OPNsense NAT → Xfinity `10.0.0.1` (Xfinity DMZ → `10.0.0.2`) → internet.

---

## 2.2 Create the VM (cobra-command shell, root)

🔌 Onboard → switch · TP-Link: plugged in, no cable (same as part 1). Manage Proxmox at `https://10.6.9.2:8006`.

Both of the VM's network cards start **unplugged** (`link_down=1`). While Xfinity still owns `10.6.9.1`, an OPNsense LAN on the same address would fight it. They get connected during the cutover.

```bash
qm create 100 --name cobra-firewall --ostype other --cpu host --cores 2 --memory 4096 --balloon 0 \
  --scsihw virtio-scsi-single --scsi0 local-lvm:32,discard=on,iothread=1 \
  --net0 virtio,bridge=vmbr1,link_down=1 --net1 virtio,bridge=vmbr0,link_down=1 \
  --cdrom local:iso/$(ls /var/lib/vz/template/iso | grep -m1 'OPNsense.*\.iso$') \
  --boot 'order=scsi0;ide2' --onboot 1 --startup order=1,up=60
qm start 100
qm config 100 | grep -E '^net[01]'            # write down both MACs (net0 = WAN, for the Xfinity reservation)
```

| Flag | Why |
|---|---|
| `net0 → vmbr1`, `net1 → vmbr0` | OPNsense sees them as `vtnet0` (WAN) and `vtnet1` (LAN) in that order |
| `link_down=1` | The virtual cable is unplugged until 2.4 |
| `--balloon 0` | FreeBSD and memory ballooning don't mix well; give it fixed 4 GB |
| `--onboot 1 --startup order=1,up=60` | Starts first at boot, and Proxmox waits 60 s before starting Pi-hole and the gate |

UI equivalent: **Create VM** (top right), same values on each tab; OS type **Other**; on the Network tab tick **Disconnect**.

## 2.3 Install OPNsense (Proxmox → 100 → Console)

🔌 Unchanged

- [ ] At the login prompt: user **`installer`**, password **`opnsense`**
- [ ] Keymap: default (US) → **Install (UFS)** → disk **`da0`** → confirm
- [ ] Set a generated root password when prompted → **Complete Install** → **Reboot**
- [ ] Remove the ISO: `qm set 100 --ide2 none,media=cdrom` (cobra-command shell)
- [ ] Log in at the console as `root` → menu appears

Console menu:

| Option | Answers |
|---|---|
| **1) Assign interfaces** | Configure LAGGs: **N**. VLANs: **N**. WAN: **`vtnet0`**. LAN: **`vtnet1`**. Optional: blank. Proceed: **y** |
| **2) Set interface IP address** → LAN | DHCP: **N**. IPv4: **`10.6.9.1`**, bits **`24`**, upstream gateway: blank. IPv6: **N** / blank. Enable DHCP server on LAN: **y**, range **`10.6.9.100`** to **`10.6.9.199`**. Change GUI to HTTP: **N**. Restore defaults: **N** |
| WAN | Leave as DHCP (default). It has no cable yet; it picks up `10.0.0.x` after the cutover. |

✅ Console header shows `LAN (vtnet1) -> v4: 10.6.9.1/24`. WAN shows no address yet. That's expected.

**Before the cutover, write down your old server's details** (the SGIN, still running today):
- [ ] Its MAC address (Xfinity app → Connected devices, or `ip -br link` on it)
- [ ] Every port forward Xfinity has for it (Xfinity app → Advanced → Port forwarding). You'll recreate them on OPNsense in 2.4 so it keeps working until part 5 replaces it.
- [ ] Any static mapping or reservation you rely on for other devices

## 2.4 Cut over (internet down from here)

**Do this at the Latitude's own keyboard and screen.** The desktop loses its connection partway through. Plan 30–60 minutes; Xfinity Wi-Fi drops briefly while the gateway restarts.

**1. Move Xfinity off 10.6.9.x.** Xfinity app (or `http://10.6.9.1` → Gateway → Connection → Local IP Network):

- [ ] Gateway IP **`10.0.0.1`**, subnet `255.255.255.0`, DHCP range **`10.0.0.10`–`10.0.0.250`** → Save. The gateway restarts and every device on it gets a new `10.0.0.x` address.

**2. Recable:**

| Cable | From → To |
|---|---|
| TP-Link USB NIC | **now** cable → Xfinity gateway |
| Switch's uplink to Xfinity | **unplug** (from now on only OPNsense connects to Xfinity by wire) |
| Latitude onboard port | stays → switch |
| Desktops, SGIN, OptiPlex | → switch |

**3. Connect OPNsense's virtual cables** (Latitude's keyboard, log in as root):

```bash
qm set 100 --net0 "$(qm config 100 | sed -n 's/^net0: //p' | sed 's/,link_down=1//')"
qm set 100 --net1 "$(qm config 100 | sed -n 's/^net1: //p' | sed 's/,link_down=1//')"
qm config 100 | grep -E '^net[01]'            # no link_down left
ip -br addr show vmbr0                        # still 10.6.9.2/24; the host's own settings never change
```

- [ ] Proxmox → 100 → Console: header shows `WAN (vtnet0) -> v4/DHCP4: 10.0.0.x`. If not: console option **11) Reload all services**.

**4. Back on the desktop:**

- [ ] `ipconfig /renew` → gets `10.6.9.1xx` (now from OPNsense)
- [ ] `https://10.6.9.2:8006` → Proxmox (same address as before)
- [ ] `https://10.6.9.1` → OPNsense login, `root` + the password from 2.3
- [ ] Xfinity app: **reserve `10.0.0.2`** for the WAN MAC from 2.2, then **Advanced → DMZ → `10.0.0.2`**. Delete the old port forwards there; the DMZ now sends everything to OPNsense.
- [ ] OPNsense → Interfaces → Overview → WAN → **Reload** (picks up `10.0.0.2`)

**5. Keep the old server reachable until part 5 replaces it:**

- [ ] OPNsense DHCP (see 2.6 for which page): static mapping **`10.6.9.200`** for the old server's MAC. On the old server: renew DHCP or reboot, then check it got `.200`.
- [ ] OPNsense → Firewall → NAT → Port Forward → Add, once per forward you wrote down in 2.3: Interface **WAN**, Protocol TCP (or UDP), Destination **WAN address**, Destination port = its port, Redirect target IP **`10.6.9.200`**, same port. Save, **Apply**. Each one auto-creates its WAN rule.
- [ ] From a phone on cellular: the old server's public addresses answer again. If they don't, check the DNS records (2.10 last step: IPv4 only, no AAAA).

## 2.5 OPNsense base setup (web UI)

🔌 Final cabling from here on: onboard → switch · TP-Link → Xfinity · nothing else wired to Xfinity


**Wizard** (System → Wizard, or it opens on first login):

| Page | Value |
|---|---|
| General | Hostname `cobra-firewall`, domain `home.arpa`. Primary/secondary DNS: blank. **Untick** "Override DNS". Unbound: enabled. |
| Time | Default NTP servers, your time zone |
| WAN | Type DHCP. At the bottom, **untick "Block RFC1918 private networks"** (*the WAN side is Xfinity's `10.0.0.0/24`, so this would block your own upstream*). Keep "Block bogon networks" ticked. |
| LAN | `10.6.9.1` / `24` (already set) |
| Root password | Skip (already set) |
| Reload | Yes |

✅ Desktop: `ping 1.1.1.1` and `nslookup google.com 10.6.9.1` both work. **Internet is back.**

Then:

- [ ] **System → Settings → General**: DNS servers blank; **untick** "Allow DNS server list to be overridden by DHCP/PPP on WAN". Save.
- [ ] **System → Settings → Administration**: Listen Interfaces = **LAN** only; HTTP redirect: disable; Secure Shell: off. Save.
- [ ] **2FA:** System → Access → Servers → **Add** → Type **Local + Timebased One Time Password**, name `TOTP`, token length 6. Save. → System → Access → Users → root → OTP seed: **Generate**, Save, scan the QR. → **System → Access → Tester**: server `TOTP`, user root, password = **code then password** (e.g. `123456MyPassword`), Test. Only when that passes: System → Settings → Administration → Authentication server: **TOTP** only. Log out and back in the same way. (Code first is OPNsense's default; the server's reverse-order option flips it.)
- [ ] **System → Firmware → Status → Check for updates** → update → reboot if asked
- [ ] **System → Firmware → Plugins**: install `os-ddclient`, `os-crowdsec`

## 2.6 DHCP reservations and DNS servers handed out

OPNsense versions differ on which DHCP service is active for LAN. Use whichever page shows LAN **enabled**: **Services → ISC DHCPv4 → LAN** (older) or **Services → Dnsmasq DNS & DHCP** (newer).

- [ ] DNS servers: `10.6.9.3` (Pi-hole, created in 2.9) and `10.6.9.1` (*fallback; changed to `10.6.9.20` in part 3*)
- [ ] Domain name: `home.arpa`
- [ ] Static mappings / hosts (MAC from `ipconfig /all`, `ip -br link`, or Services → DHCP leases after each box has connected once):

| IP | Host |
|---|---|
| 10.6.9.20 | cobra-stream (SGIN) |
| 10.6.9.30 | cobra-arcade (OptiPlex) |
| 10.6.9.40 / .41 | R620 iDRAC / R620 (later) |
| 10.6.9.50 / .51 | Desktops |

`.2`, `.3`, `.10` are static on the hosts themselves; don't add them here.

## 2.7 DNS over TLS (Services → Unbound DNS)

- [ ] **General**: Enable, Listen interfaces **LAN** (add **WG** after 2.8), DNSSEC: tick. Save, Apply.
- [ ] **DNS over TLS** → Add:

| Server IP | Port | Verify CN |
|---|---|---|
| `1.1.1.1` | 853 | `cloudflare-dns.com` |
| `1.0.0.1` | 853 | `cloudflare-dns.com` |
| `9.9.9.9` | 853 | `dns.quad9.net` |

- [ ] Apply. Check from the desktop: `nslookup example.com 10.6.9.1` works. Optional: Interfaces → Diagnostics → Packet Capture on WAN, port 53, should stay empty.

## 2.8 WireGuard (remote admin)

**On OPNsense, VPN → WireGuard:**

- [ ] **Instances** → Add: name `wg0`, click the gear to **generate keys**, Listen port `51820`, Tunnel address `10.6.99.1/24`. Save. Copy the **public key**.
- [ ] On the phone/laptop: WireGuard app → **+** → create from scratch → it generates the client key pair. Copy the client's **public key**.
- [ ] **Peers** → Add: name `phone`, Public key = client's, Allowed IPs `10.6.99.2/32`, Instances `wg0`. Save. (Next device: `.3`, `.4`, …)
- [ ] **Settings**: Enable WireGuard. Apply.
- [ ] **Interfaces → Assignments**: add `wg0` → description `WG` → Save → open `WG`, tick Enable, Save, Apply.
- [ ] **Firewall → Rules → WAN** → Add: Pass, Protocol **UDP**, Destination **WAN address**, Port **51820**. Save, Apply.
- [ ] **Firewall → Rules → WG** → Add: Pass, Source **WG net**, Destination **LAN net**. Save, Apply.
- [ ] Unbound → General → Listen interfaces: add **WG**.

Client config (the app shows these fields):

```ini
[Interface]
PrivateKey = <client private key, generated by the app>
Address = 10.6.99.2/32
DNS = 10.6.9.3, home.arpa      # the name after the IP is a search domain, so short names resolve

[Peer]
PublicKey = <wg0 public key from OPNsense>
Endpoint = songofeo.com:51820
AllowedIPs = 10.6.9.0/24, 10.6.99.0/24
PersistentKeepalive = 25
```

✅ After 2.10 (DDNS): phone on cellular, Wi-Fi off, tunnel on → `https://10.6.9.2:8006` loads.

## 2.9 Pi-hole CT 101 (cobra-command shell)

```bash
TPL=$(ls /var/lib/vz/template/cache | grep -m1 debian-13-standard)
pct create 101 local:vztmpl/$TPL --hostname cobra-pihole-1 --cores 1 --memory 512 --swap 512 \
  --rootfs local-lvm:4 --net0 name=eth0,bridge=vmbr0,ip=10.6.9.3/24,gw=10.6.9.1 \
  --nameserver 10.6.9.1 --searchdomain home.arpa \
  --unprivileged 1 --features nesting=1 --onboot 1 --startup order=2
pct start 101
pct enter 101                                 # root shell inside the container
```

`--unprivileged 1`: root in the container is a nobody on the host. `nesting=1`: Debian 13's systemd needs it inside an unprivileged CT.

Inside CT 101:

```bash
apt update && apt full-upgrade -y && apt install -y curl
curl -sSL https://install.pi-hole.net | bash
#   Upstream DNS: Custom -> 10.6.9.1   |  Blocklist: yes  |  Query logging: on  |  Privacy: 0
pihole setpassword
pihole-FTL --config dns.upstreams '["10.6.9.1"]'
# Default "LOCAL" mode ignores clients on subnets Pi-hole has no interface on, which
# includes WireGuard (10.6.99.0/24). Only the LAN can reach this CT, so ALL is safe here.
pihole-FTL --config dns.listeningMode ALL
# *.songofeo.com -> the gate, so LAN traffic never leaves the house
pihole-FTL --config misc.dnsmasq_lines '["address=/songofeo.com/10.6.9.10"]'
# local names, full and short. The short ones matter over WireGuard: a VPN client doesn't
# get the home.arpa search suffix, so \\cobra-stream would otherwise not resolve.
pihole-FTL --config dns.hosts '["10.6.9.1 cobra-firewall.home.arpa cobra-firewall","10.6.9.2 cobra-command.home.arpa cobra-command","10.6.9.3 cobra-pihole-1.home.arpa cobra-pihole-1","10.6.9.10 cobra-gate.home.arpa cobra-gate","10.6.9.20 cobra-stream.home.arpa cobra-stream","10.6.9.30 cobra-arcade.home.arpa cobra-arcade"]'
exit
```

- [ ] Admin UI: `http://10.6.9.3/admin`
- [ ] Desktop: `ipconfig /renew`, then `ipconfig /all` lists DNS `10.6.9.3`
- [ ] `nslookup tv.songofeo.com` → `10.6.9.10`; `nslookup google.com` → real IP; queries show in Pi-hole

## 2.10 Dynamic DNS (Services → Dynamic DNS)

Keeps `songofeo.com` (apex A record) pointed at your home IP. App hostnames get CNAMEs to the apex in part 5.

- [ ] **Settings**: Enable. Accounts → Add:

| Field | Value |
|---|---|
| Service | **Porkbun** |
| Username | the `cobra-ddns` **API key** (`pk1_…`) |
| Password | its **secret API key** (`sk1_…`) |
| Hostname(s) | `songofeo.com` |
| Check ip method | a web service (e.g. `ipify-ipv4`), **not** "Interface" (*WAN is `10.0.0.2`, a private address*) |

⚠️ Check the field help on screen: if the Porkbun form asks for the keys under other labels (e.g. "API key" / "Secret"), put the `pk1_` key and the `sk1_` key there instead.

- [ ] Save, Apply. Within a few minutes Porkbun → `songofeo.com` → DNS shows an **A** record for `songofeo.com` (host blank) with your public IP. If it doesn't, the most common cause is API Access still being off for the domain (part 0.4).
- [ ] **IPv4 only.** This build forwards IPv4 only; Xfinity also gives you an IPv6 address, but nothing behind OPNsense is reachable on it. If any updater (this one, or an older one from your old server) publishes it, browsers try the IPv6 first and every link breaks. Leave IPv6 off in the account (no AAAA), and in Porkbun's DNS **delete any AAAA records**. Check from any machine: `nslookup -type=AAAA songofeo.com 1.1.1.1` returns no address.
- [ ] Turn off any old updater (a script or container on the old server) that also writes to this domain, so two updaters don't fight

## 2.11 IDS/IPS and CrowdSec

- [ ] **Interfaces → Settings**: tick Disable hardware CRC, Disable hardware TSO, Disable hardware LRO. Save, **reboot OPNsense** (*IPS mode needs these off on virtio NICs*).
- [ ] **Services → Intrusion Detection → Administration → Settings**: Enabled, **IPS mode**, Pattern matcher **Hyperscan**, Interfaces **WAN**. Apply.
- [ ] **Download** tab: tick the `ET open/*` rulesets → **Enable selected** → **Download & Update Rules**.
- [ ] **Policy** tab → Add: Rulesets = the ET open ones, Action = Alert, New action = **Drop**. Save, Apply. (*Rules ship as alert-only; the policy is what makes IPS block.*)
- [ ] **Schedule** tab: enable daily rule updates.
- [ ] **Services → CrowdSec → Settings**: Enable log processor, LAPI and firewall bouncer (on by default after install on most versions). Apply.
- [ ] Check: Services → Intrusion Detection → Alerts fills over the next day; CrowdSec → Overview shows decisions.

## Done when

- [ ] Wired devices get `10.6.9.1xx` (or their reservation), DNS `10.6.9.3`, and browse normally
- [ ] Proxmox at `https://10.6.9.2:8006`, OPNsense at `https://10.6.9.1` (TOTP)
- [ ] `nslookup anything.songofeo.com` on the LAN → `10.6.9.10`
- [ ] Porkbun A record for `songofeo.com` = your public IP; no AAAA records
- [ ] Phone on cellular reaches Proxmox through WireGuard
- [ ] Back up the OPNsense config: System → Configuration → Backups → **Download configuration**

Next: **[3. Set up SGIN](03-sgin.md)**.
