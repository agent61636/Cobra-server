"""Versioned storage for arcade hiscore files.

Every upload whose bytes differ from the newest stored version becomes a new
version: the raw file is written once under raw/<system>/<file>/ and never
changed, and the database records when it arrived. "Last updated" on the page
is the time the newest version arrived.
"""

import hashlib
import json
import os
import re
import sqlite3
import subprocess
from datetime import datetime, timezone
from pathlib import Path

SEGMENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")

SCHEMA = """
CREATE TABLE IF NOT EXISTS files (
    id          INTEGER PRIMARY KEY,
    system      TEXT NOT NULL,
    name        TEXT NOT NULL,
    game        TEXT NOT NULL,
    latest_id   INTEGER,
    first_seen  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    UNIQUE (system, name)
);
CREATE TABLE IF NOT EXISTS versions (
    id          INTEGER PRIMARY KEY,
    file_id     INTEGER NOT NULL REFERENCES files(id),
    sha256      TEXT NOT NULL,
    size        INTEGER NOT NULL,
    received_at TEXT NOT NULL,
    file_mtime  TEXT,
    source      TEXT NOT NULL DEFAULT '',
    path        TEXT NOT NULL,
    decoded     TEXT
);
CREATE INDEX IF NOT EXISTS idx_files_updated ON files(updated_at);
"""


class BadRequest(ValueError):
    pass


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def check_segment(value, what):
    if not isinstance(value, str) or not SEGMENT.match(value) or ".." in value:
        raise BadRequest(f"invalid {what}: use letters, digits, '.', '_' or '-' (max 64)")
    return value


class Store:
    def __init__(self, data_dir, allowed_ext=(".hi",), decoder=None, titles=None):
        self.data = Path(data_dir)
        self.raw = self.data / "raw"
        self.raw.mkdir(parents=True, exist_ok=True)
        self.allowed_ext = tuple(e.lower() for e in allowed_ext)
        self.decoder = decoder  # argv list, or None
        self.titles = titles or {}
        self.db = sqlite3.connect(self.data / "hiscore.db", check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(SCHEMA)

    def close(self):
        self.db.close()

    # -- writing ----------------------------------------------------------

    def put(self, system, name, body, file_mtime=None, source=""):
        """Store one upload. Returns (changed, version_id)."""
        check_segment(system, "system")
        check_segment(name, "file name")
        if not name.lower().endswith(self.allowed_ext):
            raise BadRequest(f"only {', '.join(self.allowed_ext)} files are accepted")
        if not body:
            raise BadRequest("empty file")
        game = name.rsplit(".", 1)[0]
        digest = hashlib.sha256(body).hexdigest()
        received = now_iso()
        with self.db:
            row = self.db.execute(
                "SELECT f.id, v.sha256 FROM files f LEFT JOIN versions v ON v.id = f.latest_id "
                "WHERE f.system = ? AND f.name = ?", (system, name)).fetchone()
            if row and row["sha256"] == digest:
                return False, None
            if row is None:
                cur = self.db.execute(
                    "INSERT INTO files (system, name, game, first_seen, updated_at) VALUES (?,?,?,?,?)",
                    (system, name, game, received, received))
                file_id = cur.lastrowid
            else:
                file_id = row["id"]
            stamp = received.replace(":", "").replace("-", "").replace("+0000", "Z")
            rel = Path(system) / name / f"{stamp}-{digest[:12]}{Path(name).suffix}"
            dest = self.raw / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            tmp = dest.with_suffix(dest.suffix + ".tmp")
            tmp.write_bytes(body)
            os.replace(tmp, dest)
            decoded = self._decode(dest, game, system)
            cur = self.db.execute(
                "INSERT INTO versions (file_id, sha256, size, received_at, file_mtime, source, path, decoded) "
                "VALUES (?,?,?,?,?,?,?,?)",
                (file_id, digest, len(body), received, file_mtime, source[:64], rel.as_posix(),
                 json.dumps(decoded) if decoded is not None else None))
            vid = cur.lastrowid
            self.db.execute("UPDATE files SET latest_id = ?, updated_at = ? WHERE id = ?",
                            (vid, received, file_id))
        return True, vid

    def _decode(self, path, game, system):
        """Optional generic decoder. Must print a JSON list of {rank, score, name}."""
        if not self.decoder:
            return None
        try:
            out = subprocess.run([*self.decoder, str(path), game, system], capture_output=True,
                                 timeout=10, check=True).stdout
            rows = json.loads(out)
        except (OSError, subprocess.SubprocessError, ValueError):
            return None
        if not isinstance(rows, list):
            return None
        clean = []
        for r in rows[:20]:
            if isinstance(r, dict):
                clean.append({k: str(r.get(k, ""))[:32] for k in ("rank", "score", "name")})
        return clean or None

    # -- reading ----------------------------------------------------------

    def games(self, system=None, query=None, limit=500):
        sql = ("SELECT f.system, f.name, f.game, f.first_seen, f.updated_at, v.size, v.sha256, "
               "v.file_mtime, v.source, v.decoded, "
               "(SELECT COUNT(*) FROM versions x WHERE x.file_id = f.id) AS versions "
               "FROM files f JOIN versions v ON v.id = f.latest_id")
        where, args = [], []
        if system:
            where.append("f.system = ?")
            args.append(system)
        if query:
            where.append("(f.game LIKE ? ESCAPE '\\')")
            args.append("%" + query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%")
        if where:
            sql += " WHERE " + " AND ".join(where)
        sql += " ORDER BY f.updated_at DESC, f.id DESC LIMIT ?"
        args.append(max(1, min(int(limit), 2000)))
        out = []
        for r in self.db.execute(sql, args):
            d = dict(r)
            d["decoded"] = json.loads(d["decoded"]) if d["decoded"] else None
            d["title"] = self.titles.get(d["game"], "")
            out.append(d)
        return out

    def systems(self):
        return [r[0] for r in self.db.execute("SELECT DISTINCT system FROM files ORDER BY system")]

    def history(self, system, name):
        check_segment(system, "system")
        check_segment(name, "file name")
        return [dict(r) for r in self.db.execute(
            "SELECT v.id, v.sha256, v.size, v.received_at, v.file_mtime, v.source FROM versions v "
            "JOIN files f ON f.id = v.file_id WHERE f.system = ? AND f.name = ? ORDER BY v.id DESC",
            (system, name))]

    def raw_bytes(self, system, name, version_id=None):
        check_segment(system, "system")
        check_segment(name, "file name")
        if version_id is None:
            row = self.db.execute(
                "SELECT v.path FROM files f JOIN versions v ON v.id = f.latest_id "
                "WHERE f.system = ? AND f.name = ?", (system, name)).fetchone()
        else:
            row = self.db.execute(
                "SELECT v.path FROM versions v JOIN files f ON f.id = v.file_id "
                "WHERE f.system = ? AND f.name = ? AND v.id = ?", (system, name, int(version_id))).fetchone()
        if row is None:
            return None
        return (self.raw / row["path"]).read_bytes()


def load_titles(path):
    """Optional 'romname<TAB>Title' file, e.g. generated from MAME's game list."""
    titles = {}
    p = Path(path)
    if p.exists():
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
            if "\t" in line and not line.startswith("#"):
                k, v = line.split("\t", 1)
                titles[k.strip()] = v.strip()
    return titles
