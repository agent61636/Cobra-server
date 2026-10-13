"""cobra-breaks: build "<Show> — with breaks" playlists in Jellyfin.

  python -m cobra_breaks run      [--config /config/breaks.toml]   one pass, then exit
  python -m cobra_breaks serve    [--config ...]                    run now, then daily at run_at

Each pass, for every [[show]] and each of its users: take the next episodes
(starting at the user's next unwatched one), put a random video from the
filler library between them, and write that list into the user's playlist.
Watch from the playlist on any Jellyfin app (Roku, Apple TV, phone, web); the
next pass moves it forward and reshuffles the filler.
"""

import argparse
import json
import random
import sys
import time
import tomllib
from datetime import datetime, timedelta
from pathlib import Path

from . import plan as planner
from .jellyfin import Jellyfin, JellyfinError

DEFAULTS = {
    "jellyfin_url": "http://127.0.0.1:8096",
    "api_key_file": "/config/api_key",
    "filler_library": "Filler",
    "breaks_per_gap": 1,
    "max_filler_minutes": 3,
    "episodes_per_playlist": 40,
    "start": "next_unwatched",
    "break_before_first": False,
    "skip_specials": True,
    "playlist_suffix": " — with breaks",
    "run_at": "04:00",
    "state_file": "/config/recent.json",
    "avoid_recent_runs": 3,
}


def log(msg):
    print(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}", flush=True)


def load_config(path):
    raw = tomllib.loads(Path(path).read_text())
    cfg = {**DEFAULTS, **{k: v for k, v in raw.items() if k != "show"}}
    shows = raw.get("show", [])
    if not shows:
        raise ValueError("config has no [[show]] entries")
    for s in shows:
        if not s.get("series") or not s.get("users"):
            raise ValueError("every [[show]] needs series = \"...\" and users = [\"...\"]")
    cfg["shows"] = shows
    return cfg


def _recent(cfg):
    p = Path(cfg["state_file"])
    try:
        return json.loads(p.read_text())
    except (OSError, ValueError):
        return {}


def _save_recent(cfg, data):
    p = Path(cfg["state_file"])
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data))
    tmp.replace(p)


def run_once(cfg, client=None, rng=None):
    """Returns a list of (show, user, playlist name, episodes, breaks, notes)."""
    if client is None:
        key = Path(cfg["api_key_file"]).read_text().strip()
        client = Jellyfin(cfg["jellyfin_url"], key)
    rng = rng or random.Random()
    users = client.users()
    lib = client.library_id(cfg["filler_library"])
    recent = _recent(cfg)
    results, errors = [], 0
    filler_cache = {}
    for show in cfg["shows"]:
        series = show["series"]
        for uname in show["users"]:
            uid = users.get(uname.lower())
            name = f"{series}{show.get('playlist_suffix', cfg['playlist_suffix'])}"
            if uid is None:
                log(f"skip {series!r} for {uname!r}: no such Jellyfin user")
                errors += 1
                continue
            try:
                sid = client.find_series(series, uid)
                eps = [planner.Episode(e["Id"], e.get("ParentIndexNumber") or 0,
                                       e.get("IndexNumber") or 0,
                                       bool((e.get("UserData") or {}).get("Played")), e.get("Name", ""))
                       for e in client.episodes(sid, uid)]
                eps = planner.order_episodes(eps, show.get("skip_specials", cfg["skip_specials"]))
                eps = planner.pick_episodes(eps, show.get("start", cfg["start"]),
                                            int(show.get("episodes_per_playlist", cfg["episodes_per_playlist"])))
                if uid not in filler_cache:
                    filler_cache[uid] = [planner.Filler(f["Id"], (f.get("RunTimeTicks") or 0) / planner.TICKS_PER_SECOND,
                                                        f.get("Path", "")) for f in client.filler(lib, uid)]
                fill = planner.eligible_filler(
                    filler_cache[uid], float(show.get("max_filler_minutes", cfg["max_filler_minutes"])) * 60,
                    show.get("filler_folder", ""))
                key = f"{uname.lower()}|{series}"
                avoid = [i for run in recent.get(key, []) for i in run]
                p = planner.build(eps, fill,
                                  breaks_per_gap=int(show.get("breaks_per_gap", cfg["breaks_per_gap"])),
                                  break_before_first=bool(show.get("break_before_first", cfg["break_before_first"])),
                                  recent=avoid, rng=rng)
                if not p.ids:
                    log(f"{name} for {uname}: nothing to do ({'; '.join(p.notes)})")
                    continue
                if p.breaks == 0 and len(eps) > 1:
                    p.notes.append(f"no filler found in library {cfg['filler_library']!r} under the rules")
                pid, created = client.set_playlist(name, uid, p.ids)
                used = [i for i in p.ids if i not in {e.id for e in eps}]
                runs = (recent.get(key, []) + [used])[-int(cfg["avoid_recent_runs"]):]
                recent[key] = runs
                log(f"{'created' if created else 'updated'} {name!r} for {uname}: "
                    f"{p.episodes} episodes, {p.breaks} breaks" + (f" ({'; '.join(p.notes)})" if p.notes else ""))
                results.append((series, uname, name, p.episodes, p.breaks, p.notes))
            except (JellyfinError, ValueError, KeyError) as e:
                log(f"error for {series!r} / {uname!r}: {e}")
                errors += 1
    _save_recent(cfg, recent)
    return results, errors


def seconds_until(hhmm, now=None):
    now = now or datetime.now()
    h, m = (int(x) for x in hhmm.split(":"))
    target = now.replace(hour=h, minute=m, second=0, microsecond=0)
    if target <= now:
        target += timedelta(days=1)
    return (target - now).total_seconds()


def main(argv=None):
    ap = argparse.ArgumentParser(prog="cobra_breaks")
    ap.add_argument("command", choices=["run", "serve"])
    ap.add_argument("--config", default="/config/breaks.toml")
    a = ap.parse_args(argv)
    cfg = load_config(a.config)
    if a.command == "run":
        _, errors = run_once(cfg)
        return 1 if errors else 0
    while True:
        try:
            run_once(cfg)
        except (OSError, JellyfinError) as e:
            log(f"pass failed: {e}; trying again in 10 minutes")
            time.sleep(600)
            continue
        wait = seconds_until(cfg["run_at"])
        log(f"next pass in {wait / 3600:.1f} h")
        time.sleep(wait)


if __name__ == "__main__":
    sys.exit(main())
