"""Pure planning logic: which episodes, which filler, in what order.

Kept separate from the Jellyfin client so it can be tested exactly.

Jellyfin playlists can't hold the same item twice (the server silently drops
repeats), so every break in one playlist must be a *different* filler video.
If there isn't enough filler, the playlist is shortened instead of losing
breaks, and the caller is told why.
"""

import random
from dataclasses import dataclass, field

TICKS_PER_SECOND = 10_000_000


@dataclass(frozen=True)
class Episode:
    id: str
    season: int
    number: int
    played: bool = False
    name: str = ""


@dataclass(frozen=True)
class Filler:
    id: str
    seconds: float
    path: str = ""


@dataclass
class Plan:
    ids: list                      # playlist order: episode, filler..., episode, ...
    episodes: int = 0
    breaks: int = 0
    notes: list = field(default_factory=list)


def order_episodes(episodes, skip_specials=True):
    eps = [e for e in episodes if not (skip_specials and e.season == 0)]
    return sorted(eps, key=lambda e: (e.season, e.number))


def pick_episodes(episodes, start="next_unwatched", limit=40):
    if start not in ("next_unwatched", "first"):
        raise ValueError("start must be 'next_unwatched' or 'first'")
    if start == "next_unwatched":
        idx = next((i for i, e in enumerate(episodes) if not e.played), None)
        if idx is None:      # everything watched: start over from the top
            idx = 0
        episodes = episodes[idx:]
    return episodes[:max(1, limit)]


def eligible_filler(filler, max_seconds=180, folder=""):
    out = [f for f in filler if 0 < f.seconds <= max_seconds]
    if folder:
        prefix = folder.rstrip("/") + "/"
        out = [f for f in out if f.path.startswith(prefix)]
    return out


def build(episodes, filler, *, breaks_per_gap=1, break_before_first=False,
          recent=(), rng=None):
    """episodes: already chosen and ordered. filler: eligible filler. recent: filler ids
    used in recent runs, avoided when there's enough other filler."""
    rng = rng or random.Random()
    breaks_per_gap = max(0, int(breaks_per_gap))
    plan = Plan(ids=[])
    if not episodes:
        plan.notes.append("no episodes to schedule")
        return plan
    gaps = len(episodes) - 1 + (1 if break_before_first else 0)
    need = gaps * breaks_per_gap
    pool = list(filler)
    rng.shuffle(pool)
    recent = set(recent)
    fresh = [f for f in pool if f.id not in recent]
    stale = [f for f in pool if f.id in recent]
    pool = fresh + stale          # prefer filler not seen lately
    if breaks_per_gap and len(pool) < need:
        # Shorten so every gap still gets its full break with unique filler.
        max_gaps = len(pool) // breaks_per_gap
        keep = max_gaps + (0 if break_before_first else 1)
        if keep < len(episodes):
            plan.notes.append(
                f"only {len(pool)} filler videos fit the rules; playlist shortened from "
                f"{len(episodes)} to {max(keep, 1)} episodes so every break is a different video")
            episodes = episodes[:max(keep, 1)]
    it = iter(pool)
    for i, ep in enumerate(episodes):
        if breaks_per_gap and (i > 0 or break_before_first):
            chunk = [next(it, None) for _ in range(breaks_per_gap)]
            chunk = [f for f in chunk if f]
            plan.ids.extend(f.id for f in chunk)
            plan.breaks += len(chunk)
        plan.ids.append(ep.id)
        plan.episodes += 1
    return plan
