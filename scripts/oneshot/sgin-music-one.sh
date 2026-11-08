#!/usr/bin/env bash
# On the SGIN (cobra-stream), as eels:  bash /tmp/sgin-music-one.sh
# One Navidrome for all music, with a library per person (Navidrome 0.58+ multi-library):
#   navidrome  :4533  music.songofeo.com (mustang.songofeo.com is the same server)
#     library "Eels"   /media/dock1a/music/eels     (ND_MUSICFOLDER, Navidrome's "Library 1")
#     library "Rachel" /media/dock1a/music/rachel   (added once in Settings -> Libraries)
# Libraries may not overlap, so the main folder moves from music/ to music/eels.
#
# TALK=abs (default): comedy and sessions move to Audiobookshelf, so navidrome-comedy and
#                     navidrome-sessions are retired too.
# TALK=navidrome:     comedy stays a Navidrome on :4534 and sessions moves from :4536 to :4535.
#
# Retiring a Navidrome only stops it and moves its Quadlet file aside; its data folder
# (/srv/stream/navidrome-*) and every song stay where they are. Nothing on dock1a is touched.
# Backs up the Quadlet folder and every Navidrome database first, and asks before changing anything.
set -euo pipefail
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
ask() { local a; read -r -p "$1 [y/N] " a; [[ $a == [yY]* ]]; }
[ "$(id -un)" = eels ] || die "run this as eels (it uses sudo for podsvc's parts)"
TALK=${TALK:-abs}
[[ $TALK == abs || $TALK == navidrome ]] || die "TALK must be abs or navidrome"

TS=$(date +%Y%m%d-%H%M%S)
M=/srv/storage/disks/dock1a/music
PU=podsvc
PH=$(getent passwd $PU | cut -d: -f6)
Q=$PH/.config/containers/systemd
RET=$PH/.config/containers/retired-$TS
BK=/srv/stream/navidrome-backup-$TS.tgz
asp() { sudo -u $PU XDG_RUNTIME_DIR=/run/user/"$(id -u $PU)" "$@"; }

sudo -v
sudo test -f "$Q/navidrome.container" || die "no $Q/navidrome.container. Send Claude: sudo ls $Q"
mountpoint -q /srv/storage/disks/dock1a || die "dock1a isn't mounted (part 3.4)"
sudo test -d "$M/eels" || die "$M/eels is missing. The main collection must be in music/eels (nothing was changed)"
sudo test -d "$M/rachel" || die "$M/rachel is missing (nothing was changed)"

retire=(navidrome-rachel)
[ "$TALK" = abs ] && retire+=(navidrome-comedy navidrome-sessions)
say "Now"
sudo grep -h '^Environment=' "$Q/navidrome.container"
asp podman ps -a --format '{{.Names}}  {{.Status}}' | grep -E '^navidrome' || true
echo
echo "This will:"
echo "  1. stop every Navidrome and save their databases to $BK"
echo "  2. point navidrome (:4533) at $M/eels instead of $M"
echo "  3. retire: ${retire[*]} (stopped, Quadlet moved to $RET, data kept)"
[ "$TALK" = navidrome ] && echo "  4. move navidrome-sessions from :4536 to :4535"
echo "Stars and play counts from the last few days in navidrome may reset (the songs get new paths). The backup keeps them."
ask "Go ahead?" || die "stopped, nothing changed"

say "1/5 Stopping the Navidromes and backing up (Quadlets: $Q.bak-$TS)"
sudo cp -a "$Q" "$Q.bak-$TS"
mapfile -t all < <(sudo ls "$Q" | sed -n 's/^\(navidrome[a-z-]*\)\.container$/\1/p')
for n in "${all[@]}"; do asp systemctl --user stop "$n.service" || true; done
dirs=(); for n in "${all[@]}"; do sudo test -d "/srv/stream/$n" && dirs+=("srv/stream/$n"); done
sudo tar -C / -czpf "$BK" "${dirs[@]}"
sudo ls -lh "$BK"

say "2/5 navidrome reads music/eels"
sudo -u $PU sed -i -E 's#ND_MUSICFOLDER=/media/dock1a/music( |$)#ND_MUSICFOLDER=/media/dock1a/music/eels\1#' "$Q/navidrome.container"
sudo grep -q 'ND_MUSICFOLDER=/media/dock1a/music/eels' "$Q/navidrome.container" \
  || { sudo cp -p "$Q.bak-$TS/navidrome.container" "$Q/navidrome.container"; die "couldn't set ND_MUSICFOLDER; put back. Send Claude: sudo cat $Q/navidrome.container"; }
sudo diff "$Q.bak-$TS/navidrome.container" "$Q/navidrome.container" || true

say "3/5 Retiring ${retire[*]}"
sudo -u $PU mkdir -p "$RET"
for n in "${retire[@]}"; do
  if sudo test -f "$Q/$n.container"; then sudo -u $PU mv "$Q/$n.container" "$RET/"; echo "  $n: retired (data kept in /srv/stream/$n)"
  else echo "  $n: no Quadlet, nothing to retire"; fi
done
if [ "$TALK" = navidrome ] && sudo test -f "$Q/navidrome-sessions.container"; then
  sudo -u $PU sed -i 's/ND_PORT=4536/ND_PORT=4535/' "$Q/navidrome-sessions.container"
  sudo grep -h '^Environment=' "$Q/navidrome-sessions.container"
fi

say "4/5 Starting"
asp systemctl --user daemon-reload
start=(navidrome.service)
[ "$TALK" = navidrome ] && start+=(navidrome-comedy.service navidrome-sessions.service)
asp systemctl --user start "${start[@]}"

say "5/5 Waiting for the Navidromes"
ports=(4533); [ "$TALK" = navidrome ] && ports+=(4534 4535)
for p in "${ports[@]}"; do
  ok=; for _ in $(seq 60); do curl -fs -o /dev/null "http://127.0.0.1:$p/ping" && { ok=1; break; }; sleep 2; done
  if [ -n "$ok" ]; then echo "  OK    :$p"; else echo "  FAIL  :$p  (as podsvc: journalctl --user -u navidrome -n 50)"; fi
done
asp podman ps --format 'table {{.Names}}\t{{.Status}}'
say "Done. Undo: copy $Q.bak-$TS back over $Q, restore $BK, daemon-reload, start."
echo "Next, on the-box: http://10.6.9.20:4533 -> Settings -> Libraries (docs/music.md, step 3)."
