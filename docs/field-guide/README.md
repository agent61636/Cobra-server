# Claude-Viper's Visual Field Guides Present: You and Your Pod!

A retro game-magazine guide to every container on Cobra Island: how each one works, tips and tricks, and the traps we hit while building them.

- **Read it:** [`you-and-your-pod.pdf`](you-and-your-pod.pdf) (print or phone), or [`you-and-your-pod.html`](you-and-your-pod.html) (one self-contained file; open it in any browser, works offline).
- **World 1, The Gate** (`cobra-gate`, 10.6.9.10, pod `gate`): nginx, Authelia, Vaultwarden, Paperless, Postgres, Redis, MeTube, Homepage, Uptime Kuma, hiscore, eo-art.
- **World 2, The Stream** (`cobra-stream`, 10.6.9.20, pod `stream`): Jellyfin, ErsatzTV, one Navidrome (music. and mustang., a library per person), Audiobookshelf (also comedy. and sessions.), Kavita, RomM, its MariaDB, Icecast, the Liquidsoap radio.
- **Bonus stage:** the two Pi-holes. **Extras:** secret codes pages for both worlds, letters, back cover.

## Editing and rebuilding

Each chapter is one file in [`pages/`](pages/), named so they sort in reading order (`00-front`, `10-gate-*`, `20-stream-*`, `80-bonus-*`, `90-back`). A page is a `<section class="page theme-…">`; the first page of a chapter carries `data-toc="Title|Subtitle"` and `data-tocgroup="gate|stream|bonus|back"`, which builds the contents page. The boxes (`.tip`, `.trap`, `.codes`, `.intel`, `.stats`, `.panel`, `.levelmap`, `.viper`) are defined in [`style.css`](style.css). Pixel art is drawn as text: shared sprites live in [`sprites.mjs`](sprites.mjs), and a page can draw its own with `<pre class="sprite" data-px="6">` (one letter per pixel, `.` for transparent, colours from the palette in `sprites.mjs`).

```bash
node docs/field-guide/build.mjs
```

That writes the HTML and PDF next to this file and checks that every page fits its sheet (it lists any page whose content is too tall or sticks out). It needs Node and Playwright with Chromium (`npm i -g playwright && npx playwright install chromium` on a machine that doesn't have them).

```bash
ONLY=20-stream OUT_DIR=/tmp/guide node docs/field-guide/build.mjs --shots all
```

Builds only the files starting with `20-stream` into `/tmp/guide`, with a PNG per page in `.shots/` (or `SHOTS_DIR`), for working on a few chapters.

Fonts (all SIL Open Font License, from Google Fonts) are in [`fonts/`](fonts/) and get embedded into the HTML: Press Start 2P, Bungee, Bungee Shade, Archivo Narrow and VT323. All artwork is original; no game company's names, logos or art are used.
