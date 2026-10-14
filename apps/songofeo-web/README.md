# songofeo.com (public homepage)

The homepage at the bare `songofeo.com`, served by **Porkbun Static Hosting**. It's plain files: no build step, no server code.

```
index.html          the station scene (title, Cinema, Radio, Arcade, the rave ship)
cinema/index.html   sends visitors on to https://tv.songofeo.com     (Jellyfin)
radio/index.html    sends visitors on to https://music.songofeo.com  (the radio)
arcade/index.html   sends visitors on to https://arcade.songofeo.com (RomM / EmulatorJS)
music/              audio for the rave-ship playlist (only tracks you may play publicly)
```

## How the sign-in works

The homepage itself is public and holds nothing private. A static page can't check a password, so it doesn't pretend to. Each bay links to `songofeo.com/cinema` (or `/radio`, `/arcade`), which forwards to the app's own hostname at home. There, **Authelia** asks for the username and password before anything loads (part 5 of the manual). That login is the real lock.

## Upload to Porkbun

1. Porkbun → Domain Management → `songofeo.com` → **Static Hosting** (or Web Hosting → File Manager).
2. Upload the contents of this folder, keeping the folders: `index.html` at the top, then `cinema/`, `radio/`, `arcade/` and `music/` with their files.
3. Open `https://songofeo.com`. The eyes open on the station. Each bay pops out when you hover and goes to `/cinema/`, `/radio/` or `/arcade/`.

## DNS: keep the homepage and the home server apart

- The bare `songofeo.com` (and `www`) belong to Porkbun's hosting. Don't change those records.
- Your home IP lives on **`gate.songofeo.com`**, kept current by OPNsense's dynamic DNS (manual 2.10).
- Every app name is a CNAME to `gate.songofeo.com`: `tv`, `music`, `radio`, `arcade`, `auth`, `scores` and the rest (manual 5.5, 7, 8.3).

## Adding music to the rave ship

Copy audio you have the rights to play publicly into `music/`. Then edit the `PLAYLIST` list near the bottom of `index.html`:

```js
const PLAYLIST = [
  { title: "Track name", artist: "Artist", src: "music/track.mp3", note: "Licensed under CC BY 4.0" },
];
```

Re-upload `index.html` and the audio files.

## The artwork

Every drawing is original SVG in `index.html`: the planets, the station, the people (generic silhouettes in their Color), the Howler-style wolf banners and the station crest. No book covers, film stills, game sprites or trademarked logos are used. The crest in the G.I. Joe Cobra logo's spot is an original design; swap in other art only if you have the rights to it.
