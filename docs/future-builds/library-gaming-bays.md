# Library Bay, Gaming Bay and Roll20: short recommendations (2026-11-06)

Not researched in depth yet (the Commander asked to pace usage). Ask for a deep pass on any of these.

## Library Bay

| Shelf | App | Notes |
|---|---|---|
| Audiobooks | **Audiobookshelf** (running) | Drop its `Books` e-book library once Calibre-Web is up, so e-books have one home |
| E-books, e-readers | **Calibre-Web Automated** (`crocodilestick/calibre-web-automated`) | Calibre-Web plus an ingest folder that converts and adds books on its own. OPDS for e-reader apps, Kobo sync, send-to-Kindle by email. Reads `dock1a/books` |
| Comics | **Kavita** (running) | |

Ideas for the Bay's spare room:
- **Reading Room**: Kavita also reads magazines and manga, so a "Periodicals" library is one click.
- **Archive**: Immich (photos) for `dock1a/scans` and `art`, as a family-album shelf.
- **Lore stacks**: the Gaming Bay's world wiki (below) could live here instead.

## Gaming Bay: RPG book library

Folder per IP already fits **Kavita**: a second library `RPG` (type *Book* or *Comic*) on the RPG folder,
where each IP folder becomes a series and each PDF a volume. Its PDF reader works on phones and laptops.
Character sheets, maps and fillable PDFs are better downloaded than read in a browser, so add a
read-only **FileBrowser** (`filebrowser/filebrowser`) on the same folder for the "extras" drawer.

## Roll20

Roll20 is a hosted virtual tabletop (maps, tokens, dice, character sheets, voice) run in the browser. It
can't be self-hosted. Options that fit the station:

- **Foundry VTT**: the self-hosted favourite. One-time licence (about $50, only the GM buys it), runs as
  a container (`felddy/foundryvtt`), players join in a browser at e.g. `table.songofeo.com`. Huge free
  module library, imports PDFs' maps, dynamic lighting. Best pick if you want to run games here.
- **Owlbear Rodeo**: free, hosted, very simple; good for a first session back.
- **World-building for fun**: Azgaar's Fantasy Map Generator (free, runs in a browser, can be self-hosted
  as a static page) for continents, Watabou for towns, and **Kanka** (open source, self-hostable) or
  LegendKeeper for the lore wiki. Foundry can show Azgaar maps as scenes.
