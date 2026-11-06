#!/usr/bin/env bash
# On the SGIN (cobra-stream), as eels:  bash /tmp/sgin-navidromes.sh
# Four separate Navidromes in the stream pod:
#   navidrome          :4533  dock1a/music          music.songofeo.com     (Eels, sees everything)
#   navidrome-comedy   :4534  dock1a/comedy         comedy.songofeo.com
#   navidrome-rachel   :4535  dock1a/music/rachel   mustang.songofeo.com
#   navidrome-sessions :4536  dock1a/sessions       sessions.songofeo.com  (recorded podcasts)
# Backs up every file it changes. Restarts the stream pod once (Jellyfin and the rest drop for about a minute).
set -euo pipefail
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -un)" = eels ] || die "run this as eels (it uses sudo for the system parts)"

TS=$(date +%Y%m%d-%H%M%S)
D=/srv/storage/disks/dock1a
PU=podsvc
PH=$(getent passwd $PU | cut -d: -f6)
Q=$PH/.config/containers/systemd
asp() { sudo -u $PU XDG_RUNTIME_DIR=/run/user/"$(id -u $PU)" "$@"; }

sudo -v
# shellcheck disable=SC2015  # die runs only when a test fails
sudo test -f "$Q/navidrome.container" && sudo test -f "$Q/stream.pod" \
  || die "no Quadlet files in $Q (navidrome.container + stream.pod). Send Claude: sudo ls $Q"
mountpoint -q /srv/storage/disks/dock1a || die "dock1a isn't mounted (part 3.4)"

say "1/5 Folders"
for f in comedy sessions music/rachel; do
  sudo mkdir -p "$D/$f"
  sudo chown --reference="$D/music" "$D/$f"; sudo chmod --reference="$D/music" "$D/$f"
done
ls -ld "$D/comedy" "$D/sessions" "$D/music/rachel"

say "2/5 Firewall: open 4534-4536 to the LAN and WireGuard (same rule as 4533)"
NFT=/etc/nftables.conf
if sudo grep -q '4536' $NFT; then echo "already open"
else
  sudo cp -p $NFT "$NFT.bak-$TS"
  sudo sed -i 's/ 4533, / 4533, 4534, 4535, 4536, /' $NFT
  sudo grep -q '4536' $NFT || { sudo cp -p "$NFT.bak-$TS" $NFT; die "couldn't find 4533 in $NFT; nothing changed"; }
  sudo nft -c -f $NFT || { sudo cp -p "$NFT.bak-$TS" $NFT; die "nftables rejected the change; put back"; }
  sudo systemctl reload nftables || sudo systemctl restart nftables
  echo "backup: $NFT.bak-$TS"
fi

say "3/5 Quadlet files (backup: $Q.bak-$TS)"
sudo cp -a "$Q" "$Q.bak-$TS"
for p in 4534 4535 4536; do
  sudo grep -q "^PublishPort=$p:$p" "$Q/stream.pod" || sudo -u $PU sed -i "/^PublishPort=4533:4533/a PublishPort=$p:$p" "$Q/stream.pod"
done
# Eels' Navidrome reads all of music/ (it used to read music/eels only)
sudo -u $PU sed -i -E 's#ND_MUSICFOLDER=/media/dock1a/music/eels( |$)#ND_MUSICFOLDER=/media/dock1a/music\1#' "$Q/navidrome.container"
mk() {  # mk NAME PORT FOLDER
  [ -f "$Q/$1.container" ] && { echo "$1.container exists, kept"; return; }
  sudo -u $PU mkdir -p "/srv/stream/$1"
  sudo -u $PU tee "$Q/$1.container" >/dev/null <<EOF
[Container]
ContainerName=$1
Image=docker.io/deluan/navidrome:latest
Pod=stream.pod
AutoUpdate=registry
Environment=ND_PORT=$2 ND_SESSIONTIMEOUT=8h ND_MUSICFOLDER=/media/$3 ND_REVERSEPROXYWHITELIST=10.6.9.10/32
Volume=/srv/stream/$1:/data:Z
Volume=/srv/storage/disks:/media:ro,rbind
[Install]
WantedBy=default.target
EOF
  echo "wrote $1.container"
}
mk navidrome-comedy   4534 dock1a/comedy
mk navidrome-rachel   4535 dock1a/music/rachel
mk navidrome-sessions 4536 dock1a/sessions
grep -h '^PublishPort' "$Q/stream.pod" | tr '\n' ' '; echo

say "4/5 Restarting the stream pod with the new ports"
asp systemctl --user daemon-reload
running=$(asp systemctl --user list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | grep -E '^(jellyfin|ersatztv|audiobookshelf|kavita|navidrome|romm-db|romm)\.service$' || true)
asp systemctl --user restart stream-pod
# shellcheck disable=SC2086
asp systemctl --user start $running navidrome.service navidrome-comedy.service navidrome-rachel.service navidrome-sessions.service

say "5/5 Waiting for the four Navidromes"
for p in 4533 4534 4535 4536; do
  command -v curl >/dev/null || { echo "  (no curl, skipped :$p)"; continue; }
  ok=; for _ in $(seq 60); do curl -fs -o /dev/null "http://127.0.0.1:$p/ping" && { ok=1; break; }; sleep 2; done
  if [ -n "$ok" ]; then echo "  OK    :$p"; else echo "  FAIL  :$p  (journalctl --user -u navidrome... as podsvc)"; fi
done
asp podman ps --format 'table {{.Names}}\t{{.Status}}'
say "Done. First visit to each new one (http://10.6.9.20:4534, :4535, :4536 from the-box) creates its admin."
