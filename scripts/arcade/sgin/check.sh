#!/usr/bin/env bash
# SGIN (cobra-stream), as eels:  bash /tmp/cobra-arcade/check.sh
# shellcheck disable=SC2015  # ok() never fails, so A && ok || bad is safe here
# Read-only. Checks what RomM and the cabinet's nightly copy need on the SGIN. Changes nothing.
set -uo pipefail
DISKS=${COBRA_DISKS:-/srv/storage/disks}
ROMS=$DISKS/dock1b/roms
DATA=${COBRA_DATA:-/srv/stream}/romm
fails=0
ok()   { printf '\033[32m  OK  \033[0m %s\n' "$*"; }
bad()  { printf '\033[31m FAIL \033[0m %s\n' "$*"; fails=$((fails + 1)); }
info() { printf '\033[36m  ..  \033[0m %s\n' "$*"; }

[ "$(id -un)" = eels ] || info "running as $(id -un); this is meant for eels"
sudo -v || { echo "needs sudo (eels' password)"; exit 1; }

echo "== dock1b and the roms folder"
if mountpoint -q "$DISKS/dock1b"; then ok "dock1b mounted at $DISKS/dock1b"
else bad "dock1b is not mounted (part 3.4). Check: lsblk -f ; grep dock1b /etc/fstab"; fi
if [ -d "$ROMS" ]; then
  ok "$ROMS exists ($(stat -c '%U:%G %a' "$ROMS"))"
  [ "$(stat -c %G "$ROMS")" = media ] || bad "$ROMS group is $(stat -c %G "$ROMS"), should be media. Fix: sudo chgrp -R media $ROMS"
  [ $(( 0$(stat -c %a "$ROMS") & 02070 )) -eq $(( 02070 )) ] || bad "$ROMS needs group rwx + setgid (2775). Fix: sudo chmod 2775 $ROMS"
  info "dock1b free: $(df -h --output=avail "$DISKS/dock1b" | tail -1 | tr -d ' ')  used by roms: $(sudo du -sh "$ROMS" 2>/dev/null | cut -f1)"
  info "platform folders: $(find "$ROMS" -mindepth 1 -maxdepth 1 -type d -printf '%f ' | head -c 600)"
else bad "$ROMS is missing. Fix: sudo install -d -o eels -g media -m 2775 $ROMS"; fi

echo "== users"
if id podsvc >/dev/null 2>&1; then
  id -nG podsvc | tr ' ' '\n' | grep -qx media && ok "podsvc is in group media" || bad "podsvc is not in group media. Fix: sudo usermod -aG media podsvc"
  loginctl show-user podsvc -p Linger 2>/dev/null | grep -q yes && ok "podsvc has linger" || bad "podsvc has no linger. Fix: sudo loginctl enable-linger podsvc"
else bad "user podsvc is missing (part 3.5)"; fi
if id arcade >/dev/null 2>&1; then
  id -nG arcade | tr ' ' '\n' | grep -qx media && ok "Linux user arcade exists, in media" || bad "arcade is not in media. Fix: sudo usermod -aG media arcade"
else bad "Linux user arcade is missing. Fix: sudo useradd -M -s /usr/sbin/nologin -G media arcade"; fi
sudo pdbedit -L 2>/dev/null | grep -q '^arcade:' && ok "Samba login arcade exists" || bad "no Samba login for arcade. Fix: sudo smbpasswd -a arcade"

echo "== Samba"
systemctl is-active --quiet smbd && ok "smbd running" || bad "smbd is not running. Fix: sudo systemctl enable --now smbd"
shares=$(sudo testparm -s 2>/dev/null)
grep -q '^\[roms\]' <<<"$shares" && ok "share [roms] defined" || bad "share [roms] missing in /etc/samba/smb.conf (part 3.6)"
grep -q '^\[media\]' <<<"$shares" && ok "share [media] defined" || bad "share [media] missing in /etc/samba/smb.conf (part 3.6)"

echo "== firewall (nftables)"
rules=$(sudo nft list ruleset 2>/dev/null)
grep -Eq 'dport .*\b8080\b' <<<"$rules" && ok "8080 (RomM) allowed from LAN/WireGuard" || bad "8080 isn't in the nftables accept list (part 3.7, /etc/nftables.conf)"
grep -Eq 'dport .*\b445\b' <<<"$rules" && ok "445 (Samba) allowed" || bad "445 isn't in the nftables accept list (part 3.7)"

echo "== RomM data folder"
if [ -d "$DATA" ]; then
  ok "$DATA exists ($(stat -c '%U' "$DATA"))"
  if [ -n "$(sudo ls -A "$DATA/db" 2>/dev/null)" ]; then info "$DATA/db already has a database: romm-up.sh needs its old password (it will tell you)"; fi
elif [ -d "$(dirname "$DATA")" ]; then info "$DATA not made yet; romm-up.sh makes it"
else bad "$(dirname "$DATA") is missing. Fix: sudo install -d -o podsvc -g podsvc /srv/stream"; fi

echo "== how the stream pod is run"
Q=/home/podsvc/.config/containers/systemd
if sudo test -f "$Q/stream.pod"; then
  ok "Quadlet files ($Q/stream.pod): romm-up.sh writes romm Quadlets"
  sudo grep -q 'PublishPort=8080:8080' "$Q/stream.pod" && ok "stream.pod publishes 8080" || bad "stream.pod doesn't publish 8080: add PublishPort=8080:8080 to $Q/stream.pod"
  for f in romm.container romm-db.container; do sudo test -f "$Q/$f" && info "$f already exists (romm-up.sh leaves it as it is)"; done
else
  info "no stream.pod Quadlet: romm-up.sh uses the podman scripts (romm.sh)"
fi

echo
if [ "$fails" -eq 0 ]; then printf '\033[32mALL GOOD.\033[0m Next: sudo machinectl shell podsvc@  then  bash /tmp/cobra-arcade/romm-up.sh\n'
else printf '\033[31m%s problem(s).\033[0m Fix the FAIL lines, then run this again.\n' "$fails"; exit 1; fi
