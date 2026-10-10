# Elysidrome Build Manual — 00: Overview & Architecture

> **Read this first.** Every other stage refers back to the names, IPs and ports defined here.
> If your domain is actually `elysidrom.com` (no "e"), you typed it both ways. Do a find/replace across `docs/manual/` before you start.

---

## 1. Answers to your direct questions

| # | Your question | Answer (with the reasons) |
|---|---|---|
| 1 | *Proxmox runs everything from the Latitude: OPNsense, Pi-hole and Jellyfin?* | **Proxmox on the Latitude: yes. Jellyfin on it: no.** The Latitude runs Proxmox with the firewall, Pi-hole #1 and the `elysidrome-gate` VM. Jellyfin moves elsewhere (see #4). |
| 2 | *Optiplex gets Windows 10 for the arcade?* | **Windows, yes, but Windows 11 rather than 10.** Consumer Windows 10 Extended Security Updates end **Oct 13, 2026**, three days from when this manual was written. After that the cabinet would get no more security patches while sitting on your LAN. Windows 11 installs on the i7-6700 using Rufus's requirement bypass and activates with your existing license. LaunchBox/Big Box is Windows-only, so Windows is the right OS for the cabinet. Full reasoning is in Stage 6. |
| 3 | *Does Navidrome go on the Optiplex?* | **No.** Navidrome needs no GPU, and the cabinet should only run games. It goes on `elysidrome-stream` with the rest of the media apps. **One Navidrome instance is enough.** Navidrome 0.58+ supports multiple libraries with per-user access. `eelsmusic.` and `rupaulradio.` are two hostnames for the same instance, and Eels and Rachel each see only their own library. |
| 4 | *Jellyfin on the gateway box is too much. Shouldn't it go on the Optiplex and use the Intel graphics?* | **You were right to worry: it doesn't belong on the gateway.** That box has 2 cores, 16 GB and the firewall. Putting a media server facing the internet on the same machine that *is* the firewall also widens the damage if it's ever compromised. **The Optiplex is the wrong fix too.** Its HD 530 is Skylake, which has **no hardware decode for HEVC 10-bit**, and that's the format most 4K MKVs use. It would also slow down games on the cabinet. **The SGIN's Celeron N5095A (Jasper Lake) is the best video engine you own.** It does hardware HEVC 10-bit decode and encode plus HDR tone mapping, at about 10 W. So the SGIN becomes **`elysidrome-stream`** and also keeps its jobs as backup server and Pi-hole #2. |
| 5 | *SGIN = backup server + Pi-hole 2?* | **Yes, plus media** (see #4). It runs Proxmox Backup Server, Pi-hole #2, Samba, and the media pod. |
| 6 | *R620 later, labs only?* | **Yes.** It adds lab capacity (an Active Directory lab, CAPEv2, Wazuh, Security Onion) but has no video engine, so it does nothing for streaming. You'll power it on remotely for lab sessions through iDRAC. That's Stage 8. |
| 7 | *Seamless networking + SMB from the Windows 11 desktop?* | **Yes.** All storage drives attach to `elysidrome-stream` and are shared over SMB3 (Samba). Every Windows machine maps the same shares. "Put files wherever I want" means *any machine reads and writes the same library*. |
| 8 | *Both desktops move to the gateway switch?* | **Yes, and they have to.** Anything plugged into the Xfinity gateway bypasses the firewall. |
| — | *M3U or XMLTV for ErsatzTV?* | **Both.** M3U is the channel list and stream URLs (the "tuner"). XMLTV is the program guide. Jellyfin takes one of each. |
| — | *Can the cabinet's RetroArch play with web (browser) users?* | **Not directly.** RetroArch netplay and browser EmulatorJS netplay are different protocols. Stage 6 covers both of the setups that do work: friends join the cabinet with RetroArch, or everyone plays in the browser. |
| — | *Does the arcade need a 3rd pod for the web arcade + hiscore sync?* | **You do need a third pod, but not on the arcade.** (1) The **web arcade (RomM/EmulatorJS) runs the game in the player's browser**. The server only hands out ROM files and the web page, so it lives in the `stream` pod next to the ROM storage and stays up when the cabinet is off. (2) **Hiscore sync has to read files RetroArch writes on Windows.** That's a job for a small **native Windows agent** (background service/tray app). Podman on Windows runs inside a WSL2 virtual machine, which doesn't start until someone logs in, and its file-watching doesn't reliably see changes Windows programs make. (3) The **hiscore server** (scores API + storage + scoreboard website at `scores.elysidrome.com`) runs on Linux, in a **reserved slot inside the `gate` pod** (see §8). Flow: cabinet RetroArch writes `.hi` → Windows sync agent → HTTPS + API key → `hiscore` pod stores the raw `.hi` files (your backup against power loss) and the parsed scores → scoreboard page with logins and filters. |
| — | *IncusOS for security on the gate?* | **No.** IncusOS is an immutable OS whose only job is running Incus (containers/VMs). It isn't a security product, and it can't be installed on Debian. It goes into the R620 lab as a learning VM. |
| — | *Steam Link / Arch-on-USB Pi-hole?* | **No.** The Steam Link has 512 MB of RAM and frozen firmware, and Pi-hole doesn't support Arch. Both Pi-holes run on hardware that's already on 24/7. |
| — | *Joe Sandbox?* | It's a commercial product. The free, self-hosted equivalent is **CAPEv2** (Stage 8). |

---

## 2. Final machine roles

| Name | Hardware | OS | Job | Power |
|---|---|---|---|---|
| **command-center** | Dell Latitude 5580: i7-7600U 2C/4T, 16 GB, 256 GB NVMe, Intel I219-LM + **USB 3 gigabit NIC (~$12–15, the only required purchase)** | Proxmox VE 9 | Hypervisor that runs the firewall, Pi-hole #1 and the gate VM. Its battery acts as a built-in UPS for the firewall. | ~10–20 W |
| ↳ **open-the-box** (VM 100) | 2 vCPU / 4 GB | OPNsense | Firewall, DHCP, Unbound DNS-over-TLS, WireGuard VPN, Suricata IDS/IPS, CrowdSec, DDNS | — |
| ↳ **pihole-1** (CT 101) | 1 core / 512 MB | Debian 13 LXC | Primary ad/malware DNS filter + local DNS records | — |
| ↳ **elysidrome-gate** (VM 110) | 2 vCPU / 6 GB | Debian 13 | Rootless Podman pod: nginx (reverse proxy + TLS), Authelia (SSO + 2FA), Vaultwarden, Paperless-ngx, MeTube, Homepage, Uptime Kuma, NetAlertX. Also CrowdSec and Cockpit. | — |
| **elysidrome-stream** | SGIN X15: Celeron N5095A (Jasper Lake Quick Sync), 12 GB, headless | Debian 13 (bare metal) | Rootless Podman pod: Jellyfin, ErsatzTV, Audiobookshelf, Kavita, Navidrome, RomM (EmulatorJS web arcade). Also Samba (all storage), Pi-hole #2, Proxmox Backup Server, Cockpit. | ~10–15 W + drives |
| **elysidrome-arcade** | OptiPlex 7040: i7-6700, 16 GB dual-channel, AMD Oland XT (R7 250-class) | Windows 11 | LaunchBox/Big Box, RetroArch, Steam, X-Arcade Tankstick, RetroArch netplay host | ~30–60 W in use |
| **R620** (later) | 2× Xeon, DDR3, 4× 480 GB SSD | Proxmox VE 9 (2nd node) | On-demand security lab | 110–160 W *only while on* |
| Windows desktops ×2 | — | Windows 11 | Daily use; SMB access to all shares | — |

**Why `elysidrome-stream` is bare-metal Debian instead of a Proxmox guest:** the iGPU (needed for Quick Sync) and the USB storage drives are simplest and most reliable on bare metal. Running Podman inside an LXC container on Proxmox breaks regularly on AppArmor/runc updates. Real companies run hypervisors next to bare-metal appliances like this all the time. You still manage it from one place: Cockpit plus the Homepage dashboard, and its backups land in the same Proxmox Backup Server.

**What the AMD Oland card does:** it drives the cabinet's display and is moderately faster than the HD 530 for emulation. It has **no HEVC support**, so it can't help Jellyfin.

---

## 3. Network diagram (Phase A: flat LAN, no new switch needed)

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
   │  command-center  (Latitude, Proxmox VE 9)            │
   │   ├─ VM 100  open-the-box   WAN 10.0.0.2             │
   │   │                          LAN 10.10.10.1          │
   │   ├─ CT 101  pihole-1        10.10.10.3              │
   │   └─ VM 110  elysidrome-gate 10.10.10.10  :443 ◄─────┼── only public TCP port
   │  host mgmt 10.10.10.2:8006                           │
   └───────────────────────┬──────────────────────────────┘
          onboard I219-LM  │ (vmbr0, LAN 10.10.10.0/24)
                ┌──────────┴──────────┐
                │  your switch ("hub") │
                └─┬──────┬──────┬─────┬┘
                  │      │      │     │
   elysidrome-stream  arcade  desktop desktop     (R620 later: .40 iDRAC / .41)
     10.10.10.20     .30      .50     .51

   WireGuard VPN clients: 10.10.99.0/24 (UDP 51820)
```

### IP plan

| IP | Host | Notes |
|---|---|---|
| 10.0.0.1 | Xfinity gateway | Not yours to change. Its LAN is 10.0.0.0/24, **which is why your LAN must be different.** |
| 10.0.0.2 | open-the-box WAN | DHCP reservation on Xfinity + DMZ host |
| 10.10.10.1 | open-the-box LAN | Default gateway + Unbound DNS for the LAN |
| 10.10.10.2 | command-center | Proxmox web UI `https://10.10.10.2:8006` |
| 10.10.10.3 | pihole-1 | DNS #1 |
| 10.10.10.10 | elysidrome-gate | nginx 80/443, Cockpit 9090 |
| 10.10.10.20 | elysidrome-stream | Media apps, Samba, Pi-hole #2 (DNS #2), PBS 8007, Cockpit 9090 |
| 10.10.10.30 | elysidrome-arcade | Windows cabinet |
| 10.10.10.40 / .41 | R620 iDRAC / Proxmox | Later |
| 10.10.10.50 / .51 | Windows desktops | DHCP reservations |
| 10.10.10.100–199 | DHCP pool | Everything else |
| 10.10.99.0/24 | WireGuard clients | Admin access from outside |

### Port map

| Host | Service | Port | Who can reach it |
|---|---|---|---|
| gate | nginx | 80 → 443 redirect, 443 | Internet (via OPNsense forward) + LAN |
| gate (in pod) | Authelia 9091 · Vaultwarden 8222 · Paperless 8000 · Postgres 5432 · Redis 6379 · MeTube 8081 · Homepage 3000 · Uptime Kuma 3001 | localhost only | Only nginx inside the pod |
| gate | Cockpit | 9090 | LAN + VPN |
| stream | Jellyfin 8096 · ErsatzTV 8409 · Audiobookshelf 13378 · Kavita 5000 · Navidrome 4533 · RomM 8080 | LAN only (nftables) | gate's nginx + LAN clients |
| stream | Samba | 445 | LAN |
| stream | Pi-hole #2 | 53, 80/443 (admin) | LAN |
| stream | PBS | 8007 | LAN |
| command-center | Proxmox | 8006, 22 | LAN + VPN |
| open-the-box | WireGuard | 51820/udp | Internet |

---

## 4. Your user flowcharts (corrected)

All public traffic follows the same path: **user → Cloudflare DNS (grey cloud, DNS only) → your home IP → Xfinity → open-the-box (firewall, IDS/IPS, CrowdSec) → elysidrome-gate (nginx TLS + rate limits [+ Authelia]) → the app.**
At home, Pi-hole answers `*.elysidrome.com` with `10.10.10.10`, so LAN traffic never leaves the house.

| Want | URL | Path after the gate | Login |
|---|---|---|---|
| Watch a movie / Live TV | `tv.elysidrome.com` | → stream: Jellyfin (+ ErsatzTV channels) | Jellyfin login every time: hidden users, no Quick Connect, sessions revoked every 8 h |
| Audiobooks / ebooks | `books.elysidrome.com` | → stream: Audiobookshelf | In-app |
| Comics / graphic novels | `comics.elysidrome.com` | → stream: Kavita | In-app *(you had typed `books.` for both; Kavita gets its own hostname)* |
| Eels' music | `eelsmusic.elysidrome.com` | → stream: Navidrome (Eels' library) | In-app, 8 h session |
| Rachel's music | `rupaulradio.elysidrome.com` | → stream: same Navidrome (Rachel's library) | In-app, 8 h session |
| Save documents | `docs.elysidrome.com` | → gate: Paperless-ngx | **Mandatory:** Authelia 2FA, then Paperless |
| Save a YouTube video | `metube.elysidrome.com` | → gate: MeTube | **Mandatory:** Authelia 2FA (MeTube has no login of its own) |
| Web arcade | `arcade.elysidrome.com` | → stream: RomM (EmulatorJS player) | In-app |
| Cabinet | (local) | arcade: Big Box → RetroArch; ROMs from `\\elysidrome-stream\roms` | Windows auto-login |
| Dashboard | `home.elysidrome.com` | → gate: Homepage | Authelia 2FA |
| Status page | `status.elysidrome.com` | → gate: Uptime Kuma | Authelia 2FA |
| Password vault | `vault.elysidrome.com` | → gate: Vaultwarden | **LAN/VPN only.** Never public. |
| High-score boards | `scores.elysidrome.com` | → gate: reserved hiscore slot (§8, built later) | Login for viewers. The cabinet's sync agent uses an API key. |
| Live radio | `radio.elysidrome.com` | → stream: Icecast (Stage 8) | Public |
| Landing site with buttons | `elysidrome.com` | → gate: static site (Stage 8) | Public page, buttons to the apps above |

**Why Jellyfin, Audiobookshelf, Kavita, Navidrome and RomM aren't behind Authelia:** putting a login page in front of them breaks their phone and TV apps, which can't complete a web login. They rely on their own logins plus rate limiting, CrowdSec and strong passwords instead.

**Why there's no Cloudflare Tunnel or orange-cloud proxy:** Cloudflare's terms restrict serving video through its proxy and CDN. The records stay DNS-only, and only TCP 443 (plus UDP 51820 for WireGuard) is forwarded.

---

## 5. Capacity: what "a dozen 4K users" really means

- **On the LAN, 4K "direct play" costs the server almost nothing.** It just reads the file and sends it, and the TV or phone decodes it. A 4K remux runs 40–100 Mbps, so ~10 of them would fill a gigabit link. Your usual 1–3 users are easy.
- **Outside your house, the limit is your Xfinity *upload* speed, not the server.** Remote users get a transcode down to roughly 8–20 Mbps 1080p via Quick Sync. Stage 5 gives the N5095A's realistic transcode count. Plan on a handful of simultaneous 4K HDR→1080p transcodes, not twelve.
- **ErsatzTV channels transcode while someone watches them**, and that uses the same Quick Sync engine.

---

## 6. Build stages

| Stage | File | What you finish with | Est. time |
|---|---|---|---|
| 0 | `01-stage0-prep-backup.md` | Backups verified, inventory done, domain on Cloudflare, ISOs on USB | 2–3 h |
| 1 | `02-stage1-proxmox-command-center.md` | Proxmox installed and updated on the Latitude | 2 h |
| 2 | `03-stage2-open-the-box-opnsense.md` | OPNsense routing the house, WireGuard, DDNS, IDS | 3–4 h |
| 3 | `04-stage3-pihole-dns.md` | Pi-hole #1 (Pi-hole #2 after Stage 5), split DNS | 1–2 h |
| 4 | `05-stage4-elysidrome-gate.md` | TLS, Authelia, Vaultwarden, Paperless, MeTube, Homepage | 4–6 h |
| 5 | `06-stage5-elysidrome-stream.md` | Media server, Samba, Quick Sync, PBS | 4–6 h |
| 6 | `07-stage6-elysidrome-arcade-windows.md` | Arcade cabinet on Windows 11 | 3–5 h |
| 7 | `08-stage7-backups-monitoring-hardening.md` | Backups, monitoring, hardening, runbooks | 2–3 h |
| 8+ | `09-stage8-later-r620-lab-radio-site-hiscore.md` | R620 lab, VLANs, radio, landing site, hiscore platform | Later |

**Order matters.** Stage 3's Pi-hole #2 and Stage 7's backups depend on Stage 5. Each of those stages tells you when to come back to it.

---

## 7. Conventions used in every stage

- `eels`: your admin login on every Linux box (has sudo).
- `podsvc`: the unprivileged account that runs rootless Podman containers (no sudo, lingering enabled).
- Quadlet files (Podman's systemd unit files) live in `/home/podsvc/.config/containers/systemd/`.
- App data: `/srv/gate/<app>` on the gate, `/srv/stream/<app>` on the stream box, storage drives under `/srv/storage/<label>`.
- **"On <host> (as <user>):"** before a code block tells you which machine and which account to run it as.
- `✅ Checkpoint` lines tell you what you should see before moving on. Don't continue past a failed checkpoint.
- `⚠️ Verify:` marks something the research team couldn't confirm 100% from a primary source. Check it on screen as you go.
- Secrets are generated with commands, never typed by hand. Store each one in your password manager as soon as it's created.

---

## 8. Reserved slot: the hiscore platform (built after everything else)

The hiscore app gets designed and built **after the rest of the network is running and stable**. Its spot in the system is reserved now, so plugging it in later needs no re-wiring. **Every stage leaves these hooks in place, and none of them does anything until the app exists:**

| Touch-point | Reservation | Set up in |
|---|---|---|
| Public hostname | `scores.elysidrome.com` (Cloudflare DNS-only record, created when the app goes live) | Stage 0 list / hiscore stage |
| Local DNS | `scores.elysidrome.com → 10.10.10.10` in Pi-hole | Stage 3 |
| TLS | Already covered by the `*.elysidrome.com` wildcard certificate | Stage 4 |
| nginx | `scores.elysidrome.com` server block, **commented out** until the app exists | Stage 4 |
| Where it runs | Inside the **`gate` pod** so nginx reaches it over localhost: **API on `127.0.0.1:8090`**; if it needs its own Postgres, **`127.0.0.1:5433`** (5432 is Paperless's) | Hiscore stage |
| Data | `/srv/gate/hiscore/` (raw `.hi` files under `raw/` = the power-loss backup; parsed scores in the DB). It's inside VM 110, so the nightly backups already cover it. | Hiscore stage |
| Logins | Viewers: app login (or Authelia). Cabinet agent: API key over HTTPS. Upload endpoint rate-limited in nginx. | Hiscore stage |
| Cabinet side | Native Windows agent in `C:\Elysidrome\hiscore-agent\`, watching RetroArch's hiscore folders (paths documented in Stage 6) | Hiscore stage |
| Dashboard / monitoring | Homepage tile + Uptime Kuma monitor added at go-live | Stage 7 |

**Port `8090` and the hostname `scores` are reserved.** Don't assign them to anything else.
