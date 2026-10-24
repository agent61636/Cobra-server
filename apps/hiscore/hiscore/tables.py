"""Turning decoded score tables into the board's {rank, score, name} rows.

The cabinet runs hi2txt (Windows only) after a game and sends its plain text
output; this module reads it. hi2txt prints one table per section, a header
line of column names and then one line per entry, with the columns separated
by "|". The parser is forgiving on purpose: it also accepts tabs, any column
order, extra columns, and several tables (it takes the first with a score).
"""

import re

RANK = {"RANK", "POS", "POSITION", "PLACE", "#", "NO", "NO."}
SCORE = {"SCORE", "HISCORE", "HI-SCORE", "HI SCORE", "POINTS", "PTS", "TOP SCORE", "BEST"}
NAME = {"NAME", "INITIALS", "PLAYER", "INITIAL"}

MAX_ROWS = 20
MAX_FIELD = 32


def _split(line):
    if "|" in line:
        return [c.strip() for c in line.split("|")]
    if "\t" in line:
        return [c.strip() for c in line.split("\t")]
    return [c for c in re.split(r"\s{2,}", line.strip())]


def _blocks(text):
    block = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            if block:
                yield block
            block = []
        else:
            block.append(line)
    if block:
        yield block


def _column(header, names):
    for i, h in enumerate(header):
        if h.upper() in names:
            return i
    return None


def parse_hi2txt(text):
    """Return a list of {rank, score, name} dicts, or [] if nothing readable."""
    if not isinstance(text, str):
        return []
    for block in _blocks(text):
        header = _split(block[0])
        score_i = _column(header, SCORE)
        if score_i is None:
            continue
        rank_i, name_i = _column(header, RANK), _column(header, NAME)
        rows = []
        for line in block[1:]:
            cells = _split(line)
            if len(cells) <= score_i or not cells[score_i]:
                continue
            get = lambda i: cells[i] if i is not None and i < len(cells) else ""
            rows.append({
                "rank": (get(rank_i) or str(len(rows) + 1))[:MAX_FIELD],
                "score": cells[score_i][:MAX_FIELD],
                "name": get(name_i)[:MAX_FIELD],
            })
            if len(rows) == MAX_ROWS:
                break
        if rows:
            return rows
    return []


def clean_rows(rows):
    """Validate rows sent as JSON: keep up to 20, each field a short string."""
    if not isinstance(rows, list):
        return []
    out = []
    for r in rows[:MAX_ROWS]:
        if isinstance(r, dict) and str(r.get("score", "")).strip():
            out.append({k: str(r.get(k, "")).strip()[:MAX_FIELD] for k in ("rank", "score", "name")})
    return out
