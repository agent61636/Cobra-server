#!/usr/bin/env bash
# Starts (or, with UPDATE=1, updates) every app on the SGIN, in order. Run as podsvc.
# Skips the radio unless radio.liq is in place.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for s in jellyfin ersatztv navidrome audiobookshelf kavita romm; do
  "$here/$s.sh"
  echo
done
for who in rachel comedy sessions; do "$here/navidrome.sh" "$who"; echo; done
liq=${COBRA_DATA:-/srv/stream}/radio/radio.liq
if [ -r "$liq" ]; then "$here/radio.sh"; else echo "==> skipping the radio (no $liq yet, part 8)"; fi
podman ps --pod --format 'table {{.Names}}\t{{.Status}}\t{{.PodName}}'
