#!/usr/bin/env bash
# Opens the N.A.V. clone slots (ports 4537-4549) once. On the SGIN, as eels:  bash nav-vat.sh
#  1. nftables: lets the LAN and WireGuard reach 4537-4549 (backup, syntax check, rollback on failure)
#  2. stream.pod: publishes 4537-4549 (backup of the Quadlet folder first)
#  3. restarts the stream pod once, after asking (Jellyfin and the rest drop for about a minute)
# After this, new N.A.V.s never need a pod restart or a firewall change.
set -euo pipefail
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -un)" = eels ] || die "run this as eels (it uses sudo for the system parts)"
TS=$(date +%Y%m%d-%H%M%S)
PU=podsvc
PH=$(getent passwd $PU | cut -d: -f6)
Q=$PH/.config/containers/systemd
NFT=/etc/nftables.conf
asp() { sudo -u $PU XDG_RUNTIME_DIR=/run/user/"$(id -u $PU)" "$@"; }
sudo -v
sudo test -f "$Q/stream.pod" || die "no $Q/stream.pod"

say "1/3 Firewall"
if sudo grep -q '4537-4549' $NFT; then echo "already open"
else
  sudo cp -p $NFT $NFT.bak-$TS
  sudo sed -i 's/ 4536, / 4536, 4537-4549, /' $NFT
  sudo grep -q '4537-4549' $NFT || { sudo cp -p $NFT.bak-$TS $NFT; die "couldn't find 4536 in $NFT; nothing changed"; }
  sudo nft -c -f $NFT || { sudo cp -p $NFT.bak-$TS $NFT; die "nftables rejected the change; put back"; }
  sudo systemctl reload nftables || sudo systemctl restart nftables
  echo "backup: $NFT.bak-$TS"
fi
sudo nft list ruleset | grep -o '4537-4549' | head -n1

say "2/3 stream.pod"
if sudo grep -q '^PublishPort=4537-4549:4537-4549' "$Q/stream.pod"; then echo "already published"; changed=
else
  sudo cp -a "$Q" "$Q.bak-$TS"; echo "backup: $Q.bak-$TS"
  sudo -u $PU sed -i '/^PublishPort=4536:4536/a PublishPort=4537-4549:4537-4549' "$Q/stream.pod"
  sudo grep -q '^PublishPort=4537-4549' "$Q/stream.pod" || die "couldn't find PublishPort=4536:4536 in stream.pod"
  changed=1
fi
sudo -u $PU mkdir -p /srv/stream/navs

say "3/3 Pod restart"
[ -n "$changed" ] || { echo "not needed"; exit 0; }
read -rp "Restart the stream pod now? Everything in it drops for about a minute. [y/N] " a
[[ $a =~ ^[Yy]$ ]] || { echo "Later, as podsvc: systemctl --user daemon-reload && systemctl --user restart stream-pod"; exit 0; }
asp systemctl --user daemon-reload
running=$(asp systemctl --user list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | grep -vE '^(stream-pod|podman-restart)\.service$' || true)
asp systemctl --user restart stream-pod
# shellcheck disable=SC2086
[ -z "$running" ] || asp systemctl --user start $running
asp podman ps --format 'table {{.Names}}\t{{.Status}}'
say "Done. Slots 4537-4549 are open."
