#!/usr/bin/env bash
# On the GATE, as podsvc:  bash /tmp/gate-navidromes.sh
# Points the gate at the four Navidromes: music :4533, comedy :4534, mustang :4535, sessions :4536.
# Backs up both files first and puts them back if nginx or Authelia rejects the change.
set -euo pipefail
NG=${NG:-/srv/gate/nginx/conf.d/songofeo.conf}
AU=${AU:-/srv/gate/authelia/configuration.yml}
TS=$(date +%Y%m%d-%H%M%S)
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -un)" = podsvc ] || [ -n "${TEST:-}" ] || die "run this as podsvc (sudo machinectl shell podsvc@)"
[ -f "$NG" ] && [ -f "$AU" ] || die "missing $NG or $AU"

cp -p "$NG" "$NG.bak-$TS"; cp -p "$AU" "$AU.bak-$TS"
say "Backups: $NG.bak-$TS and $AU.bak-$TS"
restore() { cp -p "$NG.bak-$TS" "$NG"; cp -p "$AU.bak-$TS" "$AU"; die "$1. Both files were put back as they were."; }

# nginx: mustang -> its own port, add comedy and sessions to the map and the floors' server_name,
# and take sessions off the holding page.
sed -i -E 's#^(\s*mustang\.songofeo\.com\s+)http://10\.6\.9\.20:4533;.*#\1http://10.6.9.20:4535;    \# Rachel'"'"'s own Navidrome#' "$NG"
grep -q '^\s*comedy\.songofeo\.com\s' "$NG" || sed -i -E '/^\s*mustang\.songofeo\.com\s+http/a\  comedy.songofeo.com       http://10.6.9.20:4534;    # stand-up albums, their own Navidrome' "$NG"
grep -q '^\s*sessions\.songofeo\.com\s' "$NG" || sed -i -E '/^\s*comedy\.songofeo\.com\s+http/a\  sessions.songofeo.com     http://10.6.9.20:4536;    # recorded podcasts, their own Navidrome' "$NG"
grep -qE 'server_name music\.songofeo\.com mustang\.songofeo\.com comedy' "$NG" \
  || sed -i -E 's#server_name music\.songofeo\.com mustang\.songofeo\.com#server_name music.songofeo.com mustang.songofeo.com comedy.songofeo.com sessions.songofeo.com#' "$NG"
sed -i 's#server_name gaming\.songofeo\.com sessions\.songofeo\.com;#server_name gaming.songofeo.com;#' "$NG"

# Authelia: comedy joins the floors (sessions is already there).
grep -q 'comedy\.songofeo\.com' "$AU" || sed -i 's#mustang\.songofeo\.com,#mustang.songofeo.com, comedy.songofeo.com,#' "$AU"

[ -n "${TEST:-}" ] && { say "TEST mode: files edited, nothing restarted"; exit 0; }

say "Checking nginx"
podman exec nginx nginx -t || restore "nginx rejected the new config"
say "Checking Authelia"
podman exec authelia authelia validate-config --config /config/configuration.yml || restore "Authelia rejected the new config"

systemctl --user restart authelia
podman exec nginx nginx -s reload
say "Done. The gate now sends music. comedy. mustang. sessions. to their own Navidromes."
