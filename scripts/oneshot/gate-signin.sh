#!/usr/bin/env bash
# On the GATE, as podsvc:  bash /home/podsvc/gate-signin.sh
# One sign-in for everyone, at home too: removes the floors' "open at home" bypass, so every Bay
# gets your username (Navidrome loads your own profile), turns on a one-month "Remember me",
# and lets the VIP keypad (vip.) through once you're signed in.
# Backs up configuration.yml first and puts it back if Authelia rejects the change.
set -euo pipefail
AU=${AU:-/srv/gate/authelia/configuration.yml}
TS=$(date +%Y%m%d-%H%M%S)
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -un)" = podsvc ] || [ -n "${TEST:-}" ] || die "run this as podsvc (sudo machinectl shell podsvc@)"
[ -f "$AU" ] || die "missing $AU"

cp -p "$AU" "$AU.bak-$TS"
say "Backup: $AU.bak-$TS"
restore() { cp -p "$AU.bak-$TS" "$AU"; die "$1. configuration.yml was put back as it was."; }

rc=0
awk '
/^[[:space:]]*# the station.s floors and its pictures: open at home/ { sub(/open at home, one password everywhere else/, "one sign-in for everyone, at home too, so every Bay knows who you are"); print; next }
/^[[:space:]]*- domain: &station/ { inst=1; print; next }
inst && /^[[:space:]]*networks: \[home\][[:space:]]*$/ { next }
inst && /^[[:space:]]*policy: bypass[[:space:]]*$/ { sub(/bypass/, "one_factor"); print; inst=0; changed=1; next }
/^[[:space:]]*- domain: \*station[[:space:]]*$/ { skip=1; next }
skip && /^[[:space:]]*policy: one_factor[[:space:]]*$/ { skip=0; next }
/^[[:space:]]*remember_me: -1/ { sub(/remember_me: -1.*/, "remember_me: 1M                      # tick \"Remember me\" at sign-in: one month on that device"); print; next }
{ print }
END { if (!changed) exit 3 }' "$AU.bak-$TS" > "$AU.new" || rc=$?
case $rc in
  0) say "Home bypass removed, Remember me = 1 month" ;;
  3) echo "  the home bypass was already gone (nothing to remove)" ;;
  *) rm -f "$AU.new"; die "awk failed (rc $rc); nothing changed" ;;
esac
grep -q 'vip\.songofeo\.com' "$AU.new" || sed -i 's#- domain: &station \[#- domain: \&station [vip.songofeo.com, #' "$AU.new"
cat "$AU.new" > "$AU"; rm -f "$AU.new"
if grep -q 'policy: bypass' "$AU"; then echo "  note: a bypass rule is still there (Home Assistant's ha. keeps its own, part 10)"; fi
diff "$AU.bak-$TS" "$AU" || true

[ -n "${TEST:-}" ] && { say "TEST mode: file edited, nothing restarted"; exit 0; }

say "Checking Authelia"
podman exec authelia authelia validate-config --config /config/configuration.yml || restore "Authelia rejected the new config"
systemctl --user restart authelia
sleep 5
systemctl --user is-active --quiet authelia || restore "Authelia didn't come back up"
say "Done. Everyone is signed out once. Sign in at the concourse's ENTER and tick Remember me."
