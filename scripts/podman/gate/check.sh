#!/usr/bin/env bash
# shellcheck disable=SC2015  # "test && ok || fail" is safe here: ok() only prints, so it cannot fail
# Checks every *.songofeo.com hostname on the gate: the certificate, that each name reaches the right
# server block, that the sign-in (Authelia) guards what it should, and that the app behind it answers.
# Changes nothing. Run on the gate as eels or podsvc (needs curl and openssl: sudo apt install -y curl openssl).
#
#   ./check.sh                 asks the gate's own nginx (127.0.0.1), the view from "outside the house"
#   ./check.sh 10.6.9.10       same checks against another address, e.g. from a LAN machine with this repo
#
# From 127.0.0.1 you are NOT in Authelia's "home" network, so the floors (music., books. ...) must send you to
# the sign-in, exactly like a phone on cellular. From a LAN machine they open straight away instead.
set -uo pipefail
TARGET=${1:-127.0.0.1}
DOMAIN=songofeo.com
PORTAL=https://gate.$DOMAIN/

command -v curl >/dev/null || { echo "curl isn't installed. As eels: sudo apt install -y curl"; exit 2; }

bad=0
ok()   { printf '  \033[32mOK\033[0m    %-26s %s\n' "$1" "$2"; }
note() { printf '  \033[33mNOTE\033[0m  %-26s %s\n' "$1" "$2"; }
fail() { printf '  \033[31mFAIL\033[0m  %-26s %s\n' "$1" "$2"; bad=$((bad + 1)); }

# probe NAME -> sets CODE and LOC (the redirect target, if any).
# CODE 000 = no TLS answer at all (no server block for that name); TIMEOUT = nginx took the request but
# the app behind it never answered (curl gives up after 15 s; nginx itself would wait 60 s and send a 504).
probe() {
  local out rc
  out=$(curl -sk -m 15 -o /dev/null -w '%{http_code} %{redirect_url}' \
        --resolve "$1:443:$TARGET" "https://$1/" 2>/dev/null); rc=$?
  CODE=${out%% *}; LOC=${out#* }; [ "$LOC" = "$CODE" ] && LOC=
  [ -n "$CODE" ] || CODE=000
  [ "$rc" = 28 ] && CODE=TIMEOUT
  return 0
}

# What a status means once the request got past the sign-in
app_answer() {
  case $CODE in
    502|504|TIMEOUT) fail "$1" "$CODE: nginx is fine, but the app behind it isn't answering ($2). Is it running? Can the gate reach it?" ;;
    500)     fail "$1" "500: nginx couldn't ask Authelia (is it running? podman logs authelia)" ;;
    403)     fail "$1" "403: refused. Authelia has no access_control rule for $1 (default_policy: deny)" ;;
    000)     fail "$1" "no answer: nginx has no server block for this name (or nginx is down)" ;;
    *)       ok   "$1" "$CODE, the app answers ($2)" ;;
  esac
}

echo "== Certificate (as served for gate.$DOMAIN on $TARGET)"
if command -v openssl >/dev/null; then
  cert=$(echo | openssl s_client -connect "$TARGET:443" -servername "gate.$DOMAIN" 2>/dev/null | openssl x509 -noout -enddate -ext subjectAltName 2>/dev/null)
  if [ -z "$cert" ]; then
    fail "certificate" "nginx didn't answer on $TARGET:443 (podman ps; podman logs nginx)"
  else
    grep -q "\*\.$DOMAIN" <<<"$cert" && ok "wildcard" "covers *.$DOMAIN" || fail "wildcard" "the cert doesn't cover *.$DOMAIN (part 5.3)"
    end=$(sed -n 's/^notAfter=//p' <<<"$cert")
    if echo | openssl s_client -connect "$TARGET:443" -servername "gate.$DOMAIN" 2>/dev/null | openssl x509 -noout -checkend $((14 * 86400)) >/dev/null; then
      ok "expiry" "valid until $end"
    else
      fail "expiry" "expires within 14 days ($end): sudo systemctl start lego-renew.service; journalctl -u lego-renew"
    fi
  fi
else
  note "certificate" "openssl isn't installed, skipped"
fi

echo "== Sign-in portal"
probe "gate.$DOMAIN"
[ "$CODE" = 200 ] && ok "gate.$DOMAIN" "200, the sign-in page" || fail "gate.$DOMAIN" "$CODE (expected 200). podman logs authelia"
health=$(curl -sk -m 10 --resolve "gate.$DOMAIN:443:$TARGET" "https://gate.$DOMAIN/api/health" 2>/dev/null)
[[ $health == *'"OK"'* ]] && ok "Authelia health" "$health" || fail "Authelia health" "${health:-no answer}"

echo "== Admin apps (password + TOTP from everywhere, so always a redirect to the sign-in)"
for pair in papers:Paperless metube:MeTube command:Homepage status:"Uptime Kuma"; do
  h=${pair%%:*}.$DOMAIN app=${pair#*:}
  probe "$h"
  if [ "$CODE" = 302 ] && [[ $LOC == "$PORTAL"* ]]; then ok "$h" "302 to the sign-in ($app)"
  elif [ "$CODE" = 403 ]; then fail "$h" "403: Authelia has no rule for it"
  elif [ "$CODE" = 000 ]; then fail "$h" "no answer: no server block for this name"
  else fail "$h" "$CODE ${LOC:-}: should be a 302 to $PORTAL. Is auth_request missing from its server block?"
  fi
done

echo "== Cinema (Jellyfin's own login only, never the gate's sign-in, so the TV apps work)"
probe "tv.$DOMAIN"
if [ "$CODE" = 302 ] && [[ $LOC == "$PORTAL"* ]]; then
  fail "tv.$DOMAIN" "302 to the gate's sign-in: tv. should have its own server block with no auth_request (part 5.4)"
else app_answer "tv.$DOMAIN" "Jellyfin"
fi

echo "== The station's floors (sign-in from outside, open at home and over WireGuard)"
for pair in music:Navidrome mustang:"Rachel's Navidrome" comedy:"comedy Navidrome" books:Audiobookshelf \
            comics:Kavita arcade:RomM art:eo-art gaming:"holding page" sessions:"podcasts Navidrome" \
            scores:"hiscore, part 7" radio:"Icecast, part 8"; do
  h=${pair%%:*}.$DOMAIN app=${pair#*:}
  probe "$h"
  if [ "$CODE" = 302 ] && [[ $LOC == "$PORTAL"* ]]; then ok "$h" "302 to the sign-in ($app)"
  elif [ "$CODE" = 000 ] && [[ $h == scores.* || $h == radio.* ]]; then note "$h" "no server block yet ($app not done)"
  elif [ "$CODE" = 403 ] && [[ $h == scores.* || $h == radio.* ]]; then fail "$h" "403: add its access_control rule to Authelia ($app)"
  else app_answer "$h" "$app"
  fi
done

echo "== VIP keypad (always the sign-in, even at home: it needs to know who you are)"
probe "vip.$DOMAIN"
if [ "$CODE" = 302 ] && [[ $LOC == "$PORTAL"* ]]; then ok "vip.$DOMAIN" "302 to the sign-in"
elif [ "$CODE" = 000 ]; then note "vip.$DOMAIN" "no server block yet (part 5.4)"
else fail "vip.$DOMAIN" "$CODE ${LOC:-}: should be a 302 to $PORTAL"
fi

echo "== Forms (the website's forms post here from anywhere; only the saved inbox asks for the sign-in)"
h=forms.$DOMAIN
code=$(curl -sk -m 10 -o /dev/null -w '%{http_code}' --resolve "$h:443:$TARGET" "https://$h/health" 2>/dev/null) || code=000
case $code in
  200) ok "$h/health" "200, cobra-forms answers" ;;
  000) note "$h" "no server block yet (apps/forms/README.md)" ;;
  *)   fail "$h/health" "$code: is the forms container running? podman logs forms" ;;
esac
if [ "$code" != 000 ]; then
  out=$(curl -sk -m 10 -o /dev/null -w '%{http_code} %{redirect_url}' --resolve "$h:443:$TARGET" "https://$h/inbox/" 2>/dev/null) || out=000
  [[ $out == "302 $PORTAL"* ]] && ok "$h/inbox" "302 to the sign-in" || fail "$h/inbox" "$out: the inbox must send strangers to the sign-in"
  code=$(curl -sk -m 10 -o /dev/null -w '%{http_code}' --resolve "$h:443:$TARGET" -X POST -H 'Origin: https://evil.example' \
         -d 'Petition=check.sh' "https://$h/f/voices" 2>/dev/null) || code=000
  [ "$code" = 403 ] && ok "$h/f/ from another site" "403, refused" || fail "$h/f/ from another site" "$code (expected 403)"
fi

echo "== Vaultwarden (LAN and WireGuard only, never through the sign-in)"
probe "vault.$DOMAIN"
case $CODE in
  403) [[ $TARGET == 127.* ]] && ok "vault.$DOMAIN" "403 from 127.0.0.1, as it should be (only 10.6.9.x / 10.6.99.x get in)" \
                              || note "vault.$DOMAIN" "403: this machine isn't on the LAN or WireGuard" ;;
  302) fail "vault.$DOMAIN" "302: Vaultwarden shouldn't go through Authelia" ;;
  *)   app_answer "vault.$DOMAIN" "Vaultwarden" ;;
esac

echo "== Things that must NOT work"
probe "nosuchname.$DOMAIN"
[ "$CODE" = 000 ] && ok "unknown name" "handshake refused (catch-all)" || fail "unknown name" "$CODE: the catch-all should refuse unknown names"
code=$(curl -sk -m 10 -o /dev/null -w '%{http_code}' "https://$TARGET/" 2>/dev/null) || code=000
[ "$code" = 000 ] && ok "bare IP" "handshake refused" || fail "bare IP" "$code: https://$TARGET/ should get no page"
out=$(curl -s -m 10 -o /dev/null -w '%{http_code} %{redirect_url}' -H "Host: tv.$DOMAIN" "http://$TARGET/" 2>/dev/null) || out=000
[[ $out == "301 https://tv.$DOMAIN/" ]] && ok "port 80" "301 to https" || fail "port 80" "$out (expected 301 to https://tv.$DOMAIN/)"

echo
if [ "$bad" -eq 0 ]; then echo "All checks passed."; else echo "$bad check(s) failed. Each FAIL line says what to look at."; fi
exit $(( bad > 0 ))
