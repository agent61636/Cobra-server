#!/usr/bin/env bash
# Authelia: the station's sign-in at gate.songofeo.com (one password for every floor, 6 h; TOTP for admin apps).
# nginx asks it before serving any app.
# Needs configuration.yml and users.yml from part 5.4 in /srv/gate/authelia.
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
keep_personal_state authelia
[ -r "$DATA/configuration.yml" ] || warn "no $DATA/configuration.yml yet (part 5.4); Authelia will exit until it exists"

run_container authelia "$GATE_POD" "$IMAGE" \
  -v "$DATA:/config:Z"

pod_http authelia http://127.0.0.1:9091/api/health 60 || warn "Authelia isn't healthy yet; check podman logs authelia"
snapshot_personal_state authelia
done_msg authelia https://gate.songofeo.com
