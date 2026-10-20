# Container research: better picks and new additions

Research notes for stage 03, October 2026. Nothing here is in the manual yet. Pick what you want and it can be added as a run script and a manual section later.

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
| 1 ★ | **Frigate** (`ghcr.io/blakeblackshear/frigate:stable`) | Network video recorder for IP cameras with AI object detection (person, car, animal), so you get "person at the front door" alerts and clips instead of hours of motion triggers. | SGIN | 1–2 GB | Uses the N5095A's iGPU twice: Quick Sync to decode the camera streams, and OpenVINO on the iGPU for detection, so it doesn't need a Coral stick for 2–4 cameras. Needs RTSP cameras (Reolink and Amcrest are popular). Put recordings on the pool. Keep the cameras blocked from the internet at the firewall. It competes with Jellyfin for the GPU, so test both at once. |
| 2 ★ | **Home Assistant** | Home automation hub: locks, lights, sensors, sirens, and Frigate's alerts in one app with a good phone app. | **A VM on `cobra-command`**, not a pod | 2 GB | The container version can't use add-ons and needs host networking to find devices, which fights the rootless pod. The Home Assistant OS VM on Proxmox is the supported way and has room (after the firewall, gate and Pi-hole, roughly 3–4 GB of its 16 GB is left). Listed here because you'd want it with Frigate. |
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
| 6 ★ | **Immich** | Google Photos replacement: phones back up photos and videos automatically, with face recognition, maps, search ("dog on beach") and shared albums. | SGIN | 2–4 GB | The biggest add on this list. Four containers (server, machine-learning, Postgres, Valkey). Video thumbnails use Quick Sync. Its docs ask for 6 GB+ for the whole system, so with Jellyfin and the rest **12 GB is tight**. Turn off or limit machine learning, or run the machine-learning container on another box. Version 3.0 is due soon, so start on whatever is stable when you install. |
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

## If I were picking

For the "home security and entertainment" goal, the first wave would be **Frigate + ntfy + Scrutiny + Beszel** (security and health), then **Immich** once you've checked how much RAM the SGIN has free with Jellyfin busy, then **Calibre-Web Automated** if anyone reads on an e-reader. The rest are small enough to add whenever you want them.

Before adding much to the SGIN, run `free -h` while two Jellyfin transcodes are going, so you know the real headroom.

## Sources

- Booklore shutdown and Grimmory fork: [discuss.mschae23.de thread](https://discuss.mschae23.de/post/21331), [Cloudron forum on Grimmory](https://forum.cloudron.io/topic/15497/grimmory-self-hosted-digital-library-for-ebooks-comics-audiobooks-community-fork-of-booklore)
- Immich 3.0 status: [Linux Today, July 2026](https://www.linuxtoday.com/blog/immich-3-0-is-just-around-the-corner-heres-what-to-expect/), [Immich hardware transcoding docs](https://docs.immich.app/features/hardware-transcoding)
- Beszel vs Netdata footprint: [selfhosting.sh comparison](https://selfhosting.sh/compare/beszel-vs-netdata/)
- Jellyfin's standing and alternatives: [JellyWatch, Plex alternatives 2026](https://jellywatch.app/blog/best-plex-alternatives-2026-jellyfin-emby-immich-comparison), [Jellyfin vs Navidrome for music](https://jellywatch.app/blog/jellyfin-vs-navidrome-best-self-hosted-music-server-2026)
- Dashboards: [2026 dashboard comparison](https://tomsparkbox.com/guides/best-self-hosted-dashboard-for-beginners)
