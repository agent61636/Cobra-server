#!/usr/bin/env python3
"""cobra-forms: the station's own form receiver, a free and self-hosted stand-in for FormSubmit.

The website's plain HTML forms post to https://forms.songofeo.com/f/<form>. Each submission is saved
on the gate first (so nothing is ever lost), then emailed through an SMTP relay (a Gmail app password)
if one is set. The saved copies can be read at /inbox, which nginx puts behind Authelia.

Python standard library only. Settings come from the environment (all optional):
  FORMS_ADDR          127.0.0.1:8097   where to listen (inside the gate pod; nginx is the only way in)
  FORMS_CONFIG        /app/forms.json  which forms exist (see forms.example.json)
  FORMS_DATA          /data            inbox/ and spam/ live here
  FORMS_SMTP_HOST     smtp.gmail.com   leave FORMS_SMTP_USER empty to save without emailing
  FORMS_SMTP_PORT     587              587 = STARTTLS, 465 = TLS from the start
  FORMS_SMTP_USER     you@gmail.com    the Gmail account that sends
  FORMS_SMTP_PASS     (podman secret)  its 16-letter app password
  FORMS_FROM          = FORMS_SMTP_USER
  FORMS_TO            = FORMS_SMTP_USER   where every submission is emailed (a form can override it with "to")
  FORMS_INBOX_USERS   eels             Authelia usernames allowed to read /inbox (comma separated)
  FORMS_INBOX_URL     https://forms.songofeo.com/inbox   linked from each email
  FORMS_TRUST_PROXY   1                read the visitor's address from nginx's X-Real-IP header
"""

from __future__ import annotations

import collections
import email.parser
import email.policy
import html
import json
import os
import re
import secrets
import smtplib
import ssl
import struct
import sys
import threading
import time
import urllib.parse
from email.message import EmailMessage
from email.utils import formatdate, make_msgid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_FIELDS = 60
MAX_NAME = 100
MAX_VALUE = 20_000
MAX_FILES = 3
MAX_TEXT_BODY = 256 * 1024          # forms without uploads
ID_RE = re.compile(r"^\d{8}-\d{6}-[0-9a-f]{8}$")
FILE_RE = re.compile(r"^attachment-\d\.(jpg|png|webp)$")
EMAIL_RE = re.compile(r"^[^@\s<>\"',;]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}$")
LINK_RE = re.compile(r"https?://|www\.|\[url", re.I)
IMAGE_TYPES = {"jpg": "image/jpeg", "png": "image/png", "webp": "image/webp"}


def log(*parts: object) -> None:
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *parts, flush=True)


# ---------------------------------------------------------------- settings

class Settings:
    def __init__(self, env: dict[str, str] | None = None, config: dict | None = None):
        env = dict(os.environ if env is None else env)
        self.addr = env.get("FORMS_ADDR", "127.0.0.1:8097")
        self.data = Path(env.get("FORMS_DATA", "/data"))
        self.smtp_host = env.get("FORMS_SMTP_HOST", "smtp.gmail.com")
        self.smtp_port = int(env.get("FORMS_SMTP_PORT", "587") or 587)
        self.smtp_user = env.get("FORMS_SMTP_USER", "").strip()
        self.smtp_pass = env.get("FORMS_SMTP_PASS", "").replace(" ", "").strip()
        self.mail_from = env.get("FORMS_FROM", "").strip() or self.smtp_user
        self.mail_to = env.get("FORMS_TO", "").strip() or self.smtp_user
        self.inbox_users = {u.strip() for u in env.get("FORMS_INBOX_USERS", "eels").split(",") if u.strip()}
        self.inbox_url = env.get("FORMS_INBOX_URL", "https://forms.songofeo.com/inbox").rstrip("/")
        self.trust_proxy = env.get("FORMS_TRUST_PROXY", "1") == "1"
        if config is None:
            config = json.loads(Path(env.get("FORMS_CONFIG", "/app/forms.json")).read_text(encoding="utf-8"))
        self.forms: dict[str, dict] = config.get("forms", {})
        limits = config.get("limits", {})
        self.per_ip_per_hour = int(limits.get("per_ip_per_hour", 6))
        self.all_per_hour = int(limits.get("all_per_hour", 120))
        self.max_links = int(limits.get("max_links", 4))
        for name, form in self.forms.items():
            if not re.fullmatch(r"[a-z0-9-]{1,32}", name):
                raise SystemExit(f"forms.json: form name {name!r} must be lowercase letters, digits or -")
            if not form.get("origins") or not form.get("next"):
                raise SystemExit(f"forms.json: form {name!r} needs \"origins\" and \"next\"")

    @property
    def email_on(self) -> bool:
        return bool(self.smtp_user and self.smtp_pass and self.mail_to)


# ---------------------------------------------------------------- picture clean-up (drops EXIF, GPS, comments)

def sniff_image(data: bytes) -> str | None:
    if data[:3] == b"\xff\xd8\xff":
        return "jpg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


def strip_jpeg(data: bytes) -> bytes:
    """Keep the picture, drop APP1 (EXIF/XMP, where phones put GPS), APP13 (IPTC) and comments."""
    out = bytearray(b"\xff\xd8")
    i = 2
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            raise ValueError("bad JPEG marker")
        marker = data[i + 1]
        if marker == 0xFF:           # padding
            i += 1
            continue
        if marker == 0xDA:           # start of scan: the rest is picture data
            out += data[i:]
            return bytes(out)
        if 0xD0 <= marker <= 0xD7 or marker == 0x01:
            out += data[i:i + 2]
            i += 2
            continue
        length = struct.unpack(">H", data[i + 2:i + 4])[0]
        seg = data[i:i + 2 + length]
        if len(seg) < 2 + length:
            raise ValueError("truncated JPEG")
        if not (marker == 0xE1 or marker == 0xED or marker == 0xFE or 0xE3 <= marker <= 0xEC or marker == 0xEF):
            out += seg
        i += 2 + length
    raise ValueError("JPEG has no picture data")


def strip_png(data: bytes) -> bytes:
    out = bytearray(data[:8])
    i = 8
    while i + 12 <= len(data):
        length = struct.unpack(">I", data[i:i + 4])[0]
        kind = data[i + 4:i + 8]
        chunk = data[i:i + 12 + length]
        if len(chunk) < 12 + length:
            raise ValueError("truncated PNG")
        if kind not in (b"eXIf", b"tEXt", b"iTXt", b"zTXt", b"tIME"):
            out += chunk
        i += 12 + length
        if kind == b"IEND":
            return bytes(out)
    raise ValueError("PNG has no end")


def strip_webp(data: bytes) -> bytes:
    body = bytearray()
    i = 12
    vp8x_at = None
    while i + 8 <= len(data):
        kind = data[i:i + 4]
        length = struct.unpack("<I", data[i + 4:i + 8])[0]
        padded = length + (length & 1)
        chunk = data[i:i + 8 + padded]
        if len(chunk) < 8 + length:
            raise ValueError("truncated WEBP")
        if kind not in (b"EXIF", b"XMP "):
            if kind == b"VP8X":
                vp8x_at = len(body)
            body += chunk
        i += 8 + padded
    if vp8x_at is not None:
        body[vp8x_at + 8] &= ~0x0C & 0xFF    # clear the "has EXIF" and "has XMP" flags
    return b"RIFF" + struct.pack("<I", len(body) + 4) + b"WEBP" + bytes(body)


def clean_image(data: bytes) -> tuple[str, bytes]:
    kind = sniff_image(data)
    if kind is None:
        raise ValueError("not a JPG, PNG or WEBP picture")
    cleaned = {"jpg": strip_jpeg, "png": strip_png, "webp": strip_webp}[kind](data)
    return kind, cleaned


# ---------------------------------------------------------------- request parsing

class Reject(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def parse_body(content_type: str, body: bytes) -> tuple[list[tuple[str, str]], list[tuple[str, str, bytes]]]:
    """Returns (fields, files). files = (field name, file name, bytes)."""
    ctype = content_type.split(";", 1)[0].strip().lower()
    fields: list[tuple[str, str]] = []
    files: list[tuple[str, str, bytes]] = []
    if ctype == "application/x-www-form-urlencoded":
        try:
            pairs = urllib.parse.parse_qsl(body.decode("utf-8", "replace"), keep_blank_values=True,
                                           max_num_fields=MAX_FIELDS + 10)
        except ValueError:
            raise Reject(400, "Too many fields.")
        fields = pairs
    elif ctype == "multipart/form-data":
        if "boundary=" not in content_type:
            raise Reject(400, "The form was sent without a boundary.")
        head = b"Content-Type: " + content_type.encode("latin-1", "replace") + b"\r\nMIME-Version: 1.0\r\n\r\n"
        msg = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(head + body)
        if not msg.is_multipart():
            raise Reject(400, "The form could not be read.")
        parts = msg.get_payload()
        if len(parts) > MAX_FIELDS + MAX_FILES + 10:
            raise Reject(400, "Too many fields.")
        for part in parts:
            name = part.get_param("name", header="content-disposition")
            if not name:
                continue
            name = str(name)
            filename = part.get_filename()
            payload = part.get_payload(decode=True) or b""
            if filename is not None:
                if payload:
                    files.append((name, str(filename), payload))
            else:
                fields.append((name, payload.decode("utf-8", "replace")))
    else:
        raise Reject(415, "Forms must be sent as a normal web form.")
    return fields, files


def clean_fields(raw: list[tuple[str, str]]) -> tuple[list[tuple[str, str]], dict[str, str]]:
    """Splits visitor fields from the hidden _settings fields, and trims both."""
    fields: list[tuple[str, str]] = []
    hidden: dict[str, str] = {}
    for name, value in raw:
        name = name.strip()[:MAX_NAME]
        value = value.replace("\r\n", "\n").replace("\r", "\n").replace("\x00", "")
        if name.startswith("_"):
            hidden.setdefault(name, value[:2000])
            continue
        if not name:
            continue
        if len(value) > MAX_VALUE:
            raise Reject(413, f"“{name}” is too long. Please keep it under {MAX_VALUE:,} characters.")
        fields.append((name, value))
    if len(fields) > MAX_FIELDS:
        raise Reject(400, "Too many fields.")
    return fields, hidden


# ---------------------------------------------------------------- the app

class RateLimit:
    def __init__(self, per_ip: int, total: int, window: float = 3600):
        self.per_ip, self.total, self.window = per_ip, total, window
        self.hits: dict[str, collections.deque] = collections.defaultdict(collections.deque)
        self.all: collections.deque = collections.deque()
        self.lock = threading.Lock()

    def allow(self, ip: str, now: float | None = None) -> bool:
        now = time.time() if now is None else now
        with self.lock:
            for q in (self.hits[ip], self.all):
                while q and q[0] <= now - self.window:
                    q.popleft()
            if len(self.hits[ip]) >= self.per_ip or len(self.all) >= self.total:
                return False
            self.hits[ip].append(now)
            self.all.append(now)
            if len(self.hits) > 10_000:      # forget idle addresses
                for k in [k for k, q in self.hits.items() if not q]:
                    del self.hits[k]
            return True


def origin_of(url: str) -> str:
    try:
        p = urllib.parse.urlsplit(url)
    except ValueError:
        return ""
    if p.scheme not in ("http", "https") or not p.hostname:
        return ""
    port = f":{p.port}" if p.port and p.port not in (80, 443) else ""
    return f"{p.scheme}://{p.hostname.lower()}{port}"


class App:
    def __init__(self, settings: Settings, mailer: "Mailer | None" = None):
        self.s = settings
        self.limit = RateLimit(settings.per_ip_per_hour, settings.all_per_hour)
        self.mailer = mailer
        for box in ("inbox", "spam"):
            (settings.data / box).mkdir(parents=True, exist_ok=True)

    # A submission: returns (where to send the visitor, saved id or None)
    def submit(self, form_name: str, ip: str, origin: str, referer: str, content_type: str,
               body: bytes) -> tuple[str, str | None]:
        form = self.s.forms.get(form_name)
        if form is None:
            raise Reject(404, "There is no form by that name.")
        allowed = {o.rstrip("/").lower() for o in form["origins"]}
        came_from = (origin.rstrip("/").lower() if origin and origin != "null" else origin_of(referer))
        if came_from not in allowed:
            raise Reject(403, "Please send this form from the website.")
        max_body = int(float(form.get("max_upload_mb", 6)) * 1024 * 1024) + 64 * 1024 if form.get("uploads") else MAX_TEXT_BODY
        if len(body) > max_body:
            raise Reject(413, "That was too big to send. Pictures must be under 5 MB.")

        raw, files = parse_body(content_type, body)
        fields, hidden = clean_fields(raw)
        nxt = hidden.get("_next", "")
        nxt = nxt if nxt and origin_of(nxt) in allowed else form["next"]

        if hidden.get("_honey", "").strip():
            log(f"{form_name}: honeypot filled from {ip}, dropped")
            return nxt, None
        if not any(v.strip() for _, v in fields):
            raise Reject(400, "The form was empty.")
        if not self.limit.allow(ip):
            raise Reject(429, "That's a lot of messages in one hour. Please wait a while and try again.")

        attachments, notes = [], []
        if files and not form.get("uploads"):
            notes.append("files were attached, but this form doesn't take files; they were dropped")
        elif files:
            for field, filename, data in files[:MAX_FILES]:
                if len(data) > float(form.get("max_upload_mb", 6)) * 1024 * 1024:
                    notes.append(f"{filename}: over {form.get('max_upload_mb', 6)} MB, dropped")
                    continue
                try:
                    kind, cleaned = clean_image(data)
                except (ValueError, struct.error, IndexError) as e:
                    notes.append(f"{filename[:80]}: {e}, dropped")
                    continue
                attachments.append({"field": field, "original_name": filename[:200], "kind": kind, "data": cleaned})
            if len(files) > MAX_FILES:
                notes.append(f"only the first {MAX_FILES} files were kept")

        text = "\n".join(v for _, v in fields)
        spam = len(LINK_RE.findall(text)) > self.s.max_links
        sub_id = time.strftime("%Y%m%d-%H%M%S", time.gmtime()) + "-" + secrets.token_hex(4)
        reply_to = next((v.strip() for k, v in fields if k.lower() in ("email", "e-mail", "_replyto")
                         and EMAIL_RE.match(v.strip())), "")
        record = {
            "id": sub_id,
            "form": form_name,
            "title": form.get("title", form_name),
            "subject": form.get("subject", f"New {form_name} form"),
            "received": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "ip": ip,
            "page": referer[:500],
            "reply_to": reply_to,
            "fields": [[k, v] for k, v in fields],
            "attachments": [],
            "notes": notes,
            "spam": spam,
        }
        folder = self.s.data / ("spam" if spam else "inbox") / sub_id
        folder.mkdir(parents=True)
        for n, a in enumerate(attachments, 1):
            fname = f"attachment-{n}.{a['kind']}"
            (folder / fname).write_bytes(a["data"])
            record["attachments"].append({"file": fname, "field": a["field"], "original_name": a["original_name"],
                                          "bytes": len(a["data"])})
        tmp = folder / "submission.json.tmp"
        tmp.write_text(json.dumps(record, ensure_ascii=False, indent=1), encoding="utf-8")
        tmp.replace(folder / "submission.json")
        log(f"{form_name}: saved {sub_id} from {ip}" + (" (spam: too many links)" if spam else ""))
        if not spam and self.mailer:
            self.mailer.wake()
        return nxt, sub_id

    # ---- the inbox (nginx asks Authelia first; the app checks the username it hands over)
    def list_box(self, box: str) -> list[dict]:
        out = []
        root = self.s.data / box
        for d in sorted(root.iterdir(), reverse=True)[:300] if root.exists() else []:
            try:
                rec = json.loads((d / "submission.json").read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue
            rec["_emailed"] = (d / "emailed").exists()
            rec["_failed"] = (d / "mail-error").read_text()[:300] if (d / "mail-error").exists() else ""
            out.append(rec)
        return out

    def find(self, sub_id: str) -> Path | None:
        if not ID_RE.match(sub_id):
            return None
        for box in ("inbox", "spam"):
            d = self.s.data / box / sub_id
            if (d / "submission.json").is_file():
                return d
        return None


# ---------------------------------------------------------------- email

class Mailer:
    """Emails each saved submission once, in the background, retrying with a growing wait if the relay fails."""

    def __init__(self, settings: Settings, send=None):
        self.s = settings
        self.event = threading.Event()
        self.send = send or self._smtp_send

    def wake(self) -> None:
        self.event.set()

    def run_forever(self) -> None:
        while True:
            try:
                self.run_once()
            except Exception as e:  # never let the mail loop die
                log("mail loop error:", repr(e))
            self.event.wait(300)
            self.event.clear()

    def run_once(self, now: float | None = None) -> int:
        if not self.s.email_on:
            return 0
        now = time.time() if now is None else now
        sent = 0
        inbox = self.s.data / "inbox"
        for d in sorted(inbox.iterdir()) if inbox.exists() else []:
            if (d / "emailed").exists() or not (d / "submission.json").exists():
                continue
            tries_file = d / "mail-tries"
            tries = int(tries_file.read_text() or 0) if tries_file.exists() else 0
            if tries and now - tries_file.stat().st_mtime < min(60 * 2 ** tries, 6 * 3600):
                continue
            try:
                rec = json.loads((d / "submission.json").read_text(encoding="utf-8"))
                self.send(self.build(rec, d))
            except Exception as e:
                tries_file.write_text(str(tries + 1))
                (d / "mail-error").write_text(f"{time.strftime('%Y-%m-%d %H:%M:%S')} try {tries + 1}: {e!r}"[:1000])
                log(f"email for {d.name} failed (try {tries + 1}):", repr(e))
                continue
            (d / "emailed").write_text(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
            for f in (tries_file, d / "mail-error"):
                f.unlink(missing_ok=True)
            log(f"emailed {d.name}")
            sent += 1
        return sent

    def build(self, rec: dict, folder: Path) -> EmailMessage:
        form = self.s.forms.get(rec["form"], {})
        msg = EmailMessage()
        subject = re.sub(r"[\r\n]+", " ", rec.get("subject", "New form"))[:200]
        msg["Subject"] = f"{form.get('label', '[Forms]')} {subject}".strip()
        msg["From"] = f"Station forms <{self.s.mail_from}>"
        msg["To"] = form.get("to") or self.s.mail_to
        if rec.get("reply_to"):
            msg["Reply-To"] = rec["reply_to"]
        msg["Date"] = formatdate(localtime=True)
        msg["Message-ID"] = make_msgid(domain="forms.songofeo.com")
        lines = [f"{rec.get('title', rec['form'])} ({rec['form']} form)",
                 f"Received {rec['received']} from {rec.get('ip', '?')}", ""]
        for k, v in rec["fields"]:
            lines.append(f"{k}:")
            lines.extend("    " + line for line in (v or "(empty)").split("\n"))
            lines.append("")
        for note in rec.get("notes", []):
            lines.append(f"Note: {note}")
        lines += ["", f"Saved copy: {self.s.inbox_url}/{rec['id']}",
                  "Reply to this email to answer the sender (when they left an address)."]
        msg.set_content("\n".join(lines))
        for a in rec.get("attachments", []):
            if FILE_RE.match(a["file"]):
                kind = a["file"].rsplit(".", 1)[1]
                maintype, subtype = IMAGE_TYPES[kind].split("/")
                msg.add_attachment((folder / a["file"]).read_bytes(), maintype=maintype, subtype=subtype,
                                   filename=f"{rec['form']}-{rec['id']}-{a['file']}")
        return msg

    def _smtp_send(self, msg: EmailMessage) -> None:
        ctx = ssl.create_default_context()
        if self.s.smtp_port == 465:
            with smtplib.SMTP_SSL(self.s.smtp_host, 465, context=ctx, timeout=30) as smtp:
                smtp.login(self.s.smtp_user, self.s.smtp_pass)
                smtp.send_message(msg)
        else:
            with smtplib.SMTP(self.s.smtp_host, self.s.smtp_port, timeout=30) as smtp:
                smtp.starttls(context=ctx)
                smtp.login(self.s.smtp_user, self.s.smtp_pass)
                smtp.send_message(msg)


# ---------------------------------------------------------------- pages

PAGE_CSS = ("body{margin:0;background:#0b0c10;color:#e6ebf2;font:16px/1.5 system-ui,sans-serif}"
            "main{max-width:960px;margin:0 auto;padding:24px}a{color:#ffd36b}"
            "table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #2a2f37;padding:6px 8px;"
            "text-align:left;vertical-align:top}th{color:#9aa4b2;font-weight:600}pre{white-space:pre-wrap;margin:0;"
            "font:inherit}img{max-width:100%;height:auto;border:1px solid #2a2f37}.dim{color:#9aa4b2}"
            ".bad{color:#ff8a8a}.ok{color:#8fe3a1}nav a{margin-right:16px}")


def page(title: str, body: str) -> bytes:
    return (f"<!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content='width=device-width,"
            f"initial-scale=1'><meta name=robots content=noindex><title>{html.escape(title)}</title>"
            f"<style>{PAGE_CSS}</style><main>{body}</main></html>").encode()


def e(s: object) -> str:
    return html.escape(str(s), quote=True)


def message_page(title: str, text: str, back: str = "") -> bytes:
    link = f"<p><a href='{e(back)}'>Back</a></p>" if back else ""
    return page(title, f"<h1>{e(title)}</h1><p>{e(text)}</p>{link}")


def inbox_page(app: App, box: str) -> bytes:
    rows = []
    for r in app.list_box(box):
        who = next((v for k, v in r["fields"] if k.lower() in ("name", "codename")), "") or r.get("reply_to", "")
        first = next((v for k, v in r["fields"] if len(v) > 20), r["fields"][0][1] if r["fields"] else "")
        mail = ("<span class=ok>emailed</span>" if r["_emailed"] else
                f"<span class=bad title='{e(r['_failed'])}'>not sent yet</span>" if r["_failed"] else
                "<span class=dim>saved</span>")
        pics = f" · {len(r['attachments'])} picture(s)" if r.get("attachments") else ""
        rows.append(f"<tr><td><a href='/inbox/{e(r['id'])}'>{e(r['received'].replace('T', ' ')[:16])}</a></td>"
                    f"<td>{e(r.get('title', r['form']))}</td><td>{e(who[:60])}</td>"
                    f"<td>{e(first[:120])}{e(pics)}</td><td>{mail}</td></tr>")
    other = ("<a href='/inbox/'>Inbox</a> <a href='/inbox/?box=spam'><b>Spam</b></a>" if box == "spam"
             else "<a href='/inbox/'><b>Inbox</b></a> <a href='/inbox/?box=spam'>Spam</a>")
    table = ("<table><tr><th>Received (UTC)</th><th>Form</th><th>From</th><th>Message</th><th>Email</th></tr>"
             + "".join(rows) + "</table>") if rows else "<p class=dim>Nothing here yet.</p>"
    status = "Emails go out through " + e(app.s.smtp_host) if app.s.email_on else "Email is off: submissions are only saved here."
    return page("Station forms", f"<h1>Station forms</h1><nav>{other}</nav><p class=dim>{status}</p>{table}")


def detail_page(folder: Path) -> bytes:
    r = json.loads((folder / "submission.json").read_text(encoding="utf-8"))
    rows = "".join(f"<tr><th>{e(k)}</th><td><pre>{e(v)}</pre></td></tr>" for k, v in r["fields"])
    pics = "".join(f"<p><a href='/inbox/{e(r['id'])}/{e(a['file'])}'><img src='/inbox/{e(r['id'])}/{e(a['file'])}' "
                   f"alt=''></a><br><span class=dim>{e(a['original_name'])}, {a['bytes']:,} bytes</span></p>"
                   for a in r.get("attachments", []) if FILE_RE.match(a["file"]))
    notes = "".join(f"<p class=dim>Note: {e(n)}</p>" for n in r.get("notes", []))
    mail = (folder / "emailed").read_text() if (folder / "emailed").exists() else (
        (folder / "mail-error").read_text() if (folder / "mail-error").exists() else "not emailed")
    reply = f" · <a href='mailto:{e(r['reply_to'])}'>reply to {e(r['reply_to'])}</a>" if r.get("reply_to") else ""
    return page(r.get("title", "Submission"),
                f"<p><a href='/inbox/'>&larr; All submissions</a></p><h1>{e(r.get('title', r['form']))}</h1>"
                f"<p class=dim>{e(r['received'])} UTC from {e(r.get('ip', '?'))}{reply}<br>"
                f"{'Marked as spam (too many links) · ' if r.get('spam') else ''}Email: {e(mail)}</p>"
                f"<table>{rows}</table>{pics}{notes}")


def make_handler(app: App):
    inbox_csp = ("default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; "
                 "form-action 'none'; frame-ancestors 'none'")

    class Handler(BaseHTTPRequestHandler):
        server_version = "cobra-forms"
        sys_version = ""

        def log_message(self, fmt, *args):  # nginx already logs every request
            pass

        def client_ip(self) -> str:
            if app.s.trust_proxy and self.headers.get("X-Real-IP"):
                return self.headers["X-Real-IP"].strip()[:64]
            return self.client_address[0]

        def send(self, status: int, body: bytes, ctype: str = "text/html; charset=utf-8",
                 extra: dict[str, str] | None = None) -> None:
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Cache-Control", "no-store")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def do_GET(self):
            path, _, query = self.path.partition("?")
            if path == "/health":
                return self.send(200, b"ok\n", "text/plain; charset=utf-8")
            if path == "/" or path.startswith("/f/"):
                return self.send(200, message_page("Station forms", "This is where the website's forms are delivered. Nothing to see here."))
            if path == "/inbox" or path.startswith("/inbox/"):
                return self.inbox(path, query)
            return self.send(404, message_page("Not found", "Nothing here."))

        do_HEAD = do_GET

        def inbox(self, path: str, query: str):
            user = self.headers.get("Remote-User", "").strip()
            if not user or user not in app.s.inbox_users:
                return self.send(403, message_page("Not allowed", "The inbox is for the station's owner. Sign in at gate.songofeo.com first."))
            extra = {"Content-Security-Policy": inbox_csp, "X-Frame-Options": "DENY"}
            if path in ("/inbox", "/inbox/"):
                box = "spam" if urllib.parse.parse_qs(query).get("box") == ["spam"] else "inbox"
                return self.send(200, inbox_page(app, box), extra=extra)
            parts = path.split("/")[2:]
            folder = app.find(parts[0]) if parts else None
            if folder is None:
                return self.send(404, message_page("Not found", "No submission by that name."), extra=extra)
            if len(parts) == 1 or (len(parts) == 2 and parts[1] == ""):
                return self.send(200, detail_page(folder), extra=extra)
            if len(parts) == 2 and FILE_RE.match(parts[1]) and (folder / parts[1]).is_file():
                kind = parts[1].rsplit(".", 1)[1]
                return self.send(200, (folder / parts[1]).read_bytes(), IMAGE_TYPES[kind], extra=extra)
            return self.send(404, message_page("Not found", "Nothing here."), extra=extra)

        def do_POST(self):
            path = self.path.split("?", 1)[0]
            if not path.startswith("/f/"):
                return self.send(404, message_page("Not found", "Nothing here."))
            form_name = path[3:].strip("/")
            back = self.headers.get("Referer", "")
            try:
                length = int(self.headers.get("Content-Length") or "-1")
            except ValueError:
                length = -1
            try:
                if length < 0:
                    raise Reject(411, "The form was sent without a length.")
                form = app.s.forms.get(form_name)
                cap = (int(float(form.get("max_upload_mb", 6)) * 1024 * 1024) + 64 * 1024
                       if form and form.get("uploads") else MAX_TEXT_BODY)
                if length > cap:
                    raise Reject(413, "That was too big to send. Pictures must be under 5 MB.")
                body = self.rfile.read(length)
                nxt, _ = app.submit(form_name, self.client_ip(), self.headers.get("Origin", ""), back,
                                    self.headers.get("Content-Type", ""), body)
            except Reject as r:
                self.close_connection = True
                return self.send(r.status, message_page("Not sent", r.message, back if origin_of(back) else ""))
            except Exception as ex:  # a bug must never show a stack trace to a visitor
                log("error:", repr(ex))
                self.close_connection = True
                return self.send(500, message_page("Not sent", "Something went wrong on our side. Please try again later.",
                                                   back if origin_of(back) else ""))
            self.send(303, message_page("Sent", "Thank you, it's been delivered."), extra={"Location": nxt})

    return Handler


def main() -> None:
    s = Settings()
    mailer = Mailer(s)
    app = App(s, mailer)
    host, _, port = s.addr.rpartition(":")
    httpd = ThreadingHTTPServer((host or "127.0.0.1", int(port)), make_handler(app))
    httpd.daemon_threads = True
    threading.Thread(target=mailer.run_forever, daemon=True).start()
    log(f"cobra-forms on {s.addr}: forms {', '.join(sorted(s.forms)) or '(none)'}; "
        + (f"emailing to {s.mail_to} via {s.smtp_host}:{s.smtp_port}" if s.email_on else "email OFF (saving only)"))
    httpd.serve_forever()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "test-email":
        st = Settings()
        if not st.email_on:
            raise SystemExit("Email is off: FORMS_SMTP_USER or FORMS_SMTP_PASS is empty.")
        m = EmailMessage()
        m["Subject"], m["From"], m["To"] = "Station forms: test email", st.mail_from, st.mail_to
        m.set_content("If you can read this, the gate can email you form submissions.")
        Mailer(st)._smtp_send(m)
        print(f"Test email sent to {st.mail_to}.")
    else:
        main()
