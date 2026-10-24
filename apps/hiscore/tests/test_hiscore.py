"""Tests for the hiscore server. Run: python -m unittest discover -s tests (from apps/hiscore)."""

import hashlib
import json
import os
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from hiscore.server import App, hash_key, load_keys, make_handler  # noqa: E402
from hiscore.store import BadRequest, Store  # noqa: E402
from hiscore.tables import clean_rows, parse_hi2txt  # noqa: E402

HI2TXT = """RANK|SCORE|NAME
1|52310|EEL
2|40000|ABC
3|20000|
"""

KEY = "test-key-123"


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.data = Path(self.tmp.name)
        (self.data / "keys.txt").write_text(f"cabinet {hash_key(KEY)}\n")
        self.store = Store(self.data)
        self.app = App(self.store, load_keys(self.data / "keys.txt"), max_bytes=1024)
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.app))
        self.httpd.RequestHandlerClass.log_message = lambda *a: None
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.store.close()
        self.tmp.cleanup()

    def req(self, method, path, body=None, key=KEY, headers=None):
        h = dict(headers or {})
        if key:
            h["Authorization"] = f"Bearer {key}"
        r = urllib.request.Request(self.base + path, data=body, method=method, headers=h)
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            with opener.open(r, timeout=5) as resp:
                return resp.status, resp.read(), dict(resp.headers)
        except urllib.error.HTTPError as e:
            return e.code, e.read(), dict(e.headers)

    def put(self, system, name, body, **kw):
        return self.req("PUT", f"/api/v1/files/{system}/{name}", body, **kw)

    def games(self):
        s, b, _ = self.req("GET", "/api/v1/games", key=None)
        self.assertEqual(s, 200)
        return json.loads(b)

    def test_upload_store_and_download_identical(self):
        data = bytes(range(256))
        s, b, _ = self.put("fbneo", "galaga.hi", data, headers={"X-File-Mtime": "2026-10-13T12:00:00Z"})
        self.assertEqual(s, 201)
        self.assertTrue(json.loads(b)["changed"])
        s, b, h = self.req("GET", "/api/v1/files/fbneo/galaga.hi", key=None)
        self.assertEqual(s, 200)
        self.assertEqual(hashlib.sha256(b).hexdigest(), hashlib.sha256(data).hexdigest())
        self.assertIn("galaga.hi", h["Content-Disposition"])
        g = self.games()[0]
        self.assertEqual((g["system"], g["game"], g["versions"], g["source"]), ("fbneo", "galaga", 1, "cabinet"))
        self.assertEqual(g["file_mtime"], "2026-10-13T12:00:00Z")
        raw = list((self.data / "raw" / "fbneo" / "galaga.hi").iterdir())
        self.assertEqual(len(raw), 1)
        self.assertEqual(raw[0].read_bytes(), data)

    def test_upload_path_alias(self):
        s, b, _ = self.req("PUT", "/upload/fbneo/galaga.hi", b"abc")
        self.assertEqual(s, 201)
        self.assertEqual(self.games()[0]["game"], "galaga")
        self.assertEqual(self.req("GET", "/upload/fbneo/galaga.hi", key=None)[0], 404)

    def test_same_bytes_twice_is_not_a_new_version(self):
        self.assertEqual(self.put("fbneo", "galaga.hi", b"abc")[0], 201)
        s, b, _ = self.put("fbneo", "galaga.hi", b"abc")
        self.assertEqual((s, json.loads(b)["changed"]), (200, False))
        self.assertEqual(self.games()[0]["versions"], 1)

    def test_changed_file_adds_version_and_keeps_history(self):
        self.put("fbneo", "galaga.hi", b"v1")
        self.put("fbneo", "galaga.hi", b"v2")
        s, b, _ = self.req("GET", "/api/v1/files/fbneo/galaga.hi/history", key=None)
        hist = json.loads(b)
        self.assertEqual(len(hist), 2)
        old = hist[-1]["id"]
        s, b, _ = self.req("GET", f"/api/v1/files/fbneo/galaga.hi/versions/{old}", key=None)
        self.assertEqual(b, b"v1")
        s, b, _ = self.req("GET", "/api/v1/files/fbneo/galaga.hi", key=None)
        self.assertEqual(b, b"v2")

    def test_newest_first(self):
        self.put("fbneo", "galaga.hi", b"1")
        time.sleep(1.1)
        self.put("mame2003-plus", "dkong.hi", b"1")
        time.sleep(1.1)
        self.put("fbneo", "galaga.hi", b"2")   # galaga updated last
        self.assertEqual([g["game"] for g in self.games()], ["galaga", "dkong"])

    def test_filters(self):
        self.put("fbneo", "galaga.hi", b"1")
        self.put("mame2003-plus", "dkong.hi", b"1")
        s, b, _ = self.req("GET", "/api/v1/games?system=fbneo", key=None)
        self.assertEqual([g["game"] for g in json.loads(b)], ["galaga"])
        s, b, _ = self.req("GET", "/api/v1/games?q=dko", key=None)
        self.assertEqual([g["game"] for g in json.loads(b)], ["dkong"])
        s, b, _ = self.req("GET", "/api/v1/games?q=%25", key=None)   # LIKE wildcard is escaped
        self.assertEqual(json.loads(b), [])
        s, b, _ = self.req("GET", "/api/v1/systems", key=None)
        self.assertEqual(json.loads(b), ["fbneo", "mame2003-plus"])

    def test_auth_required_and_checked(self):
        self.assertEqual(self.put("fbneo", "galaga.hi", b"x", key=None)[0], 401)
        self.assertEqual(self.put("fbneo", "galaga.hi", b"x", key="wrong")[0], 401)
        self.assertEqual(self.games(), [])

    def test_rejects_bad_names_types_and_sizes(self):
        for system, name in [("..", "galaga.hi"), ("fbneo", "..hi"), ("fb neo", "galaga.hi"),
                             ("fbneo", "galaga.exe"), ("fbneo", ".hidden.hi")]:
            s, _, _ = self.put(system.replace(" ", "%20"), name, b"x")
            self.assertIn(s, (400, 404), (system, name, s))
        self.assertEqual(self.put("fbneo", "big.hi", b"x" * 2000)[0], 413)
        self.assertEqual(self.put("fbneo", "empty.hi", b"")[0], 400)
        self.assertEqual(self.games(), [])

    def test_page_and_health(self):
        s, b, h = self.req("GET", "/", key=None)
        self.assertEqual(s, 200)
        self.assertIn("text/html", h["Content-Type"])
        self.assertIn(b"High score board", b)
        self.assertEqual(json.loads(self.req("GET", "/healthz", key=None)[1]), {"ok": True})
        self.assertEqual(self.req("GET", "/nope", key=None)[0], 404)
        self.assertEqual(self.req("GET", "/api/v1/files/fbneo/missing.hi", key=None)[0], 404)

    def meta(self, system, name, obj, **kw):
        body = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        return self.req("PUT", f"/upload/{system}/{name}/meta", body,
                        headers={"Content-Type": "application/json"}, **kw)

    def test_meta_sets_title_platform_and_table(self):
        self.put("fbneo", "galaga.hi", b"v1")
        s, b, _ = self.meta("fbneo", "galaga.hi", {"title": "Galaga", "platform": "Arcade", "hi2txt": HI2TXT})
        self.assertEqual((s, json.loads(b)), (200, {"ok": True, "rows": 3}))
        g = self.games()[0]
        self.assertEqual((g["title"], g["platform"]), ("Galaga", "Arcade"))
        self.assertEqual(g["decoded"][0], {"rank": "1", "score": "52310", "name": "EEL"})
        # A new version starts without a table until the cabinet sends one; the title stays.
        self.put("fbneo", "galaga.hi", b"v2")
        g = self.games()[0]
        self.assertEqual((g["title"], g["decoded"]), ("Galaga", None))
        # Search finds the title as well as the ROM name.
        s, b, _ = self.req("GET", "/api/v1/games?q=gala", key=None)
        self.assertEqual(len(json.loads(b)), 1)

    def test_meta_rows_and_lan_path(self):
        self.put("fbneo", "dkong.hi", b"x")
        s, b, _ = self.req("PUT", "/api/v1/files/fbneo/dkong.hi/meta",
                           json.dumps({"rows": [{"rank": 1, "score": 100, "name": "AAA"}, {"name": "no score"}]}).encode())
        self.assertEqual(json.loads(b)["rows"], 1)
        self.assertEqual(self.games()[0]["decoded"], [{"rank": "1", "score": "100", "name": "AAA"}])

    def test_meta_needs_key_file_and_json(self):
        self.assertEqual(self.meta("fbneo", "galaga.hi", {"title": "x"})[0], 404)   # no file yet
        self.put("fbneo", "galaga.hi", b"x")
        self.assertEqual(self.meta("fbneo", "galaga.hi", {"title": "x"}, key=None)[0], 401)
        self.assertEqual(self.meta("fbneo", "galaga.hi", {"title": "x"}, key="wrong")[0], 401)
        self.assertEqual(self.meta("fbneo", "galaga.hi", b"not json")[0], 400)
        self.assertEqual(self.meta("fbneo", "galaga.hi", [1, 2])[0], 400)
        self.assertEqual(self.meta("fbneo", "galaga.hi", {"title": "bad\nline"})[0], 400)
        self.assertEqual(self.meta("fbneo", "galaga.hi", {"title": 5})[0], 400)
        self.assertEqual(self.meta("fbneo", "galaga.hi", {"title": "x" * 70000})[0], 413)
        self.assertEqual(self.games()[0]["title"], "")

    def test_public_board_off_by_default(self):
        self.put("fbneo", "galaga.hi", b"x")
        self.assertEqual(self.req("GET", "/public/v1/board", key=None)[0], 404)

    def test_public_board_shows_only_scores(self):
        self.app.public = True
        self.put("fbneo", "galaga.hi", b"x")
        self.meta("fbneo", "galaga.hi", {"title": "Galaga", "hi2txt": HI2TXT})
        s, b, h = self.req("GET", "/public/v1/board", key=None, headers={"Origin": "https://songofeo.com"})
        self.assertEqual(s, 200)
        self.assertEqual(h["Access-Control-Allow-Origin"], "https://songofeo.com")
        board = json.loads(b)
        self.assertEqual(set(board[0]), {"game", "title", "system", "platform", "updated_at", "scores"})
        self.assertEqual(board[0]["scores"][0]["name"], "EEL")
        s, b, h = self.req("GET", "/public/v1/board", key=None, headers={"Origin": "https://evil.example"})
        self.assertNotIn("Access-Control-Allow-Origin", h)

    def test_screen_can_be_framed_by_the_site_only(self):
        s, b, h = self.req("GET", "/screen", key=None)
        self.assertEqual(s, 200)
        self.assertIn(b"public/v1/board", b)
        self.assertEqual(h["Content-Security-Policy"],
                         "frame-ancestors 'self' https://songofeo.com https://www.songofeo.com")


class TablesTest(unittest.TestCase):
    def test_hi2txt_text(self):
        rows = parse_hi2txt(HI2TXT)
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[2], {"rank": "3", "score": "20000", "name": ""})

    def test_columns_in_any_order_and_first_scored_table(self):
        text = "LEVEL|STAGE\n1|5\n\nNAME|SCORE|ROUND\nAAA|900|3\nBBB|800|2\n"
        self.assertEqual(parse_hi2txt(text), [{"rank": "1", "score": "900", "name": "AAA"},
                                              {"rank": "2", "score": "800", "name": "BBB"}])

    def test_tabs_and_junk(self):
        self.assertEqual(parse_hi2txt("POS\tPOINTS\tINITIALS\n1\t10\tZZ\n")[0]["name"], "ZZ")
        self.assertEqual(parse_hi2txt("unknown game"), [])
        self.assertEqual(parse_hi2txt(None), [])
        self.assertEqual(clean_rows("x"), [])
        self.assertEqual(len(parse_hi2txt("SCORE\n" + "1\n" * 50)), 20)


class StoreTest(unittest.TestCase):
    def test_decoder_hook_and_titles(self):
        with tempfile.TemporaryDirectory() as d:
            script = Path(d) / "dec.py"
            script.write_text("import json,sys\nprint(json.dumps([{'rank':1,'score':'12345','name':sys.argv[2][:3].upper()}]))\n")
            st = Store(Path(d) / "data", decoder=[sys.executable, str(script)], titles={"galaga": "Galaga"})
            st.put("fbneo", "galaga.hi", b"x")
            g = st.games()[0]
            self.assertEqual(g["decoded"], [{"rank": "1", "score": "12345", "name": "GAL"}])
            self.assertEqual(g["title"], "Galaga")
            st.close()

    def test_failing_decoder_does_not_block_upload(self):
        with tempfile.TemporaryDirectory() as d:
            st = Store(Path(d), decoder=[sys.executable, "-c", "import sys; sys.exit(3)"])
            self.assertTrue(st.put("fbneo", "galaga.hi", b"x")[0])
            self.assertIsNone(st.games()[0]["decoded"])
            st.close()

    def test_server_decoder_wins_over_cabinet_rows(self):
        with tempfile.TemporaryDirectory() as d:
            script = Path(d) / "dec.py"
            script.write_text("import json\nprint(json.dumps([{'rank':1,'score':'7','name':'SRV'}]))\n")
            st = Store(Path(d) / "data", decoder=[sys.executable, str(script)])
            st.put("fbneo", "galaga.hi", b"x")
            st.set_meta("fbneo", "galaga.hi", {"title": "Galaga", "rows": [{"score": "1", "name": "CAB"}]})
            g = st.games()[0]
            self.assertEqual((g["title"], g["decoded"][0]["name"]), ("Galaga", "SRV"))
            st.close()

    def test_titles_file_wins_and_old_database_is_upgraded(self):
        import sqlite3
        with tempfile.TemporaryDirectory() as d:
            db = sqlite3.connect(Path(d) / "hiscore.db")   # a database from before meta existed
            db.executescript(
                "CREATE TABLE files (id INTEGER PRIMARY KEY, system TEXT NOT NULL, name TEXT NOT NULL,"
                " game TEXT NOT NULL, latest_id INTEGER, first_seen TEXT NOT NULL, updated_at TEXT NOT NULL,"
                " UNIQUE (system, name));"
                "CREATE TABLE versions (id INTEGER PRIMARY KEY, file_id INTEGER NOT NULL, sha256 TEXT NOT NULL,"
                " size INTEGER NOT NULL, received_at TEXT NOT NULL, file_mtime TEXT, source TEXT NOT NULL DEFAULT '',"
                " path TEXT NOT NULL, decoded TEXT);")
            db.close()
            st = Store(Path(d), titles={"galaga": "Galaga (tsv)"})
            st.put("fbneo", "galaga.hi", b"x")
            st.set_meta("fbneo", "galaga.hi", {"title": "Galaga (LaunchBox)"})
            self.assertEqual(st.games()[0]["title"], "Galaga (tsv)")
            st.close()

    def test_segment_validation(self):
        with tempfile.TemporaryDirectory() as d:
            st = Store(Path(d))
            with self.assertRaises(BadRequest):
                st.put("a/b", "x.hi", b"1")
            st.close()


if __name__ == "__main__":
    unittest.main()
