#!/usr/bin/env bash
# cobra-forms on the GATE (cobra-gate, 10.6.9.10). Run as podsvc, from the unpacked bundle folder:
#   sudo machinectl shell podsvc@      then      bash ~/forms-gate/install-gate.sh
# shellcheck disable=SC2015  # "test && note || warn" is safe: note only prints
#
# What it does, in order (every step can be run again safely; nothing existing is overwritten without a backup):
#   1. /srv/gate/forms/app  <- forms.py (+ forms.json, only if there isn't one yet: your edits are kept)
#   2. /srv/gate/forms/forms.env  (Gmail address, timezone) and the podman secret forms_smtp_pass (app password)
#   3. the Quadlet ~/.config/containers/systemd/forms.container, then starts it inside the gate pod
#   4. /srv/gate/nginx/conf.d/forms.conf (a NEW file; songofeo.conf is not touched), tested before reload
#   5. one Authelia rule: forms.songofeo.com (the /inbox only) = eels, password + TOTP. Backed up, validated,
#      put back if Authelia refuses it. Restarting Authelia signs everyone out once.
# Settings: INBOX_USER=eels (who may read the inbox), FORMS_PORT=8097. FORMS_GMAIL / FORMS_APP_PASSWORD skip the questions.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TS=$(date +%Y%m%d-%H%M%S)
INBOX_USER=${INBOX_USER:-eels}
PORT=${FORMS_PORT:-8097}
DIR=${FORMS_DIR:-/srv/gate/forms}
QDIR=${QUADLET_DIR:-$HOME/.config/containers/systemd}
NGINX_CONF=${NGINX_CONF:-/srv/gate/nginx/conf.d}
AU=${AUTHELIA_CONF:-/srv/gate/authelia/configuration.yml}
IMAGE=docker.io/library/python:3-slim

say()  { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
backup() { [ -e "$1" ] && cp -p "$1" "$1.bak-$TS" && note "backup: $1.bak-$TS"; return 0; }

# ---------- 0. checks
[ "$(id -un)" = podsvc ] || die "run this as podsvc:  sudo machinectl shell podsvc@"
[ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] || die "no user session. Log in with  sudo machinectl shell podsvc@"
for f in forms.py forms.example.json forms.conf; do [ -r "$HERE/$f" ] || die "missing $HERE/$f (unpack the whole bundle)"; done
[ -d "$NGINX_CONF" ] || die "$NGINX_CONF not found: is this the gate?"
[ -f "$AU" ] || die "$AU not found: is this the gate?"
podman container exists nginx || die "the nginx container isn't there (systemctl --user status nginx)"
podman container exists authelia || die "the authelia container isn't there (systemctl --user status authelia)"

# ---------- 1. the app
say "1/5 App files in $DIR"
mkdir -p "$DIR/app" "$DIR/data"
chmod 700 "$DIR" "$DIR/data"
if [ -f "$DIR/app/forms.py" ] && ! cmp -s "$HERE/forms.py" "$DIR/app/forms.py"; then backup "$DIR/app/forms.py"; fi
cp "$HERE/forms.py" "$DIR/app/forms.py"
if [ -f "$DIR/app/forms.json" ]; then
  note "kept your existing $DIR/app/forms.json (the new example is $DIR/app/forms.example.json)"
else
  cp "$HERE/forms.example.json" "$DIR/app/forms.json"
  note "wrote $DIR/app/forms.json (forms: voices, help, enlist)"
fi
cp "$HERE/forms.example.json" "$DIR/app/forms.example.json"

# ---------- 2. email settings
say "2/5 Email settings"
if [ -f "$DIR/forms.env" ]; then
  note "kept your existing $DIR/forms.env:"
  sed 's/^/      /' "$DIR/forms.env"
else
  echo "    Type the Gmail address that sends the emails (it also receives them)."
  echo "    Leave it empty and press Enter for no email (submissions are only saved, read them at /inbox)."
  if [ -n "${FORMS_GMAIL+x}" ]; then GMAIL=$FORMS_GMAIL; else read -rp "    Gmail address: " GMAIL </dev/tty; fi
  GMAIL=$(printf %s "$GMAIL" | tr -d '[:space:]')
  if [ -n "$GMAIL" ] && ! [[ $GMAIL =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then die "\"$GMAIL\" isn't an email address. Run the script again."; fi
  TZNAME=$(cat /etc/timezone 2>/dev/null || timedatectl show -p Timezone --value 2>/dev/null || echo UTC)
  umask 077
  {
    echo "FORMS_ADDR=127.0.0.1:$PORT"
    echo "FORMS_INBOX_USERS=$INBOX_USER"
    echo "FORMS_SMTP_HOST=smtp.gmail.com"
    echo "FORMS_SMTP_PORT=587"
    echo "FORMS_SMTP_USER=$GMAIL"
    echo "FORMS_TO=$GMAIL"
    echo "TZ=$TZNAME"
  } > "$DIR/forms.env"
  umask 022
  note "wrote $DIR/forms.env (mode 600)"
fi
GMAIL=$(sed -n 's/^FORMS_SMTP_USER=//p' "$DIR/forms.env")
if [ -n "$GMAIL" ]; then
  if podman secret exists forms_smtp_pass; then
    note "kept the existing podman secret forms_smtp_pass (to change it: podman secret rm forms_smtp_pass, then run this again)"
  else
    echo "    Paste the 16-letter Google app password for $GMAIL (nothing shows while you paste), then press Enter."
    if [ -n "${FORMS_APP_PASSWORD:-}" ]; then APPPW=$FORMS_APP_PASSWORD; else read -rsp "    App password: " APPPW </dev/tty; echo; fi
    APPPW=$(printf %s "$APPPW" | tr -d '[:space:]')
    [ ${#APPPW} -ge 16 ] || die "that was ${#APPPW} letters, an app password has 16. Run the script again."
    printf %s "$APPPW" | podman secret create forms_smtp_pass - >/dev/null
    unset APPPW
    note "saved the app password as podman secret forms_smtp_pass"
  fi
fi

# ---------- 3. the container (Quadlet, like every other app on the gate)
say "3/5 Quadlet $QDIR/forms.container"
mkdir -p "$QDIR"
SECRET_LINE=""
podman secret exists forms_smtp_pass && SECRET_LINE="Secret=forms_smtp_pass,type=env,target=FORMS_SMTP_PASS"
NEW=$(cat <<EOF
[Unit]
Description=cobra-forms: the website's own form receiver (forms.songofeo.com)
[Container]
ContainerName=forms
Image=$IMAGE
Pod=gate.pod
AutoUpdate=registry
EnvironmentFile=$DIR/forms.env
Environment=FORMS_CONFIG=/app/forms.json FORMS_DATA=/data PYTHONDONTWRITEBYTECODE=1
${SECRET_LINE}
Volume=$DIR/app:/app:ro,Z
Volume=$DIR/data:/data:Z
Exec=python3 /app/forms.py
[Service]
Restart=on-failure
RestartSec=10
[Install]
WantedBy=default.target
EOF
)
if [ -f "$QDIR/forms.container" ] && [ "$(cat "$QDIR/forms.container")" != "$NEW" ]; then backup "$QDIR/forms.container"; fi
printf '%s\n' "$NEW" > "$QDIR/forms.container"
chmod 600 "$QDIR/forms.container"
podman image exists "$IMAGE" || { note "pulling $IMAGE"; podman pull -q "$IMAGE" >/dev/null; }
systemctl --user daemon-reload
systemctl --user restart forms
up=0
for _ in $(seq 1 20); do
  if podman exec forms python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$PORT/health', timeout=2)" 2>/dev/null; then up=1; break; fi
  sleep 1
done
[ "$up" = 1 ] || { podman logs --tail 30 forms || true; die "forms didn't start. The lines above say why (systemctl --user status forms)"; }
podman logs --tail 2 forms | sed 's/^/    /'

# ---------- 4. nginx
say "4/5 nginx: $NGINX_CONF/forms.conf"
HAD_CONF=0
if [ -f "$NGINX_CONF/forms.conf" ]; then HAD_CONF=1; cmp -s "$HERE/forms.conf" "$NGINX_CONF/forms.conf" || backup "$NGINX_CONF/forms.conf"; fi
sed "s/127\.0\.0\.1:8097/127.0.0.1:$PORT/g" "$HERE/forms.conf" > "$NGINX_CONF/forms.conf"
NGINX_TEST=$(podman exec nginx nginx -t 2>&1 || true)
if ! grep -q 'test is successful' <<<"$NGINX_TEST"; then
  printf '%s\n' "$NGINX_TEST" >&2
  if [ "$HAD_CONF" = 1 ] && [ -f "$NGINX_CONF/forms.conf.bak-$TS" ]; then cp -p "$NGINX_CONF/forms.conf.bak-$TS" "$NGINX_CONF/forms.conf"
  elif [ "$HAD_CONF" = 0 ]; then rm -f "$NGINX_CONF/forms.conf"; fi
  die "nginx refused the new file, so it was taken back out. nginx is still running the old config"
fi
podman exec nginx nginx -s reload >/dev/null 2>&1
note "nginx reloaded"

# ---------- 5. Authelia: who may read the inbox
say "5/5 Authelia rule for forms.songofeo.com"
if grep -q 'forms\.songofeo\.com' "$AU"; then
  note "already has a forms.songofeo.com rule; left as it is"
else
  backup "$AU"
  awk -v u="$INBOX_USER" '
    { print }
    !done && /^[[:space:]]*rules:[[:space:]]*$/ {
      print "    # forms.: only the saved submissions (/inbox) ask for a sign-in; the forms themselves post to /f/ and never come here"
      print "    - domain: forms.songofeo.com"
      print "      subject: [\"user:" u "\"]"
      print "      policy: two_factor"
      done = 1
    }
    END { if (!done) exit 3 }' "$AU.bak-$TS" > "$AU.new" || { rm -f "$AU.new"; die "couldn't find the \"rules:\" line in $AU; nothing changed"; }
  cat "$AU.new" > "$AU"; rm -f "$AU.new"
  restore() { cp -p "$AU.bak-$TS" "$AU"; systemctl --user restart authelia || true; die "$1. configuration.yml was put back as it was"; }
  podman exec authelia authelia validate-config --config /config/configuration.yml >/dev/null 2>&1 || restore "Authelia rejected the new rule"
  systemctl --user restart authelia
  sleep 5
  systemctl --user is-active --quiet authelia || restore "Authelia didn't come back up"
  note "added (everyone was signed out once; sign in again)"
fi

# ---------- checks
say "Checks"
code=$(curl -sk -o /dev/null -w '%{http_code}' --resolve forms.songofeo.com:443:127.0.0.1 https://forms.songofeo.com/health || true)
[ "$code" = 200 ] && note "OK   https://forms.songofeo.com/health answers 200" || warn "https://forms.songofeo.com/health answered $code (expected 200)"
code=$(curl -sk -o /dev/null -w '%{http_code}' --resolve forms.songofeo.com:443:127.0.0.1 https://forms.songofeo.com/inbox/ || true)
[ "$code" = 302 ] && note "OK   /inbox sends strangers to the sign-in (302)" || warn "/inbox answered $code (expected 302 to gate.songofeo.com)"
code=$(curl -sk -o /dev/null -w '%{http_code}' --resolve forms.songofeo.com:443:127.0.0.1 -X POST -H 'Origin: https://evil.example' -d 'Petition=x' https://forms.songofeo.com/f/voices || true)
[ "$code" = 403 ] && note "OK   a form sent from another website is refused (403)" || warn "foreign-site test answered $code (expected 403)"
echo
say "Done. Next: the email test, then point the website's forms at https://forms.songofeo.com/f/<form>"
[ -n "$GMAIL" ] && echo "    Email test:  podman exec forms python3 /app/forms.py test-email"
echo "    Logs:        podman logs -f forms"
echo "    Saved forms: $DIR/data/inbox   (and https://forms.songofeo.com/inbox once signed in)"
