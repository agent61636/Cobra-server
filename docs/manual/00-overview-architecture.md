# Cobra Build Manual — 00: Overview & Architecture

> **Read this first.** Every other part refers back to the names, IPs and ports defined here.

---

## 1. Answers to your direct questions

| # | Your question | Answer (with the reasons) |
|---|---|---|
| 1 | *Proxmox runs everything from the Latitude: OPNsense, Pi-hole and Jellyfin?* | **Proxmox on the Latitude: yes. Jellyfin on it: no.** The Latitude runs Proxmox with the firewall, Pi-hole #1 and the `cobra-gate` VM. Jellyfin moves elsewhere (see #4). |
| 2 | *Optiplex gets Windows 10 for the arcade?* | **Windows, yes, but Windows 11 rather than 10.** Consumer Windows 10 Extended Security Updates end on **Oct 13, 2026**. After that the cabinet would get no more security patches while sitting on your LAN. Windows 11 installs on the i7-6700 using Rufus's requirement bypass and activates with your existing license. LaunchBox/Big Box is Windows-only, so Windows is the right OS for the cabinet. Setup is in part 4. |
| 3 | *Does Navidrome go on the Optiplex?* | **No.** Navidrome needs no GPU, and the cabinet should only run games. It goes on `cobra-stream` with the rest of the media apps. **One Navidrome instance is enough.** Navidrome 0.58+ supports multiple libraries with per-user access. `eelsmusic.` and `rupaulradio.` are two hostnames for the same instance, and Eels and Rachel each see only their own library. |
| 4 | *Jellyfin on the gateway box is too much. Shouldn't it go on the Optiplex and use the Intel graphics?* | **You were right to worry: it doesn't belong on the gateway.** That box has 2 cores, 16 GB and the firewall. Putting a media server facing the internet on the same machine that *is* the firewall also widens the damage if it's ever compromised. **The Optiplex is the wrong fix too.** Its HD 530 is Skylake, which has **no hardware decode for HEVC 10-bit**, and that's the format most 4K MKVs use. It would also slow down games on the cabinet. **The SGIN's Celeron N5095A (Jasper Lake) is the best video engine you own.** It does hardware HEVC 10-bit decode and encode plus HDR tone mapping, at about 10 W. So the SGIN becomes **`cobra-stream`** and also keeps its jobs as backup server and Pi-hole #2. |
| 5 | *SGIN = backup server + Pi-hole 2?* | **Yes, plus media** (see #4). It runs Proxmox Backup Server, Pi-hole #2, Samba, and the media pod. |
| 6 | *R620 later, labs only?* | **Yes.** It adds lab capacity (an Active Directory lab, CAPEv2, Wazuh, Security Onion) but has no video engine, so it does nothing for streaming. You'll power it on remotely for lab sessions through iDRAC. That's part 9. |
| 7 | *Seamless networking + SMB from the Windows 11 desktop?* | **Yes.** All the USB storage drives attach to `cobra-stream`, are pooled into one library and shared over SMB3 (Samba); every Windows machine, the gate and VPN clients use the same shares (part 3.4–3.6). The OptiPlex's internal WD drive stays in the cabinet as its game drive and an extra copy (part 4.6). "Put files wherever I want" means *any machine reads and writes the same library*. |
| 8 | *Both desktops move to the gateway switch?* | **Yes, and they have to.** Anything plugged into the Xfinity gateway bypasses the firewall. |
| — | *M3U or XMLTV for ErsatzTV?* | **Both.** M3U is the channel list and stream URLs (the "tuner"). XMLTV is the program guide. Jellyfin takes one of each. |
| — | *Can the cabinet's RetroArch play with web (browser) users?* | **Not directly.** RetroArch netplay and browser EmulatorJS netplay are different protocols. Both setups that do work are planned: friends join the cabinet with RetroArch, or everyone plays in the browser. |
| — | *Does the arcade need a 3rd pod for the web arcade + hiscore sync?* | **You do need a third pod, but not on the arcade.** (1) The **web arcade (RomM/EmulatorJS) runs the game in the player's browser**. The server only hands out ROM files and the web page, so it lives in the `stream` pod next to the ROM storage and stays up when the cabinet is off. (2) **Hiscore sync has to read files RetroArch writes on Windows.** That's a job for a small **native Windows agent** (a hidden logon task). Podman on Windows runs inside a WSL2 virtual machine, which doesn't start until someone logs in, and its file-watching doesn't reliably see changes Windows programs make. (3) The **hiscore server** (scores API + storage + scoreboard website at `scores.songofeo.com`) runs on Linux, in a **reserved slot inside the `gate` pod** (see §8). Flow: cabinet RetroArch writes `.hi` → Windows sync agent → HTTPS + API key → `hiscore` pod stores the raw `.hi` files (your backup against power loss) and the parsed scores → scoreboard page with logins and filters. |
| — | *IncusOS for security on the gate?* | **No.** IncusOS is an immutable OS whose only job is running Incus (containers/VMs). It isn't a security product, and it can't be installed on Debian. It goes into the R620 lab as a learning VM. |
| — | *Steam Link / Arch-on-USB Pi-hole?* | **No.** The Steam Link has 512 MB of RAM and frozen firmware, and Pi-hole doesn't support Arch. Both Pi-holes run on hardware that's already on 24/7. |
| — | *Joe Sandbox?* | It's a commercial product. The free, self-hosted equivalent is **CAPEv2** (R620 lab, later). |

---

## 2. Final machine roles

| Name | Hardware | OS | Job | Power |
|---|---|---|---|---|
| **cobra-command** | Dell Latitude 5580: i7-7600U 2C/4T, 16 GB, 256 GB NVMe, Intel I219-LM + **USB 3 gigabit NIC (~$12–15, the only purchase needed to start)** | Proxmox VE 9 | Hypervisor that runs the firewall, Pi-hole #1 and the gate VM. Its battery acts as a built-in UPS for the firewall. | ~10–20 W |
| ↳ **cobra-firewall** (VM 100) | 2 vCPU / 4 GB | OPNsense | Firewall, DHCP, Unbound DNS-over-TLS, WireGuard VPN, Suricata IDS/IPS, CrowdSec, DDNS | — |
| ↳ **cobra-pihole-1** (CT 101) | 1 core / 512 MB | Debian 13 LXC | Primary ad/malware DNS filter + local DNS records | — |
| ↳ **cobra-gate** (VM 110) | 2 vCPU / 6 GB | Debian 13 | Rootless Podman pod: nginx (reverse proxy + TLS), Authelia (SSO + 2FA), Vaultwarden, Paperless-ngx, MeTube, Homepage, Uptime Kuma. Also Cockpit. *(Later, if wanted: NetAlertX, and a CrowdSec agent reading nginx's logs.)* | — |
| **cobra-stream** | SGIN X15: Celeron N5095A (Jasper Lake Quick Sync), 12 GB, headless. **No built-in Ethernet**: a USB gigabit adapter (AX88179) on the powered hub, which uses the only USB 3 port (USB-C); the two USB-A ports are USB 2.0 | Debian 13 (bare metal) | Rootless Podman pod: Jellyfin, ErsatzTV, Audiobookshelf, Kavita, Navidrome, RomM (EmulatorJS web arcade). Also Samba (all storage), Pi-hole #2, Proxmox Backup Server, Cockpit. | ~10–15 W + drives |
| **cobra-arcade** | OptiPlex 7040 Mini Tower (240 W): i7-6700, 16 GB dual-channel, AMD Oland XT (R7 250-class), to be replaced by an RTX 3050 6 GB (part 4.7) | Windows 11 | LaunchBox/Big Box, RetroArch, Steam, X-Arcade Tankstick, RetroArch netplay host | ~30–60 W in use |
| **cobra-switch** | TP-Link Omada ES210X-M2: 8× 2.5GBASE-T, 2× 10G SFP+, easy managed (802.1Q VLANs, loop prevention, IGMP snooping), fanless, no PoE. Replaced the Netgear 5-port switch E, which is now a spare | Omada standalone firmware (own web UI, no controller) | Links every wired machine on the LAN to the gate (the Latitude); carries part 9's VLANs | ~10 W |
| **cobra-lab** (R620, later) | 2× Xeon, DDR3, 4× 480 GB SSD | Proxmox VE 9 (standalone; not clustered, part 9) | On-demand security lab | 110–160 W *only while on* |
| **the-box** (desktop) | Powerhouse PC, RTX 3070 | Windows 11 | Daily use and heavy work; SMB access to all shares. Wired, `10.6.9.50` | — |
| **the-spire** (desktop) | — | Windows 11 | Daily use; SMB access to all shares. Wired, `10.6.9.51` | — |
| **Cobra1** (laptop) | Wi-Fi only | Windows 10 | Portable; joins `cobra` Wi-Fi at home (`10.6.9.52`), WireGuard away (`10.6.99.3`) | — |

**Why `cobra-stream` is bare-metal Debian instead of a Proxmox guest:** the iGPU (needed for Quick Sync) and the USB storage drives are simplest and most reliable on bare metal. Running Podman inside an LXC container on Proxmox breaks regularly on AppArmor/runc updates. Real companies run hypervisors next to bare-metal appliances like this all the time. You still manage it from one place: Cockpit plus the Homepage dashboard, and its backups land in the same Proxmox Backup Server.

**What the AMD Oland card does:** it drives the cabinet's display and is moderately faster than the HD 530 for emulation. The planned **RTX 3050 6 GB** (slot-powered, 70 W) replaces it for modern PC games like MK11 and MK1 (part 4.7). It has **no HEVC support**, so it can't help Jellyfin.

---

## 3. Network diagram (Phase A: flat LAN on the Omada switch)

```
                       INTERNET
                           │
               ┌───────────┴───────────┐
               │   Xfinity gateway     │  10.0.0.1  (router mode)
               │   Wi-Fi = UNTRUSTED   │  phones / guests / IoT
               └───────────┬───────────┘
                           │ 10.0.0.0/24   (DMZ host / port-forwards → 10.0.0.2)
                 USB 3 NIC │ (vmbr1, WAN)
   ┌───────────────────────┴──────────────────────────────┐
   │  cobra-command  (Latitude, Proxmox VE 9)             │
   │   ├─ VM 100  cobra-firewall   WAN 10.0.0.2           │
   │   │                           LAN 10.6.9.1           │
   │   ├─ CT 101  cobra-pihole-1   10.6.9.3               │
   │   └─ VM 110  cobra-gate       10.6.9.10  :443 ◄──────┼── only public TCP port
   │  host mgmt 10.6.9.2:8006                             │
   └───────────────────────┬──────────────────────────────┘
          onboard I219-LM  │ (vmbr0, LAN 10.6.9.0/24)  1 GbE
   ┌───────────────────────┴──────────────────────────────┐
   │  cobra-switch  TP-Link Omada ES210X-M2   10.6.9.5    │
   │  8× 2.5GBASE-T + 2× 10G SFP+, easy managed, fanless  │
   │  (replaced the Netgear 5-port "switch E", now spare) │
   └─┬──────────┬──────────┬────────┬────────┬────────┬───┘
     │          │          │        │        │        │
  cobra-     cobra-     the-box  the-     cobra-ap  R620 (later)
  stream     arcade              spire
  .20        .30        .50      .51      .6        .40 iDRAC / .41
  1 GbE      1 GbE      1 GbE    1 GbE    1 GbE     1 GbE
  (USB NIC)                              (RE700X,  SFP+ 1–2: free, for 10G later
                                           AP mode)
                                            ┆ Wi-Fi "cobra"
                                          Cobra1 laptop .52

   WireGuard VPN clients: 10.6.99.0/24 (UDP 51820): phone .2, Cobra1 .3
```

### IP plan

| IP | Host | Notes |
|---|---|---|
| 10.0.0.1 | Xfinity gateway | **Today it's 10.6.9.1.** Part 2's cutover moves it back to its default 10.0.0.1/24 so your own LAN, behind OPNsense, can keep the 10.6.9.x numbers. Two networks can't share one range. |
| 10.0.0.2 | cobra-firewall WAN | DHCP reservation on Xfinity + DMZ host |
| 10.6.9.1 | cobra-firewall LAN | Default gateway + Unbound DNS for the LAN |
| 10.6.9.2 | cobra-command | Proxmox web UI `https://10.6.9.2:8006` |
| 10.6.9.3 | cobra-pihole-1 | DNS #1 |
| 10.6.9.5 | cobra-switch | TP-Link Omada ES210X-M2, the LAN switch: web UI `http://10.6.9.5` (part 2.12). Same switch carries the VLANs in part 9. |
| 10.6.9.6 | cobra-ap | Trusted Wi-Fi access point `cobra`: the TP-Link RE700X in Access Point mode on cobra-switch port 6 (part 2.10b) |
| 10.6.9.10 | cobra-gate | nginx 80/443, Cockpit 9090 |
| 10.6.9.20 | cobra-stream | Media apps, Samba, Pi-hole #2 (DNS #2), PBS 8007, Cockpit 9090 |
| 10.6.9.30 | cobra-arcade | Windows cabinet |
| 10.6.9.40 / .41 | cobra-lab iDRAC / cobra-lab Proxmox (R620) | Part 9. The iDRAC moves to `10.6.30.40` on the MGMT VLAN in phase B. |
| 10.6.9.50 / .51 | the-box / the-spire (Windows 11 desktops) | DHCP reservations, wired |
| 10.6.9.52 | Cobra1 (Windows 10 laptop) | DHCP reservation for its **Wi-Fi** MAC, on `cobra` Wi-Fi (2.10b). Away from home it uses WireGuard `10.6.99.3` (2.8) |
| 10.6.9.100–199 | DHCP pool | Everything else |
| 10.6.9.200 | old server (SGIN, until it's rebuilt) | Static mapping in OPNsense, so its port forwards keep working through the cutover (part 2.4) |
| 10.6.99.0/24 | WireGuard clients | Admin access from outside |
| 10.6.20.0/24 · 10.6.21.0/24 · 10.6.30.0/24 | LAB · DETONATE · MGMT VLANs | Part 9, phase B (on cobra-switch's 802.1Q VLANs) |

### Port map

| Host | Service | Port | Who can reach it |
|---|---|---|---|
| gate | nginx | 443 (80 only redirects to 443) | Internet on 443 (OPNsense forward) + LAN + VPN |
| gate (in pod) | Authelia 9091 · Vaultwarden 8222 · Paperless 8000 · Postgres 5432 · Redis 6379 · MeTube 8081 · Homepage 3000 · Uptime Kuma 3001 | localhost only | Only nginx inside the pod |
| gate | Cockpit | 9090 | LAN + VPN |
| stream | Jellyfin 8096 · ErsatzTV 8409 · Audiobookshelf 13378 · Kavita 5000 · Navidrome 4533 · RomM 8080 · Icecast 8000 | LAN + VPN only (nftables) | gate's nginx + LAN clients |
| stream | Samba | 445 | LAN + VPN |
| stream | Pi-hole #2 | 53, 80/443 (admin) | LAN + VPN |
| stream | Cockpit · SSH | 9090 · 22 | LAN + VPN |
| stream | PBS | 8007 | LAN + VPN |
| cobra-command | Proxmox | 8006, 22 | LAN + VPN |
| cobra-firewall | WireGuard | 51820/udp | Internet |

---

## 4. Your user flowcharts (corrected)

All public traffic follows the same path: **user → Porkbun DNS (plain DNS, no proxy) → your home IP → Xfinity → cobra-firewall (firewall, IDS/IPS, CrowdSec) → cobra-gate (nginx TLS + rate limits [+ Authelia]) → the app.**
At home, Pi-hole answers every name under `songofeo.com` with `10.6.9.10`, so LAN traffic never leaves the house. The bare `songofeo.com` and `www` are the exception: they're the station on Porkbun's hosting, at home too.

"Station sign-in" below means Authelia's password screen at `auth.songofeo.com` (part 5.4): one sign-in covers every floor for 6 hours, and it's skipped at home and over WireGuard.

| Want | URL | Path after the gate | Login |
|---|---|---|---|
| The station (homepage) | `songofeo.com` | Porkbun static hosting, not the gate (Project-Eo repository) | Public page. Its **Sign in** button opens the station sign-in |
| Sign in | `auth.songofeo.com` | → gate: Authelia | Username + password (+ TOTP for admin apps); 6 h |
| Watch a movie / Live TV | `tv.songofeo.com` | → stream: Jellyfin (+ ErsatzTV channels) | Station sign-in, then Jellyfin's login once per device: hidden users (nobody's name is shown on the login page), no Quick Connect |
| Music (the station's Music floor) | `music.songofeo.com` | → stream: Navidrome | Station sign-in; Navidrome trusts it, so no second login |
| Audiobooks / ebooks | `books.songofeo.com` | → stream: Audiobookshelf | Station sign-in, then in-app once per device |
| Comics / graphic novels | `comics.songofeo.com` | → stream: Kavita | Station sign-in, then in-app once per device |
| Eels' music | `eelsmusic.songofeo.com` | → stream: Navidrome (Eels' library) | Same as `music.` |
| Rachel's music | `rupaulradio.songofeo.com` | → stream: same Navidrome (Rachel's library) | Same as `music.` |
| Game Cellar / The Ward | `gaming.songofeo.com`, `sessions.songofeo.com` | → gate: holding page until their apps exist | Station sign-in |
| Landing-page pictures | `art.songofeo.com` | → gate: eo-art (random covers and backdrops from the pool's `art` folder) | Station sign-in; signed-out visitors see the drawn art instead |
| Save documents | `docs.songofeo.com` | → gate: Paperless-ngx | **Mandatory:** Authelia 2FA, then Paperless |
| Save a YouTube video | `metube.songofeo.com` | → gate: MeTube | **Mandatory:** Authelia 2FA (MeTube has no login of its own) |
| Web arcade | `arcade.songofeo.com` | → stream: RomM (EmulatorJS player) | Station sign-in, then in-app once per device |
| Cabinet | (local) | arcade: Big Box → RetroArch; ROMs from `\\cobra-stream\roms` | Windows auto-login |
| Dashboard | `home.songofeo.com` | → gate: Homepage | Authelia 2FA |
| Status page | `status.songofeo.com` | → gate: Uptime Kuma | Authelia 2FA |
| Password vault | `vault.songofeo.com` | → gate: Vaultwarden | **LAN/VPN only.** Never public. |
| High-score boards | `scores.songofeo.com` | → gate: reserved hiscore slot (§8, built later) | Login for viewers. The cabinet's sync agent uses an API key. |
| Live radio | `radio.songofeo.com` | → stream: Liquidsoap + Icecast (part 8) | Authelia password; public only with music you have the rights to stream |
| Optional buttons page from home | e.g. `links.songofeo.com` | → gate: static page (part 8.1) | Never the bare domain, which is the station |

**Why the media apps are behind the station sign-in, and why home skips it:** one sign-in for the whole station keeps the apps' own login pages off the internet. But phone and TV apps (Jellyfin on the Roku, Apple TV and phones, Subsonic music apps, the Audiobookshelf app) can't complete a web sign-in. So the sign-in is skipped on the LAN and over WireGuard: the TVs at home work as before, and away from home those apps work with the WireGuard tunnel on. In a browser, and in the Song of Eo Android app, the station sign-in works from anywhere. The apps keep their own logins too, plus rate limiting, CrowdSec and strong passwords.

**Why plain DNS and no proxy in front:** proxy services like Cloudflare's (the "orange cloud") or Cloudflare Tunnel restrict serving video through them, and a proxy in front of a server that also redirects HTTP to HTTPS is a classic cause of endless redirect loops. Porkbun just answers DNS: the records point straight at your home IP, and only TCP 443 (plus UDP 51820 for WireGuard) is forwarded.

---

## 5. Capacity: what "a dozen 4K users" really means

- **On the LAN, 4K "direct play" costs the server almost nothing.** It just reads the file and sends it, and the TV or phone decodes it. A 4K remux runs 40–100 Mbps, so ~10 of them would fill a gigabit link. Your usual 1–3 users are easy.
- **Outside your house, the limit is your Xfinity *upload* speed, not the server.** Remote users get a transcode down to roughly 8–20 Mbps 1080p via Quick Sync. Measure the N5095A's real limit after part 3: start 4K HDR→1080p transcodes one at a time and stop when playback stutters. Plan on a handful of simultaneous 4K HDR→1080p transcodes, not twelve.
- **ErsatzTV channels transcode while someone watches them**, and that uses the same Quick Sync engine.

---

## 6. Build parts

| Part | File | What you finish with | Est. time |
|---|---|---|---|
| 0 | [`00-prep.md`](00-prep.md) | Backups verified, `songofeo.com` ready on Porkbun with API keys, inventory, USB sticks made | 2–3 h |
| 1 | [`01-latitude.md`](01-latitude.md) | Proxmox installed, updated and locked down on the Latitude; installers staged | 2 h |
| 2 | [`02-networking.md`](02-networking.md) | OPNsense routing the house, DoT, WireGuard, DDNS, IDS/CrowdSec, Pi-hole #1 | 3–5 h |
| 3 | [`03-sgin.md`](03-sgin.md) | `cobra-stream`: Samba, Quick Sync media pod, Pi-hole #2, PBS | 4–6 h |
| 4 | [`04-optiplex.md`](04-optiplex.md) | Arcade cabinet on Windows 11 | 3–5 h |
| 5 | [`05-final-touches.md`](05-final-touches.md) | Gate VM: TLS, Authelia, Vaultwarden, Paperless, MeTube, Homepage; go public; backups; monitoring | 4–6 h |
| 6 | [`06-tv-breaks-plugin.md`](06-tv-breaks-plugin.md) | cobra-breaks: "… with breaks" playlists, a random filler video between episodes, on Roku, Apple TV and every other Jellyfin app | 30 min, after 3 |
| 7 | [`07-hiscore-platform.md`](07-hiscore-platform.md) | Hiscore board at `scores.songofeo.com`: cabinet agent uploads every changed `.hi` file; board newest first | 1 h, after 1–5 |
| 8 | [`08-site-and-radio.md`](08-site-and-radio.md) | Landing page at `songofeo.com`; radio at `radio.songofeo.com` (Liquidsoap + Icecast) | 1 h |
| 9 | [`09-r620-lab-and-vlans.md`](09-r620-lab-and-vlans.md) | R620 as `cobra-lab` (standalone Proxmox, remote power), then lab/detonation/management VLANs | When you're ready |

**Order matters.** Part 5's backups need PBS from part 3, and part 3 changes the DNS servers OPNsense hands out (from part 2). Each part says when it depends on another.

---

## 7. Conventions used in every part

- **Two kinds of names, kept apart on purpose:**
  - **Machines** are named for the theme and never change: `cobra-command` (Proxmox), `cobra-firewall` (OPNsense), `cobra-pihole-1`, `cobra-gate`, `cobra-stream`, `cobra-arcade`, `cobra-lab` (R620). They live under `.home.arpa`, the private suffix meant for home networks, e.g. `cobra-stream.home.arpa`.
  - **Public addresses** use the domain, currently **`songofeo.com`**: `tv.songofeo.com`, `docs.songofeo.com` and so on. Only these change if you ever switch domains (see "Changing the domain later" below).
- `eels`: your admin login on every Linux box (has sudo).
- `podsvc`: the unprivileged account that runs rootless Podman containers (no sudo, lingering enabled).
- Quadlet files (Podman's systemd unit files) live in `/home/podsvc/.config/containers/systemd/`.
- App data: `/srv/gate/<app>` on the gate, `/srv/stream/<app>` on the stream box, each storage drive at `/srv/storage/disks/<label>`, all of them pooled at `/srv/storage/pool` (the only path apps and shares use).
- **"On <host> (as <user>):"** before a code block tells you which machine and which account to run it as.
- `✅ Checkpoint` lines tell you what you should see before moving on. Don't continue past a failed checkpoint.
- `⚠️ Verify:` marks something the research team couldn't confirm 100% from a primary source. Check it on screen as you go.
- Secrets are generated with commands, never typed by hand. Store each one in your password manager as soon as it's created.

---

### Changing the domain later

Machine names, IPs, shares and backups don't mention the domain, so a swap touches only these:

| Where | What to change |
|---|---|
| Porkbun | Turn on API Access for the new domain; recreate the app CNAMEs (part 5.5); new API keys (or widen the old ones to the new domain) |
| OPNsense → Dynamic DNS | Hostname (part 2.10) |
| WireGuard clients | `Endpoint =` in each client config (part 2.8) |
| Both Pi-holes | The `address=/*.<domain>/10.6.9.10` and `server=/www.<domain>/#` lines (part 2.9, 3.9) |
| Gate: lego | New wildcard cert for the new domain (part 5.3): the domain in the first-run command, the renewal service and the deploy script |
| Gate: nginx | Every `server_name` and the map keys in `songofeo.conf` (part 5.4) |
| Gate: Authelia | `totp.issuer`, the session cookie `domain` and `authelia_url`, the access rules (part 5.4) |
| Gate: app settings | `DOMAIN=` (Vaultwarden), `PAPERLESS_URL`, `HOMEPAGE_ALLOWED_HOSTS` |
| Apps' own "public URL" settings | Jellyfin, Audiobookshelf, RomM and others, if you've set one |
| Phones/TVs | Re-add servers in the Jellyfin, Audiobookshelf and Navidrome apps |

Tip: `grep -rl songofeo.com /srv/gate ~/.config/containers` on the gate finds every file that still has the old name.

## 8. Reserved slot: the hiscore platform (built after everything else)

The hiscore app gets designed and built **after the rest of the network is running and stable**. Its spot in the system is reserved now, so plugging it in later needs no re-wiring. **Every part leaves these hooks in place, and none of them does anything until the app exists:**

| Touch-point | Reservation | Set up in |
|---|---|---|
| Public hostname | `scores.songofeo.com` (Porkbun CNAME, created when the app goes live) | Part 7 |
| Local DNS | `scores.songofeo.com → 10.6.9.10` in Pi-hole (already covered by the `address=/*.songofeo.com/` line) | Part 2 |
| TLS | Already covered by the `*.songofeo.com` wildcard certificate | Part 5 |
| nginx | `scores.songofeo.com` server block, **commented out** until the app exists | Part 5 |
| Where it runs | Inside the **`gate` pod** so nginx reaches it over localhost: **API on `127.0.0.1:8090`**; if it needs its own Postgres, **`127.0.0.1:5433`** (5432 is Paperless's) | Part 7 |
| Data | `/srv/gate/hiscore/` (raw `.hi` files under `raw/` = the power-loss backup; parsed scores in the DB). It's inside VM 110, so the nightly backups already cover it. | Part 7 |
| Logins | Viewers: app login (or Authelia). Cabinet agent: API key over HTTPS. Upload endpoint rate-limited in nginx. | Part 7 |
| Cabinet side | Windows agent in `C:\Cobra\hiscore-agent\` (a logon task as `arcade`), watching RetroArch's hiscore folders (paths noted in part 4) | Part 7 |
| Dashboard / monitoring | Homepage tile + Uptime Kuma monitor added at go-live | Part 5 |

**Port `8090` and the hostname `scores` are reserved.** Don't assign them to anything else.

---

## 9. Future projects (start only after the full build is finished and stable)

| Priority | Project | Notes |
|---|---|---|
| **1** | **Breaks between episodes.** A random video from a chosen folder between episodes, on demand, not only on Live TV. | **Built** as `apps/cobra-breaks` (part 6). Roku and Apple TV apps never ask Jellyfin for intros before episodes, so instead of a plugin it builds per-show "with breaks" playlists that every app plays. Movie pre-rolls stay with Local Intros; Live TV breaks come from ErsatzTV filler (part 3.8a). |
| 2 | **Hiscore platform.** Windows sync agent + `hiscore` slot in the gate pod + scoreboard at `scores.songofeo.com`. | **Built**: `apps/hiscore`, `apps/hiscore-agent` and the LaunchBox plugin `apps/hiscore-launchbox` (titles, hi2txt score tables), plus the public arcade screen at `scores.songofeo.com/screen`; install steps in [part 7](07-hiscore-platform.md). Optional later: browser-arcade scores. |
| 3 | Custom CSS + X-Arcade Tankstick code from earlier this month | Landing site, Jellyfin theme, cabinet controls |
