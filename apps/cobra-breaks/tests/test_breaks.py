"""Tests for cobra-breaks. Run: python -m unittest discover -s tests (from apps/cobra-breaks).

The fake Jellyfin below copies the server behaviour that matters here,
including that a playlist silently drops repeated items (PlaylistManager
uses Distinct() and skips ids already present).
"""

import json
import random
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cobra_breaks import plan as P  # noqa: E402
from cobra_breaks.jellyfin import Jellyfin  # noqa: E402
from cobra_breaks.main import load_config, run_once, seconds_until  # noqa: E402

KEY = "jf-key"
SEC = P.TICKS_PER_SECOND


class FakeJellyfin:
    def __init__(self):
        self.users = [{"Name": "Eels", "Id": "u-eels"}, {"Name": "Rachel", "Id": "u-rachel"}]
        self.series = {"s-simpsons": "The Simpsons"}
        self.episodes = {"s-simpsons": [
            {"Id": f"e{s}{n}", "Name": f"S{s}E{n}", "ParentIndexNumber": s, "IndexNumber": n}
            for s in (0, 1, 2) for n in (1, 2, 3)]}
        self.played = {"u-eels": set(), "u-rachel": set()}
        self.filler = [{"Id": f"f{i}", "RunTimeTicks": (20 + i) * SEC, "Path": f"/media/filler/{'90s' if i % 2 else '80s'}/ad{i}.mp4"}
                       for i in range(10)]
        self.filler.append({"Id": "f-long", "RunTimeTicks": 600 * SEC, "Path": "/media/filler/long.mp4"})
        self.playlists = {}   # id -> {"Name", "UserId", "Items": [...]}
        self.calls = []

    def add_items(self, pl, ids):
        seen = set(pl["Items"])
        for i in dict.fromkeys(ids):           # Distinct(), then skip existing
            if i not in seen:
                pl["Items"].append(i)
                pl.setdefault("Entries", []).append(f"entry-{len(self.calls)}-{i}")   # stable entry id
                seen.add(i)

    def handle(self, method, path, query, body):
        self.calls.append((method, path))
        if path == "/Users":
            return self.users
        if path == "/Library/VirtualFolders":
            return [{"Name": "Movies", "ItemId": "lib-movies"}, {"Name": "Filler", "ItemId": "lib-filler"}]
        if path == "/Items":
            types = query.get("includeItemTypes", "")
            uid = query.get("userId")
            if types == "Series":
                term = query.get("searchTerm", "").lower()
                items = [{"Id": k, "Name": v} for k, v in self.series.items() if term in v.lower()]
            elif types == "Playlist":
                items = [{"Id": k, "Name": v["Name"]} for k, v in self.playlists.items() if v["UserId"] == uid]
            elif query.get("parentId") == "lib-filler":
                items = self.filler
            else:
                items = []
            start, limit = int(query.get("startIndex", 0)), int(query.get("limit", 500))
            return {"Items": items[start:start + limit], "TotalRecordCount": len(items)}
        if path.startswith("/Shows/") and path.endswith("/Episodes"):
            sid = path.split("/")[2]
            uid = query["userId"]
            return {"Items": [{**e, "UserData": {"Played": e["Id"] in self.played[uid]}}
                              for e in self.episodes[sid]]}
        if path == "/Playlists" and method == "POST":
            pid = f"p{len(self.playlists) + 1}"
            pl = {"Name": body["Name"], "UserId": body["UserId"], "Items": []}
            self.add_items(pl, body["Ids"])
            self.playlists[pid] = pl
            return {"Id": pid}
        parts = path.split("/")
        if len(parts) == 3 and parts[1] == "Playlists" and method == "POST":
            raise PermissionError("UpdatePlaylist refuses API keys")       # like the real server
        if len(parts) == 4 and parts[1] == "Playlists" and parts[3] == "Items":
            pl = self.playlists[parts[2]]
            if method == "GET":
                return {"Items": [{"Id": i, "PlaylistItemId": e} for i, e in zip(pl["Items"], pl["Entries"])]}
            if method == "DELETE":
                drop = set(query["entryIds"].split(","))
                keep = [(i, e) for i, e in zip(pl["Items"], pl["Entries"]) if e not in drop]
                pl["Items"], pl["Entries"] = [k[0] for k in keep], [k[1] for k in keep]
                return None
            if method == "POST":
                assert query.get("userId") == pl["UserId"]
                self.add_items(pl, query["ids"].split(","))
                return None
        raise KeyError(path)


def serve(fake):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _go(self, method):
            if self.headers.get("Authorization") != f'MediaBrowser Token="{KEY}"':
                self.send_response(401); self.end_headers(); return
            u = urlsplit(self.path)
            q = {k: v[0] for k, v in parse_qs(u.query).items()}
            n = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(n)) if n else None
            try:
                out = fake.handle(method, u.path, q, body)
            except PermissionError:
                self.send_response(403); self.end_headers(); return
            except KeyError:
                self.send_response(404); self.end_headers(); return
            data = b"" if out is None else json.dumps(out).encode()
            self.send_response(200 if data else 204)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            self._go("GET")

        def do_POST(self):
            self._go("POST")

        def do_DELETE(self):
            self._go("DELETE")

    httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


class PlanTest(unittest.TestCase):
    def eps(self, n, played=0):
        return [P.Episode(f"e{i}", 1, i, i < played) for i in range(1, n + 1)]

    def fill(self, n):
        return [P.Filler(f"f{i}", 30) for i in range(n)]

    def test_alternates_episode_and_unique_filler(self):
        p = P.build(self.eps(4), self.fill(10), rng=random.Random(1))
        self.assertEqual([x[0] for x in p.ids], list("efefefe"))
        fillers = [x for x in p.ids if x.startswith("f")]
        self.assertEqual(len(fillers), len(set(fillers)))
        self.assertEqual((p.episodes, p.breaks), (4, 3))

    def test_break_before_first_and_multiple_per_gap(self):
        p = P.build(self.eps(2), self.fill(10), breaks_per_gap=2, break_before_first=True, rng=random.Random(2))
        self.assertEqual([x[0] for x in p.ids], list("ffeffe"))

    def test_shortens_rather_than_repeating_filler(self):
        p = P.build(self.eps(10), self.fill(3), rng=random.Random(3))
        self.assertEqual((p.episodes, p.breaks), (4, 3))
        self.assertTrue(p.notes and "shortened" in p.notes[0])

    def test_prefers_filler_not_used_recently(self):
        p = P.build(self.eps(3), self.fill(4), recent=["f0", "f1"], rng=random.Random(4))
        self.assertEqual(sorted(x for x in p.ids if x.startswith("f")), ["f2", "f3"])

    def test_pick_and_order(self):
        eps = [P.Episode("b", 2, 1), P.Episode("s", 0, 1), P.Episode("a", 1, 2, True), P.Episode("c", 1, 3)]
        ordered = P.order_episodes(eps)
        self.assertEqual([e.id for e in ordered], ["a", "c", "b"])
        self.assertEqual([e.id for e in P.pick_episodes(ordered, "next_unwatched")], ["c", "b"])
        self.assertEqual([e.id for e in P.pick_episodes(ordered, "first", limit=2)], ["a", "c"])
        allwatched = [P.Episode("x", 1, 1, True), P.Episode("y", 1, 2, True)]
        self.assertEqual([e.id for e in P.pick_episodes(allwatched)], ["x", "y"])   # starts over
        with self.assertRaises(ValueError):
            P.pick_episodes(ordered, "middle")

    def test_filler_rules(self):
        f = [P.Filler("a", 30, "/media/filler/90s/a.mp4"), P.Filler("b", 400, "/media/filler/90s/b.mp4"),
             P.Filler("c", 0, "/media/filler/90s/c.mp4"), P.Filler("d", 30, "/media/filler/80s/d.mp4")]
        self.assertEqual([x.id for x in P.eligible_filler(f, 180)], ["a", "d"])
        self.assertEqual([x.id for x in P.eligible_filler(f, 180, "/media/filler/90s")], ["a"])

    def test_no_episodes(self):
        self.assertEqual(P.build([], self.fill(3)).ids, [])

    def test_seconds_until(self):
        from datetime import datetime
        self.assertEqual(seconds_until("04:00", datetime(2026, 10, 13, 3, 0)), 3600)
        self.assertEqual(seconds_until("04:00", datetime(2026, 10, 13, 5, 0)), 23 * 3600)


class IntegrationTest(unittest.TestCase):
    def setUp(self):
        self.fake = FakeJellyfin()
        self.httpd = serve(self.fake)
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        (d / "api_key").write_text(KEY + "\n")
        (d / "breaks.toml").write_text(f'''
jellyfin_url = "http://127.0.0.1:{self.httpd.server_address[1]}"
api_key_file = "{d / 'api_key'}"
state_file = "{d / 'recent.json'}"
episodes_per_playlist = 4

[[show]]
series = "The Simpsons"
users = ["eels", "rachel", "nobody"]
''')
        self.cfg = load_config(d / "breaks.toml")

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def playlist(self, uid):
        [(pid, pl)] = [(k, v) for k, v in self.fake.playlists.items() if v["UserId"] == uid]
        return pid, pl

    def test_creates_then_updates_in_place(self):
        results, errors = run_once(self.cfg, rng=random.Random(7))
        self.assertEqual(errors, 1)                      # "nobody" isn't a Jellyfin user
        self.assertEqual(len(results), 2)
        pid, pl = self.playlist("u-eels")
        self.assertEqual(pl["Name"], "The Simpsons — with breaks")
        items = pl["Items"]
        self.assertEqual([i for i in items if i.startswith("e")], ["e11", "e12", "e13", "e21"])  # specials skipped
        self.assertEqual([i[0] for i in items], list("efefefe"))                               # nothing dropped
        self.assertNotIn("f-long", items)                                                      # over 3 minutes

        self.fake.played["u-eels"] |= {"e11", "e12"}
        run_once(self.cfg, rng=random.Random(8))
        pid2, pl2 = self.playlist("u-eels")
        self.assertEqual(pid2, pid)                                          # same playlist, updated
        self.assertEqual([i for i in pl2["Items"] if i.startswith("e")], ["e13", "e21", "e22", "e23"])
        _, rachel = self.playlist("u-rachel")
        self.assertEqual(rachel["Items"][0], "e11")                          # Rachel's own progress

    def test_replace_in_small_batches(self):
        run_once(self.cfg, rng=random.Random(9))
        pid, _ = self.playlist("u-eels")
        client = Jellyfin(self.cfg["jellyfin_url"], KEY)
        new = ["e23", "f1", "e22", "f2", "e21"]
        self.assertEqual(client.set_playlist("The Simpsons — with breaks", "u-eels", new, batch=2), (pid, False))
        self.assertEqual(self.playlist("u-eels")[1]["Items"], new)

    def test_wrong_key_is_reported(self):
        client = Jellyfin(self.cfg["jellyfin_url"], "wrong")
        from cobra_breaks.jellyfin import JellyfinError
        with self.assertRaises(JellyfinError):
            client.users()

    def test_bad_config(self):
        p = Path(self.tmp.name) / "bad.toml"
        p.write_text('jellyfin_url = "x"\n')
        with self.assertRaises(ValueError):
            load_config(p)


if __name__ == "__main__":
    unittest.main()
