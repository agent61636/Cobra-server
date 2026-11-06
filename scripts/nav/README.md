# Cobra N.A.V.s: one walled-off Navidrome per person, one shared music folder

Every N.A.V. is its own Navidrome with its own users, playlists, favourites and play counts. They all
read the one music folder on the SGIN, `dock1a/music`, and nothing is ever copied. A N.A.V. only sees
the folders you switch on for it, and each one is mounted **read-only**, so no N.A.V. can change or
delete a song.

```
dock1a/music/
  eels/                       the central collection
    blues-jazz/ classical-folk/ electronica/ hip-hop/ metal/
    new-age/ pop/ soundtracks/ techno-industiral/
      <artist>/<album>/
  rachel/                     Rachel's own uploads
```

You switch folders on in one file, the **switchboard** (`/srv/stream/navs/switchboard.conf`):

```ini
[rachel]
port = 4535
host = mustang
on = rachel
on = eels/pop
on = eels/soundtracks/John Williams
```

`on` takes a genre, an artist or an album folder (paths as they are under `dock1a/music`, capitals and
spaces exactly as on disk). `on = *` is the whole collection (your own N.A.V., `music.`). Inside every
N.A.V. a folder keeps its real path, so a song has the same path everywhere.

| Script | Where, as whom | What |
|---|---|---|
| `nav-vat.sh` | SGIN, eels, **once** | opens the clone slots 4537-4549 (firewall + `stream.pod`), asks before the one pod restart |
| `nav.sh` | SGIN, podsvc | `./nav.sh` lists every N.A.V. and checks its folders; `./nav.sh build NAME` (re)builds one and restarts it |
| `gate-nav.sh` | gate, podsvc, once per N.A.V. | `HOST.songofeo.com` → its port, the VIP keypad entry, and the **wall**: only that person and eels may open it |

All three back up what they change first. `nav.sh` shows the change to an existing N.A.V. and asks before
replacing it; `gate-nav.sh` puts both gate files back if nginx or Authelia rejects them.

## Why the wall matters

Navidrome makes an account for whoever the gate says is signed in. Without the Authelia rule that
`gate-nav.sh` adds, any friend with a gate login who opens `mustang.` would get an account in Rachel's
N.A.V. With it, everyone but Rachel and you is refused. Run it for your own N.A.V. too, because
`music.` sees everything: `bash gate-nav.sh music 4533 eels`.

## Switching folders on or off later

Edit the switchboard, then `./nav.sh build NAME`. Only that N.A.V. restarts (a few seconds) and rescans.
Songs from a folder you switched off show up under Navidrome's **Missing Files** page (admin menu),
where you can remove them; switching the folder back on brings them back with their play counts.

## First visit

The first person to open a new N.A.V. through the gate becomes its admin. Have the owner open it first,
or open it yourself first if you want to be admin of every N.A.V.

## Phone apps (Symfonium and other Subsonic apps)

Apps can't show the gate's sign-in, so they talk to Navidrome's own `/rest/` API with a Navidrome
password. An account made through the gate gets a random password, so give each person a real one once:
in that N.A.V., **Users** (admin menu) → the person → **Change password**. In Symfonium, add a
Subsonic/Navidrome server with `https://HOST.songofeo.com`, that username and that password.
The gate must let `/rest/` through without its sign-in and without a `Remote-User` header (the gate
thread handles that); the wall still covers the web pages, and `/rest/` always needs the password.
