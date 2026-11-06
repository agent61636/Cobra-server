#!/usr/bin/env bash
# SGIN, as podsvc:  bash /tmp/cobra-arcade/romm-platforms.sh
# Adds the cabinet's folder map (written by the cabinet's 03-roms-map.ps1) to RomM's config.yml.
# Backs config.yml up first, only adds when there's no platforms: section yet, then restarts RomM.
set -euo pipefail
DISKS=${COBRA_DISKS:-/srv/storage/disks}
CFG=${COBRA_DATA:-/srv/stream}/romm/config/config.yml
MAP=$DISKS/dock1a/backups/arcade/romm-platforms.yml
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -un)" = podsvc ] || die "run as podsvc: sudo machinectl shell podsvc@"
[ -r "$MAP" ] || die "no $MAP yet: run 03-roms-map.ps1 on the cabinet first"
[ -f "$CFG" ] || die "no $CFG yet: run romm-up.sh first"
grep -q '^ *platforms:' "$CFG" && die "$CFG already has a platforms: section. Edit it by hand: nano $CFG"
grep -q '^system:' "$CFG" && die "$CFG already has a system: section. Paste the lines of $MAP under it by hand: nano $CFG"
cp -p "$CFG" "$CFG.bak-$(date +%Y%m%d-%H%M%S)"
{ printf 'system:\n'; sed 's/\r$//; s/^/  /' "$MAP"; } >>"$CFG"
say "added the folder map to $CFG (backup next to it)"
cat "$CFG"
systemctl --user restart romm
say "RomM restarted. Now RomM -> Library -> Scan"
