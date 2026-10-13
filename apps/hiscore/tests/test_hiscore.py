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

    def test_segment_validation(self):
        with tempfile.TemporaryDirectory() as d:
            st = Store(Path(d))
            with self.assertRaises(BadRequest):
                st.put("a/b", "x.hi", b"1")
            st.close()


if __name__ == "__main__":
    unittest.main()
