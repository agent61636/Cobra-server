# The Commander's checklist

Everything still to do across Cobra and the Song of Eo, in order. Each line links the manual
section, script or pull request that has the steps. Tick a box (edit this file on GitHub) when
it's done. Work on the-box first; the phone is only for scanning codes and cellular tests.

## 1. Auth SSO: one sign-in at the concourse

- [ ] **One sign-in for everyone, at home too**: no home bypass, one-month Remember me. Run
      [`scripts/oneshot/gate-signin.sh`](../scripts/oneshot/gate-signin.sh) on the gate as podsvc
      ([how](../scripts/oneshot/README.md)). Then open `https://music.songofeo.com` in a private
      window on the-box, sign in with Remember me ticked, and Navidrome opens as you.
      Background: [manual 5.4](manual/05-final-touches.md#54-gate-pod-as-podsvc-sudo-machinectl-shell-podsvc), PR #53.
- [ ] **Phone apps past the gate** (Symfonium/Subsonic, Audiobookshelf, Kavita, RomM, Paperless),
      plus Remote-Name/Remote-Groups for the profile picture: run
      [`scripts/oneshot/gate-apps.sh`](../scripts/oneshot/gate-apps.sh) on the gate as podsvc.
- [ ] **Navidrome passwords**: accounts the gate made have random passwords. Set a real one once
      on Navidrome's Users page, then sign in from Symfonium
      ([music.md, Phone apps](music.md#phone-apps)).
- [ ] **Home Wi-Fi without WireGuard** (OPNsense answers DNS for the Xfinity side with 10.0.0.2):
      in OPNsense, Unbound host overrides for the app names → `10.0.0.2` (never a `*.songofeo.com`
      wildcard), Unbound listening on WAN, a WAN pass rule for TCP/UDP 53 **from 10.0.0.0/24 only**,
      then phone static IP + DNS 10.0.0.2 on Electronomicon and Cobra1's Wi-Fi DNS 10.0.0.2.
      Walkthrough is live, step by step. Undo when the access point arrives
      ([manual 2.10b](manual/02-networking.md#210b-trusted-wi-fi-access-point-on-the-switch)).
- [ ] **VIP keypad**: Porkbun CNAME `vip` → `gate.songofeo.com`, then the gate's nginx `vip.` block
      ([manual 5.4](manual/05-final-touches.md#54-gate-pod-as-podsvc-sudo-machinectl-shell-podsvc), PR #50).
- [ ] **Profile picture and Bay bar** (Project-Eo PR #37): merge it, then put its `eo_art.py` on the
      gate with [`scripts/oneshot/gate-eo-art.sh`](../scripts/oneshot/gate-eo-art.sh) (that script
      also adds the Comedy Bay's cover wall).
- [ ] **Single sign-on into the apps' web pages** (Authelia as OpenID Connect provider: Jellyfin
      SSO plugin, Audiobookshelf, Kavita, RomM). To be written.

## 2. Music, comedy and The Ward

One Navidrome with a library per person; comedy and sessions in Audiobookshelf. Walkthrough:
[docs/music.md](music.md) (replaces the four Navidromes and the N.A.V. clones).

- [ ] SGIN: [`scripts/oneshot/sgin-music-one.sh`](../scripts/oneshot/sgin-music-one.sh) as eels
      ([music.md step 1](music.md#1-sgin-one-navidrome-reading-musiceels)).
- [ ] the-box: Navidrome libraries **Eels** and **Rachel**, and Rachel's user with only hers ticked (step 2).
- [ ] Gate: [`scripts/oneshot/gate-music-one.sh`](../scripts/oneshot/gate-music-one.sh) as podsvc (step 3).
- [ ] the-box: Audiobookshelf libraries **Comedy** (Book) and **Sessions** (Podcast) (step 4).
- [ ] Genre stations for the boombox: Navidrome smart playlists (one per genre, scoped to library Eels).

## 3. Jellyfin

- [ ] Known proxies `10.6.9.10` ([manual 3.8](manual/03-sgin.md#38-media-pod)).
- [ ] Friends' Jellyfin users (only Eels exists).
- [ ] Stutter fixes on big files ([manual 3.8c](manual/03-sgin.md#38c-if-some-movies-stutter)).
- [ ] Pin the Jellyfin image to the current 10.x release before v12 lands, so an auto-update
      can't break plugins (`AutoUpdate=registry` in `jellyfin.container`, [manual 3.8](manual/03-sgin.md#38-media-pod)).

## 4. Storage

- [ ] wd1 copy-back and checks (E3), `mv series shows`, then the Seagate → vault, the video pool and
      dock1a/dock1b ([manual 3.4r](manual/03-sgin.md#34r-recover-wd1-onto-the-seagate-24-tb-maximum-safety),
      [3.4](manual/03-sgin.md#34-storage)).
- [ ] Sort dock1a's photorec music by tags; delete the spare images once you're sure.
- [ ] Make the Seagate the backup target ([manual 5.6](manual/05-final-touches.md#56-backups)).

## 5. Network and devices

- [ ] Cobra1 laptop: WireGuard peer ([manual 2.8](manual/02-networking.md#28-wireguard-remote-admin))
      and a malware scan (it hit suspicious domains on 11/4).
- [ ] Disable the old rule on the assigned `WG` interface (the WireGuard (Group) rule is the one that works).
- [ ] The trusted Wi-Fi access point, TP-Link EAP772 + PoE injector
      ([manual 2.10b](manual/02-networking.md#210b-trusted-wi-fi-access-point-on-the-switch)), then harden home Wi-Fi back up.

## 6. Arcade and cabinet

- [ ] Paste `00-status` and `03-roms-map` output from the OptiPlex
      ([arcade runbook](arcade-runbook.md), PR #51 for LaunchBox folder names).
- [ ] RomM up on the SGIN ([runbook 5](arcade-runbook.md#5-sgin-start-romm-the-box)), then the
      nightly ROM copy, LaunchBox, LED-Wiz and marquee ([manual 4](manual/04-optiplex.md),
      [manual 11](manual/11-extra-bling.md)).

## 7. Library and Game Cellar Bays

- [ ] Library Bay split: Audiobookshelf (LISTEN) and Calibre-Web Automated at `ebooks.` (READ).
- [ ] RPG books in their own Kavita for the Game Cellar (`gaming.`), and Foundry if you want a
      table of your own besides Roll20 ([library and gaming bays](future-builds/library-gaming-bays.md)).

## 8. Housekeeping

- [ ] First-run admins on `status.` (Uptime Kuma), `books.` and `comics.` if not done yet.
- [ ] Manual: the Quadlet-vs-scripts note (the gate runs the manual's Quadlets).
- [ ] Check the old "stage 0/1 guides" and "SSH denied at step 1.7" threads for anything still open.

## 9. Last: the Claude-Viper form submission extension

- [ ] Our own form service for both **hailcobra.com** and **songofeo.com** (replacing FormSubmit
      for Seek Council's petitions and Hail-Cobra's forms). Being built in the "Build our own form
      submission service" thread.
