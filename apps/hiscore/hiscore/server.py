"""HTTP API and web page for the Cobra hiscore board.

Runs inside the gate pod on 127.0.0.1:8090; nginx in front does TLS, Authelia
(for people) and rate limits. Uploads authenticate with an API key.

  PUT  /api/v1/files/<system>/<file>            upload (Authorization: Bearer <key>)
  GET  /api/v1/games[?system=&q=&limit=]        newest first
  GET  /api/v1/systems
  GET  /api/v1/files/<system>/<file>            latest raw file
  GET  /api/v1/files/<system>/<file>/history    every version
  GET  /api/v1/files/<system>/<file>/versions/<id>
  GET  /healthz
  GET  /                                        the board

Settings (environment):
  HISCORE_DATA         data folder (default /data)
  HISCORE_BIND         address:port (default 127.0.0.1:8090)
  HISCORE_KEYS         file of "label sha256(key)" lines (default $HISCORE_DATA/keys.txt)
  HISCORE_MAX_BYTES    largest accepted upload (default 262144)
  HISCORE_EXTENSIONS   accepted file endings (default .hi)
  HISCORE_DECODER      optional command that turns a .hi file into JSON rows
  HISCORE_TITLES       optional romname<TAB>title file (default $HISCORE_DATA/titles.tsv)
"""

import hashlib
import hmac
import json
import os
import shlex
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

from .store import BadRequest, Store, load_titles

STATIC = Path(__file__).parent / "static"


def hash_key(key):
    return hashlib.sha256(key.encode()).hexdigest()


def load_keys(path):
    keys = {}
    p = Path(path)
    if p.exists():
        for line in p.read_text().splitlines():
            parts = line.split()
            if len(parts) == 2 and not line.startswith("#"):
                keys[parts[1].lower()] = parts[0]
    return keys


class App:
    def __init__(self, store, keys, max_bytes=262144):
        self.store, self.keys, self.max_bytes = store, keys, max_bytes

    def key_label(self, header):
        if not header or not header.startswith("Bearer "):
            return None
        presented = hash_key(header[7:].strip())
        for stored, label in self.keys.items():
            if hmac.compare_digest(stored, presented):
                return label
        return None


def make_handler(app):
    class Handler(BaseHTTPRequestHandler):
        server_version = "cobra-hiscore"
        sys_version = ""

        def log_message(self, fmt, *args):
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

        def _send(self, status, body=b"", ctype="application/json", extra=None):
            if isinstance(body, (dict, list)):
                body = json.dumps(body).encode()
            elif isinstance(body, str):
                body = body.encode()
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Cache-Control", "no-store")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def _error(self, status, msg):
            self._send(status, {"error": msg})

        def _parts(self):
            url = urlsplit(self.path)
            return [unquote(p) for p in url.path.split("/") if p], parse_qs(url.query)

        def do_HEAD(self):
            self.do_GET()

        def do_GET(self):
            parts, q = self._parts()
            try:
                if not parts:
                    return self._send(200, (STATIC / "index.html").read_bytes(), "text/html; charset=utf-8")
                if parts == ["healthz"]:
                    return self._send(200, {"ok": True})
                if parts[:2] != ["api", "v1"]:
                    return self._error(404, "not found")
                rest = parts[2:]
                if rest == ["games"]:
                    one = lambda k: (q.get(k) or [None])[0]
                    return self._send(200, app.store.games(one("system"), one("q"), one("limit") or 500))
                if rest == ["systems"]:
                    return self._send(200, app.store.systems())
                if len(rest) >= 3 and rest[0] == "files":
                    system, name, tail = rest[1], rest[2], rest[3:]
                    if not tail:
                        data = app.store.raw_bytes(system, name)
                    elif tail == ["history"]:
                        return self._send(200, app.store.history(system, name))
                    elif len(tail) == 2 and tail[0] == "versions" and tail[1].isdigit():
                        data = app.store.raw_bytes(system, name, int(tail[1]))
                    else:
                        return self._error(404, "not found")
                    if data is None:
                        return self._error(404, "no such file")
                    return self._send(200, data, "application/octet-stream",
                                      {"Content-Disposition": f'attachment; filename="{name}"'})
                return self._error(404, "not found")
            except BadRequest as e:
                return self._error(400, str(e))
            except ValueError:
                return self._error(400, "bad request")

        def do_PUT(self):
            parts, _ = self._parts()
            label = app.key_label(self.headers.get("Authorization"))
            if label is None:
                return self._error(401, "missing or wrong API key")
            if len(parts) != 5 or parts[:3] != ["api", "v1", "files"]:
                return self._error(404, "not found")
            try:
                length = int(self.headers.get("Content-Length", "-1"))
            except ValueError:
                length = -1
            if length < 0:
                return self._error(411, "Content-Length required")
            if length > app.max_bytes:
                return self._error(413, f"file larger than {app.max_bytes} bytes")
            body = self.rfile.read(length)
            source = (self.headers.get("X-Source") or label)[:64]
            mtime = (self.headers.get("X-File-Mtime") or "")[:40] or None
            try:
                changed, vid = app.store.put(parts[3], parts[4], body, mtime, source)
            except BadRequest as e:
                return self._error(400, str(e))
            if changed:
                return self._send(201, {"changed": True, "version": vid})
            return self._send(200, {"changed": False})

        def do_POST(self):
            self._error(405, "use PUT")

    return Handler


def build_from_env(env=os.environ):
    data = Path(env.get("HISCORE_DATA", "/data"))
    data.mkdir(parents=True, exist_ok=True)
    decoder = shlex.split(env["HISCORE_DECODER"]) if env.get("HISCORE_DECODER") else None
    exts = tuple(env.get("HISCORE_EXTENSIONS", ".hi").split(","))
    store = Store(data, exts, decoder, load_titles(env.get("HISCORE_TITLES", data / "titles.tsv")))
    keys = load_keys(env.get("HISCORE_KEYS", data / "keys.txt"))
    return App(store, keys, int(env.get("HISCORE_MAX_BYTES", "262144")))


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["hash-key"]:
        # Prints the line to put in keys.txt for a new API key.
        import secrets
        key = argv[2] if len(argv) > 2 else secrets.token_urlsafe(32)
        label = argv[1] if len(argv) > 1 else "cabinet"
        print(f"API key (give this to the agent, store it in your password manager): {key}")
        print(f"keys.txt line: {label} {hash_key(key)}")
        return 0
    app = build_from_env()
    if not app.keys:
        print("warning: no API keys loaded; uploads will be refused", file=sys.stderr)
    host, _, port = os.environ.get("HISCORE_BIND", "127.0.0.1:8090").rpartition(":")
    httpd = ThreadingHTTPServer((host, int(port)), make_handler(app))
    print(f"cobra-hiscore listening on {host}:{port}", file=sys.stderr)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
