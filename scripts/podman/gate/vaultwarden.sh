#!/usr/bin/env bash
# Vaultwarden (Bitwarden-compatible password manager). https://vault.songofeo.com, LAN and WireGuard only.
# Run as podsvc on the gate:  ./vaultwarden.sh
# Sign-ups are open only until the first account exists (the database appears), then closed on the next run.
# Force either way with SIGNUPS_ALLOWED=true|false ./vaultwarden.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${VAULTWARDEN_IMAGE:-docker.io/vaultwarden/server:latest}
DATA=$GATE_DATA/vaultwarden

preflight
gate_pod
ensure_dir "$DATA"

if [ -z "${SIGNUPS_ALLOWED:-}" ]; then
  if [ -e "$DATA/db.sqlite3" ]; then SIGNUPS_ALLOWED=false; else SIGNUPS_ALLOWED=true; fi
fi

run_container vaultwarden "$GATE_POD" "$IMAGE" \
  -e ROCKET_PORT=8222 \
  -e DOMAIN=https://vault.songofeo.com \
  -e SIGNUPS_ALLOWED="$SIGNUPS_ALLOWED" \
  -v "$DATA:/data:Z"

pod_http vaultwarden http://127.0.0.1:8222/alive 60 || warn "Vaultwarden isn't answering yet; check podman logs vaultwarden"
done_msg vaultwarden https://vault.songofeo.com
if [ "$SIGNUPS_ALLOWED" = true ]; then
  echo "    Sign-ups are OPEN. Create your account now, then run ./vaultwarden.sh again to close them."
else
  echo "    Sign-ups are closed."
fi
