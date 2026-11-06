# Filling the gaps: plugins, integrations and missing apps

Research notes, 6 Nov 2026. Third pass, after [containers.md](containers.md) (C-1 to C-3). **Nothing here is installed.** This pass looks at what the first two skipped: plugins inside the apps you already run, wiring the apps into Authelia, the public side of the station, the business and production side, and the small "glue" pieces (email, alerts, backups of configs) that every other app quietly assumes exists.

Apps already covered in containers.md are only mentioned by their number there (for example "C-2 #3 ntfy"), not described again.

**How to read the tables**

- **Where**: **gate** = `cobra-gate` VM (10.6.9.10), **SGIN** = `cobra-stream` (10.6.9.20), **OPNsense** = `cobra-firewall`, **Proxmox** = `cobra-command`, **cabinet** = `cobra-arcade`, **the-box** = your desktop, **phone** = the S21. "Inside X" means a plugin or setting in an app, with no new container.
- **Effort**: **Easy** = clicks in a web UI or one package, under 30 minutes. **Medium** = a new container or an Authelia/nginx change, an evening. **Hard** = several moving parts, or a migration.
- ⚠️ **Verify** marks something I could only confirm from a third-party source, or that changes often. Check it on the live box before acting.

---

## 0. Two things to know before adding anything

### 0.1 `jellyfin:latest` now means Jellyfin 12, and 12 breaks old plugins

The manual and the run scripts pull `docker.io/jellyfin/jellyfin:latest`. Jellyfin dropped the "10." from its version numbers: **12.0 shipped on 8 Sep 2026** (what would have been 10.12), and 12.2 and 12.3 followed in October. So the next `podman auto-update` or `UPDATE=1` re-run moves the SGIN from 10.11 to 12.x.

What that means for this build, per the 12.0 write-up (⚠️ Verify against [Jellyfin's own release post](https://jellyfin.org/posts/jellyfin-release-12.0)):

- **Third-party plugins built for 10.11 must be rebuilt for 12** (it moved to .NET 10). Official plugins from Jellyfin's own catalog were already updated. Anything from an outside repository (Intro Skipper, Local Intros, the ones in section 3) needs a 12.x build from its author first. Remove those before upgrading and add them back once a 12.x build exists.
- The first start on 12 migrates the database **one way**. Only a backup takes you back. Back up `/srv/stream/jellyfin` (config) first. The nightly PBS job (5.6) already covers it, but take a fresh one by hand right before.
- Upgrading requires 10.10.7 or any 10.11.x first. Two usernames that differ only by capital letters stop the migration. A full library scan runs afterwards.
- The `/emby/...` URLs are gone and "legacy" API logins are off by default. **cobra-breaks is fine:** it already sends the modern `Authorization: MediaBrowser Token="…"` header (`apps/cobra-breaks/cobra_breaks/jellyfin.py`). Check the TV apps (Roku, Apple TV players) still sign in after the upgrade.
- 12 also brings real security fixes (path traversal, a setup-wizard re-run, XSS, a parental-control bypass), and `tv.` is the one name that faces the internet without Authelia. So **do** upgrade, on purpose and on a night you pick.

**Suggestion:** pin the tag in the Jellyfin Quadlet or `scripts/podman/sgin/jellyfin.sh` to the version you are actually on (for example `jellyfin/jellyfin:10.11.x`, then later `12.3.x`). Move the pin when you choose. Jellyfin 12 also reads books and comics natively now. That's no reason to move off Kavita and Audiobookshelf, which still do those jobs better.

### 0.2 The Jellyfin SSO plugin is dead, so `tv.` keeps Jellyfin's own login

The plugin people used to sign in to Jellyfin through an OIDC provider (`9p4/jellyfin-plugin-sso`) was **archived on 12 May 2026**. The fork that carried it on (Flowfin) **ended on 29 Sep 2026** and names no successor. Smart-TV apps could never use it anyway. This confirms the current design (part 5.4: `tv.` relies on Jellyfin accounts). To make it easier on friends:

- **Quick Connect** (Jellyfin Dashboard → General → Quick Connect, built in): the TV shows a 6-character code, and the friend approves it from their phone's browser. That way nobody types a password with a remote. **Easy.**
- **Wizarr** (C-2 #8) for invite links, so friends make their own Jellyfin accounts. That's the open "friends' Jellyfin users" to-do.

---

## 1. Shortlist: if you only do ten

| # | What | Why | Where | Effort |
|---|---|---|---|---|
| 1 | Pin the Jellyfin tag, then upgrade to 12 on purpose (0.1) | Stops an auto-update from breaking plugins and migrating the database behind your back | SGIN | Easy |
| 2 | One outgoing-mail relay for the whole station (2.1), plus the DNS records in 4.1 | Authelia's password resets and TOTP codes go to a file today. Vaultwarden, Paperless, Proxmox, PBS and Uptime Kuma all want email too | gate (config) + Porkbun | Medium |
| 3 | ntfy (C-2 #3) as the alert hub, with Proxmox, PBS, Uptime Kuma, Jellyfin and smartd pointed at it (6.1) | Turns "I found out a week later" into a phone buzz | gate | Easy–Medium |
| 4 | Pi-hole threat blocklists (6.6) | Cobra1 hit three suspicious domains on 4 Nov. Malware lists block those for every device | both Pi-holes | Easy |
| 5 | Authelia passkeys and user groups (2.2, 2.3) | Fingerprint/Windows Hello sign-in, and friends can't reach admin pages even if they guess a name | gate | Easy |
| 6 | Authelia as the OpenID Connect provider for Audiobookshelf, Kavita, RomM and Paperless (2.4) | Ends the "station pass" second login on the website's players. One account per person everywhere | gate + each app | Medium each |
| 7 | Jellyfin plugins: OpenSubtitles, TMDb Box Sets, Intro Skipper, Webhook (3) | Subtitles with no Bazarr, automatic movie collections, skip-intro, and events to ntfy/Home Assistant | inside Jellyfin | Easy |
| 8 | Backrest off-site (C-3 #22) plus a Vaultwarden file-level backup (6.4) | The irreplaceable folders and the password vault are only copied inside the house today | SGIN, gate | Easy–Medium |
| 9 | etckeeper on the Debian boxes, and OPNsense's Git backup (6.3, 6.5) | Every config change gets a history. The fstab with 8 duplicate lines would have shown up as a diff | gate, SGIN, OPNsense | Easy |
| 10 | Publish the `sessions` podcasts as a real podcast feed from Audiobookshelf (5.2), and a public status page (4.3) | The two "open to the public" pieces that need no new app | inside Audiobookshelf, Uptime Kuma | Easy–Medium |

---

## 2. The sign-in (Authelia at gate.songofeo.com)

| # | What | Why it fills a gap | Where | Effort |
|---|---|---|---|---|
| 2.1 | **Real email (SMTP) notifier** in place of `notifier: filesystem` | Today a password reset or a new TOTP device means SSH to the gate and `tail notification.txt`. For Rachel or a friend, that means you. With SMTP, Authelia mails the code. Set it up once as an SMTP relay and reuse the same account for **Vaultwarden** (emergency access, new-device mails), **Paperless** (password reset), **Proxmox/PBS** (5.7 already asks for an SMTP target), and **Uptime Kuma**. Options: a Gmail **app password** (free, sender is your Gmail); **Porkbun email** for `noreply@songofeo.com` (paid, per mailbox); or a transactional service with a free tier such as **SMTP2GO** or **Brevo** (sends as `@songofeo.com` once you add their SPF/DKIM records, see 4.1). ⚠️ Verify the free tiers' current limits | gate (Authelia `notifier.smtp`), then each app | Medium |
| 2.2 | **Passkeys** (Authelia 4.39+, March 2025) | Sign in with Windows Hello on the-box or the S21's fingerprint instead of password + TOTP. By default a passkey still counts as one factor, so the admin apps keep asking for the password too. A config switch can make the passkey count as full 2FA. You already run `authelia:latest`, so it's there. Turn on `webauthn` (enable passkey login), then each person adds one under **Settings → Security** | gate | Easy |
| 2.3 | **Groups in `users.yml`** (`admins`, `family`, `friends`) and rules that use them (`subject: group:admins`) | Today any signed-in user can open `papers.`, `metube.`, `command.` and `status.` if they have TOTP. With groups, the admin names say `group:admins` and a friend gets "forbidden" even after signing in. OIDC (2.4) also passes groups to the apps, so Kavita or Audiobookshelf can make someone an admin automatically | gate | Easy |
| 2.4 | **Authelia as an OpenID Connect provider** (`identity_providers.oidc`) | One account per person, kept in one place. Each app below gets a "Sign in with Cobra" button, and the station pass goes away. Start with the one you use most and add one app at a time. The [Authelia integration pages](https://www.authelia.com/integration/openid-connect/) have a ready config block for most of these | gate + each app | Medium per app |
| | ↳ **Audiobookshelf** | Built in: Settings → Authentication → OpenID Connect. Auto-registers users and can map groups to roles. The phone app supports it | SGIN | Medium |
| | ↳ **Kavita** (0.8.8+) | Built in: Admin → OpenID Connect. Redirect URI `https://comics.songofeo.com/signin-oidc`. The `aud` claim must equal Kavita's client ID. For role sync, set Roles claim = `groups` and add the `groups` scope. Kavita's wiki lists Authelia but doesn't support it officially | SGIN | Medium |
| | ↳ **RomM** | Built in. Both Authelia and RomM have an official guide ([RomM's](https://docs.romm.app/latest/OIDC-Guides/OIDC-Setup-With-Authelia/), [Authelia's](https://www.authelia.com/integration/openid-connect/clients/romm/)). Do it while building the arcade, before friends have RomM accounts | SGIN | Medium |
| | ↳ **Paperless-ngx** | Built in through django-allauth: `PAPERLESS_APPS=allauth.socialaccount.providers.openid_connect` plus `PAPERLESS_SOCIALACCOUNT_PROVIDERS` (JSON). Authelia has a page for it | gate | Medium |
| | ↳ **Vaultwarden** (1.35.0+) | SSO with OpenID Connect is now built in. You still need the **master password**: SSO replaces the login step, not the vault's encryption key. Keep it LAN/VPN-only as it is. ⚠️ Verify the `SSO_*` settings in Vaultwarden's wiki page "Enabling SSO support using OpenId Connect" | gate | Medium |
| | ↳ **Proxmox VE and PBS** | Datacenter → Permissions → Realms → Add → OpenID Connect. Keep the `pam` login as the fallback, and never let the only admin depend on the gate being up (the gate is a VM on that same Proxmox) | Proxmox, SGIN | Medium |
| | ↳ Not worth it / not possible | **Jellyfin** (0.2). **Navidrome** already trusts Authelia's header (`Remote-User`), which is better than OIDC there. **Uptime Kuma, Homepage, MeTube, Dozzle** have no OIDC and stay behind Authelia's forward auth, as they are now. **Home Assistant** has no built-in OIDC; community add-ons exist but would add a second login screen | — | — |
| 2.5 | **CrowdSec on the gate** (C-3 #21) **with the Authelia and nginx collections** | When you add it, include `crowdsecurity/authelia` alongside the nginx parsers, so someone guessing passwords at `gate.` gets banned at OPNsense, not just locked out for an hour by `regulation` | gate | Medium |

---

## 3. Jellyfin plugins and clients

Install from Dashboard → Plugins → Catalog. Plugins from outside repositories need the repository URL added first (Dashboard → Plugins → Repositories). **Before any of these, decide 0.1:** on 12.x, install only builds that say they're for 12.

| What | Why it fills a gap | Repo | Effort |
|---|---|---|---|
| **OpenSubtitles** | Downloads missing subtitles (per-library or on demand from the player's subtitle menu). It covers the Bazarr gap that containers.md skipped, since there's no Sonarr/Radarr. Needs a free opensubtitles.com account (the free tier has a daily download limit) | Official | Easy |
| **TMDb Box Sets** | Groups movie series into collections on its own (all the Alien films, all of Pixar's Toy Story) | Official | Easy |
| **Fanart** | Adds logos, clear art and banners. Jellyfin's themes and the TV apps' home rows look much better with logos | Official | Easy |
| **Webhook** | Sends Jellyfin events (playback started/stopped, new item added, login failed) as HTTP posts. Point it at **ntfy** ("Rachel started *Dune*", "3 failed logins on tv.") and at **Home Assistant** (dim the living-room lights when a movie starts, part 10) | Official | Easy |
| **Intro Skipper**, **Playback Reporting** | Already in C-3 (#28, #29). Intro Skipper is third-party, so wait for its 12.x build | Third-party / official | Easy |
| **Jellyfin Enhanced** (`n00bcodr`) | Extras for the **web** player: keyboard shortcuts, subtitle styling, TMDB and user ratings and reviews, a release calendar, bookmarks and a pause screen. Builds exist for both 10.11 and 12.x. Leave its Seerr/Sonarr parts off (you don't run them). Repository: `https://raw.githubusercontent.com/n00bcodr/jellyfin-plugins/main/manifest.json` | Third-party | Easy |
| **Home Screen Sections** + **File Transformation** (`IAmParadox27`) | "Because you watched…", genre rows and "Latest in Shows" sections on the web home page. Web client only. ⚠️ Verify a 12.x build before installing | Third-party | Easy |
| **Trakt** | Only if you or friends use Trakt. It syncs watched history out, so a rebuild never loses it | Official | Easy |
| A **theme** (custom CSS, e.g. ElegantFin or Ultrachromic) | It's "Custom CSS" item 3 in the overview's future projects. Dashboard → General → Custom CSS, one `@import` line. Web and the Android app only; Roku/Apple TV ignore it | — | Easy |

**Clients worth knowing** (no server change): **Jellyfin Desktop / Jellyfin Media Player** on the-box and the-spire (direct-plays almost everything, so the SGIN doesn't transcode). **Findroid** or the official app on the S21. **Streamyfin** (Android/iOS, with offline downloads) is the newer alternative. ⚠️ Verify it supports 12.x. **Swiftfin** or **Infuse** on Apple TV (part 3.8c).

---

## 4. The public side ("Cobra Island")

| # | What | Why it fills a gap | Where | Effort |
|---|---|---|---|---|
| 4.1 | **DNS hygiene at Porkbun**: DNSSEC on; a **CAA** record (`0 issue "letsencrypt.org"`); and either the mail relay's **SPF/DKIM/DMARC** records (if you do 2.1 with `@songofeo.com`), or "this domain sends no mail" records: `TXT v=spf1 -all`, `_dmarc TXT v=DMARC1; p=reject;` and a null MX (`MX 0 .`) | Today anyone can send spam "from" `@songofeo.com`, and any certificate authority may issue for it. These records cost nothing and take ten minutes. DNSSEC is a toggle on Porkbun's domain page. ⚠️ Verify with `dig CAA songofeo.com @1.1.1.1` afterwards. CAA must also allow the issuer Porkbun's own hosting uses for the bare `songofeo.com` and `www`, or that site's certificate stops renewing: check which issuer its current certificate shows before adding CAA | Porkbun | Easy |
| 4.2 | **Security headers and a `security.txt`** | Run `tv.`, `gate.` and `scores.` through Mozilla's **HTTP Observatory** and fix what it lists: usually `Referrer-Policy`, `X-Content-Type-Options`, `Permissions-Policy` and `frame-ancestors`. Add them once in the shared http block of `songofeo.conf`. Watch the `add_header` inheritance trap the manual already describes for `station-cors.inc`. `/.well-known/security.txt` is one static file with your contact address | gate (nginx) | Easy |
| 4.3 | **Uptime Kuma public status page** | Uptime Kuma has Status Pages built in. Make one ("Cobra Island status") with only the public things (Cinema, radio, scores), then add an Authelia **bypass rule for just those paths** on `status.`: `resources: ['^/status/cobra', '^/api/status-page/', '^/assets/', '^/upload/']`. The dashboard and settings stay behind TOTP. ⚠️ Verify the exact paths in the browser's network tab | gate | Easy |
| 4.4 | **GoatCounter** (`ghcr.io/arp242/goatcounter`, ~30 MB, SQLite) | Visitor counts for the station and public pages, with no cookies and no cookie banner. Lighter than Umami or Plausible, which need Postgres or ClickHouse. One `<script>` line in the Project-Eo pages | gate | Medium |
| 4.5 | **OPNsense GeoIP alias** on the 443 forward | Firewall → Aliases → GeoIP (free MaxMind licence key). Allow 443 only from the countries your friends live in. That removes most scanner noise before it reaches nginx. Downside: a friend travelling abroad gets nothing. WireGuard is unaffected (separate rule) | OPNsense | Medium |
| 4.6 | **Anubis** (bot challenge in front of a site) | Only **if** the nginx logs ever show AI scrapers hammering a public page. It makes browsers solve a small proof-of-work, which **breaks the TV and phone apps**, so never put it in front of `tv.` or any app's API. Listed so you know it exists | gate | Medium |
| 4.7 | **Listmonk** (newsletter, Postgres) | Only if Song of Eo wants a mailing list ("new episode of the podcast", "radio show tonight"). Needs 2.1 and 4.1 done first, or mail lands in spam | gate | Medium |

---

## 5. Business and production

### 5.1 Paperless-ngx extras (the business paperwork)

| What | Why | Where | Effort |
|---|---|---|---|
| **Mail rules** (Mail → Mail accounts / Mail rules, built in) | Paperless checks a mailbox over IMAP and files the attachments: forward an invoice email, and it shows up in Paperless, tagged. A dedicated mailbox is cleanest | inside Paperless | Easy |
| **Tika + Gotenberg** (`apache/tika`, `gotenberg/gotenberg`; `PAPERLESS_TIKA_ENABLED=1`) | Without them Paperless only reads PDFs and images. With them it also takes Word, Excel, LibreOffice and `.eml` files. Together about 400–600 MB, on a gate that's already the tight box: check `free -h` first | gate | Medium |
| **A phone app**: Swift Paperless (iOS), or Paperless Share / a maintained Android client | Snap a receipt and it uploads with tags. ⚠️ Verify which Android client is still maintained; the old "Paperless Mobile" app stalled | phone | Easy |
| **paperless-gpt** or **paperless-ai** | Automatic titles, tags and correspondents from an AI model. Only with a local model (Ollama on the-box's RTX 3070) or a paid API, and remember it reads every document. Optional | the-box + gate | Hard |

### 5.2 Podcasts and audio production (`sessions`)

| What | Why | Where | Effort |
|---|---|---|---|
| **Audiobookshelf's own RSS feeds** | Your recorded podcasts currently live in a Navidrome instance, which is a music player. Audiobookshelf can host them as a **podcast library**, and any item or podcast can be published with **Open RSS Feed**. You get a public feed URL (`/feed/<slug>`) that Apple Podcasts, Pocket Casts or AntennaPod can subscribe to. For the public, add an Authelia bypass for `^/feed/` on `books.` only. ⚠️ Verify the path on your version. Keep the Navidrome `sessions` instance if you also want them in the music apps | inside Audiobookshelf | Easy–Medium |
| **Recording and editing on the-box** (Audacity, Reaper or OBS) writing straight into the `sessions` share | No server change: a mapped drive to `\\cobra-stream\media\dock1a\sessions`, so a finished episode is in the library without a copy step | the-box | Easy |

### 5.3 New apps for running a business

None of these exist in the build or in containers.md. Pick only what you'd actually use. Each is a gate app behind Authelia unless noted.

| App | What it does | Why it fills a gap | RAM | Effort |
|---|---|---|---|---|
| **Forgejo** (`codeberg.org/forgejo/forgejo`) | Your own Git server (a self-hosted GitHub) | This repo is private, so the gate **can't `git clone` it** and you've been moving tarballs through project files. Forgejo can **pull-mirror** the GitHub repo every hour with a read-only token, and then `git pull` works on the gate and SGIN from the LAN. It's also the home for OPNsense's config backup (6.5) and any Song of Eo code | ~150–250 MB | Medium |
| **Gokapi** (`f0rc3/gokapi`) | Share a file by link, with an expiry and a download limit | Send a client or collaborator a big render, a podcast master or a contract without Google Drive. Uploads are admin-only (behind Authelia); the **download** path needs its own bypass rule. **Pingvin Share**, the usual pick, was archived in 2025; **Palmr** is a heavier alternative | ~30 MB | Medium |
| **DocuSeal** (`docuseal/docuseal`) | Sign PDFs online (a self-hosted DocuSign) | Guest releases for the podcast, contracts, permission slips. The signer gets an emailed link (needs 2.1) | ~200–300 MB | Medium |
| **Vikunja** (`vikunja/vikunja`) | Tasks, kanban boards, due dates, shared lists | Plans for the station and the shops, and a family to-do list. Has OIDC (2.4) and CalDAV | ~50–100 MB | Medium |
| **Invoice Ninja** or **InvoiceShelf** | Quotes, invoices, payments, clients | Only if the shops bill people. Invoice Ninja is the full product but heavy (PHP + MySQL, 500 MB+). InvoiceShelf is lighter. ⚠️ Verify InvoiceShelf's release activity before choosing | 200–600 MB | Medium–Hard |
| **IT-Tools** and **Excalidraw** | A browser toolbox (converters, QR codes, hash and JWT tools, password generator) and a whiteboard for sketching layouts and floor plans | Static pages, no database, no data kept on the server. Handy while designing the Song of Eo floors | ~20 MB each | Easy |

---

## 6. Health, alerts and backups (the glue)

| # | What | Why it fills a gap | Where | Effort |
|---|---|---|---|---|
| 6.1 | **Point everything at ntfy** (C-2 #3, once it exists) | Proxmox VE and PBS have a **Webhook** notification target (Datacenter → Notifications → Add → Webhook). **Uptime Kuma** has an ntfy notification type. **Jellyfin** uses the Webhook plugin (section 3). **smartd** can run a script that `curl`s ntfy (`-M exec` in `/etc/smartd.conf`). **Backrest** has hooks. **OPNsense** Monit (Services → Monit) sends mail, or runs a script that posts to ntfy. One app on the phone shows it all | everywhere | Easy each |
| 6.2 | **Home Assistant's ntfy and Uptime Kuma integrations** (part 10) | HA can show the station's status on its dashboard and turn a light red when something is down | cobra-home | Easy |
| 6.3 | **etckeeper** (`sudo apt install etckeeper`) | Puts `/etc` in a local Git repository and commits on every `apt` run (plus `sudo etckeeper commit "…"` by hand). `git -C /etc log -p fstab` shows who changed what, and a bad change can be reverted. The `fstab` with 8 stacked lines would have been obvious | gate, SGIN, Proxmox host | Easy |
| 6.4 | **Vaultwarden file-level backup** | The nightly VM backup catches it, but restoring one SQLite file from a VM image is slow. A daily `sqlite3 db.sqlite3 ".backup '/srv/gate/backup/vw-$(date +%F).sqlite3'"` (or the `ttionya/vaultwarden-backup` container, which also zips attachments with a password) into a folder Backrest sends off-site. A copy of the vault outside the house is the one thing you'd need if the house were gone | gate | Easy |
| 6.5 | **OPNsense Git backup** (`os-git-backup` plugin; System → Configuration → Backups → Git) | Every change to the firewall becomes a commit, pushed to a Git repo (Forgejo, 5.3). You see exactly which rule changed when WireGuard broke. The legacy port forwards you found disabled on 5 Nov would have had a history. Also worth having: the built-in **Google Drive** backup on that page, as a second copy | OPNsense | Easy |
| 6.6 | **Pi-hole threat lists**: HaGeZi **Threat Intelligence Feeds** and **Multi Pro** (or OISD Big) | Cobra1 contacted three suspicious domains on 4 Nov (CyberSecure caught them on the Xfinity side). These lists block known malware, phishing and scam domains for every cobra device, not just ads. Add them on Pi-hole #1 only; nebula-sync (C-3 #19) copies them to #2 | both Pi-holes | Easy |
| 6.7 | **vnStat** (`os-vnstat` on OPNsense) | Counts traffic per day and month on the WAN. Xfinity has a monthly data cap, and remote streaming, Speedtest Tracker (C-3 #24) and Backrest's first upload all eat into it | OPNsense | Easy |
| 6.8 | **A small UPS + NUT** (`os-nut` on OPNsense, `nut` on the SGIN) | The Latitude and the SGIN have batteries, but the **USB drives, the hub and the switch don't**. A power blip mid-write is the classic way an ext4 drive gets hurt. A ~600 VA UPS (about $60–90) on the hub, drives and switch, and NUT tells the machines to shut down cleanly | hardware + OPNsense/SGIN | Medium |
| 6.9 | **Cockpit add-ons**: `cockpit-podman` (C-1), **cockpit-files** (file browser), and 45Drives' **cockpit-file-sharing** (manage Samba shares and users from the browser) | Fewer SSH sessions for routine jobs: restart a container, look in a folder, reset the gate's Samba password (which you did by hand on 6 Nov). ⚠️ Verify that cockpit-files is packaged for Debian 13 and that 45Drives' package installs on it | SGIN, gate | Easy |
| 6.10 | **Lynis** (`sudo apt install lynis`, then `sudo lynis audit system`) | A free security audit of each Debian box: it lists weak SSH settings, missing hardening and stale packages, with a score to beat next time. Run it once now and again every few months; it changes nothing on its own | gate, SGIN | Easy |
| 6.11 | **Vaultwarden push notifications** (`PUSH_ENABLED`, `PUSH_INSTALLATION_ID`/`KEY` from bitwarden.com/host) | Without them, the phone's Bitwarden app only picks up a new password at its next periodic sync. With them it syncs at once. Free. The relay only carries a "sync now" ping, never your data | gate | Easy |

---

## 7. Library extras (books, comics, music, arcade)

| What | Why | Where | Effort |
|---|---|---|---|
| **Navidrome plugins** (0.60, Feb 2026) | Navidrome now runs sandboxed WebAssembly plugins for new metadata sources and integrations. **AudioMuse-AI** can feed its Instant Mix with sound-alike recommendations. Each of the four instances has its own plugin settings. ⚠️ Verify which plugins exist when you look; the catalog is young | inside each Navidrome | Easy–Medium |
| **ListenBrainz or Last.fm scrobbling** (built in, per user) | Your listening history outside the server, and better Instant Mix suggestions | inside Navidrome | Easy |
| **Synced lyrics**: **LRCGET** on the-box | Scans a music folder over the share and saves `.lrc` files from LRCLIB next to each track. Navidrome and Symfonium/Feishin then show karaoke-style lyrics | the-box | Easy |
| **Smart playlists** (`.nsp` files in the music folder) | "Rachel's top 100 this year" or "never played" playlists that update themselves, with no app needed | inside Navidrome | Easy |
| **Music clients**: Symfonium (Android, paid, best), Tempo/Tempus (Android, free), Feishin (desktop), Amperfy or play:Sub (iOS) | Navidrome's web player is fine, but these do offline downloads, car mode and Android Auto | phone, the-box | Easy |
| **Mihon** (Android) **with its Kavita extension**, or **Paperback** (iOS) | A proper manga and comic reader app on the phone, reading straight from Kavita | phone | Easy |
| **KOReader sync / OPDS** to Kavita or Audiobookshelf | If anyone reads on a Kobo or KOReader device. ⚠️ Verify Kavita's KOReader sync on your version. Calibre-Web Automated (C-1) is the full answer if e-readers become a big thing | e-reader | Easy |
| **Komf** (`sndxr/komf`) | Fetches series metadata and covers for Kavita from MangaUpdates, AniList, Comic Vine and others, so the comics shelf stops showing file names. ⚠️ Verify its current Kavita support | SGIN | Medium |
| **RomM metadata keys**: IGDB (via a free Twitch developer app), ScreenScraper, SteamGridDB, and **RetroAchievements** | RomM fills in box art, descriptions and achievements only with these keys. Set them while building the arcade (env vars in the RomM Quadlet). They're free accounts | SGIN (RomM) | Easy |
| **RetroAchievements in RetroArch on the cabinet** | Same account as above: achievements and "hardcore mode" in hundreds of retro games. It pairs well with the hiscore board | cabinet | Easy |

---

## 8. Apps for the phone and desktops (checklist)

Nothing to install on the servers. This is the client side that makes the server pay off.

| Device | Apps |
|---|---|
| **S21** | WireGuard (two profiles: away, and home via `10.0.0.2:51820`) · Bitwarden (server `https://vault.songofeo.com`, works on WireGuard/LAN) · Aegis or 2FAS (TOTP) · ntfy · Jellyfin or Findroid · Symfonium or Tempo · Audiobookshelf · Mihon + Kavita · Home Assistant · a Paperless app · Moonlight (the cabinet, C-3 #25) |
| **the-box / the-spire** | Jellyfin Desktop · Feishin · Bitwarden desktop app + browser extension · LRCGET · MusicBrainz Picard (C-2 #11, desktop version) · Moonlight |
| **Cobra1** | WireGuard · Bitwarden · Jellyfin Desktop. **First:** the malware scan noted on 5 Nov (Microsoft Defender Offline scan, then Malwarebytes free) before it joins the cobra network in earnest |

---

## Skipped on purpose (this pass)

- **Jellyfin SSO plugin**: dead, see 0.2.
- **Authentik, Keycloak, Pocket ID**: Authelia already does OIDC (2.4); a second identity system means two user lists.
- **Zenarmor** (OPNsense): it wants more RAM than the 4 GB firewall VM has to spare, and Suricata plus CrowdSec already cover IPS.
- **ntopng**: heavy for the firewall VM. vnStat (6.7) answers "how much did we use".
- **Nextcloud** (again): Forgejo, Gokapi, Syncthing, Paperless and Immich cover the parts you'd use, at a fraction of the weight.
- **Grafana + Prometheus + Loki**: Beszel (C-2 #5), Dozzle (C-3 #23) and Uptime Kuma cover a home station at about a tenth of the RAM.
- **AzuraCast**: the radio (part 8) already works with Icecast and Liquidsoap, and AzuraCast would replace both with a much heavier stack.

## Sources

- Jellyfin 12: [JellyWatch, "Jellyfin 12.0 is here"](https://jellywatch.app/blog/jellyfin-12-release-everything-you-need-to-know), citing [Jellyfin's release post](https://jellyfin.org/posts/jellyfin-release-12.0) and [v12.0 release](https://github.com/jellyfin/jellyfin/releases/tag/v12.0); [AlternativeTo on 12.0](https://alternativeto.net/news/2026/9/jellyfin-12-0-adds-major-books-and-comics-support-faster-browsing-and-ffmpeg-8-1/)
- Jellyfin SSO plugin's end: [9p4/jellyfin-plugin-sso (archived 12 May 2026)](https://github.com/9p4/jellyfin-plugin-sso), [Flowfin fork, issue #1925 (archived 29 Sep 2026)](https://github.com/Flowfin/jellyfin-plugin-sso/issues/1925), [Jellyfin discussion on native OIDC](https://github.com/orgs/jellyfin/discussions/16470)
- Jellyfin plugins: [Jellyfin Enhanced](https://github.com/n00bcodr/Jellyfin-Enhanced), [Home Screen Sections](https://github.com/IAmParadox27/jellyfin-plugin-home-sections/wiki), [awesome Jellyfin plugins list](https://jellywatch.app/hub/awesome)
- Authelia: [4.39 release notes (passkeys)](https://authelia.com/blog/4.39-release-notes), [OIDC integration: RomM](https://www.authelia.com/integration/openid-connect/clients/romm/)
- Kavita OIDC: [Kavita wiki, OpenID Connect](https://wiki.kavitareader.com/guides/admin-settings/open-id-connect/)
- RomM OIDC: [RomM docs, OIDC with Authelia](https://docs.romm.app/4.7.0/OIDC-Guides/OIDC-Setup-With-Authelia/)
- Vaultwarden SSO: [1.35.0 release notes](https://newreleases.io/project/github/dani-garcia/vaultwarden/release/1.35.0)
- Navidrome plugins: [AlternativeTo on Navidrome 0.60](https://alternativeto.net/news/2026/2/navidrome-0-60-adds-webassembly-based-plugin-system-new-instant-mix-feature-and-more), [Linuxiac on 0.60](https://linuxiac.com/navidrome-0-60-music-server-and-streamer-released/)
- Proxmox notifications: [PVE docs, notifications (webhook target)](https://pve.proxmox.com/pve-docs/chapter-notifications.html)
- OPNsense Git backup: [OPNsense docs, Git backup](https://docs.opnsense.org/manual/git-backup.html)
- Audiobookshelf RSS feeds: [Audiobookshelf guide, RSS feeds](https://audiobookshelf.org/guides/rss_feeds)
- Pingvin Share archived: [stonith404/pingvin-share](https://github.com/stonith404/pingvin-share)
- Anubis: [Xe Iaso, "Block AI scrapers with Anubis"](https://xeiaso.net/blog/2025/anubis/)
