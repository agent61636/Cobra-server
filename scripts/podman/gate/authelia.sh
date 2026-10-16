#!/usr/bin/env bash
# Authelia: the login + TOTP portal at auth.songofeo.com that nginx asks before serving protected apps.
# Needs configuration.yml and users.yml from part 5.5 in /srv/gate/authelia.
# Run as podsvc on the gate:  ./authelia.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${AUTHELIA_IMAGE:-docker.io/authelia/authelia:latest}
DATA=$GATE_DATA/authelia

preflight
gate_pod
ensure_dir "$DATA"
[ -r "$DATA/configuration.yml" ] || warn "no $DATA/configuration.yml yet (part 5.5); Authelia will exit until it exists"

run_container authelia "$GATE_POD" "$IMAGE" \
  -v "$DATA:/config:Z"

pod_http authelia http://127.0.0.1:9091/api/health 60 || warn "Authelia isn't healthy yet; check podman logs authelia"
done_msg authelia https://auth.songofeo.com
