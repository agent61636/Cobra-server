# 7. Design: hiscore sync and scoreboard

> **Status:** design, October 13, 2026. Build after parts 1–5 are running. Its slot is already reserved (overview §8): hostname `scores.songofeo.com`, API on `127.0.0.1:8090` inside the gate pod, data in `/srv/gate/hiscore/`.

## What it does

Every arcade high score set on the cabinet shows up on one web page, `scores.songofeo.com`, **newest first**: the game where someone just set a score sits at the top. The raw hiscore files are also kept as a backup, so a dead disk or a reinstall never wipes the scores.

## How it fits together

```
cabinet (Windows)                         gate VM (hiscore slot in the gate pod)
RetroArch writes  game.hi  ──► hiscore agent ──HTTPS + API key──► nginx ─► hiscore API (127.0.0.1:8090)
  (on game exit)            (watches folders,                               ├─ raw/   every .hi version, untouched
                             queues if offline)                             ├─ database: games, scores, updated time
                                                                            └─ web page: newest first, filters
```

| Piece | Where | What |
|---|---|---|
| **Agent** | Cabinet, `C:\Cobra\hiscore-agent\` | Watches the `.hi` folders found in part 4.4. When a file changes (RetroArch writes it on game exit), uploads it with the game name, core and time. If the network or gate is down, it keeps a queue and retries. Runs as a Windows service, so it works with Big Box in front and nobody logged in to a desktop. |
| **API** | Gate pod, `127.0.0.1:8090` | Accepts uploads with the cabinet's API key. Saves every version of each raw file under `raw/<game>/<timestamp>.hi`, decodes it to a score table when it can (next section), and records when it last changed. |
| **Web page** | Same app | Games sorted by **last updated**. Each shows its top entries (rank, initials, score), the system, and when it changed. Filters: system, "changed this week", search. A game with no decoder still lists, with "scores saved, not readable yet" and a download link. |
| **Database** | `/srv/gate/hiscore/hiscore.db` (SQLite) | Small enough that SQLite is plenty. Port `5433` stays reserved if it ever outgrows that. |

Because it all lives in VM 110 and on the cabinet's nightly copy (part 4.5), the existing backups already cover it.

## The hard part: reading `.hi` files

A `.hi` file is not a score list. It's a copy of the bytes the game kept in memory for its high-score table, and `hiscore.dat` only says *where* in memory to find them. Every game stores names and scores differently (BCD digits, custom character sets, reversed order).

The proven way to read them is **hi2txt**, by GreatStone, the tool behind the LaunchBox/Big Box "MAME Hi-Score" plugins. It ships a per-game definition for each supported game and turns a `.hi` file into rows of rank, score and name.

Plan:

1. **Phase 1 stores without decoding.** The agent uploads, the server keeps every version, and the page lists games by last updated with a raw download. Useful on day one and loses nothing.
2. **Phase 2 adds decoding with hi2txt**, run on the server for each new upload. Games it knows get a real score table; the rest stay "raw saved".
3. ⚠️ Verify before phase 2:
   - **hi2txt's license** allows running it on your own server. It's freeware, not open source.
   - **Compatibility with RetroArch's files.** hi2txt targets MAME's `.hi` format, and FinalBurn Neo and MAME 2003-Plus use the same `hiscore.dat` lineage. Test with three or four of your favourite games first.

## Scores from the browser arcade (EmulatorJS)

Browser games run in the player's browser, so their `.hi` files are written inside the browser, not on any server. RomM syncs saves and save states to the server, but its docs don't mention hiscore files. So browser scores need extra work:

- **Option 1:** a small script added to RomM's player page that, when a game closes, reads the `.hi` file from EmulatorJS's in-browser file system and posts it to the hiscore API with the player's login.
- **Option 2:** ask upstream: an issue on RomM or EmulatorJS asking for hiscore files to sync like saves.

This is **phase 3**. The cabinet is where the real high scores happen, so it isn't a blocker.

## Logins

- **Viewers:** behind Authelia, like the dashboard. Add `scores.songofeo.com` to the Authelia rules (one factor is enough for viewing) and un-comment its server block in nginx (part 5).
- **The cabinet agent:** a long random API key sent over HTTPS, stored on the cabinet with Windows DPAPI so it isn't plain text on disk. nginx rate-limits the upload URL.

## Build order and tests

| Phase | Delivers | Test |
|---|---|---|
| 1 | Agent + API + raw storage + "newest first" page | Set a score on the cabinet, quit; within a minute the game is at the top of the page and the raw file downloads byte-for-byte identical (checksum) |
| 1 | Offline queue | Stop the gate's hiscore container, play, start it again: the upload arrives |
| 2 | Decoding | For 3–4 favourite games, the page matches what the game shows on its own high-score screen |
| 3 | Browser scores | Same score test from `arcade.songofeo.com` |

## Questions to settle before building

1. Which games matter most? Their decoders get checked first.
2. Should the page show **everyone** who visits, or only logged-in friends?
3. Should initials be matched to people ("EEL" = Eels) for a per-player page?

## Sources

- FinalBurn Neo core docs (hiscore option, `hiscore.dat` location): https://docs.libretro.com/library/fbneo/
- LaunchBox "MAME Hi-Score Display" plugin (credits hi2txt): https://forums.launchbox-app.com/files/file/2173-mame-hi-score-display-a-plugin-for-bigbox/
- RomM EmulatorJS player docs (saves, states, netplay): https://docs.romm.app/4.7.0/Platforms-and-Players/EmulatorJS-Player/
