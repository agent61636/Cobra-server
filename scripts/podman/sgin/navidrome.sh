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
# ExtAuth is what current Navidrome calls that trust (ND_EXTAUTH_TRUSTEDSOURCES). The old
# ND_REVERSEPROXYWHITELIST name still maps to it. A missing setting means Navidrome ignores
# the header and shows its own login: an Authelia password does not work there.
# The web UI creates a missing user on the first page load (random password). /rest/ does not.
# The username must match Authelia exactly. tv. never sends this header; Jellyfin has its own users.
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
  -e ND_EXTAUTH_TRUSTEDSOURCES=10.6.9.10/32 \
  -e ND_EXTAUTH_USERHEADER=Remote-User \
  -v "$DATA:/data:Z" \
  -v "$DISKS:/media:ro,rbind"

wait_port "$PORT" 60 || warn "$NAME isn't answering on :$PORT yet; check podman logs $NAME"
done_msg "$NAME" "http://10.6.9.20:$PORT"
echo "    Once: the first visit creates its admin (eels, same username as in Authelia's users file)."
echo "    A later account is created when that person loads the web UI, not from a phone app's /rest/."
echo "    Then Settings -> Libraries: rename Library 1 to Eels, add Rachel (/media/$MUSIC_DIR/rachel). docs/music.md"
echo "    Tick libraries per user. Authelia's music wall still has to allow them (group music). docs/gate-sso-tv-runbook.md"
