# Music, comedy and The Ward

**The plan (8 November 2026):** one Navidrome for all music, with a library per person. This
replaces the old rule of one Navidrome instance per collection (PR #46) and the Cobra N.A.V.
clones (PR #52), which are retired.

| Name | Goes to | Holds | Who |
|---|---|---|---|
| `music.songofeo.com` | Navidrome `navidrome`, SGIN `:4533` | library **Eels** `dock1a/music/eels` + library **Rachel** `dock1a/music/rachel` | eels (admin, sees every library) |
| `mustang.songofeo.com` | the **same** Navidrome `:4533` (an alias, so Rachel's bookmarks and app keep working) | Rachel's account only sees library **Rachel** | rachel |
| `comedy.songofeo.com` | Audiobookshelf `:13378`, library **Comedy** `dock1a/comedy` | stand-up albums | everyone you give it to |
| `sessions.songofeo.com` | Audiobookshelf `:13378`, podcast library **Sessions** `dock1a/sessions` | The Ward: your recorded podcasts | everyone you give it to |

Ports `4534` and `4535` stay free for comedy and sessions in case you'd rather keep them on
Navidrome (`TALK=navidrome` in both scripts below). `4536` and the clone slots `4537-4549` are no
longer used; nothing listens there, so the open firewall lines do no harm.

## Why one Navidrome is enough

Navidrome 0.58 added [multi-library support](https://www.navidrome.org/docs/usage/features/multi-library/):
the admin adds libraries in **Settings → Libraries**, then ticks which libraries each user may see in
**Settings → Users**. Admins see every library. Phone apps (Subsonic) only get the libraries that user
may see, and search, albums and artists are filtered the same way.

**Separate instances don't serve several people at once any better.** One Navidrome streams to
many listeners at the same time; playing a file is just reading it from dock1a. The work that costs
something, transcoding (one ffmpeg per stream that needs it) and scanning, costs the same whether it
runs in one container or four. On the SGIN's 12 GB, extra instances only add memory, a second file
watcher and scan over the same disk, and one more login and password per person. The one thing
separate instances still give is a separate database per person, so a bad upgrade or a broken scan
only hits one of them. Libraries already keep Rachel's music out of your shuffles and yours out of
hers, so that isn't worth four of everything.

Two rules from the Navidrome docs shape the layout:

- **Libraries may not overlap.** That's why the main library is `dock1a/music/eels` and not
  `dock1a/music`: with `dock1a/music` as one library, `music/rachel` couldn't be a second one.
- **A user sees whole libraries, not folders inside one.** Rachel can't be given just `eels/pop`.
  If you want that later, split `eels` into one library per genre (see the end of this page).

## Why Audiobookshelf for comedy and The Ward

Navidrome is built for songs: shuffle, albums, playlists. Talk audio wants other things, and
Audiobookshelf, already running on the SGIN for audiobooks, has them:

| | Navidrome | Audiobookshelf |
|---|---|---|
| Remembers where you stopped in a long track | no (only some phone apps, with bookmarks) | yes, per person, synced between web and phone |
| Playback speed, sleep timer, skip 30 s | no in the web player | yes |
| Played / unplayed per episode | no | yes (podcast libraries) |
| Publish a show as a podcast feed | no | yes (**Open RSS feed** on a podcast) so The Ward can be followed in any podcast app |
| Library per person | yes (0.58+) | yes (Users → Libraries) |
| Gate sign-in carries over | yes (`Remote-User`) | no, its own login (until the OpenID step on the checklist) |

Dedicated podcast servers (PodFetch, Podgrab and similar) are only RSS downloaders for other
people's shows, so they don't fit recordings you make yourself. Jellyfin has no resume-friendly
audio player. Audiobookshelf is the one to use: no new container, no new port.

The folders fit Audiobookshelf as they are:

- `dock1a/comedy/<Comedian>/<Album>/` → a **Book** library: comedian = author, album = book, tracks
  play in order and resume where you stopped.
- `dock1a/sessions/<Show>/<episode files>` → a **Podcast** library: each show folder is a podcast and
  each file an episode. Put the date at the start of each file name (`2026-11-08 Episode title.mp3`)
  so they sort.

## Switching over, step by step

Everything starts on **the-box**. Each block is one command; copy it on its own. The scripts are in
this repo under `scripts/oneshot/` (and in the project files under `navidrome/`); save them in your
Downloads folder first. Both back up everything they change, show the change, and the SGIN one asks
**y/N** before it stops anything.

### 1. SGIN: one Navidrome reading `music/eels`

On the-box, in **PowerShell**, in your Downloads folder: copy the script to the SGIN.

```powershell
scp .\sgin-music-one.sh eels@10.6.9.20:/tmp/
```

Still in PowerShell: log in to the SGIN. The prompt becomes `eels@cobra-stream`.

```powershell
ssh eels@10.6.9.20
```

On the SGIN as eels: run it. It asks for your sudo password, prints what it will do, and waits for `y`.

```bash
bash /tmp/sgin-music-one.sh
```

What it does: stops every Navidrome, saves their databases to `/srv/stream/navidrome-backup-<time>.tgz`,
changes `ND_MUSICFOLDER` in `navidrome.container` from `/media/dock1a/music` to
`/media/dock1a/music/eels`, retires `navidrome-rachel`, `navidrome-comedy` and `navidrome-sessions`
(stopped, Quadlet file moved to `~podsvc/.config/containers/retired-<time>/`, their data folders and
all music left alone), then starts `navidrome` again and waits for `:4533`. It ends with `OK :4533`.

Stars and play counts from the last few days in the main Navidrome may reset, because the songs get
new paths. Rachel's playlists from her old Navidrome don't move over. Both are in the backup.

### 2. the-box browser: the two libraries

Open `http://10.6.9.20:4533` and sign in as **eels**.

1. **Settings → Libraries**. Open **Library 1**: name it `Eels`, check that its path reads
   `/media/dock1a/music/eels` (change it to that if it still says `/media/dock1a/music`), untick
   **default for new users** if it's ticked, **Save**.
2. Click **+**: name `Rachel`, path `/media/dock1a/music/rachel`, leave **default for new users**
   unticked, **Save**. It scans on its own.
3. **Settings → Users**. If `rachel` is there, open her. If not, click **+** and make her now, user
   name `rachel` exactly as in Authelia's `users.yml`, with a password (her phone app uses it).
   Under **Libraries** tick only **Rachel**, **Save**.

Making her before she first opens the page means her account never sees your library, not even once.

### 3. Gate: point the names at it and put up the wall

On the-box, in a **new PowerShell window** (the first one is still on the SGIN): copy the gate script.

```powershell
scp .\gate-music-one.sh eels@10.6.9.10:/tmp/
```

Log in to the gate. The prompt becomes `eels@cobra-gate`.

```powershell
ssh eels@10.6.9.10
```

On the gate as eels: hand the script to podsvc.

```bash
sudo install -o podsvc -m 755 /tmp/gate-music-one.sh /home/podsvc/
```

Run it as podsvc. It prints both diffs, checks nginx and Authelia, and puts both files back if either
says no.

```bash
sudo machinectl shell podsvc@ /bin/bash /home/podsvc/gate-music-one.sh
```

What it does: `music.` and `mustang.` → `:4533`; `comedy.` and `sessions.` → Audiobookshelf `:13378`
(and lets the Audiobookshelf app in on those names); an Authelia wall so `eels`, `rachel`, and
anyone in the Authelia group `music` can open `music.` and `mustang.`. The wall matters because
Navidrome makes an account for anyone the gate signs in. A Jellyfin user is not on that wall:
`tv.` never asks Authelia, so the same person can open Jellyfin and get *forbidden* on music.
Put `groups: [music]` on their block in the Authelia users file (same username), then run this
script again. Listing people by name still works: `MUSIC_USERS="eels rachel"` in front of the
command. `MUSIC_GROUPS` defaults to `music`; set it empty only if you want the named users alone.

### 4. the-box browser: Comedy and Sessions in Audiobookshelf

Open `http://10.6.9.20:13378` and sign in as the Audiobookshelf root user.

1. **Settings → Libraries → Add Library**: name `Comedy`, media type **Book**, folder
   `/media/dock1a/comedy`, **Create**.
2. **Add Library** again: name `Sessions`, media type **Podcast**, folder `/media/dock1a/sessions`, **Create**.
3. **Settings → Users**: for each person, open them and under library access tick the libraries
   they may see (untick **Can access all libraries** first).

Optional, so the bare `comedy.` and `sessions.` addresses open their own library instead of the last
one you used: open the Comedy library, copy everything after `10.6.9.20:13378` in the address bar
(it looks like `/audiobookshelf/library/<long id>`), do the same for Sessions, and run step 3's
command again with them in front:

```bash
sudo machinectl shell podsvc@ /usr/bin/env COMEDY_SHELF=/audiobookshelf/library/PASTE SESSIONS_SHELF=/audiobookshelf/library/PASTE /bin/bash /home/podsvc/gate-music-one.sh
```

### 5. Check it

- [ ] the-box, private window: `https://music.songofeo.com` → gate sign-in → Navidrome as eels, with
      both libraries in the sidebar's library picker.
- [ ] Signed in as rachel (private window): `https://mustang.songofeo.com` shows only her music.
- [ ] Signed in as anyone who is not eels, rachel, or in the Authelia group `music`: `music.` and `mustang.` say *forbidden*.
- [ ] `https://comedy.songofeo.com` and `https://sessions.songofeo.com` open Audiobookshelf.
- [ ] On the gate as podsvc: `bash ~/cobra-server/scripts/oneshot/gate-sso-check.sh` (read-only).

## Phone apps

- **Music** (Symfonium or another Subsonic app): server `https://music.songofeo.com` (Rachel can use
  `https://mustang.songofeo.com`, same thing), the Navidrome username and the password from step 2.
  Accounts the gate made on its own have a random password: set one in **Settings → Users**.
- **Comedy and The Ward**: the Audiobookshelf app, server `https://books.songofeo.com` (or `comedy.`
  or `sessions.`, all the same server), the Audiobookshelf login. Pick the library at the top.

## Someone new

Add them to Authelia's users file on Gate 110 (manual 5.4). The repo's example calls that file
`/srv/gate/authelia/users.yml` because `configuration.yml` sets
`authentication_backend.file.path` to `/config/users.yml`. If the live line says
`/config/users_database.yml`, that host file is `/srv/gate/authelia/users_database.yml` instead.
It is not in git. Do not copy it into the repo: it holds password hashes.

On their block, add `groups: [music]` (keep any groups they already have). The username has to be
the one Navidrome will use, character for character.

Then run `gate-music-one.sh` again. That is the wall that gets applied on a live gate, and it writes
the same subject as manual 5.4: `group:music`, then deny. A wall written before 2026-11-09 lists
only `user:eels` and `user:rachel`. No new container, port, name or CNAME.

Open `https://music.songofeo.com` once in a browser as that person. Navidrome creates the row
on that page load, with a random password, and only the libraries marked default for new users.
Those two libraries are unticked, so the new row sees no music until you open **Settings → Users**
and tick their libraries. A phone app's `/rest/` path does not create the row. If Navidrome's log
says `Authenticated username not found in DB`, the web page was never loaded, or the header's
username is not the Navidrome username.

## A Jellyfin account that cannot open music

`tv.songofeo.com` has no `auth_request`. Jellyfin's own user table is the only lock, so a test
account created in Jellyfin's Dashboard opens TV without Authelia.

`music.songofeo.com` is forward-auth. Authelia's first matching rule for that name is the music
wall: `one_factor` for the listed subjects, then `policy: deny`. There is no missing
`music.songofeo.com` rule, and there is no Authelia group that includes TV. TV is not an Authelia
rule. The example users file has no `groups` at all, so a test account added the same way as the
manual's two people is signed in at the gate and then refused at music.

After the wall lets them through, nginx sets `Remote-User` and Navidrome accepts it only from
`10.6.9.10` (`ND_EXTAUTH_TRUSTEDSOURCES`; the old `ND_REVERSEPROXYWHITELIST` still maps to that).
The check on the gate is [gate-sso-tv-runbook.md](gate-sso-tv-runbook.md).

## Later: share some of your genres with Rachel

Because a user sees whole libraries, giving Rachel `pop` and `soundtracks` means making each genre
its own library: `/media/dock1a/music/eels/pop`, `/media/dock1a/music/eels/soundtracks` and so on,
nine in all, plus `Rachel`. Library 1 then has to be one of those genres (libraries can't overlap),
so `ND_MUSICFOLDER` would point at, say, `.../eels/blues-jazz`. You'd tick genres per person on
the Users page, which does what the N.A.V. switchboard did, at genre level. Ask Claude when you want it.

## Undo

- SGIN: the script prints its backup names. Copy `~podsvc/.config/containers/systemd.bak-<time>` back
  over `systemd`, restore `/srv/stream/navidrome-backup-<time>.tgz` with `sudo tar -C / -xzpf`, then
  as podsvc `systemctl --user daemon-reload` and start the Navidromes.
- Gate: copy `songofeo.conf.bak-<time>` and `configuration.yml.bak-<time>` back, restart Authelia,
  reload nginx.
