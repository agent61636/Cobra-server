#!/usr/bin/env bash
# shellcheck disable=SC2016  # $abs_shelf and friends are nginx variables, written literally
# On the GATE, as podsvc:  bash /home/podsvc/gate-music-one.sh
# Points the gate at the one Navidrome and walls it off:
#   music.   and mustang.  -> 10.6.9.20:4533 (one Navidrome, a library per person)
#   TALK=abs (default):      comedy. and sessions. -> Audiobookshelf 10.6.9.20:13378
#   TALK=navidrome:          comedy. -> :4534, sessions. -> :4535 (their own Navidromes)
# Authelia wall: only MUSIC_USERS (default "eels rachel") may open music. and mustang.; anyone else
# signed in is refused, so Navidrome never auto-makes an account for them. Replaces the old
# N.A.V. walls for those two names.
# Optional, TALK=abs: COMEDY_SHELF=/path SESSIONS_SHELF=/path send the bare comedy. and sessions.
# addresses straight to their Audiobookshelf library (copy the path from the browser's address bar
# with that library open, everything after .songofeo.com).
# Backs up both files first and puts them back if nginx or Authelia rejects the change.
set -euo pipefail
NG=${NG:-/srv/gate/nginx/conf.d/songofeo.conf}
AU=${AU:-/srv/gate/authelia/configuration.yml}
TALK=${TALK:-abs}
MUSIC_USERS=${MUSIC_USERS:-eels rachel}
COMEDY_SHELF=${COMEDY_SHELF:-}
SESSIONS_SHELF=${SESSIONS_SHELF:-}
TS=$(date +%Y%m%d-%H%M%S)
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -un)" = podsvc ] || [ -n "${TEST:-}" ] || die "run this as podsvc (sudo machinectl shell podsvc@)"
[[ $TALK == abs || $TALK == navidrome ]] || die "TALK must be abs or navidrome"
for s in "$COMEDY_SHELF" "$SESSIONS_SHELF"; do
  [ -z "$s" ] || [[ $s =~ ^/[A-Za-z0-9/_-]+$ ]] || die "a shelf path looks like /audiobookshelf/library/<id> (got: $s)"
done
for u in $MUSIC_USERS; do [[ $u =~ ^[a-z0-9._-]+$ ]] || die "bad username in MUSIC_USERS: $u"; done
if [ ! -f "$NG" ] || [ ! -f "$AU" ]; then die "missing $NG or $AU"; fi

cp -p "$NG" "$NG.bak-$TS"; cp -p "$AU" "$AU.bak-$TS"
say "Backups: $NG.bak-$TS and $AU.bak-$TS"
restore() { cp -p "$NG.bak-$TS" "$NG"; cp -p "$AU.bak-$TS" "$AU"; die "$1. Both files were put back as they were."; }
grep -qE '^\s*music\.songofeo\.com\s+http' "$NG" || restore "no music.songofeo.com line in the \$station map of $NG"

# nginx: the $station map. set_station NAME URL COMMENT (replaces the line, or adds it under music.)
set_station() {
  local re="^\s*${1//./\\.}\s+http"
  if grep -qE "$re" "$NG"; then
    sed -i -E "s#^(\s*${1//./\\.}\s+)http://[0-9.]+:[0-9]+;.*#\1$2;    \# $3#" "$NG"
  else
    sed -i -E "/^\s*music\.songofeo\.com\s+http/a\  $1   $2;    # $3" "$NG"
  fi
}
sed -i -E "s#^(\s*music\.songofeo\.com\s+)http://[0-9.]+:[0-9]+;.*#\1http://10.6.9.20:4533;    \# Music: the one Navidrome (a library per person)#" "$NG"
set_station mustang.songofeo.com http://10.6.9.20:4533 "Rachel's music: same Navidrome as music., her own library"
if [ "$TALK" = abs ]; then
  set_station comedy.songofeo.com   http://10.6.9.20:13378 "stand-up albums: Audiobookshelf library Comedy"
  set_station sessions.songofeo.com http://10.6.9.20:13378 "The Ward: Audiobookshelf podcast library Sessions"
  # Audiobookshelf's phone app works on all three names
  sed -i -E 's#~\^books\\\.songofeo\\\.com/\(api#~^(books|comedy|sessions)\\.songofeo\\.com/(api#' "$NG"
else
  set_station comedy.songofeo.com   http://10.6.9.20:4534 "stand-up albums, their own Navidrome"
  set_station sessions.songofeo.com http://10.6.9.20:4535 "The Ward: recorded podcasts, their own Navidrome"
fi
# every name on the floors' server_name line, and sessions. off the holding page
sed -i 's#server_name gaming\.songofeo\.com sessions\.songofeo\.com;#server_name gaming.songofeo.com;#' "$NG"
for n in mustang comedy sessions; do
  grep -qE "server_name .*\b$n\.songofeo\.com\b" "$NG" \
    || sed -i -E "0,/server_name .*music\.songofeo\.com/s#(server_name .*)\bmusic\.songofeo\.com#\1music.songofeo.com $n.songofeo.com#" "$NG"
done

# nginx, optional: the bare comedy./sessions. address opens its Audiobookshelf library
if [ "$TALK" = abs ] && { [ -n "$COMEDY_SHELF" ] || [ -n "$SESSIONS_SHELF" ]; }; then
  awk -v c="$COMEDY_SHELF" -v s="$SESSIONS_SHELF" '
    /^# --- abs shelves ---$/ { skip=1; next }
    skip && /^}$/ { skip=0; next }
    skip { next }
    { print }
    /^map "\$app_api\$subsonic_api" \$own_login/ && !done {
      print "# --- abs shelves ---"
      print "map \"$host$request_uri\" $abs_shelf {   # the bare comedy./sessions. address opens its Audiobookshelf library"
      if (c != "") print "  \"comedy.songofeo.com/\"     " c ";"
      if (s != "") print "  \"sessions.songofeo.com/\"   " s ";"
      print "  default \"\";"
      print "}"
      done=1
    }' "$NG" > "$NG.tmp"
  cat "$NG.tmp" > "$NG"; rm -f "$NG.tmp"
  grep -q 'abs_shelf {' "$NG" || restore "couldn't find the \$own_login map (run gate-apps.sh first)"
  if ! grep -q 'if ($abs_shelf)' "$NG"; then
    awk '{ print }
      !done && /include \/etc\/nginx\/conf\.d\/station-cors\*\.inc;  # the website/ {
        print "    if ($abs_shelf) { return 302 $abs_shelf; }   # comedy./sessions.: straight to their library"; done=1 }' "$NG" > "$NG.tmp"
    cat "$NG.tmp" > "$NG"; rm -f "$NG.tmp"
  fi
  grep -q 'if ($abs_shelf)' "$NG" || restore "couldn't find the floors' location / (the station-cors include line)"
fi

# Authelia: one wall for music. and mustang., above the station's shared rule (first match wins).
# Old N.A.V. walls for those two names (6 lines each, from gate-nav.sh) and an older music wall go first.
subj=""; for u in $MUSIC_USERS; do subj+="${subj:+, }\"user:$u\""; done
awk -v subj="$subj" '
  { line[NR]=$0 }
  END {
    for (i = 1; i <= NR; i++) {
      if (line[i] ~ /# N\.A\.V\. wall: (music|mustang)\.songofeo\.com/) { i += 5; continue }
      if (line[i] ~ /# Music wall: music\. and mustang\./) {   # its comment lines, then 5 rule lines
        i++; while (i <= NR && line[i] ~ /^[[:space:]]*#/) i++; i += 4; continue }
      keep[++n] = line[i]
    }
    for (i = 1; i <= n; i++) if (!at && keep[i] ~ /^[[:space:]]*- domain: &station/) at = i
    if (!at) exit 3
    ins = at; while (ins > 1 && keep[ins-1] ~ /^[[:space:]]*#/) ins--
    ind = keep[at]; sub(/-.*/, "", ind)
    for (i = 1; i <= n; i++) {
      if (i == ins) {
        print ind "# Music wall: music. and mustang. (one Navidrome): only these people, anyone else is refused"
        print ind "- domain: [music.songofeo.com, mustang.songofeo.com]"
        print ind "  subject: [" subj "]"
        print ind "  policy: one_factor"
        print ind "- domain: [music.songofeo.com, mustang.songofeo.com]"
        print ind "  policy: deny"
      }
      print keep[i]
    }
  }' "$AU.bak-$TS" > "$AU.tmp" || { rm -f "$AU.tmp"; restore "couldn't find the '- domain: &station' rule in $AU"; }
cat "$AU.tmp" > "$AU"; rm -f "$AU.tmp"
grep -q 'comedy\.songofeo\.com' "$AU" || sed -i 's#mustang\.songofeo\.com,#mustang.songofeo.com, comedy.songofeo.com,#' "$AU"

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
say "Done. music. and mustang. open the one Navidrome (only: $MUSIC_USERS)."
[ "$TALK" = abs ] && echo "    comedy. and sessions. open Audiobookshelf." || echo "    comedy. -> :4534, sessions. -> :4535."
