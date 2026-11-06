#!/usr/bin/env bash
# On the GATE, as eels:  bash /tmp/eo-art/gate-eo-art.sh
# Installs the new eo_art.py (Comedy Bay wall, recursive scans, 6 h rescan) and its folders.json,
# and lets eo-art read dock1a (read-only) so the comedy wall can use the real album covers.
# Backs up everything it changes and puts it all back if eo-art doesn't come up.
set -euo pipefail
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -un)" = eels ] || die "run this as eels (it uses sudo)"

SRC=$(cd "$(dirname "$0")" && pwd)
J=$SRC/folders.json; [ -f "$J" ] || J=$SRC/eo-art-folders.json   # the repo keeps it as eo-art-folders.json
APP=/srv/gate/eo-art
PU=podsvc
Q=$(getent passwd $PU | cut -d: -f6)/.config/containers/systemd
C=$Q/eo-art.container
TS=$(date +%Y%m%d-%H%M%S)
asp() { sudo -u $PU XDG_RUNTIME_DIR=/run/user/"$(id -u $PU)" "$@"; }

sudo -v
if [ ! -f "$SRC/eo_art.py" ] || [ ! -f "$J" ]; then die "eo_art.py (Project-Eo home/eo-art) and folders.json must sit next to this script in $SRC"; fi
sudo test -f "$C" || die "no $C (the manual's Quadlet). Send Claude: sudo ls $Q"
python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$SRC/eo_art.py" || die "eo_art.py didn't copy whole; scp it again"
python3 -m json.tool "$J" >/dev/null || die "folders.json isn't valid JSON"

say "1/4 Backups"
sudo cp -p "$C" "$C.bak-$TS"
sudo test -f "$APP/eo_art.py" && sudo cp -p "$APP/eo_art.py" "$APP/eo_art.py.bak-$TS"
echo "  $C.bak-$TS"; sudo test -f "$APP/eo_art.py.bak-$TS" && echo "  $APP/eo_art.py.bak-$TS"
restore() {
  sudo cp -p "$C.bak-$TS" "$C"
  sudo test -f "$APP/eo_art.py.bak-$TS" && sudo cp -p "$APP/eo_art.py.bak-$TS" "$APP/eo_art.py"
  [ -n "${NEWJSON:-}" ] && sudo rm -f "$APP/folders.json"
  asp systemctl --user daemon-reload; asp systemctl --user restart eo-art || true
  die "$1. Everything was put back as it was."
}

say "2/4 New eo_art.py and folders.json"
sudo install -o $PU -g $PU -m 644 "$SRC/eo_art.py" "$APP/eo_art.py"
if sudo test -f "$APP/folders.json"; then
  echo "  $APP/folders.json already exists: kept as it is (the new one is in $J to compare)"
else
  sudo install -o $PU -g $PU -m 644 "$J" "$APP/folders.json"; NEWJSON=1
  echo "  wrote $APP/folders.json"
fi

say "3/4 Let eo-art read dock1a (read-only)"
if sudo grep -q '^Volume=/srv/storage/disks/dock1a:/media/dock1a:ro' "$C"; then echo "  already there"
else
  sudo -u $PU sed -i '\#^Volume=/srv/storage/disks/dock1a/art:/art:ro#a Volume=/srv/storage/disks/dock1a:/media/dock1a:ro' "$C"
  sudo grep -q '^Volume=/srv/storage/disks/dock1a:/media/dock1a:ro' "$C" || restore "couldn't find the /art Volume line in $C"
fi
sudo grep '^Volume=' "$C"

say "4/4 Restarting eo-art"
asp systemctl --user daemon-reload
asp systemctl --user restart eo-art || restore "eo-art wouldn't start"
up=
for _ in $(seq 20); do
  if asp podman exec eo-art python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8790/ping", timeout=2)' 2>/dev/null; then up=1; break; fi
  sleep 3
done
[ -n "$up" ] || restore "eo-art isn't answering (podman logs eo-art shows why)"
for w in comedy/cover radio/cover cinema/backdrop; do
  code=$(asp podman exec eo-art python3 -c '
import sys, urllib.request, urllib.error
try: print(urllib.request.urlopen("http://127.0.0.1:8790/"+sys.argv[1], timeout=5).status)
except urllib.error.HTTPError as e: print(e.code)' "$w" 2>/dev/null || echo "?")
  case $code in 200|302) echo "  OK     $w";; 404) echo "  EMPTY  $w (no pictures found yet)";; *) echo "  ?      $w ($code)";; esac
done
say "Done. eo-art rescans every 6 hours. The Comedy Bay's walls use every folder.jpg / cover.jpg under dock1a/comedy."
