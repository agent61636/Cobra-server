#!/usr/bin/env bash
# On the GATE, as podsvc:  bash /home/podsvc/gate-apps.sh
# Lets the apps' own phone apps through the gate's sign-in, which an app can't show.
# Only each app's API paths skip Authelia; the app then checks its own username and password.
# The web pages stay behind the sign-in, and the N.A.V. walls still guard every Navidrome's web page.
#   every Navidrome (ports 4533-4549)  /rest/          Subsonic apps: Symphonium, DSub, Substreamer ...
#   books.  Audiobookshelf             /api/ /login /status /ping /socket.io/ /hls/ /auth/ /feed/ /public/
#   comics. Kavita                     /api/           Paperback / Mihon Kavita extension, OPDS readers
#   arcade. RomM                       /api/
#   papers. Paperless                  /api/           Paperless mobile apps (password or token, no TOTP)
# Nobody can pass as someone else: when the sign-in is skipped no Remote-User reaches the app.
# Backs up songofeo.conf first and puts it back if nginx rejects the change.
set -euo pipefail
NG=${NG:-/srv/gate/nginx/conf.d/songofeo.conf}
TS=$(date +%Y%m%d-%H%M%S)
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -un)" = podsvc ] || [ -n "${TEST:-}" ] || die "run this as podsvc (sudo machinectl shell podsvc@)"
[ -f "$NG" ] || die "missing $NG"
# shellcheck disable=SC2016  # the $ are nginx variables, matched literally
if grep -q '^map "\$host\$request_uri" \$app_api' "$NG"; then say "Already done: the phone apps' paths are open"; exit 0; fi

cp -p "$NG" "$NG.bak-$TS"
say "Backup: $NG.bak-$TS"
restore() { cp -p "$NG.bak-$TS" "$NG"; die "$1. songofeo.conf was put back as it was."; }

rc=0
awk '
  /^map \$host \$station \{/ { inmap=1 }
  inmap && /^\}/ {
    print; inmap=0; mapdone=1
    print "# --- Phone apps: their API paths skip the gate sign-in (an app cannot show it); the app checks its own login ---"
    print "map \"$host$request_uri\" $app_api {"
    print "  ~\\.\\.                                                                     0;   # never a path with .. in it"
    print "  ~*%2e                                                                     0;"
    print "  ~^books\\.songofeo\\.com/(api|login|logout|status|ping|socket\\.io|hls|auth|feed|public)(/|\\?|$)  1;   # Audiobookshelf"
    print "  ~^comics\\.songofeo\\.com/api/                                              1;   # Kavita"
    print "  ~^arcade\\.songofeo\\.com/api/                                              1;   # RomM"
    print "  ~^papers\\.songofeo\\.com/api/                                              1;   # Paperless"
    print "  default                                                                   0;"
    print "}"
    print "map \"$station$request_uri\" $subsonic_api {                                  # every Navidrome: Subsonic apps"
    print "  ~\\.\\.                                                  0;"
    print "  ~*%2e                                                  0;"
    print "  ~^http://10\\.6\\.9\\.20:45(3[3-9]|4[0-9])/rest/            1;"
    print "  default                                                0;"
    print "}"
    print "map \"$app_api$subsonic_api\" $own_login { ~1 1; default 0; }"
    next
  }
  /location \/internal\/authelia\/authz \{ internal;/ {
    sub(/internal;/, "internal; if ($own_login) { return 200; }"); n++; print; next
  }
  inauthz && /^[[:space:]]*internal;[[:space:]]*$/ {
    print; ind=$0; sub(/internal;.*/, "", ind)
    print ind "if ($own_login) { return 200; }   # a phone app'"'"'s API path: no sign-in, so no Remote-User either"
    n++; inauthz=0; next
  }
  /location \/internal\/authelia\/authz \{[[:space:]]*$/ { inauthz=1 }
  { print }
  END { if (!mapdone || !n) exit 3 }' "$NG.bak-$TS" > "$NG.tmp" || rc=$?
[ "$rc" = 0 ] || { rm -f "$NG.tmp"; restore "couldn't find the station map or the sign-in check in $NG"; }
cat "$NG.tmp" > "$NG"; rm -f "$NG.tmp"
diff "$NG.bak-$TS" "$NG" || true

[ -n "${TEST:-}" ] && { say "TEST mode: file edited, nothing reloaded"; exit 0; }
say "Checking nginx"
podman exec nginx nginx -t || restore "nginx rejected the new config"
podman exec nginx nginx -s reload
say "Done. Each phone app signs in with that app's own username and password (Symphonium: https://music.songofeo.com)."
