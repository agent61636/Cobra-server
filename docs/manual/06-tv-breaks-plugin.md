# 6. Design: breaks between episodes (Jellyfin plugin)

> **Status:** design, researched October 13, 2026. Build after parts 1–5 are running. This is future project #1 from the overview (§9).

## What you asked for

- **Movies:** a pre-roll before each movie. The **Local Intros** plugin already does this; nothing new is needed.
- **Shows:** when you watch episodes on demand (not Live TV), play one **random video from a chosen folder** (`/media/filler`) **between episodes**, like a commercial break.
- **Live TV:** already covered. ErsatzTV's filler presets put breaks between everything on its channels (part 3.8a).

## The catch: how Jellyfin intros actually work

Jellyfin has a server-side hook for this, `IIntroProvider`. A plugin implements it, and when a client asks the server for an item's intros (`/Items/{id}/Intros`) the plugin returns videos to play first. Local Intros works this way.

**But Jellyfin's apps only ask for intros before movies, never before episodes.** This was confirmed in two places:

- The Jellyfin forum thread on pre-roll plugins: the plugin returns intros only for movies, and series get an empty list.
- The **Projectionist** plugin (MIT license, targets Jellyfin 10.11) documents the problem. It works around it with a small script injected into the Jellyfin **web** page, which asks for intros before each episode. That fix works in Jellyfin Web and Jellyfin Media Player only. **Native Android TV, Roku and iOS apps don't load the web page, so the script never runs there.**

So a plugin that only implements `IIntroProvider` would do nothing for episodes on your TVs and phones.

## Options

| Option | Works on | Feels like | Effort |
|---|---|---|---|
| **A. Projectionist (existing)**: prerolls from a folder before each episode, via its web script | Browser, Jellyfin Media Player | A break before every episode, including the first | Install and test; no code |
| **B. "With breaks" playlists (new plugin)**: a scheduled task builds a playlist per show: episode, random filler, episode, random filler, … and reshuffles the filler daily | **Every client**, because playlists are a normal Jellyfin feature | Pick the show's playlist instead of the show, and it plays through with breaks | Small plugin, a few hundred lines of C# |
| **C. One ErsatzTV channel per show** | Every client (Live TV) | Real TV: it's already playing, you can't pick an episode | Configuration only |
| **D. Change the clients** | Only clients you rebuild | Exactly what you want | Not realistic: Android TV, Roku and iOS apps each have their own codebase |

## Recommendation

1. **Try A first** (an evening). If you mostly watch in a browser or Jellyfin Media Player, it may be all you need. Point it at `/media/filler`, and set it to skip movies so it doesn't double up with Local Intros.
2. **Build B for the TVs and phones.** It's the only route that works on native apps, and it's small.
3. Keep **C** for "just put something on" channels.

## Plugin B: design

**Name:** `Elysidrome Breaks` (working name).

**What it does:**

- Settings page (Dashboard → Plugins → Elysidrome Breaks):
  - Filler folder (default `/media/filler`)
  - Which series get a "with breaks" playlist (tick boxes), and for which users
  - Breaks per gap (default 1), maximum filler length (e.g. 3 minutes), and "don't repeat a filler within the last N"
  - Start from: first episode, or the user's next unwatched episode
- A **scheduled task** (Dashboard → Scheduled Tasks, daily at 4 am, plus a "Run now" button):
  1. For each ticked series and user, list the episodes in order, starting from the first or the next unwatched one.
  2. Pick random filler for each gap, honoring the length and no-repeat rules.
  3. Create or replace the playlist `<Show> — with breaks`, owned by that user.
- **Movies are left alone.** No `IIntroProvider` for movies, so Local Intros stays the only movie pre-roll.

**Jellyfin pieces it uses** (all part of the normal plugin API):

| Need | Jellyfin interface |
|---|---|
| Plugin + settings page | `BasePlugin<PluginConfiguration>`, `IHasWebPages` |
| Daily job with "Run now" | `IScheduledTask` |
| Find series, episodes, filler | `ILibraryManager` (filler folder added as a library, part 3.8a) |
| Users and watched state | `IUserManager`, `IUserDataManager` |
| Make the playlists | `IPlaylistManager` |

**Build setup:** C# from the official `jellyfin-plugin-template`, matched to the server's Jellyfin version and .NET version. ⚠️ Verify both on the template's README when starting; Jellyfin 10.11 builds against `Jellyfin.Controller` 10.11.x. Distribute it through a small plugin repository (a `manifest.json` on GitHub Releases), so Jellyfin installs and updates it from Dashboard → Plugins → Repositories.

**Tests before it goes on the real server:**

- Unit tests for the playlist builder: order kept, no filler repeats within N, filler length limit respected, "next unwatched" start.
- A throwaway Jellyfin container on the SGIN (separate port, copy of a small test library) to install the build and play a playlist on the web, Android TV and phone apps.

## Questions to settle before building

1. Which clients matter most: the TV app (Android TV, Roku, Fire TV?), phones, or the browser?
2. A break before the **first** episode too, or only between episodes?
3. Should filler be tied to a show or era (e.g. 90s commercials for 90s shows)? That means subfolders like `/media/filler/90s` and a per-series folder setting.

## Sources

- Jellyfin forum, "Pre-roll plugin movies only": https://forum.jellyfin.org/t-pre-roll-plugin-movies-only
- Projectionist plugin (episode prerolls via web hook; client limits): https://github.com/ZL154/jellyfin-projectionist
- ErsatzTV filler kinds and modes (pre-roll, mid-roll, post-roll, pad): https://mintlify.wiki/ErsatzTV/legacy/configuration/watermarks-filler
