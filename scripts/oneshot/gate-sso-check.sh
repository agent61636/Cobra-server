#!/usr/bin/env bash
# shellcheck disable=SC2015  # "test && ok || fail" is safe here: ok() only prints
# READ-ONLY. Changes nothing, restarts nothing. On the GATE, as podsvc:
#   bash /home/podsvc/gate-sso-check.sh
# Tells you which of the one-shot scripts are already on the live gate, whether Authelia and nginx
# accept their config, and whether the sign-in, the phone apps' paths and the TV (Jellyfin) behave.
# Every FAIL line says which fix to run.
set -uo pipefail
NG=${NG:-/srv/gate/nginx/conf.d/songofeo.conf}
AU=${AU:-/srv/gate/authelia/configuration.yml}
TARGET=${TARGET:-127.0.0.1}   # the nginx to ask (the gate itself)
D=songofeo.com
PORTAL=https://gate.$D/
bad=0
ok()   { printf '  \033[32mOK\033[0m    %-30s %s\n' "$1" "$2"; }
note() { printf '  \033[33mNOTE\033[0m  %-30s %s\n' "$1" "$2"; }
fail() { printf '  \033[31mFAIL\033[0m  %-30s %s\n' "$1" "$2"; bad=$((bad + 1)); }
[ "$(id -un)" = podsvc ] || { echo "Run this as podsvc:  sudo machinectl shell podsvc@ /bin/bash $0"; exit 2; }
command -v curl >/dev/null || { echo "curl is missing. As eels: sudo apt install -y curl"; exit 2; }

echo "== 1. Containers"
for c in authelia nginx; do
  st=$(podman ps --filter "name=^$c\$" --format '{{.Status}}' 2>/dev/null)
  [[ $st == Up* ]] && ok "$c" "$st" || fail "$c" "not running (${st:-absent}): systemctl --user restart $c; podman logs --tail 30 $c"
done

echo "== 2. Authelia config ($AU)"
if [ -r "$AU" ]; then
  out=$(podman exec authelia authelia validate-config --config /config/configuration.yml 2>&1)
  [[ $out == *"without errors"* ]] && ok "validate-config" "no errors" || fail "validate-config" "$out"
  if awk '/- domain: &station/{s=1} s&&/networks: \[home\]/{f=1} s&&/policy:/{exit} END{exit !f}' "$AU"; then
    fail "home bypass" "still on for the floors: run gate-signin.sh (one sign-in for everyone)"
  else ok "home bypass" "gone: everyone signs in once, at home too"; fi
  rm_=$(sed -n 's/^[[:space:]]*remember_me:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$AU")
  [ "$rm_" = 1M ] && ok "remember_me" "1M (one month)" || note "remember_me" "${rm_:-unset}: gate-signin.sh sets 1M"
  grep -q "vip\.$D" "$AU" || note "rule for vip." "missing (the VIP keypad isn't built yet; gate-signin.sh adds the rule)"
  for n in music mustang comedy sessions books comics arcade gaming art; do
    grep -q "$n\.$D" "$AU" || fail "rule for $n." "missing in Authelia (default deny refuses it): run gate-navidromes.sh / gate-signin.sh"
  done
  grep -q "tv\.$D" "$AU" && note "tv. in Authelia" "listed but harmless: tv.'s nginx block never asks Authelia"
  walls=$(sed -n 's/.*# N\.A\.V\. wall: \([^ ]*\).*/\1/p' "$AU" | tr '\n' ' ')
  [ -n "$walls" ] && ok "N.A.V. walls" "$walls" || note "N.A.V. walls" "none: every signed-in person can open every Navidrome, incl. music. and mustang."
  errs=$(podman logs --since 24h authelia 2>&1 | grep -ciE 'level=(error|fatal)')
  [ "$errs" = 0 ] && ok "Authelia log (24h)" "no errors" || note "Authelia log (24h)" "$errs error lines: podman logs --since 24h authelia 2>&1 | grep -iE 'level=(error|fatal)' | tail"
else fail "configuration.yml" "can't read $AU"; fi

echo "== 3. nginx config ($NG)"
out=$(podman exec nginx nginx -t 2>&1)
[[ $out == *"test is successful"* ]] && ok "nginx -t" "syntax ok" || fail "nginx -t" "$out"
w=$(grep -i 'conflicting server name' <<<"$out" | sed 's/.*conflicting server name "\([^"]*\)".*/\1/' | sort -u | tr '\n' ' ')
[ -z "$w" ] && ok "duplicate names" "none" || fail "duplicate names" "$w: a name in two server blocks; nginx uses the first one only"
if [ -r "$NG" ]; then
  sn=$(awk '/server_name/{f=1} f{print} /;/{f=0}' "$NG")
  grep -qE "(^|[[:space:]])vip\.$D([[:space:];]|$)" <<<"$sn" || note "server block for vip." "not built yet (VIP keypad, manual 5.4); nothing else needs it"
  for n in tv music mustang comedy sessions books comics arcade art gaming gate vault papers metube command status; do
    grep -qE "(^|[[:space:]])$n\.$D([[:space:];]|$)" <<<"$sn" || fail "server block for $n." "missing: $n.$D gets the catch-all (handshake refused)"
  done
  grep -q '\$own_login' "$NG" && ok "phone-app paths" "gate-apps.sh is applied" || fail "phone-app paths" "not applied: Subsonic/ABS/Kavita apps hit the sign-in. Run gate-apps.sh"
  grep -qE 'mustang\.songofeo\.com[[:space:]]+http://10\.6\.9\.20:4535' "$NG" && ok "mustang. -> :4535" "Rachel's own Navidrome" || fail "mustang. port" "not :4535: run gate-navidromes.sh"
  tvblk=$(awk '/server_name[^;]*tv\.songofeo\.com/{f=1} f{print} f&&/^}/{exit}' "$NG")
  grep -q auth_request <<<"$tvblk" && fail "tv. server block" "shares a block with auth_request: TV apps can't sign in" || ok "tv. server block" "its own, no gate sign-in"
else fail "songofeo.conf" "can't read $NG"; fi

echo "== 4. Live answers (asking this gate's nginx directly)"
req() { rm -f /tmp/ssochk.$$; curl -sk --noproxy '*' -m 15 -o /tmp/ssochk.$$ -w '%{http_code} %{redirect_url}' --resolve "$1:443:$TARGET" "${@:3}" "https://$1$2" 2>/dev/null; }
for n in music mustang comedy sessions books comics; do
  r=$(req "$n.$D" /); [[ $r == "302 $PORTAL"* ]] && ok "$n. web page" "302 to the sign-in" || fail "$n. web page" "$r (expected a 302 to $PORTAL)"
done
for n in music mustang comedy sessions; do
  r=$(req "$n.$D" "/rest/ping.view?v=1.16.1&c=ssocheck&f=json" -H 'Remote-User: eels'); b=$(head -c 300 /tmp/ssochk.$$)
  if [[ $r == 302* ]]; then fail "$n. /rest/ (apps)" "sent to the sign-in: run gate-apps.sh"
  elif [[ $b == *'"status":"ok"'* ]]; then fail "$n. /rest/ (apps)" "DANGER: a forged Remote-User header got in. Stop and tell Claude"
  elif [[ $b == *subsonic-response* ]]; then ok "$n. /rest/ (apps)" "Navidrome asks for the app's own login; forged header ignored"
  else fail "$n. /rest/ (apps)" "${r%% *}: Navidrome isn't answering (SGIN: systemctl --user status navidrome*)"; fi
done
r=$(req "books.$D" /ping); [[ $r == 200* ]] && ok "books. /ping (ABS app)" "200 from Audiobookshelf" || fail "books. /ping (ABS app)" "$r"
r=$(req "tv.$D" /System/Info/Public); b=$(head -c 400 /tmp/ssochk.$$)
if [[ $b == *ServerName* ]]; then ok "tv. (Jellyfin apps)" "$(sed -E 's/.*"ServerName":"([^"]*)".*"Version":"([^"]*)".*/Jellyfin "\1" \2/' <<<"$b")"
else fail "tv. (Jellyfin apps)" "$r: Jellyfin didn't answer (SGIN: systemctl --user status jellyfin)"; fi
r=$(req "gate.$D" /api/health); [[ $(cat /tmp/ssochk.$$) == *OK* ]] && ok "gate. portal" "Authelia healthy" || fail "gate. portal" "$r"
rm -f /tmp/ssochk.$$

echo
[ "$bad" = 0 ] && echo "All gate checks passed." || echo "$bad check(s) failed. Send Claude everything from '== 1.' down."
exit $(( bad > 0 ))
