# Container research: better picks and new additions

Research notes for stage 03, October 2026, with a second pass on 26 Oct 2026 (section C-3). Nothing here is in the manual yet. Pick what you want and it can be added as a run script and a manual section later.

**What the boxes can hold.** The SGIN (`cobra-stream`) has 4 Jasper Lake cores and 12 GB of RAM, and Jellyfin's transcodes come first. The gate VM has 2 vCPU and 6 GB and faces the internet, so only small web apps belong there. The R620 is only on while you're using it, so nothing that must run 24/7 can live on it. RAM figures below are rough idle-to-busy numbers from the projects' docs and community reports, not measurements on your hardware.

---

## C-1. Is there something better for what you already run?

Short answer: your stack is already the community's first choice in almost every category. Two spots are worth a look (ebooks and YouTube), and one thing in your list works differently than you described (Homepage).

| Category | You run | Verdict | Worth a look instead / alongside |
|---|---|---|---|
| Movies and TV | **Jellyfin** | **Keep.** Still the leading free media server, and the only one of the big three with no paid tier for hardware transcoding or remote play. | Emby and Plex are closed source and charge for features Jellyfin gives away. Nothing to switch to. |
| Music | **Navidrome** | **Keep.** The best Subsonic server: fast, small (about 50–150 MB), works with every Subsonic phone app (Symfonium, Substreamer, Feishin on desktop). | **Gonic** is even lighter but has no web player. Jellyfin's own music side is weaker. Note that Navidrome *plays* ripped music; it doesn't rip CDs. See ARM and Picard in C-2 for getting CDs in cleanly. |
| Audiobooks and podcasts | **Audiobookshelf** | **Keep for audio.** Nothing else comes close for audiobooks and podcasts, with a good phone app and offline downloads. | — |
| Ebooks (EPUB/PDF) | Audiobookshelf | **Weakest spot.** Audiobookshelf reads ebooks, but its e-reader sync is basic. If you read on a Kobo, Kindle or a KOReader device, use a dedicated ebook server. | **Calibre-Web Automated** (`crocodilestick/calibre-web-automated`): Calibre's library engine with an auto-import folder, metadata fixes, Kobo sync, send-to-Kindle and OPDS. Mature, about 200–400 MB. **This is the pick.** **Grimmory** (`ghcr.io/grimmory-tools/grimmory`): a community fork of **Booklore**, made after Booklore's creator pulled the project in spring 2026. Nicer interface, Kobo/KOReader/OPDS sync, but it's young, needs MariaDB, and users report ingestion bugs. Don't install Booklore itself, since it's no longer maintained. Kavita also reads EPUB fine, so a third option is to point Kavita at your ebook folder too and skip a new app. |
| Comics, manga, graphic novels | **Kavita** | **Keep.** Kavita is the best all-rounder, with a good web reader, reading progress, and OPDS. | **Komga** is the main rival and stronger on western comics with ComicInfo metadata, but it's Java and uses more RAM (500 MB+). Only switch if Kavita's series grouping annoys you. |
| Retro games | **RomM + EmulatorJS** | **Keep.** RomM is the clear leader for a ROM library with metadata and in-browser play. | Nothing better. |
| Documents | **Paperless-ngx** | **Keep.** The standard, with nothing close. | **Stirling-PDF** (C-2) pairs well with it for splitting, merging and OCR before import. |
| Passwords | **Vaultwarden** | **Keep.** Works with every Bitwarden app and uses about 30 MB. | — |
| Dashboard | **Homepage** | **Keep, with a correction.** Homepage *shows* your apps, their status and widgets (Jellyfin now-playing, disk space and so on). It doesn't start, stop or update pods. | To actually **control** the pods from a browser, add the `cockpit-podman` package to the Cockpit you already install in part 3.2 (`sudo apt install cockpit-podman`). It gives start/stop/logs/restart for podsvc's containers. **Homarr** is a Homepage alternative you edit by drag-and-drop instead of YAML, but it's heavier. **Glance** is a lighter "feeds and widgets" start page. Neither beats Homepage for your setup. |
| YouTube downloads | **MeTube** | **Keep for one-off grabs.** | **Pinchflat** (`ghcr.io/kieraneglin/pinchflat`): subscribes to channels or playlists and downloads new videos on its own, named for Jellyfin to pick up. Add it if you follow channels. **Tube Archivist** is the "full YouTube clone" option, but it needs Elasticsearch (2 GB+), too heavy for either box. |

---

## C-2. New containers to expand the server

Sorted by how much they'd add to this particular setup. ★ marks the ones I'd pick first. Each one is a single image with Podman-friendly docs unless noted.

### Home security (the other half of the project's goal)

| # | App | What it does | Where | RAM | Notes |
|---|---|---|---|---|---|
| 1 ★ | **Frigate** (`ghcr.io/blakeblackshear/frigate:stable`) | Network video recorder for IP cameras with AI object detection (person, car, animal), so you get "person at the front door" alerts and clips instead of hours of motion triggers. | SGIN | 1–2 GB | Uses the N5095A's iGPU twice: Quick Sync to decode the camera streams, and OpenVINO on the iGPU for detection, so it doesn't need a Coral stick for 2–4 cameras. Needs RTSP cameras (Reolink and Amcrest are popular). Put recordings on the pool. Keep the cameras blocked from the internet at the firewall. It competes with Jellyfin for the GPU, so test both at once. **Current release: 0.17** (Feb 2026): per-camera viewer roles (a guest sees only the porch), state classification you train yourself ("garage door open/closed"), and lighter OpenVINO detection. In 0.17 go2rtc's `exec`/`echo` stream sources are off by default; you won't need them with RTSP cameras. |
| 2 ★ | **Home Assistant** | Home automation hub: locks, lights, sensors, sirens, and Frigate's alerts in one app with a good phone app. | **A VM on `cobra-command`**, not a pod | 2 GB | The container version can't use add-ons and needs host networking to find devices, which fights the rootless pod. The Home Assistant OS VM on Proxmox is the supported way and has room (after the firewall, gate and Pi-hole, roughly 3–4 GB of its 16 GB is left). Listed here because you'd want it with Frigate. **Smart home control (the Sensi thermostat, Eufy bulbs and switches) is being planned in its own thread**, so this list doesn't design it. |
| 3 ★ | **ntfy** (`docker.io/binwiederhier/ntfy`) | Your own push-notification server. Uptime Kuma, Frigate, Home Assistant, backup scripts and `curl` can all send alerts to your phone. | Gate | ~20 MB | Tiny. Turns everything else here into "it tells me when something's wrong." |

### Keeping the server healthy

| # | App | What it does | Where | RAM | Notes |
|---|---|---|---|---|---|
| 4 ★ | **Scrutiny** (`ghcr.io/analogj/scrutiny`) | Web dashboard for your drives' SMART health, with warnings before a pool drive dies. | SGIN | ~100 MB | Reading SMART needs root, so the collector runs as root (a rootful container or the host's `smartctl`, which part 3.2 already installs). The web part can stay rootless. |
| 5 ★ | **Beszel** (`henrygd/beszel` hub + `henrygd/beszel-agent`) | CPU, RAM, disk, temperature and per-container graphs for every box, with alerts. Fills the gap between Uptime Kuma ("is it up?") and "why is it slow?". | Hub on gate, agent on each host | Hub ~50 MB, agent ~15 MB | Point the agent at the Podman API socket for container stats. Much lighter than Netdata (150–300 MB per box). |

Tip, no container needed: Podman has built-in update notices and updates. Add the label `io.containers.autoupdate=registry` and `podman auto-update --dry-run` lists which apps have a newer image. That's a nice follow-up to your scripts' `UPDATE=1`.

### Media and entertainment

| # | App | What it does | Where | RAM | Notes |
|---|---|---|---|---|---|
| 6 ★ | **Immich** | Google Photos replacement: phones back up photos and videos automatically, with face recognition, maps, search ("dog on beach") and shared albums. | SGIN | 2–4 GB | The biggest add on this list. Four containers (server, machine-learning, Postgres, Valkey). Video thumbnails use Quick Sync. Its docs ask for 6 GB+ for the whole system, so with Jellyfin and the rest **12 GB is tight**. Turn off or limit machine learning, or run the machine-learning container on another box. **Version 3.0 shipped on 1 July 2026** (non-destructive editing on phones, Workflows, more reliable Android background backup). It dropped the old `pgvecto.rs` database extension, so install from 3.0's own compose file, not an older guide. |
| 7 | **Jellystat** (`cyfershepard/jellystat`) | Watch history and stats for Jellyfin: who watched what, most-played, transcodes vs direct plays. | SGIN | ~200 MB | Needs its own Postgres. Handy for spotting which devices force transcodes. |
| 8 | **Wizarr** (`ghcr.io/wizarrrr/wizarr`) | Invite links for Jellyfin: send family a link and they make their own account and get a "which app to install" guide. | Gate | ~100 MB | Saves you making accounts by hand. |
| 9 | **Tdarr** or **FileFlows** | Batch re-encodes your library with Quick Sync, for example old H.264 files to HEVC, which roughly halves their size, or fixes audio that forces Jellyfin to transcode. | SGIN | 300 MB+ | Schedule it overnight so it doesn't fight Jellyfin. The N5095A encodes HEVC but **not AV1**, so HEVC is the target. FileFlows is easier to set up; Tdarr has more ready-made plugins. |
| 10 | **Automatic Ripping Machine** (`automaticrippingmachine/automatic-ripping-machine`) | Put a disc in a USB drive and it rips it on its own: audio CDs to FLAC with tags (straight into Navidrome), DVDs and Blu-rays to MKV (into Jellyfin). | SGIN | ~300 MB | Answers your "audio CDs" question. Needs the USB optical drive passed into the container. Only for discs you own; check what your country allows for DVD/Blu-ray backups. |
| 11 | **MusicBrainz Picard** (`jlesage/musicbrainz-picard`) | The standard music tagger, running in a browser tab. Fixes artist, album and cover art so Navidrome groups albums correctly. | SGIN | ~300 MB while open | Only run it when tidying music. **beets** is the command-line alternative. |
| 12 | **Kiwix** (`ghcr.io/kiwix/kiwix-serve`) | Offline Wikipedia, plus Stack Exchange, Project Gutenberg, iFixit and more, served on your LAN. | SGIN | ~100 MB | Light on CPU, heavy on disk (the full English Wikipedia with pictures is about 110 GB). Fun "the internet is down" resource. |

### Everyday life

| # | App | What it does | Where | RAM | Notes |
|---|---|---|---|---|---|
| 13 ★ | **Syncthing** (`docker.io/syncthing/syncthing`) | Keeps folders in sync between phones, PCs and the server with no cloud, for example phone downloads or a "Scans" folder that feeds Paperless. | SGIN | ~100 MB | Peer to peer and encrypted. Lighter than Nextcloud for "my files everywhere." |
| 14 | **Stirling-PDF** (`docker.io/stirlingtools/stirling-pdf`) | All the PDF tools in a browser: merge, split, rotate, compress, OCR, sign, convert. | Gate | 300–600 MB | Pairs with Paperless. Its core is free; a few business features are paid. |
| 15 | **Mealie** (`ghcr.io/mealie-recipes/mealie`) | Recipe manager: paste a recipe site's URL and it saves the recipe without the ads, with meal plans and shopping lists. | Gate | ~200 MB | Good family app. |
| 16 | **Actual Budget** (`docker.io/actualbudget/actual-server`) | Personal budgeting (envelope style, like YNAB), private on your server. | Gate | ~100 MB | Bank sync is optional. Works offline in the browser. |
| 17 | **FreshRSS** (`docker.io/freshrss/freshrss`) | RSS reader for news, blogs and YouTube channels, with phone app support. | Gate | ~50 MB | Very light. |
| 18 | **Linkding** (`docker.io/sissbruecker/linkding`) | Bookmarks and read-later with a browser extension. | Gate | ~50 MB | **Karakeep** (formerly Hoarder) does more, like AI tags and page archiving, but needs a headless Chrome and Meilisearch. |

### Skipped on purpose

- **Nextcloud.** Heavy (PHP, a database, a cache, cron), and Syncthing, Immich, Paperless and Vaultwarden already cover most of what people use it for.
- **Tube Archivist.** Elasticsearch is too heavy for either box. Use Pinchflat.
- **Booklore.** Pulled by its creator in 2026. Use Calibre-Web Automated or Grimmory.
- **Seerr, Sonarr, Radarr, Lidarr, Prowlarr, Bazarr** (second pass). The "request a movie" and auto-download apps all assume a download client, which this build doesn't have. Your library comes from rips and your own files, and ARM (C-2 #10) covers discs. Bazarr in particular needs Sonarr or Radarr to work.
- **Pocket ID / Authentik** (second pass). Authelia (part 5.4) already runs the station's sign-in, and it can also be the OpenID Connect provider when the apps' own logins get wired to it later. A second identity app would mean two sets of users.
- **Watchtower** (second pass). It's built for Docker, and Podman's own `podman auto-update` (part 5.7) already does the job.

## If I were picking

For the "home security and entertainment" goal, the first wave would be **Frigate + ntfy + Scrutiny + Beszel** (security and health), then **Immich** once you've checked how much RAM the SGIN has free with Jellyfin busy, then **Calibre-Web Automated** if anyone reads on an e-reader. The rest are small enough to add whenever you want them.

Before adding much to the SGIN, run `free -h` while two Jellyfin transcodes are going, so you know the real headroom.

The second pass (C-3) puts nebula-sync and Backrest ahead of this wave; see its "Updated pick order".

A third pass (Nov 2026), covering plugins, Authelia integrations, the public side and business apps, is in [gaps-plugins-and-apps.md](gaps-plugins-and-apps.md).

---

## C-3. Second pass (26 Oct 2026)

A fresh look at everything above, plus what the first pass missed. Two of the gaps it fills are already named in the manual itself: the Pi-holes are synced by hand (3.9's Teleporter export and import), and 5.6 says the irreplaceable folders still need a copy outside the house. ⚠️ Verify: the RAM numbers are rough figures from the projects' docs and user reports, not measurements on your machines.

### What changed since the first pass

| App | Status now | What to do |
|---|---|---|
| **Immich** (C-2 #6) | 3.0 is out (1 July 2026). | Install 3.0 from its own compose file when you get to it (row 6 updated). |
| **Frigate** (C-2 #1) | 0.17 is current. | Row 1 updated. Nothing changes in the plan. |
| **Uptime Kuma** | 2.0 went stable in Oct 2025. | The manual already pins `uptime-kuma:2` (part 5.4), so nothing to do. |
| **Scrutiny** (C-2 #4) | Still maintained: v0.9.5 on 30 Sep 2026. A fork (`ghcr.io/staros-labs/scrutiny`, v1.x) also exists. | Keep the original `ghcr.io/analogj/scrutiny`. The fork only matters if the original stalls. |
| **ErsatzTV** | `ghcr.io/ersatztv/legacy` is the current, maintained line (v26.x releases). A rewrite called ErsatzTV Next is in early testing. | Keep `legacy`, as part 3.8 does. Look at Next only once it calls itself stable. |
| **Overseerr / Jellyseerr** | Merged into **Seerr**. The old two were retired at the end of May 2026. | Not on this list (see "Skipped on purpose"). If an old guide says Jellyseerr, read it as Seerr. |
| **Ebooks** (C-1) | Calibre-Web Automated and Grimmory are both active. Grimmory's first release removed Booklore's telemetry. | Calibre-Web Automated is still the pick. |

### New additions

★ marks the ones to pick first. "Where" uses the manual's machine names: **gate** = the `cobra-gate` VM on the Latitude, **SGIN** = `cobra-stream`, **cabinet** = `cobra-arcade`, the Windows 11 OptiPlex.

#### Network and security

| # | App | What it does | Where | RAM | Why it fits |
|---|---|---|---|---|---|
| 19 ★ | **nebula-sync** (`ghcr.io/lovelaze/nebula-sync`) | Copies Pi-hole #1's blocklists, allow/deny lists, groups and clients to Pi-hole #2 every hour. | Gate (gate pod) | ~15 MB | Replaces 3.9's "Teleporter export, then import, again every time you change lists". Without it the two Pi-holes drift apart, and a site is blocked or allowed depending on which one a device asked. Made for Pi-hole v6, which both of yours are. Quick start below. |
| 20 ★ | **NetAlertX** (`ghcr.io/jokob-sk/netalertx`) | Watches the LAN and alerts you (through ntfy) when a **new device** joins, or a known one goes missing. | SGIN or gate | ~150 MB | Already in the manual's "later, if wanted" line for the gate (part 0, §2). This promotes it: it's the cheapest real security win on the list, because a strange device on the `cobra` Wi-Fi is exactly what you'd want to hear about. ⚠️ Verify before installing: its ARP scan needs host networking and raw sockets, which a rootless pod can't give. Either run it as the one rootful container on that box, or use its plugins that read OPNsense's DHCP leases and Pi-hole's client list instead of scanning. |
| 21 | **CrowdSec agent on the gate** | Reads nginx's logs and has OPNsense block IPs that probe for logins, scan paths or hammer Authelia. | Gate | ~100 MB | Also already in the manual's "later" line. OPNsense's CrowdSec (part 2) only sees traffic at the firewall; the gate's agent sees what attackers do *after* TLS. It pairs with Authelia's lockout from part 5.4. |

#### Keeping the server healthy

| # | App | What it does | Where | RAM | Why it fits |
|---|---|---|---|---|---|
| 22 ★ | **Backrest** (`docker.io/garethgeorge/backrest`), a web UI for **restic** | Encrypted, versioned backups of chosen folders to a cloud bucket (Backblaze B2 or any S3) or to a drive at a relative's, with a schedule, retention, and browse-and-restore in the browser. | SGIN (stream pod) | ~50 MB idle, a few hundred MB while backing up | Fills the gap 5.6 names: PBS keeps two copies **in the house**, and a fire or a surge through the USB hub would take both. Back up only the irreplaceable part (photos, home video, `scans`, `backups`, your own music, saves): at B2's prices that's a few dollars a month for a few hundred GB. restic encrypts on the SGIN before upload, so the cloud never sees your files. Quick start below. |
| 23 ★ | **Dozzle** (`docker.io/amir20/dozzle`) | Live logs of every container in a browser tab, with search, and a quick view of which containers keep restarting. | Gate, plus an agent on the SGIN | ~30 MB each | Today a misbehaving app means `ssh`, then `machinectl shell podsvc@`, then `podman logs`. Dozzle shows both pods' logs on one page behind Authelia's TOTP. It reads the rootless **Podman socket**, mounted read-only. Quick start below. |
| 24 | **Speedtest Tracker** (`lscr.io/linuxserver/speedtest-tracker`) | Runs an internet speed test on a schedule and graphs it. It can alert through ntfy when upload drops. | Gate | ~150 MB | Part 0 §5 says remote streaming is limited by your **Xfinity upload**, not the server. This shows what that upload really is, hour by hour, and gives you evidence if Xfinity under-delivers. Run it 2–4 times a day, not hourly: each test uses a few hundred MB, which counts against Xfinity's data cap. |

`cockpit-podman` (C-1, Dashboard row) is still the right way to start, stop and restart containers from a browser. Dozzle only shows logs; together they cover most of what you'd otherwise SSH in for.

#### The cabinet (Windows 11 OptiPlex)

The overview's rule stands: the cabinet runs games, so nothing heavy and nothing always-busy goes on it. These three are light and serve the cabinet itself.

| # | App | What it does | RAM | Why it fits |
|---|---|---|---|---|
| 25 ★ | **Sunshine** (Windows installer: `winget install LizardByte.Sunshine`) + **Moonlight** on the TVs, phones and desktops | Streams the cabinet's screen and controls to another device, so you can play LaunchBox/Big Box on the living-room TV or a phone while the cabinet does the work. | ~100 MB, plus GPU encoding while streaming | Uses the GPU's video encoder: the HD 530 now, NVENC once the RTX 3050 is in (part 4.7). Moonlight has apps for Android, iOS, Apple TV, Windows and some smart TVs. LAN only: don't forward its ports; away from home, use it over WireGuard. **Apollo** is a Sunshine fork that adds an automatic virtual screen at the client's resolution, but its last release was July 2025, so start with Sunshine. |
| 26 | **Syncthing** for Windows (the C-2 #13 pick, on the cabinet) | Copies RetroArch's `saves` and `states` folders to the pool as they change. | ~100 MB | The hiscore agent (part 7) already protects `.hi` files. Save games are only covered today by the nightly copy. Syncthing sends each save to the SGIN within seconds, and PBS then keeps versions of it. Use the official Syncthing Windows build, set to start at logon as `arcade`. |
| 27 | **Beszel agent** (C-2 #5, Windows build) | Puts the cabinet's CPU, RAM, temperatures and disk on the same Beszel page as the Linux boxes. | ~15 MB | Handy for "why did that game stutter" and for watching the RTX 3050's temperatures in the case. ⚠️ Verify: check Beszel's install page for the current Windows agent before installing; its Podman page doesn't cover Windows. |

#### Media extras (no new container)

| # | Add-on | What it does | Where | Why it fits |
|---|---|---|---|---|
| 28 | **Intro Skipper** (Jellyfin plugin) | Finds TV intros and credits by their audio and shows a "Skip intro" button. | Jellyfin (SGIN) | Runs inside Jellyfin, so no new container and no new port. Jellyfin 10.10+ passes the skip markers to the apps through Media Segments. ⚠️ Verify on the Roku and Apple TV apps; the button depends on the app's version. Let its first scan run overnight, since it reads every episode's audio. |
| 29 | **Playback Reporting** (Jellyfin plugin, in Jellyfin's own catalog) | Who watched what, and when. | Jellyfin (SGIN) | A lighter alternative to Jellystat (C-2 #7) that needs no extra Postgres. Try it first, and add Jellystat only if you want its charts. |

### Home automation

The Sensi thermostat, Eufy bulbs and Eufy light switches are being worked out in a separate thread. That plan will most likely land on Home Assistant (C-2 #2) as a VM on the Latitude, which fits in the RAM shown below. Nothing else in this list depends on it.

### Where the room is

| Machine | Spoken for | Room for |
|---|---|---|
| **Latitude** (Proxmox, 16 GB) | Firewall 4 GB, Pi-hole 0.5 GB, gate VM 6 GB, Proxmox itself ~1 GB | ~3–4 GB: a Home Assistant VM (2 GB) **or** raising the gate VM to 8 GB, not both comfortably |
| **Gate VM** (6 GB) | nginx, Authelia, Vaultwarden, Paperless + Postgres + Redis, MeTube, Homepage, Uptime Kuma | The small web apps: nebula-sync, Dozzle, Speedtest Tracker, ntfy, the Beszel hub and C-2's "Everyday life" apps. Paperless is the big one here (around 1 GB while it reads a scan). Check `free -h` after adding three or four |
| **SGIN** (12 GB) | Jellyfin's transcodes first, then the media pod, PBS, Samba, Pi-hole #2 | Backrest, Dozzle's agent and Scrutiny are small. **Frigate and Immich are the two big ones**, and both want the iGPU too: add one, measure with Jellyfin busy, then decide on the other |
| **Cabinet** (16 GB) | Games come first | Only the three light Windows apps above |

### Updated pick order

1. **nebula-sync** and **Backrest** first: both fix gaps the manual already admits to, and both are small.
2. Then the first pass's wave: **ntfy + Scrutiny + Beszel**, with **Dozzle** alongside.
3. **NetAlertX** and the gate's **CrowdSec agent** once the gate is public.
4. **Sunshine** on the cabinet whenever you want to play on the TV; it doesn't touch the servers.
5. **Frigate** if cameras are coming, otherwise **Immich**, one at a time on the SGIN.

### Quick starts for the top three new picks

These follow the manual's conventions: rootless Podman as `podsvc` (`sudo machinectl shell podsvc@`), Quadlet files, and passwords typed without echo or generated. They're a starting point. Each gets a proper manual section, a run script and a Homepage tile when you decide to install it.

#### nebula-sync (on the gate, as podsvc)

First, in **each** Pi-hole's web admin (`http://10.6.9.3/admin` and `http://10.6.9.20/admin`): Settings → Web interface / API → switch to **Expert** → **Configure app password**, and copy the password it shows into Vaultwarden. An app password only works for the API, so neither admin login ever sits in a config file. ⚠️ Verify: the menu names on screen.

```bash
# Store each Pi-hole's address and app password as one podman secret, typed without echo.
# The format nebula-sync expects is:  http://<address>|<app password>
read -rsp "Pi-hole #1 app password: " pw; echo
printf 'http://10.6.9.3|%s' "$pw" | podman secret create nebula-primary -    # "-" = read the secret from stdin
read -rsp "Pi-hole #2 app password: " pw; echo
printf 'http://10.6.9.20|%s' "$pw" | podman secret create nebula-replicas -
unset pw                                                                     # don't leave it in the shell

cd ~/.config/containers/systemd
cat > nebula-sync.container <<'UNIT'
[Container]
ContainerName=nebula-sync
Image=ghcr.io/lovelaze/nebula-sync:latest
Pod=gate.pod
# The two secrets become the PRIMARY and REPLICAS environment variables, inside the container only
Secret=nebula-primary,type=env,target=PRIMARY
Secret=nebula-replicas,type=env,target=REPLICAS
# FULL_SYNC=false: copy only the lists below, never the whole config. A full sync would also copy
# Pi-hole #1's network settings onto Pi-hole #2, which runs on different hardware with a different
# network adapter. Each Pi-hole keeps the local DNS lines that parts 2.9 and 3.9 gave it.
Environment=FULL_SYNC=false
Environment=SYNC_GRAVITY_AD_LIST=true
Environment=SYNC_GRAVITY_AD_LIST_BY_GROUP=true
Environment=SYNC_GRAVITY_DOMAIN_LIST=true
Environment=SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP=true
Environment=SYNC_GRAVITY_GROUP=true
Environment=SYNC_GRAVITY_CLIENT=true
Environment=SYNC_GRAVITY_CLIENT_BY_GROUP=true
# Rebuild Pi-hole #2's blocklist database after each sync, so new lists take effect at once
Environment=RUN_GRAVITY=true
# Every hour, on the hour
Environment=CRON=0 * * * *
Label=io.containers.autoupdate=registry
[Service]
Restart=always
[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload && systemctl --user start nebula-sync
podman logs -f nebula-sync     # Ctrl+C to stop watching. Each run should finish without an error
```

- [ ] Add a test domain to Pi-hole #1's deny list. At the next full hour (or run `systemctl --user restart nebula-sync` to sync now) it appears on Pi-hole #2. Remove it from #1, and it's gone from #2 after the next run.
- [ ] The gate reaches both Pi-holes over the LAN on port 80. Pi-hole #2's port 80 is already open to the LAN in 3.7's nftables list.
- [ ] From now on, change lists **only on Pi-hole #1**. Anything added to #2 by hand is overwritten at the next sync.

#### Backrest (on the SGIN, as podsvc)

```bash
# Its own folders under /srv/stream, so the nightly PBS backup of /srv/stream (5.6) also keeps Backrest's settings
mkdir -p /srv/stream/backrest/{data,config,cache}

cd ~/.config/containers/systemd
cat > backrest.container <<'UNIT'
[Container]
ContainerName=backrest
Image=docker.io/garethgeorge/backrest:latest
Pod=stream.pod
Environment=BACKREST_DATA=/data
Environment=BACKREST_CONFIG=/config/config.json
Environment=XDG_CACHE_HOME=/cache
Environment=BACKREST_PORT=0.0.0.0:9898
Volume=/srv/stream/backrest/data:/data:Z
Volume=/srv/stream/backrest/config:/config:Z
Volume=/srv/stream/backrest/cache:/cache:Z
# The pool, READ-ONLY: Backrest can read everything there, but can never change or delete a library file.
# No :Z on this one: relabelling the whole pool would take hours, and Debian doesn't need it (no SELinux).
Volume=/srv/storage/pool:/pool:ro
Label=io.containers.autoupdate=registry
[Service]
Restart=always
[Install]
WantedBy=default.target
UNIT
# Publish port 9898 from the stream pod, next to the other apps' ports
cp stream.pod stream.pod.bak                                  # keep the old file until this works
sed -i '/^PublishPort=8080:8080/a PublishPort=9898:9898' stream.pod
grep PublishPort stream.pod                                   # 9898 must now be in the list
systemctl --user daemon-reload && systemctl --user restart stream-pod   # restarts every media app for a few seconds
```

Then as eels, open the port in the SGIN's firewall (3.7) for the LAN and WireGuard only, like the other apps:

```bash
sudo cp /etc/nftables.conf /etc/nftables.conf.bak                       # keep the working rules until the new ones check out
sudo sed -i 's/8409, 9090/8409, 9090, 9898/' /etc/nftables.conf          # add 9898 to the LAN + VPN port list
sudo nft -c -f /etc/nftables.conf && sudo systemctl restart nftables     # -c only checks the file; restart only if it's valid
sudo nft list ruleset | grep 9898                                        # the port list now includes 9898
```

- [ ] Keep your SSH session open and check a **new** one still connects, as 3.7 says for any firewall change.
- [ ] Open `http://10.6.9.20:9898` from the desktop. The first screen asks for an instance name (`cobra-stream`) and an admin username and password: generate the password in Vaultwarden.
- [ ] Add a **repository**. For Backblaze B2: make a private bucket and an application key limited to that bucket, then give Backrest the URI `b2:<bucket>:cobra`, with `B2_ACCOUNT_ID` and `B2_ACCOUNT_KEY` set to the key ID and key in the repository's environment variables. **The repository password Backrest asks for is the encryption key. Without it the backup can never be restored. Save it in Vaultwarden and on paper.**
- [ ] Add a **plan**: paths under `/pool` (only the irreplaceable folders), daily at a time that doesn't overlap PBS's jobs between 01:00 and about 03:30 (04:30, for example), and retention keep-daily 7, keep-weekly 4, keep-monthly 12.
- [ ] Run it once by hand, then **restore one file** from the UI and open it. A backup you haven't restored from isn't a backup yet.
- It's admin-only and LAN-only on purpose: don't put it behind the gate.

#### Dozzle (on the gate, plus an agent on the SGIN, both as podsvc)

On **each** box, turn on the rootless Podman API socket that Dozzle reads (it's off by default):

```bash
systemctl --user enable --now podman.socket
ls -l "$XDG_RUNTIME_DIR/podman/podman.sock"   # must exist, e.g. /run/user/1001/podman/podman.sock
```

On the SGIN, the agent (it only answers the gate's Dozzle):

```bash
cd ~/.config/containers/systemd
# No quotes around UNIT here on purpose: the shell fills in $XDG_RUNTIME_DIR, podsvc's socket folder
cat > dozzle-agent.container <<UNIT
[Container]
ContainerName=dozzle-agent
Image=docker.io/amir20/dozzle:latest
Exec=agent
# The socket goes where Dozzle looks for it; read-only, so Dozzle can view containers but not control them
Volume=$XDG_RUNTIME_DIR/podman/podman.sock:/var/run/docker.sock:ro
PublishPort=7007:7007
Label=io.containers.autoupdate=registry
[Service]
Restart=always
[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload && systemctl --user start dozzle-agent
```

As eels on the SGIN, allow port 7007 **from the gate only**, not the whole LAN. Open the file, add the line shown in the comment under the other `accept` lines, then check and restart:

```bash
sudo cp /etc/nftables.conf /etc/nftables.conf.bak
sudo nano /etc/nftables.conf
#   add:    ip saddr 10.6.9.10 tcp dport 7007 accept
sudo nft -c -f /etc/nftables.conf && sudo systemctl restart nftables
```

On the gate, Dozzle itself, inside the gate pod on `127.0.0.1:8085` (nothing in part 0's port map uses 8085):

```bash
cd ~/.config/containers/systemd
cat > dozzle.container <<UNIT
[Container]
ContainerName=dozzle
Image=docker.io/amir20/dozzle:latest
Pod=gate.pod
Volume=$XDG_RUNTIME_DIR/podman/podman.sock:/var/run/docker.sock:ro
# Listen inside the pod only; nginx is the way in
Environment=DOZZLE_ADDR=127.0.0.1:8085
# Also show the SGIN's containers, through its agent
Environment=DOZZLE_REMOTE_AGENT=10.6.9.20:7007
# Signing in is Authelia's job (with TOTP), so Dozzle's own login stays off
Environment=DOZZLE_AUTH_PROVIDER=none
Label=io.containers.autoupdate=registry
[Service]
Restart=always
[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload && systemctl --user start dozzle
```

- [ ] nginx: add a `logs.songofeo.com` server block copied from an admin app's block in 5.4 (Homepage's), with `proxy_pass http://127.0.0.1:8085`, and add `logs.songofeo.com` to Authelia's **admin** rule (password + TOTP). Dozzle shows every container's logs, and logs can include tokens, so it must never be reachable without TOTP. If you'd rather not publish it at all, keep it LAN/VPN-only like `vault.` and skip the Porkbun CNAME.
- [ ] `https://logs.songofeo.com` lists the gate's containers and, under the agent, the SGIN's.

## Sources

- Booklore shutdown and Grimmory fork: [discuss.mschae23.de thread](https://discuss.mschae23.de/post/21331), [Cloudron forum on Grimmory](https://forum.cloudron.io/topic/15497/grimmory-self-hosted-digital-library-for-ebooks-comics-audiobooks-community-fork-of-booklore)
- Immich 3.0 status: [Linux Today, July 2026](https://www.linuxtoday.com/blog/immich-3-0-is-just-around-the-corner-heres-what-to-expect/), [Immich hardware transcoding docs](https://docs.immich.app/features/hardware-transcoding)
- Beszel vs Netdata footprint: [selfhosting.sh comparison](https://selfhosting.sh/compare/beszel-vs-netdata/)
- Jellyfin's standing and alternatives: [JellyWatch, Plex alternatives 2026](https://jellywatch.app/blog/best-plex-alternatives-2026-jellyfin-emby-immich-comparison), [Jellyfin vs Navidrome for music](https://jellywatch.app/blog/jellyfin-vs-navidrome-best-self-hosted-music-server-2026)
- Dashboards: [2026 dashboard comparison](https://tomsparkbox.com/guides/best-self-hosted-dashboard-for-beginners)
- Second pass, Oct 2026: [Immich v3.0.0 release](https://immich.app/blog/v3.0.0-release), [Frigate 0.17.0 release](https://github.com/blakeblackshear/frigate/releases/tag/v0.17.0), [Uptime Kuma 2.0 stable](https://linuxiac.com/uptime-kuma-2-0-arrives-with-mariadb-support-modern-ui-refresh/), [Scrutiny releases](https://releasealert.dev/ghcr/AnalogJ%252Fscrutiny), [Overseerr and Jellyseerr retired for Seerr](https://store.elfhosted.com/blog/2026/04/28/overseerr-jellyseerr-sunset-may-2026/), [nebula-sync](https://hub.docker.com/r/lovelaze/nebula-sync), [Backrest](https://forum.restic.net/t/backrest-a-cross-platform-backup-orchestrator-and-webui-for-restic/7069), [Beszel with Podman](https://www.beszel.dev/guide/podman), [Dozzle with Podman](https://raw.githubusercontent.com/amir20/dozzle/HEAD/docs/guide/podman.md), [Apollo vs Sunshine, 2026](https://tech-insider.org/?p=21197), [ErsatzTV legacy releases](https://newreleases.io/project/github/ErsatzTV/legacy/release/v26.11.2), [ebook servers discussion, Apr 2026](https://discuss.mschae23.de/post/24775)
