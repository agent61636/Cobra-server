"""Tests for cobra-forms. Run: python -m unittest discover -s tests (from apps/forms)."""

import json
import struct
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import forms  # noqa: E402

CONFIG = json.loads((Path(__file__).resolve().parents[1] / "forms.example.json").read_text())

APP1 = b"\xff\xe1" + struct.pack(">H", 2 + 16) + b"Exif\x00\x00GPS-SECRET"
JPEG = (b"\xff\xd8" + b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
        + APP1 + b"\xff\xfe" + struct.pack(">H", 8) + b"comment" [:6]
        + b"\xff\xda" + struct.pack(">H", 8) + b"\x01\x01\x00\x00\x3f\x00" + b"PIXELS" + b"\xff\xd9")


def png_chunk(kind, data):
    import zlib
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


PNG = (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
       + png_chunk(b"tEXt", b"Location\x00GPS-SECRET") + png_chunk(b"eXIf", b"MM\x00*GPS-SECRET")
       + png_chunk(b"IDAT", b"x\x9cc\xf8\x0f\x00\x01\x01\x01\x00") + png_chunk(b"IEND", b""))


def webp():
    vp8x = b"VP8X" + struct.pack("<I", 10) + bytes([0x0C, 0, 0, 0]) + b"\x00" * 6
    vp8l = b"VP8L" + struct.pack("<I", 5) + b"\x2f\x00\x00\x00\x00" + b"\x00"
    exif = b"EXIF" + struct.pack("<I", 10) + b"GPS-SECRET"
    body = vp8x + vp8l + exif
    return b"RIFF" + struct.pack("<I", len(body) + 4) + b"WEBP" + body


def multipart(fields, files=()):
    b = uuid.uuid4().hex
    out = b""
    for k, v in fields:
        out += f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
    for k, name, ctype, data in files:
        out += (f'--{b}\r\nContent-Disposition: form-data; name="{k}"; filename="{name}"\r\n'
                f"Content-Type: {ctype}\r\n\r\n").encode() + data + b"\r\n"
    out += f"--{b}--\r\n".encode()
    return f"multipart/form-data; boundary={b}", out


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


class FormsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.data = Path(self.tmp.name)
        env = {"FORMS_DATA": str(self.data), "FORMS_SMTP_USER": "me@example.com", "FORMS_SMTP_PASS": "abcd efgh",
               "FORMS_INBOX_USERS": "eels"}
        self.settings = forms.Settings(env, CONFIG)
        self.sent = []
        self.fail_mail = False

        def send(msg):
            if self.fail_mail:
                raise OSError("relay down")
            self.sent.append(msg)

        self.mailer = forms.Mailer(self.settings, send=send)
        self.app = forms.App(self.settings, self.mailer)
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), forms.make_handler(self.app))
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        self.opener = urllib.request.build_opener(NoRedirect)

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def post(self, form, body, ctype="application/x-www-form-urlencoded", origin="https://songofeo.com",
             ip="203.0.113.5", headers=None):
        if isinstance(body, list):
            body = urllib.parse.urlencode(body).encode()
        h = {"Content-Type": ctype, "X-Real-IP": ip}
        if origin:
            h["Origin"] = origin
        h.update(headers or {})
        req = urllib.request.Request(f"{self.base}/f/{form}", data=body, headers=h, method="POST")
        try:
            r = self.opener.open(req)
            return r.status, r.headers, r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read()

    def get(self, path, user=None):
        h = {"Remote-User": user} if user else {}
        try:
            r = urllib.request.urlopen(urllib.request.Request(self.base + path, headers=h))
            return r.status, r.headers, r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read()

    def saved(self, box="inbox"):
        return sorted((self.data / box).iterdir())

    COUNCIL = [("_subject", "x"), ("_template", "table"), ("_next", "https://songofeo.com/council/?heard=advocate"),
               ("_honey", ""), ("Advocating for", "Film"), ("Petition", "Add Alien\r\nplease"),
               ("email", "fan@example.org")]

    def test_council_form_saved_emailed_and_redirected(self):
        code, h, _ = self.post("voices", self.COUNCIL)
        self.assertEqual(code, 303)
        self.assertEqual(h["Location"], "https://songofeo.com/council/?heard=advocate")
        [d] = self.saved()
        rec = json.loads((d / "submission.json").read_text())
        self.assertEqual(rec["fields"], [["Advocating for", "Film"], ["Petition", "Add Alien\nplease"],
                                         ["email", "fan@example.org"]])
        self.assertEqual(rec["ip"], "203.0.113.5")
        self.assertEqual(self.mailer.run_once(), 1)
        [msg] = self.sent
        self.assertEqual(msg["Reply-To"], "fan@example.org")
        self.assertEqual(msg["To"], "me@example.com")
        self.assertIn("Advocate Change", msg["Subject"])
        self.assertIn("Add Alien", msg.get_content())
        self.assertEqual(self.mailer.run_once(), 0, "never emailed twice")

    def test_next_must_stay_on_the_site(self):
        body = [("_next", "https://evil.example/phish"), ("Petition", "hi")]
        code, h, _ = self.post("voices", body)
        self.assertEqual(h["Location"], "https://songofeo.com/council/?heard=advocate")
        body = [("_next", "https://www.songofeo.com/council/?heard=advocate"), ("Petition", "hi")]
        _, h, _ = self.post("voices", body, origin="https://www.songofeo.com")
        self.assertEqual(h["Location"], "https://www.songofeo.com/council/?heard=advocate")

    def test_other_sites_and_unknown_forms_refused(self):
        self.assertEqual(self.post("voices", [("Petition", "x")], origin="https://evil.example")[0], 403)
        self.assertEqual(self.post("voices", [("Petition", "x")], origin="")[0], 403)
        self.assertEqual(self.post("voices", [("Petition", "x")], origin="",
                                   headers={"Referer": "https://songofeo.com/council/"})[0], 303)
        self.assertEqual(self.post("enlist", [("Name", "x")], origin="https://songofeo.com")[0], 403)
        self.assertEqual(self.post("nope", [("Petition", "x")])[0], 404)
        self.assertEqual(len(self.saved()), 1)

    def test_honeypot_pretends_and_drops(self):
        code, h, _ = self.post("voices", [("_honey", "buy pills"), ("Petition", "spam")])
        self.assertEqual(code, 303)
        self.assertEqual(self.saved(), [])

    def test_links_go_to_spam_without_email(self):
        text = " ".join(f"https://spam{i}.example" for i in range(6))
        self.assertEqual(self.post("voices", [("Petition", text)])[0], 303)
        self.assertEqual(self.saved(), [])
        self.assertEqual(len(self.saved("spam")), 1)
        self.assertEqual(self.mailer.run_once(), 0)

    def test_rate_limit_per_address(self):
        for _ in range(6):
            self.assertEqual(self.post("voices", [("Petition", "x")])[0], 303)
        self.assertEqual(self.post("voices", [("Petition", "x")])[0], 429)
        self.assertEqual(self.post("voices", [("Petition", "x")], ip="198.51.100.7")[0], 303)

    def test_empty_and_oversize_refused(self):
        self.assertEqual(self.post("voices", [("Petition", "  ")])[0], 400)
        self.assertEqual(self.post("voices", [("Petition", "x" * 30_000)])[0], 413)
        self.assertEqual(self.post("voices", b"x" * (300 * 1024))[0], 413)
        self.assertEqual(self.post("voices", b"{}", ctype="application/json")[0], 415)

    def test_enlist_with_picture_strips_metadata(self):
        ctype, body = multipart([("_next", "https://hailcobra.com/enlist-thanks.html"), ("Name", "Rocky"),
                                 ("Codename", "Rocky Bal-BOA"), ("email", "r@example.org")],
                                [("attachment", "me.jpg", "image/jpeg", JPEG)])
        code, h, _ = self.post("enlist", body, ctype=ctype, origin="https://hailcobra.com")
        self.assertEqual(code, 303)
        self.assertEqual(h["Location"], "https://hailcobra.com/enlist-thanks.html")
        [d] = self.saved()
        pic = (d / "attachment-1.jpg").read_bytes()
        self.assertNotIn(b"GPS-SECRET", pic)
        self.assertNotIn(b"Exif", pic)
        self.assertIn(b"JFIF", pic)
        self.assertTrue(pic.endswith(b"PIXELS\xff\xd9"))
        self.mailer.run_once()
        [msg] = self.sent
        [att] = list(msg.iter_attachments())
        self.assertEqual(att.get_content_type(), "image/jpeg")
        self.assertEqual(att.get_content(), pic)

    def test_png_and_webp_cleaned_and_fake_pictures_dropped(self):
        kind, clean = forms.clean_image(PNG)
        self.assertEqual(kind, "png")
        self.assertNotIn(b"GPS-SECRET", clean)
        self.assertIn(b"IDAT", clean)
        kind, clean = forms.clean_image(webp())
        self.assertEqual(kind, "webp")
        self.assertNotIn(b"GPS-SECRET", clean)
        self.assertEqual(struct.unpack("<I", clean[4:8])[0], len(clean) - 8)
        self.assertEqual(clean[20] & 0x0C, 0)
        ctype, body = multipart([("Name", "x")], [("attachment", "evil.jpg", "image/jpeg", b"<script>alert(1)</script>")])
        self.assertEqual(self.post("enlist", body, ctype=ctype, origin="https://hailcobra.com")[0], 303)
        [d] = self.saved()
        rec = json.loads((d / "submission.json").read_text())
        self.assertEqual(rec["attachments"], [])
        self.assertIn("dropped", rec["notes"][0])

    def test_files_refused_on_text_forms(self):
        ctype, body = multipart([("Petition", "x")], [("attachment", "a.jpg", "image/jpeg", JPEG)])
        self.assertEqual(self.post("voices", body, ctype=ctype)[0], 303)
        [d] = self.saved()
        self.assertFalse(list(d.glob("attachment-*")))

    def test_mail_failure_keeps_submission_and_retries(self):
        self.fail_mail = True
        self.post("voices", [("Petition", "x")])
        self.assertEqual(self.mailer.run_once(), 0)
        [d] = self.saved()
        self.assertTrue((d / "mail-error").exists())
        self.fail_mail = False
        self.assertEqual(self.mailer.run_once(), 0, "waits before retrying")
        self.assertEqual(self.mailer.run_once(now=__import__("time").time() + 3600), 1)
        self.assertFalse((d / "mail-error").exists())

    def test_header_injection_cannot_add_recipients(self):
        self.post("voices", [("Petition", "x"), ("email", "a@b.co\r\nBcc: victim@example.com")])
        self.mailer.run_once()
        [msg] = self.sent
        self.assertIsNone(msg["Reply-To"])
        self.assertIsNone(msg["Bcc"])

    def test_inbox_needs_the_owner(self):
        self.post("voices", [("Petition", "<script>alert(1)</script>")])
        [d] = self.saved()
        self.assertEqual(self.get("/inbox/")[0], 403)
        self.assertEqual(self.get("/inbox/", user="rachel")[0], 403)
        code, h, body = self.get("/inbox/", user="eels")
        self.assertEqual(code, 200)
        self.assertIn("default-src 'none'", h["Content-Security-Policy"])
        code, _, body = self.get(f"/inbox/{d.name}", user="eels")
        self.assertEqual(code, 200)
        self.assertIn(b"&lt;script&gt;", body)
        self.assertNotIn(b"<script>", body)
        self.assertEqual(self.get("/inbox/../../etc/passwd", user="eels")[0], 404)
        self.assertEqual(self.get(f"/inbox/{d.name}/submission.json", user="eels")[0], 404)

    def test_health_and_get(self):
        self.assertEqual(self.get("/health")[2], b"ok\n")
        self.assertEqual(self.get("/f/voices")[0], 200)


if __name__ == "__main__":
    unittest.main()
