# 2. Redo networking (OPNsense gateway VM 100, Pi-hole CT 101)

**Result:** OPNsense, running as a VM on the Latitude, is the router/firewall for the house. All wired gear sits behind it on `10.6.9.0/24`, Pi-hole filters DNS, and WireGuard gets you in from outside.

**Needs:** part 1 done. `songofeo.com` on Porkbun with **API Access turned on** for the domain, and the `cobra-ddns` Porkbun API key + secret key (part 0.4). A 2–3 h window: **wired internet is down from 2.4 until 2.5 is finished.** Xfinity Wi-Fi keeps working except for a minute while the gateway restarts.

**"The switch"** in this part is the LAN switch every wired machine plugs into: the TP-Link Omada ES210X-M2, `cobra-switch` (set up in 2.12). It replaced the Netgear 5-port switch E, and every step here works the same on either, so the swap can happen before, during or after this part. Doing the cutover (2.4) on switch E and swapping afterwards is the simplest order: one change at a time.

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

**Make the cutover a one-word command.** During 2.4 you work at the Latitude's keyboard without copy and paste, so write the two commands you'll need now, while the web Shell still works (cobra-command → **>_ Shell**, paste):

```bash
cat > /usr/local/bin/opn-connect <<'EOF'
#!/bin/sh
# Plug OPNsense's virtual cables in (2.4 step 3)
for n in net0 net1; do
  qm set 100 --$n "$(qm config 100 | sed -n "s/^$n: //p" | sed 's/,link_down=1//')"
done
qm config 100 | grep -E '^net[01]'
EOF
cat > /usr/local/bin/opn-disconnect <<'EOF'
#!/bin/sh
# Rollback: unplug OPNsense's virtual cables again
for n in net0 net1; do
  qm set 100 --$n "$(qm config 100 | sed -n "s/^$n: //p" | sed 's/,link_down=1//'),link_down=1"
done
qm config 100 | grep -E '^net[01]'
EOF
chmod 755 /usr/local/bin/opn-connect /usr/local/bin/opn-disconnect
```

## 2.4 Cut over (internet down from here)

**Do this at the Latitude's own keyboard and screen.** The desktop loses its connection partway through. Plan 30–60 minutes; Xfinity Wi-Fi drops briefly while the gateway restarts.

> **If it goes wrong: get the internet back in 2 minutes.** Nothing in this section is permanent until you finish it.
> 1. Latitude keyboard: `opn-disconnect` (so OPNsense stops handing out addresses; `qm stop 100` works too).
> 2. Plug the switch's uplink back into the Xfinity gateway (the TP-Link USB NIC cable can stay or come out).
> 3. Every device renews from Xfinity and has internet again: `10.0.0.x` if you already did step 1 below, `10.6.9.x` if you didn't. (Reboot or unplug/replug a device that doesn't.)
> 4. To reach Proxmox while rolled back: it is still `10.6.9.2`. If your desktop now has a `10.0.0.x` address, it can't see `10.6.9.2`; either use the Latitude's own screen, or set the desktop to a fixed address for a moment (Windows: Settings → Network → Ethernet → IP assignment → Edit → Manual, IPv4 `10.6.9.50`, mask `255.255.255.0`, gateway blank). It has no internet while set that way; switch it back to Automatic (DHCP) when you're done.
> 5. Try again later: `qm start 100` if you stopped it, then pick up at step 2 (Recable) below. Your OPNsense install and settings are kept.

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
opn-connect                                   # the helper from 2.3; no link_down left in its output
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

- [ ] Old server on **`10.6.9.200`**. If it's already set to `.200` on the box itself (yours is, with gateway and DNS `10.6.9.1`), skip this: it keeps working once OPNsense owns `.1`. Only if it still uses DHCP: OPNsense DHCP (see 2.6 for which page) → static mapping `10.6.9.200` for its MAC, then renew DHCP or reboot it and check it got `.200`.
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
- [ ] **Proxmox's own DNS** now goes to OPNsense (part 1 pointed it at Xfinity's public DNS): cobra-command shell, `printf 'search home.arpa\nnameserver 10.6.9.1\n' > /etc/resolv.conf && ping -c3 download.proxmox.com`. (UI: cobra-command → System → DNS.)
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
| 10.6.9.6 | cobra-ap (Wi-Fi access point, 2.10b) |
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
Endpoint = gate.songofeo.com:51820     # the DDNS name (2.10); the bare songofeo.com is the station on Porkbun's hosting
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
# *.songofeo.com -> the gate, so LAN traffic never leaves the house. "*." matches only the names
# under songofeo.com, so the bare songofeo.com and www (the station, on Porkbun's hosting) still
# resolve normally; without that, the station wouldn't load at home.
pihole-FTL --config misc.dnsmasq_lines '["address=/*.songofeo.com/10.6.9.10","server=/www.songofeo.com/#"]'
# local names, full and short. The short ones matter over WireGuard: a VPN client doesn't
# get the home.arpa search suffix, so \\cobra-stream would otherwise not resolve.
pihole-FTL --config dns.hosts '["10.6.9.1 cobra-firewall.home.arpa cobra-firewall","10.6.9.2 cobra-command.home.arpa cobra-command","10.6.9.3 cobra-pihole-1.home.arpa cobra-pihole-1","10.6.9.5 cobra-switch.home.arpa cobra-switch","10.6.9.6 cobra-ap.home.arpa cobra-ap","10.6.9.10 cobra-gate.home.arpa cobra-gate","10.6.9.20 cobra-stream.home.arpa cobra-stream","10.6.9.30 cobra-arcade.home.arpa cobra-arcade"]'
exit
```

- [ ] Admin UI: `http://10.6.9.3/admin`
- [ ] Desktop: `ipconfig /renew`, then `ipconfig /all` lists DNS `10.6.9.3`
- [ ] `nslookup tv.songofeo.com` → `10.6.9.10`; `nslookup google.com` → real IP; queries show in Pi-hole
- [ ] `nslookup songofeo.com` and `nslookup www.songofeo.com` → Porkbun's addresses, **not** `10.6.9.10` (the station has to load at home too)

## 2.10 Dynamic DNS (Services → Dynamic DNS)

Keeps **`gate.songofeo.com`** (an A record) pointed at your home IP. The bare `songofeo.com` is **not** touched: Porkbun's static hosting serves your public homepage there (the SongofEo project). App hostnames get CNAMEs to `gate.songofeo.com` in part 5.

- [ ] **Settings**: Enable. Accounts → Add:

| Field | Value |
|---|---|
| Service | **Porkbun** |
| Username | the `cobra-ddns` **API key** (`pk1_…`) |
| Password | its **secret API key** (`sk1_…`) |
| Hostname(s) | `gate.songofeo.com` |
| Check ip method | a web service (e.g. `ipify-ipv4`), **not** "Interface" (*WAN is `10.0.0.2`, a private address*) |

⚠️ Check the field help on screen: if the Porkbun form asks for the keys under other labels (e.g. "API key" / "Secret"), put the `pk1_` key and the `sk1_` key there instead.

- [ ] Save, Apply. Within a few minutes Porkbun → `songofeo.com` → DNS shows an **A** record for `gate` with your public IP. (If the updater won't create the record itself, add `gate` → `1.1.1.1` by hand first; it then corrects the address.) If it doesn't appear, the most common cause is API Access still being off for the domain (part 0.4). ⚠️ Never point the updater at the bare `songofeo.com`: it would overwrite Porkbun's hosting record and take your homepage down.
- [ ] **IPv4 only.** This build forwards IPv4 only; Xfinity also gives you an IPv6 address, but nothing behind OPNsense is reachable on it. If any updater (this one, or an older one from your old server) publishes it, browsers try the IPv6 first and every link breaks. Leave IPv6 off in the account (no AAAA), and in Porkbun's DNS **delete any AAAA records**. Check from any machine: `nslookup -type=AAAA gate.songofeo.com 1.1.1.1` returns no address.
- [ ] Turn off any old updater (a script or container on the old server) that also writes to this domain, so two updaters don't fight

## 2.10a Wi-Fi devices (TVs, phones, laptops)

Xfinity's Wi-Fi sits **outside** OPNsense on `10.0.0.x`, the untrusted side. That's deliberate (guests and smart gadgets can't see your servers), but it means:

| On Xfinity Wi-Fi | Works? |
|---|---|
| Internet | Yes |
| `https://tv.songofeo.com`, `arcade.`, etc. | Yes, the same way as from outside the house (through the public address and port 443) |
| `\\cobra-stream` shares, Proxmox, `10.6.9.x` addresses | **No**, unless WireGuard is on (2.8) |

- [ ] **Test the TVs now.** On the Roku and the Apple TV, open the Jellyfin app and use the server address `https://tv.songofeo.com` (not an IP). It should connect once part 3 is done; the bare `songofeo.com` is hosted by Porkbun, so it always loads and proves nothing here; test with an app hostname.
- [ ] **If it doesn't load on Wi-Fi but does on cellular:** the Xfinity gateway isn't looping traffic for your own public address back in ("NAT loopback"). Two fixes, best first:
  1. **Wire the TVs to the switch.** Streaming is smoother wired anyway, and they then get `10.6.9.x` and Pi-hole sends `tv.songofeo.com` straight to the gate.
  2. **Join the trusted Wi-Fi access point** (2.10b, below). Devices on it are on `10.6.9.x` like wired ones. Use it for the TVs and your own laptops; leave guests and gadgets on Xfinity Wi-Fi.
- [ ] **Laptops that need the shares** (`\\cobra-stream`): plug in, join `cobra` Wi-Fi (2.10b), or turn on WireGuard (2.8). On Xfinity Wi-Fi alone they can't see the shares, by design.

## 2.10b Trusted Wi-Fi access point (on the switch)

**Result:** a Wi-Fi network of your own, `cobra`, that sits **inside** OPNsense like a wired port. Laptops, phones and TVs on it get `10.6.9.1xx`, use the Pi-holes, see `\\cobra-stream`, and are covered by the IDS/IPS (2.11). Xfinity's Wi-Fi stays on as the untrusted network for guests and smart gadgets.

### What to buy

Full comparison of the models considered: [Future builds: Wi-Fi access points](../future-builds/wifi-access-points.md).

| | Model | Price (Oct 2026) | Why |
|---|---|---|---|
| **Top pick** | **TP-Link Omada EAP772** (Wi-Fi 7, tri-band 2.4/5/6 GHz, 2.5 GbE port) | ~$160–170 | Full local web UI in **standalone mode**: no controller, no cloud account, nothing else to run. One SSID per VLAN when part 9 brings VLANs. 6 GHz gives the newest laptops and phones a clean band the neighbours aren't on. |
| Budget | TP-Link Omada EAP723 (Wi-Fi 7, dual-band, no 6 GHz) | ~$85–90 | Same standalone web UI and VLAN support; plenty for a house of 1080p/4K streams. |
| No-TP-Link option | Zyxel NWA110BE (Wi-Fi 7) | ~$140 | Full local web UI and CLI, also takes USB-C power. |
| **Plus** | a **PoE+ (802.3at, 30 W) injector**: gigabit (e.g. TP-Link TL-POE160S, ~$20–25), or the 2.5 GbE **TL-POE260S**, so the AP's 2.5 GbE port gets the full speed of cobra-switch's 2.5G ports | ~$20–40 | These APs ship **without** a power adapter, and cobra-switch (the ES210X-M2, 2.12) has no PoE. The injector sits between the switch and the AP. |

**Skip** for this build: UniFi APs (in standalone mode they're limited to the phone app; the full features need a UniFi controller running somewhere, one more service to keep alive) and a mesh kit or old router in "AP mode" (works, but most can't put an SSID on a VLAN, which part 9 needs).

### Cable it

```
cobra-switch port 6 ──► injector "LAN/Data" ──► injector "PoE" ──► AP's ETH/PoE port
                        injector power cord → wall outlet (or the UPS)
```

Mount the AP high and central (ceiling or top of a shelf, logo facing down/out), away from the Xfinity gateway so their signals don't sit on top of each other. One run of Cat 6 from the switch can be up to 100 m.

### Set it up (from a desktop wired to the switch)

- [ ] AP powers up and asks OPNsense for an address. Find it on the DHCP page from 2.6 → **Leases** (hostname like `EAP772` or a MAC starting with the TP-Link prefix). Add a **static mapping `10.6.9.6`** for that MAC, Save/Apply, then unplug and replug the AP's cable at the injector so it picks up `.6`.
  (`.5` is cobra-switch, 2.12.)
- [ ] Browser: `https://10.6.9.6` → accept the self-signed certificate → create the admin user with a **generated password** (save it in Vaultwarden once part 5 is up). If it offers **Omada Cloud / app adoption**, decline: you want **standalone**.
- [ ] **System → Firmware Update** (or Management → Firmware): update before anything else. Reboot.
- [ ] **System → Time Settings**: time zone, NTP server `10.6.9.1`.
- [ ] **Network / IP settings:** keep DHCP (OPNsense hands out `.6`). Leave **Management VLAN off** for now.
- [ ] **Wireless → SSID → Add**, one SSID on all bands:
  - Name: `cobra` (or anything that doesn't identify the house). Not hidden.
  - Security: **WPA2/WPA3-Personal** (mixed / transition). 6 GHz forces WPA3 on its own; that's expected.
  - Password: a long passphrase (20+ characters).
  - VLAN: **off / none** (so it lands on the untagged LAN, `10.6.9.x`).
  - **Guest network / client isolation: off** for this SSID (your own devices need to see the shares and each other, e.g. casting).
- [ ] **Wireless → Radio settings** (names vary): Region **United States**. 2.4 GHz: 20 MHz, channel **1, 6 or 11**, whichever Xfinity's 2.4 GHz isn't on (the Xfinity app shows its channel). 5 GHz: 80 MHz, channel Auto or a fixed one away from Xfinity's. 6 GHz: 160 MHz (EAP772 only).
- [ ] Turn **off** anything the AP doesn't need: Omada Cloud access, SSH (unless you want it), and "Remote management" if listed. Its LED can go off too.
- [ ] **Local name** (both Pi-holes' `dns.hosts`, parts 2.9 and 3.9): `"10.6.9.6 cobra-ap.home.arpa cobra-ap"`.

### Move your devices over

| Device | Network |
|---|---|
| Your laptops and phones, the Roku and Apple TV (unless wired), tablets | **`cobra`** (trusted) |
| Guests, smart plugs, bulbs, cameras, voice assistants, anything you didn't build | **Xfinity Wi-Fi** (untrusted, outside OPNsense) |

- [ ] Forget the Xfinity network on each moved device, so it doesn't hop back.
- [ ] Rename Xfinity's Wi-Fi (Xfinity app → WiFi → Edit) to something like `cobra-guest`, so it's obvious which is which. Optional: if you'll never use it for guests or gadgets, turn it off there instead.

### Check

- [ ] A laptop on `cobra`: `ipconfig` shows `10.6.9.1xx`, gateway `10.6.9.1`, DNS `10.6.9.3`. `\\cobra-stream` opens. `https://10.6.9.2:8006` loads.
- [ ] A phone on `cobra` loads `https://tv.songofeo.com`, and the Pi-hole dashboard (2.9) lists the phone's `10.6.9.1xx` address as a client.
- [ ] Once part 5 is done: Uptime Kuma → add a **Ping** monitor for `10.6.9.6` (`cobra-ap`).

### Later, with VLANs (part 9, phase B)

The AP is ready for VLANs as-is. When part 9 turns on VLANs on cobra-switch, its port (6) is "Everything else" in 9.5 (untagged 1). If you later want guests and gadgets off Xfinity's Wi-Fi too, add a GUEST/IoT VLAN the same way part 9 adds LAB (OPNsense VLAN + DHCP + "block `PRIVATE`, allow internet" rules), tag it on the AP's switch port, and add a second SSID on that VLAN with client isolation on. Then Xfinity's Wi-Fi can be switched off entirely.

## 2.11 IDS/IPS and CrowdSec

- [ ] **Interfaces → Settings**: tick Disable hardware CRC, Disable hardware TSO, Disable hardware LRO. Save, **reboot OPNsense** (*IPS mode needs these off on virtio NICs*).
- [ ] **Services → Intrusion Detection → Administration → Settings**: Enabled, **IPS mode**, Pattern matcher **Hyperscan**, Interfaces **WAN**. Apply.
- [ ] **Download** tab: tick the `ET open/*` rulesets → **Enable selected** → **Download & Update Rules**.
- [ ] **Policy** tab → Add: Rulesets = the ET open ones, Action = Alert, New action = **Drop**. Save, Apply. (*Rules ship as alert-only; the policy is what makes IPS block.*)
- [ ] **Schedule** tab: enable daily rule updates.
- [ ] **Services → CrowdSec → Settings**: Enable log processor, LAPI and firewall bouncer (on by default after install on most versions). Apply.
- [ ] Check: Services → Intrusion Detection → Alerts fills over the next day; CrowdSec → Overview shows decisions.

## 2.12 The LAN switch: TP-Link Omada ES210X-M2 (`cobra-switch`)

**Result:** every wired machine on the LAN, the Latitude (the gate) included, plugs into the **TP-Link Omada ES210X-M2** at `10.6.9.5`, with its own login, current firmware and loop prevention on. It replaces the Netgear 5-port **switch E**, which becomes a spare.

**What it is:** 8× 2.5GBASE-T ports, 2× 10G SFP+ slots, fanless, *easy managed* (its own web UI, 802.1Q VLANs, loop prevention, port statistics and cable test). **No PoE**, so the Wi-Fi AP keeps its injector (2.10b). In standalone mode it needs no Omada controller, cloud account or app. Being managed is what part 9's VLANs need, so phase B needs no further purchase.

**Port plan.** Stick to it: part 9's VLAN table goes by port number, and a label on each cable end saves guessing later.

| Port | Goes to | Link you should see |
|---|---|---|
| 1 | Latitude onboard port (`nic0`, OPNsense LAN and the gate) | 1000M (the I219-LM is 1 GbE) |
| 2 | SGIN's USB network adapter (AX88179) | 1000M |
| 3 | OptiPlex (cobra-arcade) | 1000M |
| 4 | Desktop 1 | 1000M (2500M if it has a 2.5 GbE port) |
| 5 | Desktop 2 | 1000M (or 2500M) |
| 6 | Wi-Fi AP, through its PoE injector (2.10b) | 2500M with a 2.5G-rated injector; 1000M through a gigabit one |
| 7 | R620 iDRAC (part 9) | 1000M |
| 8 | R620 NIC 1 (part 9); spare until then | 1000M |
| SFP+ 9–10 | Free: 10G later (needs an SFP+ module or a DAC cable) | — |

⚠️ **Never connect two cables between the same two switches** (this one and the spare Netgear, say). That makes a loop that floods the whole LAN. Loop prevention (below) shuts a looped port down, but don't rely on it.

### Before you start

- [ ] Take a photo of switch E with its cables in, and put a piece of tape on each cable near the plug with what it goes to (`latitude`, `sgin`, `arcade`, `desk1`, `desk2`, `ap`)
- [ ] A desktop wired to switch E, with this manual open on it
- [ ] Stop anything long-running on the SGIN that you'd mind pausing (a copy, an image in 3.4): moving its cable drops its network for a few seconds. `ddrescue` itself doesn't care (it reads and writes local USB drives), but SSH sessions outside `tmux` will drop
- [ ] The switch's power brick goes on a UPS **battery-backed** outlet, like the Latitude's and the SGIN's: if the switch loses power, the whole LAN does

### 1. First power-up, on one cable (everything else keeps working)

- [ ] Plug in the new switch's power. Then **one** cable: a free port on switch E → **port 8** on the new switch. If switch E has no free port, move Desktop 2's cable from switch E to new port 5, and use the freed switch E port for the link. Nothing else goes on the new switch yet.
- [ ] The switch asks for an address by DHCP (its default), so OPNsense gives it one. Find it on the DHCP page from 2.6 → **Leases**: the MAC printed on the switch's label (also the hostname, e.g. `ES210X-M2`). Write down the address.
- [ ] If it never appears in the leases after 2 minutes, it's at its fallback `192.168.0.1`: unplug the desktop from switch E, cable it straight into port 1 of the new switch, and give the desktop `192.168.0.100`, mask `255.255.255.0` for the setup (Windows: Settings → Network → Ethernet → IP assignment → Edit → Manual; set it back to Automatic (DHCP) when done).

### 2. Log in and secure it (browser on the desktop)

- [ ] `http://<address from step 1>` → the setup wizard opens. Create the admin account it asks for: a username that **isn't** `admin`, and a **generated password** (store it in KeePassXC now, Vaultwarden once part 5 is up). Older firmware shows a login instead: `admin` / `admin`, and it then forces a new password.
- [ ] If the wizard offers **Omada controller / cloud** management, skip it: this switch runs **standalone**.
- [ ] **Firmware first:** System → **Firmware Upgrade** shows the version. On the desktop, `support.omadanetworks.com` → ES210X-M2 → **Firmware**, pick the hardware version on the switch's label (e.g. V1), download, unzip, upload the `.bin`. Don't unplug it while it upgrades (a few minutes; it reboots and comes back on the same address).
- [ ] **System → System Info / Device Description:** name `cobra-switch`, location where it sits.
- [ ] **System → System Time:** your time zone, NTP server `10.6.9.1` (OPNsense).
- [ ] **System → IP Setting:** DHCP **off**, static: IP `10.6.9.5`, mask `255.255.255.0`, gateway `10.6.9.1`, DNS `10.6.9.3` (and `10.6.9.20` if it takes a second one). Management VLAN stays **1**. Apply. The page stops answering; after 30 seconds browse to **`http://10.6.9.5`** and log in again. (Did you use the `192.168.0.100` fallback? Set the desktop back to Automatic (DHCP) first, move its cable back to switch E, and then browse to `10.6.9.5`.) Static rather than a DHCP mapping on purpose: the switch then comes up on a known address even when the OPNsense VM is down, which is exactly when you need to reach it.
- [ ] **Security / Access:** if it has an HTTPS option, turn it on and use `https://10.6.9.5` from now on (self-signed warning, as on Proxmox). Turn off **Telnet** if it's listed. The UI is only reachable from the LAN and over WireGuard, because OPNsense forwards nothing to it.
- [ ] **Loop Prevention** (under L2 Features or Monitoring): **on**, globally and on every port. It usually ships on; check it.
- [ ] **VLAN → 802.1Q VLAN:** leave the default: VLAN 1, every port **untagged**, every PVID **1**. Part 9 changes this; until then a tag in the wrong place cuts machines off.
- [ ] Leave **IGMP snooping off** for now. With no IGMP querier on the LAN (OPNsense isn't one by default), snooping can stop casting and device discovery from working.
- [ ] **Save** if the UI has a Save Config button (some firmware keeps changes only until a reboot otherwise). Then System Tools → **Backup Config** → save the file next to the OPNsense config backup.

### 3. Move the cables over (each device blips for a few seconds)

Both switches are linked through port 8 during this, so every machine can still reach every other one while you move them one at a time. Move each cable from switch E to its port from the table above, and wait for that port's light before the next:

1. [ ] Desktop 1 → port 4, Desktop 2 → port 5 (if not moved already)
2. [ ] OptiPlex → port 3
3. [ ] Wi-Fi AP's injector "LAN/Data" cable → port 6 (if the AP is in yet)
4. [ ] SGIN's adapter cable → port 2. Streams and shares pause for a few seconds.
5. [ ] Latitude's **onboard** port → port 1. That's the cable to the gate, so the whole house drops for a few seconds. **Not** the TP-Link USB NIC's cable: that one goes to Xfinity and stays there.
6. [ ] Now switch E has only the link cable left. Unplug it from **both** ends, then unplug switch E's power.

Nothing on the LAN changes address: DHCP reservations go by MAC, not by switch port.

### 4. Check

```bash
# On the Latitude (cobra-command shell): the gate's link to the switch
ethtool nic0 | grep -E 'Speed|Duplex|Link detected'      # 1000Mb/s, Full, yes
ip -s link show nic0 | grep -A1 -E 'RX|TX'                # errors / dropped stay 0 (run again after an hour)
ping -c3 10.6.9.5                                         # the switch answers

# On the SGIN (ssh eels@10.6.9.20): its USB adapter's link
IF=$(ls /sys/class/net | grep -m1 '^enx'); echo $IF       # the adapter's name, e.g. enx9c69d3b6174b
sudo ethtool $IF | grep -E 'Speed|Duplex|Link detected'   # 1000Mb/s, Full, yes
ping -c3 10.6.9.1 && ping -c3 10.6.9.5
```

```powershell
# On each desktop (PowerShell)
Get-NetAdapter | Where-Object Status -eq Up | Format-Table Name, LinkSpeed   # 1 Gbps (or 2.5 Gbps)
ping 10.6.9.1; ping 10.6.9.5; ping 10.6.9.20
Test-NetConnection 10.6.9.20 -Port 445                                         # TcpTestSucceeded : True (the shares)
```

- [ ] Switch UI → **Port Status / Statistics:** every used port shows Link Up, **Full** duplex, at the speed in the table. An hour later, the error counters are still 0
- [ ] A port at **100M**, or one that keeps dropping: bad or old cable (gigabit and faster need all 8 wires; use Cat 5e or better). The switch's **Cable Test** page tests it in place
- [ ] OPNsense → **Interfaces → Overview → LAN**: In/Out errors 0
- [ ] Internet from a desktop, `\\cobra-stream` opens, and a stream plays
- [ ] **Local name** on both Pi-holes. The `dns.hosts` setting is the whole list, so set it all at once. Pi-hole #1 from the cobra-command shell (Pi-hole #2, once part 3.9 is done: the same command on the SGIN with `sudo` in place of `pct exec 101 --`):

```bash
pct exec 101 -- pihole-FTL --config dns.hosts '["10.6.9.1 cobra-firewall.home.arpa cobra-firewall","10.6.9.2 cobra-command.home.arpa cobra-command","10.6.9.3 cobra-pihole-1.home.arpa cobra-pihole-1","10.6.9.5 cobra-switch.home.arpa cobra-switch","10.6.9.6 cobra-ap.home.arpa cobra-ap","10.6.9.10 cobra-gate.home.arpa cobra-gate","10.6.9.20 cobra-stream.home.arpa cobra-stream","10.6.9.30 cobra-arcade.home.arpa cobra-arcade"]'
nslookup cobra-switch 10.6.9.3        # answers 10.6.9.5
```

- [ ] Once part 5 is done: Uptime Kuma → a **Ping** monitor for `10.6.9.5` (`cobra-switch`)

### The spare Netgear (switch E)

Unplugged, labelled *spare, unmanaged*, and kept with its power brick. Two good uses:

- **Emergency replacement.** If cobra-switch dies, switch E carries the flat LAN exactly as before (move the cables back, nothing else changes). After part 9 it can't carry the VLANs, so the lab stays off until the Omada is back.
- **A few more ports in one room** (a TV corner, say): one cable from a cobra-switch port to switch E, and the devices there land on the LAN as usual. Only ever on a port that's "untagged 1" in part 9, never on the R620's or the iDRAC's ports, and never with a second cable back to cobra-switch.

## Done when

- [ ] Wired devices get `10.6.9.1xx` (or their reservation), DNS `10.6.9.3`, and browse normally
- [ ] Proxmox at `https://10.6.9.2:8006`, OPNsense at `https://10.6.9.1` (TOTP)
- [ ] `nslookup anything.songofeo.com` on the LAN → `10.6.9.10`; `nslookup songofeo.com` → not `10.6.9.10`
- [ ] Porkbun A record for `gate.songofeo.com` = your public IP; no AAAA records; the bare `songofeo.com` still shows your Porkbun-hosted homepage
- [ ] Phone on cellular reaches Proxmox through WireGuard
- [ ] A laptop on `cobra` Wi-Fi (2.10b) gets `10.6.9.1xx` and opens `\\cobra-stream`
- [ ] Every wired machine is on cobra-switch (2.12) at its expected link speed, and `http://10.6.9.5` (or `https://`) opens its UI
- [ ] Once part 5 is done: a phone on Xfinity Wi-Fi loads `https://tv.songofeo.com` (if not, see 2.10a before you rely on the TVs)
- [ ] Back up the OPNsense config: System → Configuration → Backups → **Download configuration**

Next: **[3. Set up SGIN](03-sgin.md)**.
