#!/usr/bin/env bash
# The radio from part 8: Icecast (the transmitter, :8000) and Liquidsoap (the AutoDJ, apps/radio/radio.liq).
# Run as podsvc on the SGIN after copying radio.liq to /srv/stream/radio/ (part 8.2):  ./radio.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

ICECAST_IMAGE=${ICECAST_IMAGE:-docker.io/libretime/icecast:latest}
RADIO_IMAGE=${RADIO_IMAGE:-docker.io/savonet/liquidsoap:v2.4.x-latest}
DATA=$STREAM_DATA/radio

preflight
need_folders "$MUSIC_DIR"
[ -r "$DATA/radio.liq" ] || die "$DATA/radio.liq is missing; copy apps/radio/radio.liq there first (part 8.2)"
stream_pod

ensure_secret icecast-source-password
ensure_secret icecast-admin-password
ensure_secret icecast-relay-password

run_container icecast "$STREAM_POD" "$ICECAST_IMAGE" \
  --secret icecast-source-password,type=env,target=ICECAST_SOURCE_PASSWORD \
  --secret icecast-admin-password,type=env,target=ICECAST_ADMIN_PASSWORD \
  --secret icecast-relay-password,type=env,target=ICECAST_RELAY_PASSWORD \
  -e ICECAST_HOSTNAME=radio.songofeo.com -e ICECAST_MAX_CLIENTS=50

wait_port 8000 60 || warn "Icecast isn't answering on :8000 yet; check podman logs icecast"

run_container radio "$STREAM_POD" "$RADIO_IMAGE" \
  --secret icecast-source-password,type=env,target=ICECAST_SOURCE_PASSWORD \
  -e RADIO_MUSIC=/media/music -e RADIO_NAME="Song of Eo Radio" \
  -v "$DATA:/radio:ro,Z" \
  -v "$DISKS/$MUSIC_DIR:/media/music:ro" \
  --entrypoint liquidsoap \
  -- /radio/radio.liq

done_msg radio http://10.6.9.20:8000
echo "    Icecast admin password: podman secret inspect --showsecret --format '{{.SecretData}}' icecast-admin-password"
