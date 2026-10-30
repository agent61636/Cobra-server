#!/usr/bin/env bash
# eo-art: one random picture at a time for the station's landing pages (Cinema backdrops, album, book,
# comic and game-book covers). https://art.songofeo.com (behind the station sign-in, part 5.4).
# Needs eo_art.py from the Project-Eo repository (home/eo-art/eo_art.py) in /srv/gate/eo-art.
# Run as podsvc on the gate:  ./eo-art.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${EO_ART_IMAGE:-docker.io/library/python:3-slim}
DATA=$GATE_DATA/eo-art

preflight
need_folders "$ART_DIR/movies" "$ART_DIR/albums" "$ART_DIR/books" "$ART_DIR/comics" "$ART_DIR/gaming"
gate_pod
ensure_dir "$DATA"
[ -r "$DATA/eo_art.py" ] || die "no $DATA/eo_art.py yet. Copy it from the Project-Eo repository (home/eo-art/eo_art.py), part 5.4"

# The pictures are copies the owner puts in the art folders on dock1a; eo-art only reads them.
run_container eo-art "$GATE_POD" "$IMAGE" \
  -e EO_ART_ADDR=127.0.0.1:8790 \
  -e EO_ART_MOVIES=/art/movies -e EO_ART_RADIO=/art/albums -e EO_ART_BOOKS=/art/books \
  -e EO_ART_COMICS=/art/comics -e EO_ART_GAMING=/art/gaming \
  -v "$DATA:/app:ro,Z" \
  -v "$DISKS/$ART_DIR:/art:ro" \
  -- python3 /app/eo_art.py

# The image has no curl or wget, so ask with Python. Any HTTP answer counts (404 = that folder is still empty).
up=0
for _ in $(seq 1 15); do
  if podman exec eo-art python3 -c '
import urllib.request, urllib.error
try: urllib.request.urlopen("http://127.0.0.1:8790/cinema/backdrop", timeout=2)
except urllib.error.HTTPError: pass' 2>/dev/null; then up=1; break; fi
  sleep 2
done
[ "$up" = 1 ] || warn "eo-art isn't answering yet; check podman logs eo-art"
done_msg eo-art https://art.songofeo.com/cinema/backdrop
echo "    Fill $DISKS/$ART_DIR/{movies,albums,books,comics,gaming} with .jpg copies; eo-art rescans every 2 minutes."
