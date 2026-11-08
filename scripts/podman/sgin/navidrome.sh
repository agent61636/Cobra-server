#!/usr/bin/env bash
# Navidrome: ONE instance for all music, with a library per person (Navidrome 0.58+ multi-library).
# http://10.6.9.20:4533  (public: music.songofeo.com, and mustang.songofeo.com is the same server)
# Run as podsvc on the SGIN:  ./navidrome.sh
#
#   Library 1 "Eels"   /media/dock1a/music/eels     (ND_MUSICFOLDER below)
#   "Rachel"           /media/dock1a/music/rachel   (add once: Settings -> Libraries -> +)
# Libraries may not overlap, so the main library is music/eels, never all of music/.
# Who sees which library: Settings -> Users -> the person -> Libraries. Admins see them all.
# Comedy and The Ward (sessions) live in Audiobookshelf (docs/music.md).
#
# It trusts the gate's Remote-User header (the station's Authelia sign-in, part 5.4), so it doesn't ask twice.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${NAVIDROME_IMAGE:-docker.io/deluan/navidrome:latest}
NAME=navidrome
PORT=4533
DATA=$STREAM_DATA/$NAME

preflight
need_folders "$MUSIC_DIR/eels" "$MUSIC_DIR/rachel"
stream_pod
ensure_dir "$DATA"

run_container "$NAME" "$STREAM_POD" "$IMAGE" \
  -e ND_PORT="$PORT" \
  -e ND_MUSICFOLDER="/media/$MUSIC_DIR/eels" \
  -e ND_SESSIONTIMEOUT=8h \
  -e ND_ENABLEINSIGHTSCOLLECTOR=false \
  -e ND_REVERSEPROXYWHITELIST=10.6.9.10/32 \
  -v "$DATA:/data:Z" \
  -v "$DISKS:/media:ro,rbind"

wait_port "$PORT" 60 || warn "$NAME isn't answering on :$PORT yet; check podman logs $NAME"
done_msg "$NAME" "http://10.6.9.20:$PORT"
echo "    Once: the first visit creates its admin (eels, same as in Authelia's users.yml)."
echo "    Then Settings -> Libraries: rename Library 1 to Eels, add Rachel (/media/$MUSIC_DIR/rachel). docs/music.md"
