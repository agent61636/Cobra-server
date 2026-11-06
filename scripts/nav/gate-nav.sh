#!/usr/bin/env bash
# Puts one N.A.V. on the gate and walls it off. On the GATE, as podsvc:
#   bash gate-nav.sh HOST PORT USER
#   e.g. bash gate-nav.sh sam 4537 sam        bash gate-nav.sh mustang 4535 rachel
#  - nginx: HOST.songofeo.com -> 10.6.9.20:PORT, and the VIP keypad sends USER there
#  - Authelia: only USER and eels may open HOST. (anyone else signed in is refused, so nobody else
#    ever gets an account auto-made in that N.A.V.)
# Backs up both files first and puts them back if nginx or Authelia rejects the change.
# Still yours to do: a Porkbun CNAME HOST -> gate.songofeo.com, and USER in Authelia's users.yml.
set -euo pipefail
H=${1:-}; P=${2:-}; U=${3:-}
NG=${NG:-/srv/gate/nginx/conf.d/songofeo.conf}
AU=${AU:-/srv/gate/authelia/configuration.yml}
UY=${UY:-/srv/gate/authelia/users.yml}
ADMIN=${ADMIN:-eels}
TS=$(date +%Y%m%d-%H%M%S)
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
[[ $H =~ ^[a-z0-9-]+$ && $P =~ ^45(3[3-9]|4[0-9])$ && $U =~ ^[a-z0-9._-]+$ ]] || die "usage: bash gate-nav.sh HOST PORT USER   (e.g. sam 4537 sam)"
[ "$(id -un)" = podsvc ] || [ -n "${TEST:-}" ] || die "run this as podsvc (sudo machinectl shell podsvc@)"
[ -f "$NG" ] && [ -f "$AU" ] || die "missing $NG or $AU"
F=$H.songofeo.com

cp -p "$NG" "$NG.bak-$TS"; cp -p "$AU" "$AU.bak-$TS"
say "Backups: $NG.bak-$TS and $AU.bak-$TS"
restore() { cp -p "$NG.bak-$TS" "$NG"; cp -p "$AU.bak-$TS" "$AU"; die "$1. Both files were put back as they were."; }

# nginx: the floors' map and server_name, and the VIP keypad's map
if grep -qE "^\s*${F//./\\.}\s+http" "$NG"; then
  sed -i -E "s#^(\s*${F//./\\.}\s+)http://[0-9.]+:[0-9]+;#\1http://10.6.9.20:$P;#" "$NG"
else
  sed -i -E "/^map \\\$host \\\$station \{/a\  $F   http://10.6.9.20:$P;    # Cobra N.A.V. ($U)" "$NG"
fi
grep -qE "server_name .*music\.songofeo\.com.*\b${F//./\\.}\b" "$NG" \
  || sed -i -E "0,/server_name music\.songofeo\.com/s#server_name music\.songofeo\.com#server_name music.songofeo.com $F#" "$NG"
if grep -qE "^\s*$U\s+https://" <(sed -n '/^map \$vip_user/,/^}/p' "$NG"); then
  sed -i -E "/^map \\\$vip_user/,/^}/s#^(\s*$U\s+)https://[^;]*;#\1https://$F/;#" "$NG"
else
  sed -i -E "/^map \\\$vip_user/a\  $U   https://$F/;" "$NG"
fi

# Authelia: a walled rule for this one name, placed above the station's shared rule (first match wins)
if grep -q "# N.A.V. wall: $F" "$AU"; then
  echo "  Authelia wall for $F already there"
else
  awk -v f="$F" -v u="$U" -v a="$ADMIN" '
    { line[NR]=$0 }
    !at && /^[[:space:]]*- domain: &station/ { at=NR }
    END {
      if (!at) exit 3
      ins = (at > 1 && line[at-1] ~ /^[[:space:]]*#/) ? at-1 : at
      ind = line[at]; sub(/-.*/, "", ind)
      for (i = 1; i <= NR; i++) {
        if (i == ins) {
          print ind "# N.A.V. wall: " f " (only " u " and " a ")"
          print ind "- domain: " f
          print ind "  subject: [\"user:" u "\", \"user:" a "\"]"
          print ind "  policy: one_factor"
          print ind "- domain: " f
          print ind "  policy: deny"
        }
        print line[i]
      }
    }' "$AU.bak-$TS" > "$AU.tmp" || { rm -f "$AU.tmp"; restore "couldn't find the '- domain: &station' rule in $AU"; }
  cat "$AU.tmp" > "$AU"; rm -f "$AU.tmp"
fi
grep -qE "^\s+$U:\s*$" "$UY" 2>/dev/null || echo "  NOTE: no '$U:' in $UY yet. Add them (manual 5.4, users.yml) before they sign in."
diff "$NG.bak-$TS" "$NG" || true
diff "$AU.bak-$TS" "$AU" || true

[ -n "${TEST:-}" ] && { say "TEST mode: files edited, nothing restarted"; exit 0; }
say "Checking nginx"
podman exec nginx nginx -t || restore "nginx rejected the new config"
say "Checking Authelia"
podman exec authelia authelia validate-config --config /config/configuration.yml || restore "Authelia rejected the new config"
systemctl --user restart authelia
sleep 5
systemctl --user is-active --quiet authelia || restore "Authelia didn't come back up"
podman exec nginx nginx -s reload
say "Done. https://$F opens $U's N.A.V. (and yours). Porkbun: CNAME $H -> gate.songofeo.com if it isn't there yet."
