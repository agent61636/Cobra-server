# 10. Smart home: Home Assistant (VM 120) instead of the Alexa app

**Result:** one app and one dashboard for the house. The Sensi thermostat and the Eufy bulbs and light switches show up in **Home Assistant** (`cobra-home`, VM 120 on the Latitude), on your phone through the Home Assistant app, and in a browser at `https://ha.songofeo.com` behind the station sign-in. Wherever the devices allow it, Home Assistant talks to them **directly over your own network**, so the lights and the thermostat keep working when Eufy's, Sensi's or Amazon's servers are down.

**Needs:** parts 1, 2 and 5 done (Proxmox, OPNsense, Pi-holes, the gate with Authelia). The thermostat and the Eufy gadgets stay on the Xfinity Wi-Fi, where part 2.10a put them. About 2 hours, most of it pairing devices.

🔌 No cable changes.

---

## 10.1 What works, and how (checked October 2026)

| Device | How Home Assistant talks to it | Local or cloud | Notes |
|---|---|---|---|
| **Sensi thermostat**, plan A | Built-in **HomeKit Device** integration (Apple's HomeKit protocol over Wi-Fi). You don't need any Apple device for it. | **Local** | Copeland lists the Sensi Touch as HomeKit-capable. Owners also report the non-touch Sensi Smart (ST55) pairing this way, as recently as Oct 21, 2026. The Sensi app keeps working alongside it. |
| Sensi thermostat, plan B | **`iprak/sensi`** custom integration, installed through HACS | **Cloud** (polls Sensi's servers every 30 s) | Use it only if your model won't pair over HomeKit. Since Sensi app 8.6.3 the login has a reCAPTCHA, so you paste a *refresh token* from your browser once (10.6). There's no Sensi integration built into Home Assistant. |
| **Eufy bulbs**: T1011 (white), T1012 (tunable white), T1013 (colour) | Built-in **EufyHome** integration (`eufy`, set up in YAML) | **Local** after a one-time cloud lookup of each device's local code | ⚠️ **Broken in Home Assistant 2026.10.x** for at least the T1013 (`Expected an int, got a boolean`, [core issue #186877](https://github.com/home-assistant/core/issues/186877), still open on Oct 26, 2026). The last version that works is **2026.9.4**, and 10.5 shows how to hold Home Assistant on it until a fix ships. |
| **Eufy switches and plugs**: T1201, T1202, T1203, T1211 | Same EufyHome integration | Local, same as the bulbs | Same caveat as the bulbs. |
| Newer Eufy bulbs (T1015, T1016 and later) | **Not supported.** Owners report they only talk through Eufy's cloud. | — | Check your model numbers first (10.5, step 1). If yours are on this row, read "If your Eufy models aren't supported" at the end of 10.5. |

**What "local" buys you:** a switch flips in a fraction of a second, it works when the internet is down, and nothing about when you're home goes to a vendor's server. The Eufy and Sensi apps keep working in parallel either way; Home Assistant doesn't take the devices away from them.

---

## 10.2 Where it runs, and why

**Home Assistant OS as a VM on `cobra-command` (the Latitude), with a second network card on the Xfinity Wi-Fi side.**

| Option | Verdict |
|---|---|
| **HA OS VM on the Latitude** | **Chosen.** The Latitude is the only machine that's plugged into both networks: `vmbr0` is the LAN (`10.6.9.x`) and `vmbr1` is the Xfinity side (`10.0.0.x`), where the thermostat and bulbs live. A VM with one card on each can find the gadgets with mDNS (that's how HomeKit discovery works) without opening anything in OPNsense. HA OS also brings add-ons (a terminal, HACS, Matter later), one-click updates with rollback, and its own backups, all of which the container install doesn't have. The research notes say the same (`docs/research/containers.md`, C-2 #2). |
| A rootless Podman pod on `cobra-stream` or the gate | Not chosen. Those boxes are only on `10.6.9.x`, and mDNS doesn't cross OPNsense, so HomeKit discovery would need an mDNS repeater that also leaks the LAN's names onto the guest Wi-Fi. The container install also has no add-ons. |
| An IoT VLAN first (part 9 phase B + an EAP772) | The best long-term layout, and this design moves straight onto it (10.9). It needs an access point that can put an SSID on a VLAN, and the RE700X can't, so it isn't a requirement for today. |

**About Podman:** HA OS is a sealed appliance, like OPNsense. It runs its own containers internally and you never run a container command on it, so the rule for the Linux boxes (rootless Podman with Quadlet, never Docker) doesn't change. Nothing in this part installs Docker anywhere.

**Resources:** HA OS asks for 2 GB of RAM and 32 GB of disk. The Latitude has 16 GB, with 4 GB for the firewall, 0.5 GB for Pi-hole and 6 GB for the gate, so roughly 3–4 GB is free. 10.3 checks that before creating the VM.

### Network layout

```
                      Xfinity gateway 10.0.0.1  (Wi-Fi: thermostat, bulbs, switches, guests)
                                │ 10.0.0.0/24
               USB NIC ── vmbr1 ┤
                                ├── VM 100 cobra-firewall  WAN 10.0.0.2
                                └── VM 120 cobra-home net1 10.0.0.3   ← no gateway, no DNS,
                                                                        Proxmox firewall: in = mDNS + ping only
    cobra-command (Latitude)
               onboard ── vmbr0 ┬── VM 120 cobra-home net0 10.6.9.11  ← default route via OPNsense,
                                │                                       DNS = Pi-holes, port 8123
                                └── LAN 10.6.9.0/24 (gate 10.6.9.10 → https://ha.songofeo.com)
```

**Why the second card is safe:** a machine with a leg on each network could become a path around the firewall. Three things stop that:

1. **No gateway on `net1`.** Home Assistant's own internet traffic still goes out through OPNsense (Pi-hole, IDS/IPS), never straight out the Xfinity side.
2. **IPv6 off on `net1`.** Otherwise Xfinity's router advertisements would hand it a public IPv6 address and a default route that skips OPNsense.
3. **The Proxmox firewall on `net1` drops every new connection *from* the Xfinity side** except mDNS and ping. Home Assistant always opens the connection to a bulb or the thermostat, and the replies are allowed back in, so guests and gadgets on the Xfinity Wi-Fi can't open Home Assistant's login page or route through it.

### Addresses (added to the IP plan in part 0)

| IP | What |
|---|---|
| `10.6.9.11` | `cobra-home` (VM 120) LAN side, port 8123. OPNsense static mapping. |
| `10.0.0.3` | `cobra-home` Xfinity side (`net1`). Reserved on the Xfinity gateway, set static in HA OS with no gateway. |
| `10.0.0.20`–`.39` | The thermostat, bulbs and switches, reserved on the Xfinity gateway so the EufyHome config (which uses IPs) never goes stale. |

---

## 10.3 Create the VM (cobra-command shell, root)

**1. Check there's room.** Look at the `available` column:

```bash
free -h                                   # "available" on the Mem: line should be 3.5 GB or more
qm list                                   # 100, 110 running (and 101 under pct list); 120 must NOT exist yet
pct list
pvesm status | grep local-lvm             # local-lvm needs 32 GB free for the new disk
```

If `available` is under 3.5 GB, use `--memory 2048` below instead of 3072. 2 GB is Home Assistant's minimum, and it's plenty for a thermostat and a dozen lights.

**2. Download HA OS.** The version is the newest on the [HA OS releases page](https://github.com/home-assistant/operating-system/releases) (18.3 on Oct 26, 2026). Use whatever is newest when you do this.

```bash
VER=18.3                                  # newest HA OS version from the releases page
cd /root
# The KVM/Proxmox image is the "ova" build in qcow2 format, compressed with xz
wget "https://github.com/home-assistant/operating-system/releases/download/${VER}/haos_ova-${VER}.qcow2.xz"
xz -d "haos_ova-${VER}.qcow2.xz"          # unpacks to haos_ova-18.3.qcow2 (about 1.5 GB → ~6 GB sparse)
ls -lh "haos_ova-${VER}.qcow2"
```

**3. Find the MAC to reserve on Xfinity later**, then create the VM. Both network cards start **unplugged** (`link_down=1`), the same trick part 2.2 used for OPNsense: `net1` mustn't touch the Xfinity network until HA OS has been told "static address, no gateway" (10.4).

```bash
qm create 120 --name cobra-home --ostype l26 \
  --machine q35 --bios ovmf \
  --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=0 \
  --cpu host --cores 2 --memory 3072 \
  --scsihw virtio-scsi-single \
  --scsi0 "local-lvm:0,import-from=/root/haos_ova-${VER}.qcow2,discard=on,iothread=1,ssd=1" \
  --boot order=scsi0 \
  --net0 virtio,bridge=vmbr0,link_down=1 \
  --net1 virtio,bridge=vmbr1,firewall=1,link_down=1 \
  --agent 1 --onboot 1 --startup order=4
qm resize 120 scsi0 32G                   # the image ships at ~6 GB; HA OS grows into the rest on first boot
qm config 120 | grep -E '^(net[01]|scsi0|efidisk0)'   # write down both MACs: net0 for OPNsense, net1 for Xfinity
rm "/root/haos_ova-${VER}.qcow2"          # the disk now lives in local-lvm; the download isn't needed
```

| Flag | Why |
|---|---|
| `--machine q35 --bios ovmf` | HA OS boots with UEFI only. With the default BIOS (SeaBIOS) you get a black screen. |
| `pre-enrolled-keys=0` | Secure Boot off. HA OS isn't signed with Microsoft's keys, so with them enrolled the VM refuses to boot. |
| `import-from=…` | Copies the downloaded image straight into a new `local-lvm` disk (Proxmox 7.2 and later; replaces the old separate `qm importdisk` step). |
| `discard=on,ssd=1` | Deleted space inside HA OS is handed back to the thin pool. |
| `net0 → vmbr0` | LAN side: what you, the gate and the phone app talk to. |
| `net1 → vmbr1,firewall=1` | The Xfinity side, where the gadgets are. `firewall=1` puts it under the Proxmox firewall rules in 10.3 step 5. `net0` has no `firewall=1`, so it isn't filtered there (OPNsense already guards the LAN). |
| `--agent 1` | HA OS includes the QEMU guest agent, so Proxmox can shut it down cleanly and freeze its disk for consistent nightly backups. |
| `--startup order=4` | Starts after the firewall (1), Pi-hole (2) and the gate (3). |

**4. Reservations, before plugging anything in.**

- [ ] **OPNsense** → the DHCP page from 2.6 → static mapping: MAC of **`net0`** → `10.6.9.11`, hostname `cobra-home`. Save, Apply.
- [ ] **Xfinity gateway** (Xfinity app → Connect → the network → Advanced settings → Reserved IP, or the admin page `http://10.0.0.1` from a device on the Xfinity Wi-Fi → Connected Devices → **Add Device with Reserved IP**): name `cobra-home-iot`, MAC of **`net1`**, IP **`10.0.0.3`**. This just keeps Xfinity from ever handing `.3` to something else; HA OS sets the address itself in 10.4.
  If `.3` is already in use (the Xfinity device list shows it), pick another free address and use it everywhere this part says `10.0.0.3`.
- [ ] **Both Pi-holes** get the local name. `dns.hosts` is replaced as a whole list, so print what's there now and add one entry to the end of *that*, not to the copy in this manual (you may have added names since):

```bash
# cobra-command shell → Pi-hole #1
pct exec 101 -- pihole-FTL --config dns.hosts       # prints the current list; copy it
# paste the printed list back with one more entry at the end:
#   ,"10.6.9.11 cobra-home.home.arpa cobra-home"
pct exec 101 -- pihole-FTL --config dns.hosts '[ ...the printed entries..., "10.6.9.11 cobra-home.home.arpa cobra-home"]'
pct exec 101 -- pihole-FTL --config dns.hosts       # check: the new entry is there and nothing else is missing
```

```bash
# on cobra-stream (eels) → Pi-hole #2, same three steps
sudo pihole-FTL --config dns.hosts
sudo pihole-FTL --config dns.hosts '[ ...the printed entries..., "10.6.9.11 cobra-home.home.arpa cobra-home"]'
sudo pihole-FTL --config dns.hosts
```

**5. The Proxmox firewall rules for `net1`.** Proxmox only filters a VM if the firewall is switched on for the datacenter. The datacenter file below switches it on **with ACCEPT policies**, so the Proxmox host, OPNsense, Pi-hole and the gate behave exactly as before; only VM 120's `net1` gets rules.

First make sure you're not about to replace an existing file:

```bash
ls -l /etc/pve/firewall/                  # normally empty or missing; if cluster.fw or 120.fw exists, STOP:
cat /etc/pve/firewall/cluster.fw 2>/dev/null   # show what's there and merge the lines below into it by hand
```

Only if neither file exists:

```bash
mkdir -p /etc/pve/firewall
# Datacenter: firewall on, but let everything through by default (no change for the host or other guests).
cat > /etc/pve/firewall/cluster.fw <<'EOF'
[OPTIONS]
enable: 1
policy_in: ACCEPT
policy_out: ACCEPT
EOF

# VM 120: on NICs marked firewall=1 (only net1), drop every NEW connection coming in from the
# Xfinity side, except mDNS (how HomeKit devices announce themselves) and ping.
# Replies to connections Home Assistant opened itself are always allowed back in.
cat > /etc/pve/firewall/120.fw <<'EOF'
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT
log_level_in: nolog

[RULES]
IN ACCEPT -i net1 -p udp -dport 5353 -log nolog # mDNS: HomeKit discovery (the Sensi thermostat)
IN ACCEPT -i net1 -p icmp -log nolog # ping, for troubleshooting from the Xfinity side
EOF

pve-firewall compile >/dev/null && echo "rules compile OK"   # syntax check; prints errors if any
pve-firewall restart
pve-firewall status                        # "Status: enabled/running"
```

- [ ] Check the host is still reachable exactly as before: `https://10.6.9.2:8006` from the desktop, **and** from the phone over WireGuard (`10.6.99.x`). If either fails, `pve-firewall stop` puts everything back while you look.

---

## 10.4 First boot and networking (Proxmox → 120 → Console)

**1. Plug in only the LAN side and start it:**

```bash
qm set 120 --net0 virtio=<net0 MAC from 10.3>,bridge=vmbr0,link_down=0   # keep the same MAC, or the OPNsense mapping won't match
qm start 120
```

Or in the UI: VM 120 → Hardware → net0 → Edit → untick **Disconnect**. Same for `net1` in step 4.

- [ ] The console shows the HA OS banner and, after a few minutes, `ha >` with the address `http://10.6.9.11:8123`. If it shows a different address, the OPNsense mapping's MAC doesn't match `net0`.
- [ ] Desktop browser: `http://10.6.9.11:8123` → "Preparing Home Assistant" (up to 20 minutes on the first boot while it downloads its parts) → **Create my smart home**.
  - Owner account: username `eels`, a generated password, saved in Vaultwarden.
  - Location: your home (sets the time zone and the sunrise/sunset automations), units **US customary** (°F, which must match the thermostat).
  - Analytics: your choice.
- [ ] Your profile (bottom left) → turn on **Advanced mode**. Several network settings below only show with it on.
- [ ] Profile → Security → **Multi-factor authentication** → enable **Authenticator app** (TOTP), scan it. This is the login the phone app uses, so it gets its own 2FA.
- [ ] Settings → System → **Updates**: install anything offered, *except* read 10.5 first if a Core 2026.10.x update is waiting and you have T1013 bulbs.

**2. Give `net1` a static address with no gateway, before it's plugged in.** In the VM console (Proxmox → 120 → Console), type `login` at the `ha >` prompt first. That opens a root shell on HA OS itself, where every command below works exactly as written (`exit` goes back to `ha >`):

```bash
ha network info                       # lists the two cards; with q35 they're usually enp6s18 (net0) and enp6s19 (net1)
# net1 = the one whose MAC matches net1 in `qm config 120`. Replace enp6s19 below if yours differs.
ha network update enp6s19 \
  --ipv4-method static \
  --ipv4-address 10.0.0.3/24 \
  --ipv6-method disabled              # no gateway and no nameserver given = no default route out the Xfinity side
ha network info                       # enp6s19: static 10.0.0.3/24, no gateway; enp6s18: DHCP 10.6.9.11, gateway 10.6.9.1
```

UI equivalent: Settings → System → Network → **Configure network interfaces** → the second card's tab → IPv4 **Static**: address `10.0.0.3/24`, gateway **empty**, DNS **empty**; IPv6 **Disabled** → Save.

**3. Point Home Assistant's device discovery at both cards.** By default it only listens on the card with the default route, so it would never hear the thermostat's mDNS on the Xfinity side.

- [ ] Settings → System → Network → **Network adapter**: untick **Autoconfigure**, tick **both** cards. Save.

**4. Plug in `net1`** (cobra-command shell):

```bash
qm set 120 --net1 virtio=<net1 MAC from 10.3>,bridge=vmbr1,firewall=1,link_down=0   # keep the MAC and firewall=1
```

**5. Check the routing** in the same console shell (`login` at the `ha >` prompt):

```bash
ip -4 route                    # exactly ONE "default via 10.6.9.1"; a "10.0.0.0/24 dev enp6s19" line with NO "via"
ip -6 route | grep default     # prints NOTHING (an IPv6 default via the Xfinity side would skip OPNsense)
ping -c3 10.0.0.1              # the Xfinity gateway answers, straight out net1
ping -c3 10.6.9.1              # OPNsense answers
ping -c3 one.one.one.one       # internet + DNS via the Pi-holes work
cat /etc/resolv.conf           # nameservers are the Pi-holes (10.6.9.3, 10.6.9.20) handed out by OPNsense, not 10.0.0.1
```

- [ ] From a phone **on the Xfinity Wi-Fi** (not `cobra`), open `http://10.0.0.3:8123`. It must **not load** (the Proxmox firewall drops it). If it loads, check `firewall=1` is on `net1` (`qm config 120 | grep net1`) and `pve-firewall status`.
- [ ] From the desktop on the LAN, `http://10.6.9.11:8123` still loads.

---

## 10.5 Eufy bulbs and light switches

**1. Write down each device's model code.** EufyHome app → tap the device → ⚙ (top right) → **Device info** (or "About"): the model is a code like `T1012`. Note the name you gave it too. Compare against the table in 10.1:
- T1011, T1012, T1013 (bulbs) and T1201, T1202, T1203, T1211 (switches and plugs): carry on.
- Anything else: skip to "If your Eufy models aren't supported" at the end of this section.

**2. Reserve each device's address on the Xfinity gateway.** The integration finds devices by IP, so an address that changes after a power cut breaks that light until you edit the config. In the Xfinity app (or `http://10.0.0.1` → Connected Devices), each Eufy device appears under its EufyHome name or as `ESP_xxxxxx`: give each one a reserved IP from `10.0.0.20` upward and write it next to its model code. Then power-cycle each device (switch the lamp off and on at the wall; flip the light switch's breaker, or use the switch's own reset if you'd rather not) so it picks up the reserved address.

**3. Fetch each device's local code (once).** Eufy's cloud hands out a per-device key that Home Assistant then uses to talk to the device directly. Run this on **cobra-gate as eels** (any Linux box on the LAN with Python 3 works). It makes the same two calls as Home Assistant's own EufyHome docs, but asks for the password without echoing it, so the password never lands in your shell history or on disk:

```bash
python3 - <<'PY'
import getpass, json, urllib.request

API = "https://home-api.eufylife.com/v1"

def call(url, body=None, headers=None):
    """POST (with a JSON body) or GET, and return the JSON reply."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", **(headers or {})})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)

# 1) Log in to Eufy's cloud. client_id/client_Secret are the EufyHome app's public values,
#    the same ones Home Assistant's docs and the lakeside library use.
login = call(f"{API}/user/email/login", {
    "client_id": "eufyhome-app",
    "client_Secret": "GQCpr9dSp3uQpsOMgJ4xQ",
    "email": input("EufyHome email: "),
    "password": getpass.getpass("EufyHome password: "),   # typed invisibly
})
token = login.get("access_token")
if not token:
    raise SystemExit(f"Login refused: {login}")          # shows Eufy's error message

# 2) List your devices: name, model code, the IP Eufy's cloud last saw, and the local code.
devices = call(f"{API}/device/list/devices-and-groups", headers={"token": token, "category": "Home"})
print(f"{'NAME':<24} {'MODEL':<6} {'IP':<15} LOCAL CODE")
for item in devices["items"]:
    d = item.get("device")
    if d:                                                # groups have no "device"
        print(f"{d['alias_name']:<24} {d['product']['product_code']:<6} {d['wifi']['lan_ip_addr']:<15} {d['local_code']}")
PY
```

- [ ] Each line shows name, model, IP and a 16-character local code. The IPs should match your reservations from step 2; if one doesn't, it hasn't picked up its new address yet: power-cycle it and run the script again.
- [ ] If it prints `Login refused` with an error about the account or a verification code, Eufy has changed its login since these docs were written (⚠️ Verify). Then use the integration's username/password mode instead (the commented block in step 4), which runs the same login inside Home Assistant.
- The local code stays the same until the device is reset or removed from the EufyHome app. If you ever re-add a device, run this again.

**4. Add them to Home Assistant.** Install the **File editor** add-on (Settings → Add-ons → Add-on store → File editor → Install → Start → Open Web UI). Keys go in `secrets.yaml`, which Home Assistant's backups mark as sensitive and which never shows in the UI:

`/config/secrets.yaml` (add lines, keep anything already there):

```yaml
eufy_living_lamp: 0123456789abcdef      # local codes from step 3, one per device
eufy_hall_switch: fedcba9876543210
```

`/config/configuration.yaml` (add at the end; keep the lines HA OS wrote at the top):

```yaml
# Eufy bulbs and switches, controlled locally (EufyHome integration).
# One entry per device: its reserved Xfinity IP, its local code, and its model code.
eufy:
  devices:
    - address: 10.0.0.20
      access_token: !secret eufy_living_lamp
      type: T1013                       # colour bulb
      name: Living room lamp
    - address: 10.0.0.21
      access_token: !secret eufy_hall_switch
      type: T1211                       # light switch
      name: Hall light
# Alternative if step 3 fails: let HA log in to Eufy's cloud itself at each start and find the
# devices (it still controls them locally afterwards). Use this INSTEAD of the devices: list.
#  eufy:
#    username: !secret eufy_email
#    password: !secret eufy_password
```

- [ ] Developer tools → YAML → **Check configuration** → "Configuration will not prevent Home Assistant from starting". Then **Restart** (top right ⋮ → Restart Home Assistant).
- [ ] Settings → Devices & services → **Entities**: search `light.` and `switch.`; each device is listed and toggling it in Home Assistant switches the real light within a second.

**5. If you see `Expected an int, got a boolean`** (Settings → System → Logs, under `lakeside` or `eufy`), you're on a 2026.10 version with the open bug. Hold Home Assistant Core on the last good version until the fix ships. In the VM console, after `login` at the `ha >` prompt (as in 10.4):

```bash
ha core info | grep -E '^version'       # what you're on now, e.g. 2026.10.4
ha backups new --name before-core-downgrade   # a restore point first (Settings → System → Backups lists it)
ha core update --version 2026.9.4       # Core only; HA OS and the add-ons stay as they are
ha core info | grep -E '^version'       # 2026.9.4
```

- [ ] Settings → System → Updates: **skip** each new Core release until its release notes (or [issue #186877](https://github.com/home-assistant/core/issues/186877)) mention the EufyHome fix. HA OS and add-on updates are fine to install meanwhile.
- [ ] Write the date you pinned it in your notes, and check monthly: an old Core misses security fixes. It isn't directly on the internet (the gate and Authelia are in front of it, 10.7), which is why holding it for a few weeks is acceptable.

### If your Eufy models aren't supported

Newer Eufy bulbs only talk through Eufy's cloud, and there's no maintained Home Assistant integration for them. Honest options:

1. **Leave those in the EufyHome app**, and use Home Assistant for everything else.
2. **Replace them with Matter-over-Wi-Fi bulbs and switches**, which Home Assistant controls locally with its built-in Matter support (the **Matter Server** add-on). Many brands sell them now. Look for the Matter logo on the box. Wi-Fi Matter devices need no extra hub (Thread ones need a Thread border router).
3. **TP-Link Kasa/Tapo** switches and bulbs: local control through the built-in TP-Link integration.

---

## 10.6 Sensi thermostat

**1. Model and code.** On the thermostat's label (pull it off the wall plate; it unclips) or in the Sensi app → the thermostat → Settings → About: the model (e.g. ST55, ST75) and, on HomeKit-capable models, an 8-digit **HomeKit setup code** like `123-45-678`. ⚠️ Verify: on some models the code is also shown on screen under the menu's HomeKit or Network item.

**2. Reserve its address on the Xfinity gateway** (same as 10.5 step 2, e.g. `10.0.0.30`). Home Assistant finds it again by mDNS after a change, but a fixed address makes troubleshooting simpler.

**3. Plan A: pair it over HomeKit (local).**

- [ ] If the thermostat was ever added to an Apple Home: remove it there first (Home app → the thermostat → settings → **Remove Accessory**). A HomeKit device only pairs with one controller at a time.
- [ ] Home Assistant → Settings → Devices & services: a **Discovered: HomeKit Device** card for the Sensi should appear within a minute. Configure → **Pair** → type the code **with the dashes** (`123-45-678`).
  - Nothing discovered: check 10.4 step 3 (both network cards ticked), then that the thermostat is on the Xfinity Wi-Fi and powered.
- [ ] Settings → Devices & services → HomeKit Device → the thermostat: a `climate.` entity with the current temperature, the setpoint and the mode. Change the setpoint in Home Assistant and watch the thermostat's screen follow.

**If it says "Incorrect HomeKit code"** with the right code: an owner's fix from Oct 21, 2026 (Sensi Smart ST55), which costs you its Wi-Fi setup and schedule in the Sensi app (redo those afterwards):

1. Factory-reset the thermostat (Sensi app → Settings → Reset, or the reset steps in its manual).
2. In the Xfinity app, **pause** internet for the thermostat (Connect → the device → Pause), so it joins the Wi-Fi but can't reach Sensi's cloud.
3. Join it to the Xfinity Wi-Fi again from the Sensi app.
4. Pair it in Home Assistant as above.
5. **Unpause** it in the Xfinity app, and re-add it in the Sensi app if you want the app too.

**4. Plan B: the cloud integration**, only if your model has no HomeKit code or plan A keeps failing.

- [ ] Install HACS: Settings → Add-ons → Add-on store → ⋮ → **Repositories** → add `https://github.com/hacs/addons` → install **Get HACS** → Start → read its log, which ends with "restart Home Assistant" → restart → Settings → Devices & services → Add integration → **HACS** → follow the GitHub sign-in it shows. ⚠️ Verify: HACS changes its install steps now and then; its own docs (hacs.xyz) win if they differ.
- [ ] HACS → search **Sensi** → the one by **iprak** → Download → restart Home Assistant.
- [ ] Get a refresh token: on the desktop, open `https://manager.sensicomfort.com` in Chrome, press **F12** → **Network** tab, then log in. Click the request named `token` in the list → **Response** → copy the value of `refresh_token`. That token is a password: paste it straight into the next step and nowhere else.
- [ ] Settings → Devices & services → Add integration → **Sensi** → paste the token. A `climate.` entity appears. You'll need a new token after changing your Sensi password.

---

## 10.7 Through the gate: `https://ha.songofeo.com` with the station sign-in

Home Assistant controls the house, so it gets the admin apps' treatment: **password + TOTP from outside**, and (like the station's floors) **no Authelia prompt at home or over WireGuard**, because the phone app can't complete a web sign-in. Its own login (with the 2FA from 10.4) still applies everywhere.

**1. Tell Home Assistant to trust the gate.** In `/config/configuration.yaml` (File editor), add:

```yaml
http:
  use_x_forwarded_for: true          # take the visitor's real address from the gate's X-Forwarded-For header
  trusted_proxies:
    - 10.6.9.10                      # the gate only; requests through anything else are refused with 400
  ip_ban_enabled: true               # block an address after repeated failed logins
  login_attempts_threshold: 5
```

Check configuration, then restart (as in 10.5 step 4). From now on only the gate may proxy to it; opening `http://10.6.9.11:8123` directly from the LAN still works.

**2. Authelia** (as podsvc on the gate). In `/srv/gate/authelia/configuration.yml`, add these two rules to `access_control.rules`, at the top for simplicity (Authelia uses the first rule that matches, and no other rule names `ha.`). `home` is the named network (LAN + WireGuard) part 5.4 already defines:

```yaml
    # Home Assistant: open at home and over WireGuard (the phone app can't do a web sign-in),
    # password + TOTP from anywhere else. Its own login and 2FA still apply.
    - domain: ha.songofeo.com
      networks: [home]
      policy: bypass
    - domain: ha.songofeo.com
      policy: two_factor
```

**3. nginx.** Add this server block to `/srv/gate/nginx/conf.d/songofeo.conf`, below the admin apps' block (it's the same pattern as 5.4: copy the whole block, `/internal/authelia/authz` location included):

```nginx
# --- Home Assistant (cobra-home, VM 120): Authelia first (skipped at home and over WireGuard) ---
server {
  listen 443 ssl; http2 on; server_name ha.songofeo.com;
  location /internal/authelia/authz {
    internal;
    proxy_pass http://127.0.0.1:9091/api/authz/auth-request;
    # a location's own proxy_set_header replaces ALL inherited ones, so list what Authelia needs
    proxy_set_header X-Original-Method $request_method;
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Content-Length ""; proxy_set_header Connection "";
    proxy_set_header Authorization "";   # the phone app's own token is for Home Assistant, not Authelia
    proxy_pass_request_body off;
  }
  location / {
    auth_request /internal/authelia/authz;
    auth_request_set $redirection_url $upstream_http_location;
    error_page 401 =302 $redirection_url;
    limit_req zone=perip burst=100 nodelay;  # the dashboard loads a burst of icons and states at once
    proxy_buffering off;                     # live state updates arrive at once, not in batches
    proxy_read_timeout 1h; proxy_send_timeout 1h;   # the dashboard and the app keep one websocket open
    proxy_pass http://10.6.9.11:8123;
  }
}
```

The `Host`, `X-Forwarded-For`, `Upgrade` and `Connection` headers come from the shared settings at the top of the file; Home Assistant's dashboard needs the websocket ones.

```bash
# on the gate, as podsvc
podman exec nginx nginx -t && podman exec nginx nginx -s reload
systemctl --user restart authelia
```

**4. The gate's firewall** needs no change: it only filters what comes *in* to the gate, and this is the gate connecting *out* to `10.6.9.11`. OPNsense needs no change either: both are on the LAN.

**5. DNS and certificate.**

- [ ] At home the Pi-holes already answer `ha.songofeo.com` with `10.6.9.10` (the `*.songofeo.com` line from 2.9). Check from the desktop: `nslookup ha.songofeo.com` → `10.6.9.10`.
- [ ] The wildcard certificate (5.3) already covers `ha.songofeo.com`. Nothing to do.
- [ ] Porkbun → `songofeo.com` → DNS: add a **CNAME** `ha` → `gate.songofeo.com`, like the other apps (5.5). Skip it if you only ever want Home Assistant at home and over WireGuard: without the record, it simply doesn't exist from outside.

**Checks:**

- [ ] Desktop on the LAN: `https://ha.songofeo.com` → padlock, Home Assistant's own login, no Authelia screen.
- [ ] Phone on **cellular**, WireGuard **off**: `https://ha.songofeo.com` → the Authelia sign-in at `gate.songofeo.com` with a TOTP code, then Home Assistant's login.
- [ ] Same phone with WireGuard **on**: straight to Home Assistant's login.
- [ ] Home Assistant → Settings → System → Logs: no `A request from a reverse proxy was received from 10.6.9.10, but your HTTP integration is not set-up for reverse proxies` (that means step 1 isn't saved or Home Assistant wasn't restarted).

---

## 10.8 Your phone, the dashboard, and Alexa

**The phone app** (Home Assistant Companion, free for iPhone and Android):

- [ ] Install it, then **enter the address manually**: `https://ha.songofeo.com`. Log in as `eels` with your 2FA code.
- [ ] It works on the **`cobra` Wi-Fi** (2.10b) and anywhere with **WireGuard on**. On the Xfinity Wi-Fi or cellular without WireGuard it hits the Authelia page, which the app can't get past. Two ways to never think about it:
  - iPhone: WireGuard app → the tunnel → **On-Demand** → on for Cellular, and for Wi-Fi "except these SSIDs: `cobra`".
  - Android: Settings → Network → VPN → WireGuard → **Always-on VPN**. The `AllowedIPs` in part 2.8 only send home traffic through it, so everything else stays fast.
- [ ] Android: long-press the home screen → Widgets → Home Assistant, or pull down Quick Settings → edit → add Home Assistant tiles (one per light). iPhone: Home Assistant widgets on the home screen, and Shortcuts for Siri.
- [ ] Rachel: Settings → People → **Add person**, with a login, ticking "Can only log in from the local network" if you like. Same app, same address.

**The dashboard.** Overview builds itself from your rooms. To tidy it: Overview → ✎ → **Take control** → add a **Thermostat** card for the Sensi and **Tile** cards for each light (tap = on/off, hold = brightness and colour). An old tablet or phone on the `cobra` Wi-Fi with the app open makes a wall panel.

**Automations** worth five minutes each (Settings → Automations & scenes → Create):
- Porch or living room lamp on at sunset, off at 11 pm.
- Thermostat to an away setpoint when everyone's phone leaves home (the app reports location if you allow it), back when the first one returns.
- All lights off with one tap: a **Scene** on the dashboard.

**Alexa.** You can uninstall the Alexa app as soon as everything above works; the bulbs, switches and thermostat don't need it. If you still want **voice** control from an Echo:
- Keep the Eufy and Sensi skills in Alexa for voice only. They keep working, through the vendors' clouds, alongside Home Assistant.
- Or link Home Assistant to Alexa with a **Home Assistant Cloud** subscription (paid, run by the company behind Home Assistant), so one list of devices and names serves both. Voice still goes through Amazon either way.
- On an iPhone, Settings → Devices & services → Add **HomeKit Bridge** puts Home Assistant's lights and thermostat in Apple's Home app, so Siri and Control Center work locally, without Amazon.

---

## 10.9 Backups, monitoring, updates, and the IoT VLAN later

**Backups:** the nightly job from 5.6 backs up `--all` guests, so VM 120 is already in it from tonight. Check tomorrow: Proxmox → Datacenter → Backup → the job → **Job detail** lists 120, and PBS (`https://10.6.9.20:8007`) shows a `vm/120` group.
Home Assistant also makes its own backups (Settings → System → Backups): keep the automatic ones. They live inside the VM, so the nightly VM backup carries them to PBS too.

**Monitoring (5.7):**
- [ ] Uptime Kuma: an **HTTP** monitor for `http://10.6.9.11:8123` (Home Assistant itself), and one for `https://ha.songofeo.com` (the gate's route to it; from the gate that's a LAN request, so Authelia lets it through). The Xfinity-side address `10.0.0.3` can't be monitored from the gate, which isn't on that network.
- [ ] Homepage: a tile in **Admin**, as podsvc on the gate in `/srv/gate/homepage/services.yaml`:

```yaml
    - Home Assistant: { href: "https://ha.songofeo.com", icon: home-assistant.png, description: "Lights + thermostat", siteMonitor: "http://10.6.9.11:8123" }
```

then `systemctl --user restart homepage`.

**Updates:** Settings → System → Updates, weekly with the rest (5.7). Read the release notes' "Backward-incompatible changes" first, and leave Core alone while it's pinned for Eufy (10.5 step 5). HA OS updates roll back on their own if the new version doesn't boot.

**Later, with the IoT VLAN (part 9 phase B + an access point with VLAN per SSID, like the EAP772):** add an `IOT` VLAN the way 9.7 adds LAB (OPNsense VLAN, DHCP, "block `PRIVATE`, allow internet"), give it its own SSID, move the thermostat and Eufy gadgets onto that SSID, and move Home Assistant's second card from the Xfinity side onto the VLAN:

```bash
# cobra-command shell, after 9.6 made vmbr0 VLAN-aware. <ID> = the IOT VLAN's number.
qm set 120 --net1 virtio=<net1 MAC>,bridge=vmbr0,tag=<ID>,firewall=1   # same MAC, same firewall rules, new network
```

Then in HA OS set `net1`'s static address to one on the IoT subnet (no gateway, as in 10.4), and update the Eufy IPs in `configuration.yaml` to their new reservations. Everything else in this part stays the same, and the Xfinity Wi-Fi can be switched off.

---

## Done when

- [ ] `cobra-home` (VM 120) starts on its own after a Latitude reboot, after the firewall, Pi-hole and the gate
- [ ] `ip -4 route` in Home Assistant shows one default route, via `10.6.9.1`; no IPv6 default route
- [ ] `http://10.0.0.3:8123` does **not** load from the Xfinity Wi-Fi
- [ ] Every Eufy bulb and switch toggles from Home Assistant within a second, and still does with the Latitude's internet unplugged for a minute (the local check)
- [ ] The thermostat's setpoint changes from Home Assistant (plan A: also with internet unplugged)
- [ ] `https://ha.songofeo.com`: no Authelia at home, Authelia 2FA from cellular, straight in over WireGuard
- [ ] The phone app controls a light from the `cobra` Wi-Fi and from cellular with WireGuard on
- [ ] Tomorrow: PBS has a `vm/120` backup

## Sources

- Sensi and HomeKit: [Copeland, Sensi and Apple HomeKit](https://sensi.copeland.com/en-us/blog/sensi-apple-homekit-thermostat); owners pairing Sensi as a HomeKit Device in Home Assistant, including the ST55 reset workaround (Oct 21, 2026): [Home Assistant community thread](https://community.home-assistant.io/t/how-do-i-connect-home-assistant-to-my-sensi-thermostat/723439); "Incorrect HomeKit code" reports and "no core Sensi integration" (Apr 2026): [community thread](https://community.home-assistant.io/t/error-code-when-adding-sensi-thermostat/1000820)
- Sensi cloud integration (HACS, refresh token since app 8.6.3): [iprak/sensi](https://github.com/iprak/sensi)
- EufyHome integration, supported model codes and local-code lookup: [Home Assistant docs](https://www.home-assistant.io/integrations/eufy/), [integration source](https://github.com/home-assistant/core/tree/dev/homeassistant/components/eufy); 2026.10 breakage: [core issue #186877](https://github.com/home-assistant/core/issues/186877); newer bulbs cloud-only: [python-lakeside issue #17](https://github.com/google/python-lakeside/issues/17)
- HA OS images: [operating-system releases](https://github.com/home-assistant/operating-system/releases)
